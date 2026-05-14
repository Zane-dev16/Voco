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
    private var downloadDelegates: [String: DownloadDelegate] = [:]

    private let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Voco/Models", isDirectory: true)
    }()

    init() {
        ensureModelsDirectoryExists()
        scanExistingModels()
    }

    func download(_ model: TranslationModel) {
        guard downloadTasks[model.id] == nil else { return }
        downloadStates[model.id] = .downloading(progress: 0)

        let targetURL = modelsDirectory.appendingPathComponent(model.filename)
        let modelID = model.id

        let delegate = DownloadDelegate(
            destination: targetURL,
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
                        try? FileManager.default.moveItem(at: url, to: targetURL)
                        self?.downloadStates[modelID] = .downloaded
                    case .failure(let error):
                        self?.downloadStates[modelID] = .failed(error.localizedDescription)
                    }
                    self?.downloadTasks.removeValue(forKey: modelID)
                    self?.downloadDelegates.removeValue(forKey: modelID)
                }
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        downloadDelegates[model.id] = delegate

        let request = URLRequest(url: model.sourceURL)
        let task = session.downloadTask(with: request)

        downloadTasks[modelID] = task
        task.resume()
    }

    func cancelDownload(for modelID: String) {
        downloadTasks[modelID]?.cancel()
        downloadTasks.removeValue(forKey: modelID)
        downloadDelegates.removeValue(forKey: modelID)
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

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Double) -> Void
    private let onComplete: @Sendable (Result<URL, Error>) -> Void
    private let destination: URL

    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void, onComplete: @escaping @Sendable (Result<URL, Error>) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        onComplete(.success(location))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { onComplete(.failure(error)) }
    }
}
