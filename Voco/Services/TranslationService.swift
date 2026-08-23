import Foundation
import Observation
import SwiftLlama
import OSLog

/// Manages GGUF model loading and text generation via llama.cpp using SwiftLlama.
///
/// Orchestrates PromptBuilder + OutputProcessor + LlamaEngine for translation.
@Observable
@MainActor
final class TranslationService {
    private var inferenceService: SwiftLlama.LlamaEngine?
    private var currentModel: TranslationModel?

    /// Streaming translation producers currently running. The producer Task
    /// strongly retains the LlamaEngine (via the token stream), so the lifecycle
    /// manager cancels these BEFORE unloading — otherwise the multi-GB engine
    /// stays resident until the stream drains to maxTokenCount.
    private var activeProducers: [UUID: Task<Void, Never>] = [:]

    /// Whether a model is currently loaded and ready for inference.
    var isModelLoaded: Bool {
        currentModel != nil
    }

    /// The ID of the currently loaded model, if any.
    var loadedModelID: String? {
        currentModel?.id
    }

    init() {}

    // MARK: - Model Lifecycle

    /// Loads a GGUF model from a local file URL using the model's own configuration.
    ///
    /// - Parameters:
    ///   - isStillCurrent: Evaluated inside the synchronous mutation section so a
    ///     superseded activation can never install an engine. Both this manager and
    ///     the caller are main-actor isolated and there are no awaits between the
    ///     check and the assignments, making check+mutate atomic.
    func loadModel(_ model: TranslationModel, at url: URL, isStillCurrent: @MainActor () -> Bool = { true }) async throws {
        guard isStillCurrent(), !Task.isCancelled else { throw CancellationError() }
        if currentModel?.id == model.id { return }
        unloadModel()
        defer { cleanupProducer(nil) }

        let cfg = model.config
        let llamaConfig = LlamaConfig(
            batchSize: UInt32(cfg.runtime.batchSize),
            maxTokenCount: UInt32(cfg.runtime.maxTokenCount),
            useGPU: cfg.runtime.useGPU,
            nThreads: UInt32(cfg.runtime.threadCount),
            nThreadsBatch: UInt32(cfg.runtime.threadCountBatch)
        )

        inferenceService = SwiftLlama.LlamaEngine(modelUrl: url, config: llamaConfig)
        currentModel = model
        VocoLog.translation.info("[TranslationService] Loaded model '\(model.displayName)' — threads=\(cfg.runtime.threadCount)/\(cfg.runtime.threadCountBatch)")    }

    /// Releases the currently loaded model to free memory.
    func unloadModel() {
        inferenceService = nil
        currentModel = nil
    }

    /// Cancels every in-flight streaming translation. Callers unload the engine
    /// right after; without cancelling first, the producer task keeps the engine
    /// alive and generating until EOS/maxTokenCount — burning CPU and blocking
    /// the exact memory relief the unload exists to provide.
    func cancelInFlightTranslations() {
        let producers = activeProducers.values
        activeProducers = [:]
        for producer in producers {
            producer.cancel()
        }
    }

    private func registerProducer(_ task: Task<Void, Never>, key: UUID) {
        activeProducers[key] = task
    }

    private func cleanupProducer(_ key: UUID?) {
        if let key {
            activeProducers.removeValue(forKey: key)
        } else {
            // Load/unload boundary: drop stale registry entries wholesale.
            for producer in activeProducers.values { producer.cancel() }
            activeProducers = [:]
        }
    }

    // MARK: - Translation

    /// Translates text using the loaded model with per-model prompt formatting.
    func translate(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> String {
        guard let service = inferenceService, let model = currentModel else {
            throw LlamaError.noModelLoaded
        }

        // Validate target language
        guard model.supportedLanguages.contains(where: { $0.hunyuanTargetName == targetLanguage || $0.displayName == targetLanguage }) else {
            throw LlamaError.unsupportedLanguage(targetLanguage)
        }

        let sampling = PromptBuilder.samplingConfig(from: model.config)

        let rawOutput: String
        switch model.config.prompt.strategy {
        case .raw:
            let rawPrompt = PromptBuilder.formatRawPrompt(
                text: text,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                config: model.config
            )
            var output = ""
            for try await token in try await service.streamCompletionRaw(of: rawPrompt, samplingConfig: sampling, addBos: model.config.prompt.addBos) { output += token }
            rawOutput = OutputProcessor.stripPromptEcho(output, marker: model.config.prompt.rawPromptMarker)

        case .chatUserOnly, .chatWithSystem:
            let messages = PromptBuilder.buildMessages(text: text, source: sourceLanguage, target: targetLanguage, config: model.config)
            rawOutput = OutputProcessor.stripThinkingTags(from: try await service.respond(to: messages, samplingConfig: sampling))
        }

        return OutputProcessor.truncateAtStopStrings(rawOutput, stopStrings: model.config.prompt.stopStrings)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }


    /// Translates text with streaming token generation.
    /// The returned stream is tracked by this service: the lifecycle manager
    /// calls cancelInFlightTranslations() before unloading so producers release
    /// the multi-GB engine promptly.
    func translateStream(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) -> AsyncThrowingStream<String, any Error> {
        guard let engine = inferenceService, let model = currentModel else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LlamaError.noModelLoaded)
            }
        }

        let sampling = PromptBuilder.samplingConfig(from: model.config)

        if model.config.prompt.strategy == .raw {
            let rawPrompt = PromptBuilder.formatRawPromptForStream(
                text: text,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                config: model.config
            )
            return makeRawTokenStream(
                engine: engine,
                prompt: rawPrompt,
                sampling: sampling,
                addBos: model.config.prompt.addBos,
                stopStrings: model.config.prompt.stopStrings,
                marker: model.config.prompt.rawPromptMarker
            )
        }

        let messages = PromptBuilder.buildMessages(
            text: text,
            source: sourceLanguage,
            target: targetLanguage,
            config: model.config
        )
        return makeChatTokenStream(
            engine: engine,
            messages: messages,
            sampling: sampling,
            stopStrings: model.config.prompt.stopStrings
        )
    }

    // MARK: - Streaming Producers

    private func makeRawTokenStream(
        engine: SwiftLlama.LlamaEngine,
        prompt: String,
        sampling: LlamaSamplingConfig,
        addBos: Bool?,
        stopStrings: [String],
        marker: String?
    ) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let key = UUID()
            let producer = Task { [weak self] in
                guard let self else { return }
                await self.runRawProducer(
                    key: key, engine: engine, prompt: prompt, sampling: sampling,
                    addBos: addBos, stopStrings: stopStrings, marker: marker,
                    continuation: continuation
                )
            }
            // Main-actor serialization guarantees registration lands before the
            // producer body runs.
            registerProducer(producer, key: key)
            continuation.onTermination = { termination in
                guard case .cancelled = termination else { return }
                producer.cancel()
                Task { await engine.stopCompletion() }
            }
        }
    }

    private func makeChatTokenStream(
        engine: SwiftLlama.LlamaEngine,
        messages: [LlamaChatMessage],
        sampling: LlamaSamplingConfig,
        stopStrings: [String]
    ) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let key = UUID()
            let producer = Task { [weak self] in
                guard let self else { return }
                await self.runChatProducer(
                    key: key, engine: engine, messages: messages,
                    sampling: sampling, stopStrings: stopStrings,
                    continuation: continuation
                )
            }
            registerProducer(producer, key: key)
            continuation.onTermination = { termination in
                guard case .cancelled = termination else { return }
                producer.cancel()
                Task { await engine.stopCompletion() }
            }
        }
    }

    private func runRawProducer(
        key: UUID,
        engine: SwiftLlama.LlamaEngine,
        prompt: String,
        sampling: LlamaSamplingConfig,
        addBos: Bool?,
        stopStrings: [String],
        marker: String?,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async {
        defer { cleanupProducer(key) }
        do {
            let stream = try await engine.streamCompletionRaw(of: prompt, samplingConfig: sampling, addBos: addBos)
            var buffer = ""
            var stopped = false
            var markerFound = marker == nil  // If no marker, start yielding immediately

            for try await token in stream {
                if stopped { break }
                buffer += token

                // Look for rawPromptMarker to detect end of prompt echo
                if !markerFound {
                    guard let (stripped, foundNow) = Self.stripThroughEchoMarker(buffer, marker: marker) else {
                        // Marker not seen yet — keep accumulating, bounded so a
                        // missing marker can't grow the buffer without limit.
                        if buffer.count > 500 {
                            buffer = String(buffer.suffix(200))
                        }
                        continue
                    }
                    buffer = stripped
                    markerFound = foundNow
                }

                // Check stop strings (only after marker is found)
                if let range = Self.firstStopRange(in: buffer, stopStrings: stopStrings) {
                    let before = String(buffer[..<range.lowerBound])
                    if !before.isEmpty { continuation.yield(before) }
                    stopped = true
                }
                if stopped { break }

                if buffer.count >= 4, Self.isSafeToFlush(buffer, stopStrings: stopStrings) {
                    continuation.yield(buffer)
                    buffer = ""
                }
            }

            // Stop engine generation once we stop consuming (EOS, stop string,
            // cancellation, or error) so llama.cpp does not keep generating into
            // a dead stream.
            await engine.stopCompletion()
            if !buffer.isEmpty && !stopped && markerFound {
                continuation.yield(buffer)
            }
            continuation.finish()
        } catch {
            await engine.stopCompletion()
            finishAfterCancellation(error, continuation: continuation)
        }
    }

    private func runChatProducer(
        key: UUID,
        engine: SwiftLlama.LlamaEngine,
        messages: [LlamaChatMessage],
        sampling: LlamaSamplingConfig,
        stopStrings: [String],
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async {
        defer { cleanupProducer(key) }
        do {
            let stream = try await engine.streamCompletion(of: messages, samplingConfig: sampling)
            var buffer = ""
            var inThinkBlock = false
            var stopped = false
            var hasYielded = false  // Track whether we've yielded real content

            for try await token in stream {
                if stopped { break }
                buffer += token

                if let range = Self.firstStopRange(in: buffer, stopStrings: stopStrings) {
                    let before = String(buffer[..<range.lowerBound])
                    let out = hasYielded ? before : OutputProcessor.trimmingLeadingNewlines(before)
                    if !out.isEmpty && !inThinkBlock {
                        continuation.yield(out)
                        hasYielded = true
                    }
                    stopped = true
                }
                if stopped { break }

                if !inThinkBlock {
                    if let range = buffer.range(of: "<think>") {
                        let before = String(buffer[..<range.lowerBound])
                        let out = hasYielded ? before : OutputProcessor.trimmingLeadingNewlines(before)
                        if !out.isEmpty {
                            continuation.yield(out)
                            hasYielded = true
                        }
                        buffer = ""
                        inThinkBlock = true
                    } else if buffer.count > 20 {
                        let out = hasYielded ? buffer : OutputProcessor.trimmingLeadingNewlines(buffer)
                        if !out.isEmpty {
                            continuation.yield(out)
                            hasYielded = true
                        }
                        buffer = ""
                    }
                } else if let range = buffer.range(of: "</think>") {
                    buffer = String(buffer[range.upperBound...])
                    inThinkBlock = false
                    if !buffer.isEmpty && buffer.range(of: "<think>") == nil {
                        continuation.yield(buffer)
                        buffer = ""
                    }
                }
            }

            // Stop engine generation once we stop consuming — see raw path.
            await engine.stopCompletion()
            if !buffer.isEmpty && !inThinkBlock && !stopped {
                let out = hasYielded ? buffer : OutputProcessor.trimmingLeadingNewlines(buffer)
                if !out.isEmpty {
                    continuation.yield(out)
                }
            }
            continuation.finish()
        } catch {
            await engine.stopCompletion()
            finishAfterCancellation(error, continuation: continuation)
        }
    }

    /// Deliberate cancellation ends with a plain finish so consumers don't
    /// present an intentional cancel as a failure.
    private func finishAfterCancellation(
        _ error: Error,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) {
        if error is CancellationError {
            continuation.finish()
        } else {
            continuation.finish(throwing: error)
        }
    }

    // MARK: - Stream Buffer Helpers

    /// Strips the buffer through the end of the prompt-echo marker.
    /// Returns nil when the marker hasn't arrived yet; otherwise returns the
    /// content after the marker and `true`.
    private static func stripThroughEchoMarker(_ buffer: String, marker: String?) -> (String, Bool)? {
        guard let marker, let range = buffer.range(of: marker) else { return nil }
        return (String(buffer[range.upperBound...]), true)
    }

    /// First stop-string occurrence in the buffer, if any.
    private static func firstStopRange(in buffer: String, stopStrings: [String]) -> Range<String.Index>? {
        guard !stopStrings.isEmpty else { return nil }
        for stop in stopStrings where buffer.contains(stop) {
            if let range = buffer.range(of: stop) {
                return range
            }
        }
        return nil
    }

    /// True when flushing the whole buffer cannot split a partially-received
    /// stop string across a chunk boundary.
    private static func isSafeToFlush(_ buffer: String, stopStrings: [String]) -> Bool {
        !stopStrings.contains(where: { stop in
            stop.hasPrefix(buffer) || buffer.hasPrefix(stop)
        })
    }
}

// MARK: - Errors

enum LlamaError: LocalizedError {
    case noModelLoaded
    case unsupportedLanguage(String)

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No model loaded. Download and select a model first."
        case .unsupportedLanguage(let lang):
            return "The language \"\(lang)\" is not supported by the current model."
        }
    }
}
