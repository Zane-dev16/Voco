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

        // Warn if model may exceed available RAM.
        // A 6 GB device has ~2-3 GB usable after iOS overhead.
        // Models > 3 GB risk jetsam on entry-level devices.
        if model.fileSizeBytes > 3_000_000_000 {
            let available = availableMemory()
            // Model needs at least fileSize + 1.5 GB working-set headroom
            let required = UInt64(model.fileSizeBytes) + 1_500_000_000
            if available < required {
                VocoLog.models.warning("[ModelLifecycle] Low memory: model \(model.displayName) requires ~\(ByteCountFormatter.string(fromByteCount: Int64(required), countStyle: .file)), only \(ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file)) available. Jetsam risk.")
            }
        }

        lifecycleState = .loading(model.id)

        let url = try await resolveModelURL(model)
        try await inferenceService.loadModel(model, at: url)

        activeModelID = model.id
        lifecycleState = .ready(model.id)
    }

    /// Estimated available memory in bytes. Uses task_vm_info on device;
    /// falls back to physicalMemory on simulator.
    nonisolated private func availableMemory() -> UInt64 {
#if os(iOS)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            // Free + inactive + purgeable memory
            let available = info.free_count + info.inactive_count + info.purgeable_count
            return UInt64(available) * UInt64(vm_page_size)
        }
        // Fallback: assume 50% of physical memory is available
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
