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

    /// Monotonic request counter for streaming translations. Producers capture
    /// their epoch and only issue engine stopCompletion while still current.
    private var translationEpoch = 0

    /// Everything a raw-path producer needs, bundled to keep signatures small.
    private struct RawStreamContext {
        let engine: SwiftLlama.LlamaEngine
        let prompt: String
        let sampling: LlamaSamplingConfig
        let addBos: Bool?
        let stopStrings: [String]
        let marker: String?
        let epoch: Int
    }

    /// Everything a chat-path producer needs.
    private struct ChatStreamContext {
        let engine: SwiftLlama.LlamaEngine
        let messages: [LlamaChatMessage]
        let sampling: LlamaSamplingConfig
        let stopStrings: [String]
        let epoch: Int
    }

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

    /// Enforces the active model's supportedLanguageCodes against the request.
    /// Names arrive from the UI as registry-backed prompt names — resolve them
    /// back to registry entries and check membership. Models without a code
    /// list are unrestricted.
    private func enforceSupportedLanguages(source: String, target: String, model: TranslationModel) throws {
        guard let codes = model.supportedLanguageCodes else { return }
        for name in [source, target] {
            let lang = LanguageRegistry.shared.language(byName: name)
                ?? LanguageRegistry.shared.languages.first {
                    $0.promptName.caseInsensitiveCompare(name) == .orderedSame
                        || $0.hunyuanName?.caseInsensitiveCompare(name) == .orderedSame
                }
            guard let lang, codes.contains(lang.id) else {
                throw LlamaError.unsupportedLanguage(name)
            }
        }
    }

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

        try enforceSupportedLanguages(source: sourceLanguage, target: targetLanguage, model: model)

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

        do {
            try enforceSupportedLanguages(source: sourceLanguage, target: targetLanguage, model: model)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        // Each request gets an epoch so a stale producer's stopCompletion
        // cleanup can never cancel its successor's generation (the engine
        // already stops prior generations itself when a new request starts).
        translationEpoch += 1
        let myEpoch = translationEpoch
        let sampling = PromptBuilder.samplingConfig(from: model.config)

        if model.config.prompt.strategy == .raw {
            let rawPrompt = PromptBuilder.formatRawPromptForStream(
                text: text,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                config: model.config
            )
            return makeRawTokenStream(RawStreamContext(
                engine: engine,
                prompt: rawPrompt,
                sampling: sampling,
                addBos: model.config.prompt.addBos,
                stopStrings: model.config.prompt.stopStrings,
                marker: model.config.prompt.rawPromptMarker,
                epoch: myEpoch
            ))
        }

        let messages = PromptBuilder.buildMessages(
            text: text,
            source: sourceLanguage,
            target: targetLanguage,
            config: model.config
        )
        return makeChatTokenStream(ChatStreamContext(
            engine: engine,
            messages: messages,
            sampling: sampling,
            stopStrings: model.config.prompt.stopStrings,
            epoch: myEpoch
        ))
    }

    // MARK: - Streaming Producers

    private func makeRawTokenStream(_ context: RawStreamContext) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let key = UUID()
            let producer = Task { [weak self] in
                guard let self else { return }
                await self.runRawProducer(context: context, key: key, continuation: continuation)
            }
            // Main-actor serialization guarantees registration lands before the
            // producer body runs.
            registerProducer(producer, key: key)
            continuation.onTermination = { termination in
                guard case .cancelled = termination else { return }
                producer.cancel()
                Task { await self.stopEngineIfCurrent(context.epoch, engine: context.engine) }
            }
        }
    }

    private func makeChatTokenStream(_ context: ChatStreamContext) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let key = UUID()
            let producer = Task { [weak self] in
                guard let self else { return }
                await self.runChatProducer(context: context, key: key, continuation: continuation)
            }
            registerProducer(producer, key: key)
            continuation.onTermination = { termination in
                guard case .cancelled = termination else { return }
                producer.cancel()
                Task { await self.stopEngineIfCurrent(context.epoch, engine: context.engine) }
            }
        }
    }

    /// Stops the engine only while `epoch` is still the newest translation
    /// request. The engine stops prior generations itself when a new request
    /// initializes, so a stale producer's cleanup must be a no-op — otherwise
    /// it silently truncates its successor's output.
    private func stopEngineIfCurrent(_ epoch: Int, engine: SwiftLlama.LlamaEngine) async {
        guard epoch == translationEpoch else { return }
        await engine.stopCompletion()
    }

    private func runRawProducer(
        context: RawStreamContext,
        key: UUID,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async {
        defer { cleanupProducer(key) }
        do {
            let stream = try await context.engine.streamCompletionRaw(of: context.prompt, samplingConfig: context.sampling, addBos: context.addBos)
            var assembler = StreamChunkAssembler(stopStrings: context.stopStrings, echoMarker: context.marker)
            var stopped = false

            for try await token in stream {
                if stopped { break }
                for event in assembler.append(token) {
                    switch event {
                    case .emitted(let text):
                        if !text.isEmpty { continuation.yield(text) }
                    case .stopHit:
                        stopped = true
                    case .echoStripped, .thinkOpened, .thinkClosed:
                        break  // Raw path has no think tags; echo is internal.
                    }
                }
                if stopped { break }
            }

            // Stop engine generation once we stop consuming (EOS, stop string,
            // cancellation, or error) so llama.cpp does not keep generating into
            // a dead stream. Epoch-guarded: a superseded producer must not
            // truncate the request that replaced it.
            if !Task.isCancelled {
                await stopEngineIfCurrent(context.epoch, engine: context.engine)
            }
            let tail = assembler.flushRemaining()
            if !stopped && assembler.echoConsumed && !tail.isEmpty {
                continuation.yield(tail)
            }
            continuation.finish()
        } catch {
            await stopEngineIfCurrent(context.epoch, engine: context.engine)
            finishAfterCancellation(error, continuation: continuation)
        }
    }

    private func runChatProducer(
        context: ChatStreamContext,
        key: UUID,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async {
        defer { cleanupProducer(key) }
        do {
            let stream = try await context.engine.streamCompletion(of: context.messages, samplingConfig: context.sampling)
            var assembler = StreamChunkAssembler(stopStrings: context.stopStrings, watchesThinkTags: true)
            var stopped = false
            var hasEmitted = false  // First emission trims leading newlines.

            for try await token in stream {
                if stopped { break }
                for event in assembler.append(token) {
                    switch event {
                    case .emitted(let text):
                        // Never produced inside a think block (the assembler's
                        // watch list prevents it), so no suppression needed.
                        emit(text, suppress: false, hasEmitted: &hasEmitted, continuation: continuation)
                    case .thinkOpened(let before):
                        // Text preceding <think> predates the block — emit it.
                        emit(before, suppress: false, hasEmitted: &hasEmitted, continuation: continuation)
                    case .stopHit(let before):
                        // Stop wins even inside a think block; its text stays suppressed.
                        emit(before, suppress: assembler.inThinkBlock, hasEmitted: &hasEmitted, continuation: continuation)
                        stopped = true
                    case .echoStripped, .thinkClosed:
                        break
                    }
                }
                if stopped { break }
            }

            if !Task.isCancelled {
                await stopEngineIfCurrent(context.epoch, engine: context.engine)
            }
            if !stopped && !assembler.inThinkBlock {
                emit(assembler.flushRemaining(), suppress: false, hasEmitted: &hasEmitted, continuation: continuation)
            } else {
                _ = assembler.flushRemaining()
            }
            continuation.finish()
        } catch {
            await stopEngineIfCurrent(context.epoch, engine: context.engine)
            finishAfterCancellation(error, continuation: continuation)
        }
    }

    /// Emits text with first-emission leading-newline trimming. `suppress`
    /// drops reasoning-era text (reasoning must never reach the user), matching
    /// historical behavior.
    private func emit(
        _ rawText: String,
        suppress: Bool,
        hasEmitted: inout Bool,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) {
        var text = rawText
        if !hasEmitted {
            text = OutputProcessor.trimmingLeadingNewlines(text)
        }
        guard !text.isEmpty, !suppress else { return }
        continuation.yield(text)
        hasEmitted = true
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
