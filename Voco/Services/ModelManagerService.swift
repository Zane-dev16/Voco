//
//  ModelManagerService.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import Foundation
import Observation
import OSLog
import CryptoKit

@Observable
@MainActor
final class ModelManagerService {
    private(set) var downloadStates: [String: DownloadState] = [:]
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private let downloadDelegate = DownloadDelegate()
    private let session: URLSession

    private let modelsDirectory: URL = {
        // Application Support always resolves in the iOS sandbox; fall back to
        // tmp defensively rather than trap if it ever doesn't.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("Voco/Models", isDirectory: true)
    }()

    /// True when the error is a user-initiated download cancellation.
    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
            || (error as? URLError)?.code == .cancelled
            || (error as NSError?)?.domain == NSURLErrorDomain && error._code == NSURLErrorCancelled
    }

    init() {
        let config = URLSessionConfiguration.default
        // Long-tail transfers over flaky networks: wait for connectivity
        // instead of failing fast, and give the whole resource a generous
        // time budget (per-request timeouts still apply).
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 24 * 60 * 60
        session = URLSession(configuration: config, delegate: downloadDelegate, delegateQueue: nil)
        ensureModelsDirectoryExists()
        scanExistingModels()
        cleanupPartialInstalls()
    }

    func download(_ model: TranslationModel) {
        guard downloadTasks[model.id] == nil else { return }
        let modelID = model.id
        let targetURL = modelsDirectory.appendingPathComponent(model.filename)

        let task = beginDownload(model, targetURL: targetURL) { [weak self] progress in
            Task { @MainActor in
                self?.downloadStates[modelID] = .downloading(progress: progress)
            }
        } onComplete: { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let url):
                    if FileManager.default.fileExists(atPath: url.path) {
                        self?.downloadStates[modelID] = .downloaded
                    } else {
                        self?.downloadStates[modelID] = .failed("Downloaded file not found at destination")
                    }
                case .failure(let error):
                    // A cancelled download was already reset to .notDownloaded
                    // by cancelDownload(for:) — don't turn it into an error state.
                    if !Self.isCancellation(error) {
                        self?.downloadStates[modelID] = .failed(error.localizedDescription)
                    }
                }
                self?.downloadTasks.removeValue(forKey: modelID)
            }
        }
        _ = task
    }

    /// Shared download machinery for both the fire-and-forget and async APIs:
    /// picks up stashed resume data when a previous attempt failed mid-transfer,
    /// registers the delegate handler, and starts the task.
    private func beginDownload(
        _ model: TranslationModel,
        targetURL: URL,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (Result<URL, Error>) -> Void
    ) -> URLSessionDownloadTask {
        downloadStates[model.id] = .downloading(progress: 0)

        let task: URLSessionDownloadTask
        if let resumeData = downloadDelegate.takeResumeData(for: model.id) {
            VocoLog.models.info("[Download] Resuming \(model.displayName) from partial transfer")
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: URLRequest(url: model.sourceURL))
        }

        let modelID = model.id
        downloadDelegate.register(
            for: modelID, task: task, destination: targetURL,
            sha256: model.sha256,
            onProgress: onProgress,
            onComplete: onComplete,
            onHashingStarted: { [weak self] in
                Task { @MainActor in
                    self?.downloadStates[modelID] = .processing
                }
            }
        )

        downloadTasks[modelID] = task
        task.resume()
        return task
    }

    /// Async wrapper — returns local URL on success. Uses continuation to avoid polling.
    /// Cancelling the awaiting Task cancels the underlying URLSessionDownloadTask
    /// (via cancelDownload), so an abandoned multi-GB activation stops downloading
    /// instead of finishing in the background and loading the wrong model.
    func downloadAsync(_ model: TranslationModel) async throws -> URL {
        guard let targetURL = localURL(for: model) else {
            let modelID = model.id
            return try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    guard downloadTasks[model.id] == nil else {
                        // Second waiter on an in-flight download — fail with the
                        // closest truthful message rather than blocking forever.
                        continuation.resume(throwing: LlamaError.noModelLoaded)
                        return
                    }
                    _ = beginDownload(
                        model,
                        targetURL: modelsDirectory.appendingPathComponent(model.filename),
                        onProgress: { [weak self] progress in
                            Task { @MainActor in
                                self?.downloadStates[modelID] = .downloading(progress: progress)
                            }
                        },
                        onComplete: { [weak self] result in
                            Task { @MainActor in
                                switch result {
                                case .success(let url):
                                    self?.downloadStates[modelID] = .downloaded
                                    continuation.resume(returning: url)
                                case .failure(let err):
                                    if Self.isCancellation(err) {
                                        self?.downloadStates[modelID] = .notDownloaded
                                    } else {
                                        self?.downloadStates[modelID] = .failed(err.localizedDescription)
                                    }
                                    // Resumed exactly once for every outcome — including
                                    // cancellation — so the awaiting task never hangs.
                                    continuation.resume(throwing: err)
                                }
                                self?.downloadTasks.removeValue(forKey: modelID)
                            }
                        }
                    )
                }
            }, onCancel: { [weak self] in
                // Runs synchronously, possibly off the main actor. cancelDownload
                // is main-actor isolated, so hop back; the continuation is resumed
                // by the delegate's failure callback exactly once.
                Task { @MainActor [weak self] in
                    self?.cancelDownload(for: modelID)
                }
            })
        }
        return targetURL
    }

    func cancelDownload(for modelID: String) {
        let task = downloadTasks.removeValue(forKey: modelID)
        downloadStates[modelID] = .notDownloaded
        downloadDelegate.clearResumeData(for: modelID)
        // Mark handler as cancelled so didCompleteWithError ignores the error callback
        downloadDelegate.cancel(task: task)
    }

    func deleteModel(_ model: TranslationModel) async throws {
        let fileURL = modelsDirectory.appendingPathComponent(model.filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            // Verify the file is actually gone — if a file handle is still open,
            // the directory entry may be removed but the inode persists.
            // Retry once after a short delay to allow pending handles to close.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                // File still present — likely held by a lingering file descriptor.
                // Suspend (not block) so the main actor stays responsive during the retry wait.
                try await Task.sleep(nanoseconds: 300_000_000)
                try FileManager.default.removeItem(at: fileURL)
            }
        }
        downloadStates[model.id] = .notDownloaded
        downloadDelegate.clearResumeData(for: model.id)
    }

    /// Adopts an on-disk GGUF only when its size matches the registry entry.
    /// A truncated file (app killed mid-copy) fails the check, gets removed,
    /// and the model falls back to `.notDownloaded` instead of short-circuiting
    /// every flow to a corrupt GGUF with a cryptic llama load error.
    /// Files installed through the hash-verified pipeline pass trivially —
    /// this gate exists for unverified pre-existing files.
    private func adoptedFileURL(for model: TranslationModel) -> URL? {
        let fileURL = modelsDirectory.appendingPathComponent(model.filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let byteSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard byteSize == model.fileSizeBytes else {
            VocoLog.models.warning("[Download] '\(model.filename)' on disk (\(byteSize) B) doesn't match registry (\(model.fileSizeBytes) B) — removing corrupt file")
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return fileURL
    }

    func isModelDownloaded(_ model: TranslationModel) -> Bool {
        adoptedFileURL(for: model) != nil
    }

    func localURL(for model: TranslationModel) -> URL? {
        adoptedFileURL(for: model)
    }

    func totalDiskUsage() -> Int64 {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    private func ensureModelsDirectoryExists() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        } catch {
VocoLog.models.error("Failed to create models directory: \(error)")
        }
    }

    private func scanExistingModels() {
        for model in TranslationModel.availableModels {
            if isModelDownloaded(model) {
                downloadStates[model.id] = .downloaded
            } else if downloadStates[model.id] == nil || downloadStates[model.id] == .downloaded {
                // Missing or corrupt (failed adoption) — reset stale markers.
                downloadStates[model.id] = .notDownloaded
            }
        }
    }

    /// Removes orphaned `.downloading` temp files from installs interrupted by
    /// process death mid-copy.
    private func cleanupPartialInstalls() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil) else { return }
        for item in contents where item.pathExtension == "downloading" {
            VocoLog.models.info("[Download] Removing orphaned partial install \(item.lastPathComponent)")
            try? fm.removeItem(at: item)
        }
    }
}

/// Thread-safe partial-transfer resume data cache keyed by model ID.
/// Explicitly `nonisolated`: accessed from both the session delegate queue and
/// the main actor; safety comes from its internal lock.
nonisolated final class ResumeDataStore: @unchecked Sendable {
    private let lock = NSLock()
    private var data: [String: Data] = [:]

    func set(_ key: String, _ value: Data?) {
        lock.lock()
        defer { lock.unlock() }
        if let value { data[key] = value } else { data.removeValue(forKey: key) }
    }

    /// Removes and returns the stored resume data for `key`, if any.
    func take(_ key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data.removeValue(forKey: key)
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate, @unchecked Sendable {

    /// Handlers are registered from the main actor but mutated and consumed by the
    /// session's delegate queue — every access must hold `handlersLock`.
    /// `@unchecked Sendable`: thread safety is guaranteed by `handlersLock`, not by
    /// immutability.
    private var handlers: [Int: DownloadHandler] = [:]
    private let handlersLock = NSLock()

    /// Partial-transfer resume data keyed by model ID, captured when a download
    /// fails mid-flight so the next attempt continues instead of restarting.
    private let resumeDataStore = ResumeDataStore()

    func takeResumeData(for modelID: String) -> Data? {
        resumeDataStore.take(modelID)
    }

    func clearResumeData(for modelID: String) {
        resumeDataStore.set(modelID, nil)
    }

    /// `@unchecked Sendable`: consumers already deliver values across threads
    /// (delegate queue → main actor hop inside the closures themselves), so the
    /// struct's closure members cross isolation boundaries by design.
    private struct DownloadHandler: @unchecked Sendable {
        let modelID: String
        let destination: URL
        let expectedSHA256: String      // expected hash; empty = skip verification
        var copiedLocation: URL?
        var copyError: Error?
        /// Time-gate for progress flushes (delegate queue cadence is far
        /// higher than UI needs; every hop invalidates observing views).
        var lastProgressFlush: TimeInterval = 0
        let onProgress: (Double) -> Void
        let onComplete: (Result<URL, Error>) -> Void
        /// Fired when body reception ends and SHA-256 verification begins,
        /// so the UI can surface the hashing phase instead of jumping 100%→ready.
        let onHashingStarted: (() -> Void)?
    }

    func register(
        for modelID: String,
        task: URLSessionDownloadTask,
        destination: URL,
        sha256: String,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (Result<URL, Error>) -> Void,
        onHashingStarted: (() -> Void)? = nil
    ) {
        let handler = DownloadHandler(
            modelID: modelID,
            destination: destination,
            expectedSHA256: sha256,
            onProgress: onProgress,
            onComplete: onComplete,
            onHashingStarted: onHashingStarted
        )
        handlersLock.lock()
        handlers[task.taskIdentifier] = handler
        handlersLock.unlock()
    }

    func cancel(task: URLSessionDownloadTask?) {
        task?.cancel()
        // Remove the handler and fail its completion immediately so any awaiting
        // `downloadAsync` continuation is resumed instead of hanging forever.
        // The later didCompleteWithError callback then finds no handler and no-ops.
        guard let task else { return }
        handlersLock.lock()
        let handler = handlers.removeValue(forKey: task.taskIdentifier)
        handlersLock.unlock()
        handler?.onComplete(.failure(CancellationError()))
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        handlersLock.lock()
        let handler = handlers[downloadTask.taskIdentifier]
        handlersLock.unlock()
        guard let handler else { return }
        let fm = FileManager.default
        let destination = handler.destination

        // Ensure parent directory exists
        let parentDir = destination.deletingLastPathComponent()
        try? fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Remove existing file if present (re-download scenario)
        if fm.fileExists(atPath: destination.path) {
            try? fm.removeItem(at: destination)
        }

        // Atomic install: copy to a temp name first, then rename into place.
        // A kill mid-copy can no longer strand a truncated file at the final
        // path that adoption checks would happily promote.
        let tempDestination = destination.appendingPathExtension("downloading")
        try? fm.removeItem(at: tempDestination)

        do {
            try fm.copyItem(at: location, to: tempDestination)
            // Cancelled while copying? The handler is gone — nobody will hash
            // or complete this file. Remove the partial install.
            handlersLock.lock()
            let stillRegistered = handlers[downloadTask.taskIdentifier] != nil
            handlersLock.unlock()
            guard stillRegistered else {
                try? fm.removeItem(at: tempDestination)
                return
            }
            if fm.fileExists(atPath: destination.path) {
                try? fm.removeItem(at: destination)
            }
            try fm.moveItem(at: tempDestination, to: destination)
            handlersLock.lock()
            handlers[downloadTask.taskIdentifier]?.copiedLocation = destination
            handlersLock.unlock()
        } catch {
            try? fm.removeItem(at: tempDestination)
            handlersLock.lock()
            handlers[downloadTask.taskIdentifier]?.copyError = error
            handlersLock.unlock()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        // Throttle: at most ~4 MainActor hops/second per active download, plus
        // a guaranteed terminal 100% flush. Delegate fires far more often.
        let now = Date().timeIntervalSince1970
        handlersLock.lock()
        let shouldFlush: Bool
        if var handler = handlers[downloadTask.taskIdentifier] {
            shouldFlush = fraction >= 1.0 || now - handler.lastProgressFlush >= 0.25
            if shouldFlush { handler.lastProgressFlush = now }
            handlers[downloadTask.taskIdentifier] = handler
        } else {
            shouldFlush = false
        }
        handlersLock.unlock()
        guard shouldFlush else { return }

        handlersLock.lock()
        let progressClosure = handlers[downloadTask.taskIdentifier]?.onProgress
        handlersLock.unlock()
        progressClosure?(fraction)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        handlersLock.lock()
        let handler = handlers.removeValue(forKey: task.taskIdentifier)
        handlersLock.unlock()
        guard let handler else { return }

        if let error {
            // Stash resume data so the next attempt continues from the byte
            // offset instead of restarting a multi-GB transfer from zero.
            // Only for genuine failures — deliberate cancellation is final.
            if !(error is CancellationError),
               let urlError = error as? URLError,
               let resumeData = urlError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                resumeDataStore.set(handler.modelID, resumeData)
            }
            handler.onComplete(.failure(error))
        } else if let copyError = handler.copyError {
            handler.onComplete(.failure(copyError))
        } else if let copiedLocation = handler.copiedLocation {
            handler.onHashingStarted?()
            verifyChecksumAndComplete(handler, fileURL: copiedLocation)
        }
    }


    // MARK: - Checksum Verification

    /// Verifies the downloaded file's SHA-256 (when one is expected) and delivers
    /// the completion. Runs on a background queue: hashing multi-GB GGUFs must not
    /// block the session's serial delegate queue.
    private func verifyChecksumAndComplete(_ handler: DownloadHandler, fileURL: URL) {
        DispatchQueue.global(qos: .utility).async {
            if handler.expectedSHA256.isEmpty {
                handler.onComplete(.success(fileURL))
                return
            }
            do {
                let actualHash = try Self.sha256Hex(of: fileURL)
                if actualHash != handler.expectedSHA256 {
                    // Delete the corrupt file so a retry starts clean — otherwise
                    // `localURL(for:)` would keep short-circuiting to the invalid
                    // file and the model could never be re-downloaded.
                    try? FileManager.default.removeItem(at: fileURL)
                    let err = NSError(domain: "Voco", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Checksum mismatch — downloaded file may be corrupted. Expected \(handler.expectedSHA256.prefix(16))…, got \(actualHash.prefix(16))…"])
                    handler.onComplete(.failure(err))
                } else {
                    handler.onComplete(.success(fileURL))
                }
            } catch {
                // A failed read means the file cannot be verified — treat it as a
                // failure rather than silently reporting success.
                handler.onComplete(.failure(error))
            }
        }
    }

    /// Streams the file through an incremental SHA-256 hasher in 4 MB chunks,
    /// avoiding a full in-memory load of potentially multi-GB model files.
    private static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 4 * 1024 * 1024
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
