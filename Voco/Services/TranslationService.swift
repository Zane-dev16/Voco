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
    func loadModel(_ model: TranslationModel, at url: URL) async throws {
        if currentModel?.id == model.id { return }
        unloadModel()

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
        VocoLog.translation.info("[TranslationService] Loaded model '\(model.displayName)' — threads=\(cfg.runtime.threadCount)/\(cfg.runtime.threadCountBatch)")
    }

    /// Releases the currently loaded model to free memory.
    func unloadModel() {
        inferenceService = nil
        currentModel = nil
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
    func translateStream(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) -> AsyncThrowingStream<String, any Error> {
        guard let service = inferenceService, let model = currentModel else {
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

            let stopStrings = model.config.prompt.stopStrings
            let marker = model.config.prompt.rawPromptMarker
            return AsyncThrowingStream { continuation in
                let producer = Task {
                    do {
                        let stream = try await service.streamCompletionRaw(of: rawPrompt, samplingConfig: sampling, addBos: model.config.prompt.addBos)
                        var buffer = ""
                        var stopped = false
                        var markerFound = marker == nil  // If no marker, start yielding immediately
                        for try await token in stream {
                            if stopped { break }
                            buffer += token

                            // Look for rawPromptMarker to detect end of prompt echo
                            if !markerFound {
                                if let m = marker, let range = buffer.range(of: m) {
                                    // Found marker — yield everything after it
                                    let afterMarker = String(buffer[range.upperBound...])
                                    buffer = afterMarker
                                    markerFound = true
                                } else {
                                    // Keep accumulating but don't yield yet
                                    // Trim buffer to avoid unbounded growth (marker shouldn't be >200 chars from end)
                                    if buffer.count > 500 {
                                        buffer = String(buffer.suffix(200))
                                    }
                                    continue
                                }
                            }

                            // Check stop strings (only after marker is found)
                            if !stopStrings.isEmpty {
                                for stop in stopStrings {
                                    if buffer.contains(stop) {
                                        if let range = buffer.range(of: stop) {
                                            let before = String(buffer[..<range.lowerBound])
                                            if !before.isEmpty {
                                                continuation.yield(before)
                                            }
                                        }
                                        stopped = true
                                        break
                                    }
                                }
                            }
                            if stopped { break }
                            // Flush every few characters
                            if buffer.count >= 4 {
                                let safeToFlush = !stopStrings.contains(where: { stop in
                                    stop.hasPrefix(buffer) || buffer.hasPrefix(stop)
                                })
                                if safeToFlush {
                                    continuation.yield(buffer)
                                    buffer = ""
                                }
                            }
                        }
                        // Stop engine generation once we stop consuming (EOS, stop string,
                        // or error) so llama.cpp does not keep generating into a dead stream.
                        await service.stopCompletion()
                        if !buffer.isEmpty && !stopped && markerFound {
                            continuation.yield(buffer)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                // Forward consumer cancellation to the producer task AND the inference
                // engine — without this, cancelling a translation leaves llama.cpp
                // generating tokens until EOS/maxTokenCount, burning CPU and battery.
                continuation.onTermination = { termination in
                    guard case .cancelled = termination else { return }
                    producer.cancel()
                    Task { await service.stopCompletion() }
                }
            }
        }

        // Standard chat-template path
        let messages = PromptBuilder.buildMessages(
            text: text,
            source: sourceLanguage,
            target: targetLanguage,
            config: model.config
        )

        let stopStrings = model.config.prompt.stopStrings
        return AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    let stream = try await service.streamCompletion(of: messages, samplingConfig: sampling)
                    var buffer = ""
                    var inThinkBlock = false
                    var stopped = false
                    var hasYielded = false  // Track whether we've yielded real content
                    for try await token in stream {
                        if stopped { break }
                        buffer += token
                        // Check stop strings
                        if !stopStrings.isEmpty {
                            for stop in stopStrings {
                                if buffer.contains(stop) {
                                    if let range = buffer.range(of: stop) {
                                        let before = String(buffer[..<range.lowerBound])
                                        let out = hasYielded ? before : OutputProcessor.trimmingLeadingNewlines(before)
                                        if !out.isEmpty && !inThinkBlock {
                                            continuation.yield(out)
                                            hasYielded = true
                                        }
                                    }
                                    stopped = true
                                    break
                                }
                            }
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
                        } else {
                            if let range = buffer.range(of: "</think>") {
                                buffer = String(buffer[range.upperBound...])
                                inThinkBlock = false
                                if !buffer.isEmpty && buffer.range(of: "<think>") == nil {
                                    continuation.yield(buffer)
                                    buffer = ""
                                }
                            }
                        }
                    }
                    // Stop engine generation once we stop consuming (EOS, stop string,
                    // or error) so llama.cpp does not keep generating into a dead stream.
                    await service.stopCompletion()
                    if !buffer.isEmpty && !inThinkBlock && !stopped {
                        let out = hasYielded ? buffer : OutputProcessor.trimmingLeadingNewlines(buffer)
                        if !out.isEmpty {
                            continuation.yield(out)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Forward consumer cancellation to the producer task AND the inference
            // engine — see the raw-path comment above.
            continuation.onTermination = { termination in
                guard case .cancelled = termination else { return }
                producer.cancel()
                Task { await service.stopCompletion() }
            }
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
