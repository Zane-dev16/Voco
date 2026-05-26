//
//  ModelLifecycleManager.swift
//  Voco
//
//  Coordinates lazy model lifecycle for a multi-provider architecture.
//  Local models load on demand and unload when the user switches away.
//

import Foundation
import Observation
import OSLog

/// Tracks which provider is currently active and manages model lifecycle.
@Observable
@MainActor
final class ModelLifecycleManager {
    private(set) var activeModelID: String?
    private(set) var lifecycleState: LifecycleState = .idle

    enum LifecycleState: Equatable {
        case idle
        case loading(String)
        case ready(String)
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
    }

    // MARK: - Private

    private func resolveModelURL(_ model: TranslationModel) async throws -> URL {
        if let url = downloadManager.localURL(for: model) { return url }
        return try await downloadManager.downloadAsync(model)
    }

    /// Unload the currently active model and free memory.
    func deactivate() async {
        lifecycleState = .unloading
        inferenceService.unloadModel()
        activeModelID = nil
        lifecycleState = .idle
    }

    /// Whether a model is currently loaded and ready.
    var isModelReady: Bool {
        if case .ready = lifecycleState { return true }
        return false
    }

    /// Forward translation to the inference service.
    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        try await inferenceService.translate(text, from: source, to: target)
    }

    /// Forward streaming translation to the inference service.
    func translateStream(_ text: String, from source: String, to target: String) -> AsyncThrowingStream<String, any Error> {
        inferenceService.translateStream(text, from: source, to: target)
    }

    // MARK: - Background / lifecycle handling

    func handleDidEnterBackground() {
        VocoLog.models.info("[ModelLifecycle] App backgrounded — keeping model resident")
    }

    func handleWillEnterForeground() async {
        guard let modelID = activeModelID else { return }
        if case .ready = lifecycleState { return }
        if let model = TranslationModel.availableModels.first(where: { $0.id == modelID }) {
            try? await activate(model)
        }
    }
}
