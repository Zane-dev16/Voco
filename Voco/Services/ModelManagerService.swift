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
                        self?.downloadStates[modelID] = .failed(error.localizedDescription)
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
                                self?.downloadStates[modelID] = .failed(err.localizedDescription)
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

    func deleteModel(_ model: TranslationModel) throws {
        let fileURL = modelsDirectory.appendingPathComponent(model.filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
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
VocoLog.models.error("Failed to create models directory: \\(error)")
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

    private var handlers: [Int: DownloadHandler] = [:]

    private struct DownloadHandler {
        let destination: URL
        let expectedSHA256: String      // expected hash; empty = skip verification
        var copiedLocation: URL?
        var copyError: Error?
        var isCancelled = false
        let onProgress: (Double) -> Void
        let onComplete: (Result<URL, Error>) -> Void
    }

    func register(for modelID: String, task: URLSessionDownloadTask, destination: URL, sha256: String, onProgress: @escaping (Double) -> Void, onComplete: @escaping (Result<URL, Error>) -> Void) {
        handlers[task.taskIdentifier] = DownloadHandler(destination: destination, expectedSHA256: sha256, onProgress: onProgress, onComplete: onComplete)
    }

    func cancel(task: URLSessionDownloadTask?) {
        task?.cancel()
        if let task, let handler = handlers[task.taskIdentifier] {
            var updated = handler
            updated.isCancelled = true
            handlers[task.taskIdentifier] = updated
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let handler = handlers[downloadTask.taskIdentifier] else { return }
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
            handlers[downloadTask.taskIdentifier]?.copiedLocation = destination
        } catch {
            handlers[downloadTask.taskIdentifier]?.copyError = error
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        handlers[downloadTask.taskIdentifier]?.onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let handler = handlers.removeValue(forKey: task.taskIdentifier) else { return }
        // Cancellation is intentional — skip the error callback
        if handler.isCancelled { return }
        if let error {
            handler.onComplete(.failure(error))
        } else if let copyError = handler.copyError {
            handler.onComplete(.failure(copyError))
        } else if let copiedLocation = handler.copiedLocation {
            // Verify SHA-256 checksum if one is expected
            if !handler.expectedSHA256.isEmpty {
                if let data = try? Data(contentsOf: copiedLocation) {
                    let actualHash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
                    if actualHash != handler.expectedSHA256 {
                        let err = NSError(domain: "Voco", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Checksum mismatch — downloaded file may be corrupted. Expected \(handler.expectedSHA256.prefix(16))…, got \(actualHash.prefix(16))…"])
                        handler.onComplete(.failure(err))
                        return
                    }
                }
            }
            handler.onComplete(.success(copiedLocation))
        }
    }
}
