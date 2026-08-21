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
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
        session = URLSession(configuration: config, delegate: downloadDelegate, delegateQueue: nil)
        ensureModelsDirectoryExists()
        scanExistingModels()
    }

    func download(_ model: TranslationModel) {
        guard downloadTasks[model.id] == nil else { return }
        downloadStates[model.id] = .downloading(progress: 0)

        let request = URLRequest(url: model.sourceURL)
        let task = session.downloadTask(with: request)
        let modelID = model.id
        let targetURL = modelsDirectory.appendingPathComponent(model.filename)

        downloadDelegate.register(
            for: modelID, task: task, destination: targetURL,
            sha256: model.sha256,
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    self?.downloadStates[modelID] = .downloading(progress: progress)
                }
            },
            onComplete: { [weak self] result in
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
                        if !(error is CancellationError) {
                            self?.downloadStates[modelID] = .failed(error.localizedDescription)
                        }
                    }
                    self?.downloadTasks.removeValue(forKey: modelID)
                }
            }
        )

        downloadTasks[modelID] = task
        task.resume()
    }

    /// Async wrapper — returns local URL on success. Uses continuation to avoid polling.
    func downloadAsync(_ model: TranslationModel) async throws -> URL {
        guard let targetURL = localURL(for: model) else {
            // Need to download — use continuation
            return try await withCheckedThrowingContinuation { continuation in
                guard downloadTasks[model.id] == nil else {
                    continuation.resume(throwing: LlamaError.noModelLoaded)
                    return
                }
                downloadStates[model.id] = .downloading(progress: 0)

                let request = URLRequest(url: model.sourceURL)
                let task = session.downloadTask(with: request)
                let modelID = model.id
                let destURL = modelsDirectory.appendingPathComponent(model.filename)

                downloadDelegate.register(
                    for: modelID, task: task, destination: destURL,
                    sha256: model.sha256,
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

                downloadTasks[modelID] = task
                task.resume()
            }
        }
        return targetURL
    }

    func cancelDownload(for modelID: String) {
        let task = downloadTasks.removeValue(forKey: modelID)
        downloadStates[modelID] = .notDownloaded
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
    }

    func isModelDownloaded(_ model: TranslationModel) -> Bool {
        let fileURL = modelsDirectory.appendingPathComponent(model.filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    func localURL(for model: TranslationModel) -> URL? {
        let fileURL = modelsDirectory.appendingPathComponent(model.filename)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
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
            } else if downloadStates[model.id] == nil {
                downloadStates[model.id] = .notDownloaded
            }
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {

    /// Handlers are registered from the main actor but mutated and consumed by the
    /// session's delegate queue — every access must hold `handlersLock`.
    private var handlers: [Int: DownloadHandler] = [:]
    private let handlersLock = NSLock()

    private struct DownloadHandler {
        let destination: URL
        let expectedSHA256: String      // expected hash; empty = skip verification
        var copiedLocation: URL?
        var copyError: Error?
        let onProgress: (Double) -> Void
        let onComplete: (Result<URL, Error>) -> Void
    }

    func register(for modelID: String, task: URLSessionDownloadTask, destination: URL, sha256: String, onProgress: @escaping (Double) -> Void, onComplete: @escaping (Result<URL, Error>) -> Void) {
        let handler = DownloadHandler(destination: destination, expectedSHA256: sha256, onProgress: onProgress, onComplete: onComplete)
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

        do {
            // Copy the temp file to final destination BEFORE returning.
            // The temp file is deleted by the system after this method returns.
            try fm.copyItem(at: location, to: destination)
            handlersLock.lock()
            handlers[downloadTask.taskIdentifier]?.copiedLocation = destination
            handlersLock.unlock()
        } catch {
            handlersLock.lock()
            handlers[downloadTask.taskIdentifier]?.copyError = error
            handlersLock.unlock()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        handlersLock.lock()
        let onProgress = handlers[downloadTask.taskIdentifier]?.onProgress
        handlersLock.unlock()
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        handlersLock.lock()
        let handler = handlers.removeValue(forKey: task.taskIdentifier)
        handlersLock.unlock()
        guard let handler else { return }
        if let error {
            handler.onComplete(.failure(error))
        } else if let copyError = handler.copyError {
            handler.onComplete(.failure(copyError))
        } else if let copiedLocation = handler.copiedLocation {
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
