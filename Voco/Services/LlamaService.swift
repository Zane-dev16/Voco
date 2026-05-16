//
//  LlamaService.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
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
    private var currentModelID: String?

    /// Whether a model is currently loaded and ready for inference.
    var isModelLoaded: Bool {
        currentModelID != nil
    }

    /// The ID of the currently loaded model, if any.
    var loadedModelID: String? {
        currentModelID
    }

    /// Configuration for model inference.
    private let config = LlamaConfig(
        batchSize: 2048,
        maxTokenCount: 2048,
        useGPU: true
    )

    private let samplingConfig = LlamaSamplingConfig(
        temperature: 0.3,
        seed: 1234,
        topP: 0.9,
        topK: 40
    )

    init() {}

    // MARK: - Model Lifecycle

    /// Loads a GGUF model from a local file URL.
    func loadModel(at url: URL, modelID: String) async throws {
        if currentModelID == modelID { return }
        unloadModel()
        inferenceService = SwiftLlama.LlamaService(modelUrl: url, config: config)
        currentModelID = modelID
    }

    /// Releases the currently loaded model to free memory.
    func unloadModel() {
        inferenceService = nil
        currentModelID = nil
    }

    // MARK: - Translation

    /// Builds the translation prompt for the model.
    private func buildPrompt(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) -> String {
        "Translate the following text from \(sourceLanguage) to \(targetLanguage). Output ONLY the translation:\n\n\(text)"
    }

    /// Translates text using the loaded model.
    func translate(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> String {
        guard let service = inferenceService else {
            throw LlamaError.noModelLoaded
        }
        let prompt = buildPrompt(text, from: sourceLanguage, to: targetLanguage)
        let messages = [
            LlamaChatMessage(role: .system, content: "You are a professional translator. Translate the user's text accurately and naturally. Output ONLY the translated text with no explanations, notes, or additional content."),
            LlamaChatMessage(role: .user, content: prompt)
        ]
        let response = try await service.respond(to: messages, samplingConfig: samplingConfig)
        return Self.stripThinkingTags(from: response)
    }

    /// Translates text with streaming token generation.
    func translateStream(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) -> AsyncThrowingStream<String, any Error> {
        guard let service = inferenceService else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LlamaError.noModelLoaded)
            }
        }
        let prompt = buildPrompt(text, from: sourceLanguage, to: targetLanguage)
        let messages = [
            LlamaChatMessage(role: .system, content: "You are a professional translator. Translate the user's text accurately and naturally. Output ONLY the translated text with no explanations, notes, or additional content."),
            LlamaChatMessage(role: .user, content: prompt)
        ]
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = try await service.streamCompletion(of: messages, samplingConfig: samplingConfig)
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
                                // Yield accumulated text outside think blocks
                                continuation.yield(buffer)
                                buffer = ""
                            }
                        } else {
                            if let range = buffer.range(of: "</think>") {
                                buffer = String(buffer[range.upperBound...])
                                inThinkBlock = false
                                // Process any remaining text in buffer
                                if !buffer.isEmpty {
                                    if buffer.range(of: "<think>") == nil {
                                        continuation.yield(buffer)
                                        buffer = ""
                                    }
                                }
                            }
                        }
                    }
                    // Yield any remaining text
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

    // MARK: - Helpers

    /// Strips `<think>...</think>` reasoning blocks from model output.
    static func stripThinkingTags(from text: String) -> String {
        var result = text
        while let start = result.range(of: "<think>"), let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
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
