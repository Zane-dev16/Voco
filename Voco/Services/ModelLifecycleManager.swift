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
import UIKit

/// Errors that can fail model activation before any inference work begins.
enum ActivationError: LocalizedError {
    /// RAM preflight failed: loading would exceed available memory and
    /// likely trigger a jetsam kill. Surfaced through the UI alert paths.
    case insufficientMemory(modelName: String, required: UInt64, available: UInt64)

    var errorDescription: String? {
        switch self {
        case let .insufficientMemory(modelName, required, available):
            let requiredStr = ByteCountFormatter.string(fromByteCount: Int64(required), countStyle: .memory)
            let availableStr = ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .memory)
            return "\(modelName) needs about \(requiredStr) of free memory but only \(availableStr) is available. Close other apps or choose a smaller model."
        }
    }
}

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
    private let downloadManager: ModelManagerService

    /// Monotonic token distinguishing one activation/deactivation attempt from
    /// the next. Every async step re-checks it after each suspension point; a
    /// superseded attempt discards its results instead of clobbering the state
    /// written by its successor (the "user tapped B, engine holds A" race).
    /// All mutations happen on the main actor, so read-increment pairs are atomic.
    private var activationGeneration = 0
    /// nonisolated(unsafe): the token is written once on the main actor in init
    /// and only read from deinit; NSObjectProtocol isn't Sendable so a plain
    /// stored property can't be touched from nonisolated deinit under Swift 6.
    nonisolated(unsafe) private(set) var memoryWarningObserver: NSObjectProtocol?

    /// - Parameter downloadManager: Shared instance to use for resolving/downloading
    ///   model files. Injecting the app's single instance avoids a duplicate
    ///   URLSession and divergent `downloadStates` (callers that construct with no
    ///   arguments — previews and environment defaults — get their own instance).
    init(downloadManager: ModelManagerService = ModelManagerService()) {
        self.downloadManager = downloadManager
        // All stored properties are initialized above, so capturing self in the
        // escaping observer block below is valid.
        // Unload the multi-GB resident model when iOS reports memory pressure;
        // without this it stays pinned until jetsam kills the process.
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMemoryWarning()
            }
        }
    }

    deinit {
        if let token = memoryWarningObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Switch to a new model — deactivate the current one first, then activate.
    /// Centralises the deactivate→activate sequence that callers otherwise duplicate.
    /// Both halves share one generation so a newer switchTo supersedes this
    /// attempt at its next checkpoint instead of interleaving destructively.
    func switchTo(_ model: TranslationModel) async throws {
        activationGeneration += 1
        let generation = activationGeneration

        if activeModelID != nil {
            await performDeactivate(generation: generation)
            try Task.checkCancellation()
            guard generation == activationGeneration else { throw CancellationError() }
        }
        try await activate(model, generation: generation)
    }

    /// Activate a local model — download if needed, then load into memory.
    func activate(_ model: TranslationModel) async throws {
        activationGeneration += 1
        try await activate(model, generation: activationGeneration)
    }

    /// Internal activation bound to a specific generation. Throws
    /// CancellationError when superseded, leaving state management to whichever
    /// attempt holds the current generation — never writes state after losing
    /// the race.
    private func activate(_ model: TranslationModel, generation: Int) async throws {
        guard model.id != activeModelID else { return }

        if activeModelID != nil {
            await performDeactivate(generation: generation)
            try Task.checkCancellation()
            guard generation == activationGeneration else { throw CancellationError() }
        }

        // RAM preflight: the model needs at least fileSize + 1.5 GB working-set
        // headroom. Fail fast with a typed error instead of proceeding after a
        // log-only warning — jetsam would otherwise kill the app mid-load.
        let requiredMemory = UInt64(model.fileSizeBytes) + 1_500_000_000
        let availableMem = availableMemory()
        if availableMem < requiredMemory {
            let requiredStr = ByteCountFormatter.string(fromByteCount: Int64(requiredMemory), countStyle: .memory)
            let availableStr = ByteCountFormatter.string(fromByteCount: Int64(availableMem), countStyle: .memory)
            VocoLog.models.error("[ModelLifecycle] RAM preflight failed for \(model.displayName): requires ~\(requiredStr), only \(availableStr) available.")
            throw ActivationError.insufficientMemory(
                modelName: model.displayName,
                required: requiredMemory,
                available: availableMem
            )
        }

        lifecycleState = .loading(model.id)

        do {
            let url = try await resolveModelURL(model)
            try Task.checkCancellation()
            guard generation == activationGeneration else { throw CancellationError() }
            // isStillCurrent is evaluated inside loadModel's synchronous mutation
            // section, so a superseded activation can never install an engine —
            // checking here alone would leave a window across the await boundary.
            try await inferenceService.loadModel(model, at: url) { [weak self] in
                self?.isGenerationCurrent(generation) ?? false
            }
        } catch {
            // Without this, a failed download/load leaves lifecycleState stuck in
            // .loading forever and the .error case is never reached. Superseded
            // attempts skip the write entirely — their successor owns the state.
            guard generation == activationGeneration else { throw error }
            activeModelID = nil
            lifecycleState = .error(error.localizedDescription)
            VocoLog.models.error("[ModelLifecycle] Failed to activate '\(model.displayName)': \(error.localizedDescription)")
            throw error
        }

        guard generation == activationGeneration else { throw CancellationError() }
        activeModelID = model.id
        lifecycleState = .ready(model.id)
    }

    private func isGenerationCurrent(_ generation: Int) -> Bool {
        generation == activationGeneration
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
        activationGeneration += 1
        await performDeactivate(generation: activationGeneration)
    }

    /// Deactivate bound to a generation. Cancels any in-flight translation
    /// first (the streaming producer strongly retains the multi-GB engine, so
    /// skipping this means unload never actually frees memory during active
    /// generation), then unloads. The post-sleep `.idle` write only happens if
    /// this attempt still holds the current generation — otherwise a successor
    /// (e.g. the next activation) owns the state and must not be clobbered.
    private func performDeactivate(generation: Int) async {
        inferenceService.cancelInFlightTranslations()
        lifecycleState = .unloading
        inferenceService.unloadModel()
        activeModelID = nil
        // Allow actor deallocation and llama_model_free to release file handles.
        try? await Task.sleep(nanoseconds: 500_000_000) // 500 ms
        guard generation == activationGeneration else { return }
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

    /// Frees the resident model when iOS signals memory pressure.
    /// Wired to UIApplication.didReceiveMemoryWarningNotification in init.
    func handleMemoryWarning() {
        guard activeModelID != nil else { return }
        VocoLog.models.warning("[ModelLifecycle] Memory warning — unloading '\(self.activeModelID ?? "")' to relieve pressure")
        Task { await deactivate() }
    }

    func handleWillEnterForeground() async {
        guard let modelID = activeModelID else { return }
        if case .ready = lifecycleState { return }
        if let model = TranslationModel.availableModels.first(where: { $0.id == modelID }) {
            try? await activate(model)
        }
    }
}
