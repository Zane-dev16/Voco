//
//  ModelLifecycleManager.swift
//  Voco
//
//  Coordinates lazy model lifecycle for a multi-provider architecture.
//  Local models load on demand and unload when the user switches away.
//

import Foundation
import Observation

/// Tracks which provider is currently active and manages model lifecycle.
@Observable
@MainActor
final class ModelLifecycleManager {
    private(set) var activeModelID: String?
    private(set) var lifecycleState: LifecycleState = .idle

    enum LifecycleState: Equatable {
        case idle
        case loading(String)      // model ID being loaded
        case ready(String)        // model ID loaded and ready
        case unloading
        case error(String)
    }

    private let inferenceService = LlamaService()
    private let downloadManager = ModelManagerService()

    /// Activate a local model — download if needed, then load into memory.
    func activate(_ model: TranslationModel) async throws {
        guard model.id != activeModelID else { return }

        if activeModelID != nil { await deactivate() }
        lifecycleState = .loading(model.id)

        let url = try await resolveModelURL(model)
        try await inferenceService.loadModel(model, at: url)

        activeModelID = model.id
        lifecycleState = .ready(model.id)
        print("[ModelLifecycle] Model activated — \(model.displayName)")
        NSLog("[ModelLifecycle] Model activated — \(model.displayName)")
    }

    // MARK: - Private

    private func resolveModelURL(_ model: TranslationModel) async throws -> URL {
        // Already on disk
        if let url = downloadManager.localURL(for: model) { return url }
        // State says downloaded but file missing — should not happen, but check
        if case .downloaded = downloadManager.downloadStates[model.id] {
            guard let url = downloadManager.localURL(for: model) else {
                lifecycleState = .error("Download completed but file not found")
                throw LlamaError.noModelLoaded
            }
            return url
        }
        // Start download and wait
        downloadManager.download(model)
        try await waitForDownload(model)
        guard let url = downloadManager.localURL(for: model) else {
            lifecycleState = .error("Download timeout")
            throw LlamaError.noModelLoaded
        }
        return url
    }

    /// Unload the currently active model and free memory.
    func deactivate() async {
        lifecycleState = .unloading
        inferenceService.unloadModel()
        activeModelID = nil
        lifecycleState = .idle
        print("[ModelLifecycle] Model deactivated — memory freed")
        NSLog("[ModelLifecycle] Model deactivated — memory freed")
    }

    /// Whether a model is currently loaded and ready.
    var isModelReady: Bool {
        if case .ready = lifecycleState { return true }
        return false
    }

    /// Forward translation to the inference service.
    func translate(
        _ text: String,
        from source: String,
        to target: String
    ) async throws -> String {
        try await inferenceService.translate(text, from: source, to: target)
    }

    /// Forward streaming translation to the inference service.
    func translateStream(
        _ text: String,
        from source: String,
        to target: String
    ) -> AsyncThrowingStream<String, any Error> {
        inferenceService.translateStream(text, from: source, to: target)
    }

    // MARK: - Background / lifecycle handling

    /// Call when the app enters background.
    /// Keeps the model loaded for fast resume but notes the state.
    func handleDidEnterBackground() {
        // Current policy: keep model loaded for quick resume.
        // The system may still evict us under memory pressure.
        print("[ModelLifecycle] App backgrounded — keeping model resident")
    }

    /// Call when the app returns to foreground.
    /// Verifies the model is still loaded; reloads if needed.
    func handleWillEnterForeground() async {
        guard let modelID = activeModelID else { return }
        if case .ready = lifecycleState { return }

        // Model was evicted or never loaded — attempt reload
        print("[ModelLifecycle] Foreground — reloading model \(modelID)")
        if let model = TranslationModel.availableModels.first(where: { $0.id == modelID }) {
            try? await activate(model)
        }
    }

    // MARK: - Private helpers

    private func waitForDownload(_ model: TranslationModel) async throws {
        var attempts = 0
        while attempts < 600 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let _ = downloadManager.localURL(for: model) { return }
            if case .failed(let msg) = downloadManager.downloadStates[model.id] {
                throw LlamaError.noModelLoaded
            }
            attempts += 1
        }
        throw LlamaError.noModelLoaded
    }
}
