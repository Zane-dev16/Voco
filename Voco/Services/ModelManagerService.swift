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

    // Cached disk facts (S7-21): view bodies previously re-scanned the models
    // directory on every render — including at progress-tick frequency during
    // downloads. Refreshed at launch, terminal download outcomes, deletion,
    // and foreground-active.
    private(set) var cachedDiskUsageBytes: Int64 = 0
    private(set) var cachedDownloadedIDs: Set<String> = []

    /// downloadAsync callers awaiting an in-flight download. They fan in on the
    /// shared outcome instead of failing with a misleading error (S7-22).
    private struct DownloadWaiter {
        let id = UUID()
        let continuation: CheckedContinuation<URL, Error>
    }

    /// Hands the cancelling task the identity of the waiter it registered, so
    /// cancelWaiter removes exactly that entry (R7-02) instead of an arbitrary
    /// sibling. Written by the continuation body, read by onCancel — both hops
    /// land on the main actor.
    private final class WaiterRegistration: @unchecked Sendable {
        var waiterID: UUID?
    }

    /// downloadAsync callers awaiting an in-flight download, keyed by model.
    private var asyncWaiters: [String: [DownloadWaiter]] = [:]

    /// Models whose on-disk file is loadable: adopted at launch (size-checked)
    /// or checksum-verified after a this-session download (R7-05). A file that
    /// just finished transferring is NOT trusted until its SHA-256 passes, so
    /// the hashing window can't hand an unverifiable GGUF to the loader.
    private var sessionTrustedModelIDs: Set<String> = []

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
        refreshCaches()
    }

    /// Recomputes cached disk usage and downloaded flags. Cheap (a handful of
    /// stat calls) but not free — call on terminal events, not per frame.
    func refreshCaches() {
        cachedDiskUsageBytes = computeTotalDiskUsage()
        cachedDownloadedIDs = Set(
            TranslationModel.availableModels
                .filter { adoptedFileURL(for: $0) != nil }
                .map(\.id)
        )
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
                self?.finishDownloadTask(for: modelID, result: result)
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
        if let targetURL = localURL(for: model) { return targetURL }

        let modelID = model.id

        let registration = WaiterRegistration()

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                // Cancel-before-entry race: the handler already fired.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                let waiter = DownloadWaiter(continuation: continuation)
                registration.waiterID = waiter.id
                asyncWaiters[modelID, default: []].append(waiter)

                // Already downloading? Fan in on its shared outcome (S7-22).
                guard downloadTasks[modelID] == nil else { return }

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
                            self?.finishDownloadTask(for: modelID, result: result)
                        }
                    }
                )
            }
        }, onCancel: { [weak self] in
            // Runs synchronously, possibly off the main actor — hop to it.
            Task { @MainActor [weak self] in
                self?.cancelWaiter(modelID: modelID, registration: registration)
            }
        })
    }

    /// Single terminal handler for every finished transfer regardless of which
    /// API started it (R7-03): state write, waiter fan-out, cache refresh, and
    /// task deregistration happen together, exactly once per download.
    private func finishDownloadTask(for modelID: String, result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            if FileManager.default.fileExists(atPath: url.path) {
                downloadStates[modelID] = .downloaded
                // The delegate verifies SHA-256 before reporting success — the
                // file is loadable from here on (R7-05).
                sessionTrustedModelIDs.insert(modelID)
            } else {
                downloadStates[modelID] = .failed("Downloaded file not found at destination")
            }
        case .failure(let err):
            downloadStates[modelID] = Self.isCancellation(err)
                ? .notDownloaded
                : .failed(err.localizedDescription)
        }
        flushWaiters(for: modelID, with: result)
        refreshCaches()
        downloadTasks.removeValue(forKey: modelID)
    }

    /// Resumes every downloadAsync waiter with the shared outcome, exactly once.
    private func flushWaiters(for modelID: String, with result: Result<URL, Error>) {
        guard let waiters = asyncWaiters.removeValue(forKey: modelID) else { return }
        for waiter in waiters {
            switch result {
            case .success(let url):
                waiter.continuation.resume(returning: url)
            case .failure(let err):
                waiter.continuation.resume(throwing: err)
            }
        }
    }

    /// Removes and fails exactly the waiter registered by the cancelling task
    /// (identity-matched, R7-02), never an arbitrary sibling.
    private func cancelWaiter(modelID: String, registration: WaiterRegistration) {
        guard let waiterID = registration.waiterID,
              var list = asyncWaiters[modelID],
              let index = list.firstIndex(where: { $0.id == waiterID }) else { return }
        let cancelled = list.remove(at: index)
        if list.isEmpty {
            asyncWaiters.removeValue(forKey: modelID)
        } else {
            asyncWaiters[modelID] = list
        }
        cancelled.continuation.resume(throwing: CancellationError())
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
        sessionTrustedModelIDs.remove(model.id)
        refreshCaches()
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
        cachedDownloadedIDs.contains(model.id)
    }

    /// Loader-facing resolution. Files downloaded THIS SESSION become loadable
    /// only after their SHA-256 verified (finishDownloadTask) — during the
    /// hashing window this gate keeps an unverified GGUF away from the engine,
    /// which would otherwise race its post-failure deletion (R7-05). Launch-time
    /// adoptions are trusted on size alone (scanExistingModels seeds the set).
    func localURL(for model: TranslationModel) -> URL? {
        guard sessionTrustedModelIDs.contains(model.id) else { return nil }
        return adoptedFileURL(for: model)
    }

    func totalDiskUsage() -> Int64 {
        cachedDiskUsageBytes
    }

    private func computeTotalDiskUsage() -> Int64 {
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
            // Consult the disk directly, NOT the cache-backed isModelDownloaded:
            // init order must not matter (R7-01 — reading the empty cache before
            // refreshCaches() filled it reset every installed model at launch).
            if adoptedFileURL(for: model) != nil {
                downloadStates[model.id] = .downloaded
                sessionTrustedModelIDs.insert(model.id)
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
