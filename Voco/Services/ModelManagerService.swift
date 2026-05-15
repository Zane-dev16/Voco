//
//  ModelManagerService.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import Foundation
import Observation

@Observable
@MainActor
final class ModelManagerService {
    var downloadStates: [String: DownloadState] = [:]
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private let session: URLSession

    private let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Voco/Models", isDirectory: true)
    }()

    init() {
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: DownloadDelegate.shared, delegateQueue: nil)
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

        DownloadDelegate.shared.register(
            for: modelID, task: task, destination: targetURL,
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    self?.downloadStates[modelID] = .downloading(progress: progress)
                }
            },
            onComplete: { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let url):
                        self?.downloadStates[modelID] = .processing
                        do {
                            try FileManager.default.moveItem(at: url, to: targetURL)
                            self?.downloadStates[modelID] = .downloaded
                        } catch {
                            self?.downloadStates[modelID] = .failed("Failed to save model: \(error.localizedDescription)")
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

    func cancelDownload(for modelID: String) {
        downloadTasks[modelID]?.cancel()
        downloadTasks.removeValue(forKey: modelID)
        downloadStates[modelID] = .notDownloaded
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
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
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
    static let shared = DownloadDelegate()

    private var handlers: [Int: DownloadHandler] = [:]

    private struct DownloadHandler {
        let destination: URL
        var location: URL?
        let onProgress: (Double) -> Void
        let onComplete: (Result<URL, Error>) -> Void
    }

    func register(for modelID: String, task: URLSessionDownloadTask, destination: URL, onProgress: @escaping (Double) -> Void, onComplete: @escaping (Result<URL, Error>) -> Void) {
        handlers[task.taskIdentifier] = DownloadHandler(destination: destination, onProgress: onProgress, onComplete: onComplete)
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Store the location — the completion callback fires via didCompleteWithError
        handlers[downloadTask.taskIdentifier]?.location = location
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        handlers[downloadTask.taskIdentifier]?.onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let handler = handlers.removeValue(forKey: task.taskIdentifier) else { return }
        if let error {
            handler.onComplete(.failure(error))
        } else if let location = handler.location {
            handler.onComplete(.success(location))
        }
    }
}
