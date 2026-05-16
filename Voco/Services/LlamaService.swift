//
//  LlamaService.swift
//  Voco
//
//  GGUF model loading and inference via SwiftLlama.
//  Per-model configuration is read from TranslationModel.config.
//

import Foundation
import Observation
import SwiftLlama

/// Manages GGUF model loading and text generation via llama.cpp using SwiftLlama.
///
/// Works on both device and simulator by using prebuilt llama.cpp xcframework binaries.
@Observable
@MainActor
final class LlamaService {
    private var inferenceService: SwiftLlama.LlamaService?
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
            batchSize: UInt32(cfg.batchSize),
            maxTokenCount: UInt32(cfg.maxTokenCount),
            useGPU: cfg.useGPU
        )

        inferenceService = SwiftLlama.LlamaService(modelUrl: url, config: llamaConfig)
        currentModel = model
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
        let messages = buildMessages(
            text: text,
            source: sourceLanguage,
            target: targetLanguage,
            config: model.config
        )
        let sampling = samplingConfig(from: model.config)
        let response = try await service.respond(to: messages, samplingConfig: sampling)
        return Self.stripThinkingTags(from: response)
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
        let messages = buildMessages(
            text: text,
            source: sourceLanguage,
            target: targetLanguage,
            config: model.config
        )
        let sampling = samplingConfig(from: model.config)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = try await service.streamCompletion(of: messages, samplingConfig: sampling)
                    var buffer = ""
                    var inThinkBlock = false
                    for try await token in stream {
                        buffer += token
                        if !inThinkBlock {
                            if let range = buffer.range(of: "<think>") {
                                let before = String(buffer[..<range.lowerBound])
                                if !before.isEmpty {
                                    continuation.yield(before)
                                }
                                buffer = ""
                                inThinkBlock = true
                            } else if buffer.count > 20 {
                                continuation.yield(buffer)
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
                    if !buffer.isEmpty && !inThinkBlock {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func buildMessages(
        text: String,
        source: String,
        target: String,
        config: ModelConfiguration
    ) -> [LlamaChatMessage] {
        let userPrompt = config.userPromptTemplate
            .replacingOccurrences(of: "{source}", with: source)
            .replacingOccurrences(of: "{target}", with: target)
            .replacingOccurrences(of: "{text}", with: text)

        return [
            LlamaChatMessage(role: .system, content: config.systemPrompt),
            LlamaChatMessage(role: .user, content: userPrompt)
        ]
    }

    private func samplingConfig(from config: ModelConfiguration) -> LlamaSamplingConfig {
        LlamaSamplingConfig(
            temperature: config.temperature,
            seed: config.seed,
            topP: config.topP,
            topK: config.topK
        )
    }

    /// Strips `<think>...</think>` reasoning blocks from model output.
    static func stripThinkingTags(from text: String) -> String {
        var result = text
        while let start = result.range(of: "<think>"),
              let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum LlamaError: LocalizedError {
    case noModelLoaded

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No model loaded. Download and select a model first."
        }
    }
}
