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

    private let inferenceService = TranslationService()
    private let downloadManager = ModelManagerService()

    /// Switch to a new model — deactivate the current one first, then activate.
    /// Centralises the deactivate→activate sequence that callers otherwise duplicate.
    func switchTo(_ model: TranslationModel) async throws {
        if activeModelID != nil {
            await deactivate()
        }
        try await activate(model)
    }

    /// Activate a local model — download if needed, then load into memory.
    func activate(_ model: TranslationModel) async throws {
        guard model.id != activeModelID else { return }

        if activeModelID != nil { await deactivate() }

        // Warn if model may exceed available RAM.
        // A 6 GB device has ~2-3 GB usable after iOS overhead.
        // Models > 3 GB risk jetsam on entry-level devices.
        if model.fileSizeBytes > 3_000_000_000 {
            let available = availableMemory()
            // Model needs at least fileSize + 1.5 GB working-set headroom
            let required = UInt64(model.fileSizeBytes) + 1_500_000_000
            if available < required {
                let requiredStr = ByteCountFormatter.string(fromByteCount: Int64(required), countStyle: .file)
                let availableStr = ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file)
                VocoLog.models.warning("[ModelLifecycle] Low memory: model \(model.displayName) requires ~\(requiredStr), only \(availableStr) available. Jetsam risk.")
            }
        }

        lifecycleState = .loading(model.id)

        do {
            let url = try await resolveModelURL(model)
            try await inferenceService.loadModel(model, at: url)
        } catch {
            // Without this, a failed download/load leaves lifecycleState stuck in
            // .loading forever and the .error case is never reached.
            activeModelID = nil
            lifecycleState = .error(error.localizedDescription)
            VocoLog.models.error("[ModelLifecycle] Failed to activate '\(model.displayName)': \(error.localizedDescription)")
            throw error
        }

        activeModelID = model.id
        lifecycleState = .ready(model.id)
    }

    /// Estimated available memory in bytes. Uses host_statistics64 for
    /// free + inactive + purgeable pages; falls back to physicalMemory.
    nonisolated private func availableMemory() -> UInt64 {
#if os(iOS)
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let available = UInt64(stats.free_count + stats.inactive_count + stats.purgeable_count)
            return available * UInt64(pageSize)
        }
        return ProcessInfo.processInfo.physicalMemory / 2
#else
        return ProcessInfo.processInfo.physicalMemory / 2
#endif
    }

    // MARK: - Private

    private func resolveModelURL(_ model: TranslationModel) async throws -> URL {
        if let url = downloadManager.localURL(for: model) { return url }
        return try await downloadManager.downloadAsync(model)
    }

    /// Unload the currently active model and free memory.
    /// Adds a short delay after unloading to allow the llama.cpp context
    /// and model to fully release their file handles before any caller
    /// attempts to delete the GGUF file from disk.
    func deactivate() async {
        lifecycleState = .unloading
        inferenceService.unloadModel()
        activeModelID = nil
        // Allow actor deallocation and llama_model_free to release file handles.
        try? await Task.sleep(nanoseconds: 500_000_000) // 500 ms
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
