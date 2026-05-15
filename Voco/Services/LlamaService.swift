//
//  LlamaService.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import Foundation
import Observation

#if canImport(LocalLLMClient) && !targetEnvironment(simulator)
import LocalLLMClient
import LocalLLMClientLlama
#endif

/// Manages GGUF model loading and text generation via llama.cpp.
///
/// On device: wraps `LocalLLMClient` for real inference.
/// On simulator: provides stub for UI testing.
@Observable
@MainActor
final class LlamaService {
    #if canImport(LocalLLMClient) && !targetEnvironment(simulator)
    private var session: LLMSession?
    private var currentModelID: String?
    #else
    private var currentModelID: String?
    #endif

    /// Whether a model is currently loaded and ready for inference.
    var isModelLoaded: Bool {
        currentModelID != nil
    }

    /// The ID of the currently loaded model, if any.
    var loadedModelID: String? {
        currentModelID
    }

    #if canImport(LocalLLMClient) && !targetEnvironment(simulator)
    /// Parameters for model inference.
    private let parameters: LlamaClient.Parameter

    init(parameters: LlamaClient.Parameter = .init(
        context: 2048,
        temperature: 0.3,
        topK: 40,
        topP: 0.9
    )) {
        self.parameters = parameters
    }
    #else
    /// On simulator, parameters are ignored (stub only).
    init(parameters: Void = ()) { _ = parameters }
    #endif

    // MARK: - Model Lifecycle

    /// Loads a GGUF model from a local file URL.
    func loadModel(at url: URL, modelID: String) async throws {
        if currentModelID == modelID { return }

        unloadModel()

        #if canImport(LocalLLMClient) && !targetEnvironment(simulator)
        let localModel = LLMSession.LocalModel.llama(
            url: url,
            parameter: parameters
        )
        let newSession = LLMSession(model: localModel)
        newSession.messages = [
            .system("You are a professional translator. Translate the user's text accurately and naturally. Output ONLY the translated text with no explanations, notes, or additional content.")
        ]
        try await newSession.prewarm()
        self.session = newSession
        #endif

        self.currentModelID = modelID
    }

    /// Releases the currently loaded model to free memory.
    func unloadModel() {
        #if canImport(LocalLLMClient) && !targetEnvironment(simulator)
        session = nil
        #endif
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
        guard currentModelID != nil else {
            throw LlamaError.noModelLoaded
        }

        #if canImport(LocalLLMClient) && !targetEnvironment(simulator)
        guard let session else {
            throw LlamaError.noModelLoaded
        }
        // Reset to system prompt only — each translation is stateless
        session.messages = [
            .system("You are a professional translator. Translate the user's text accurately and naturally. Output ONLY the translated text with no explanations, notes, or additional content.")
        ]
        let prompt = buildPrompt(text, from: sourceLanguage, to: targetLanguage)
        let response = try await session.respond(to: prompt)
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        // Simulator stub — return placeholder
        return "[Simulator stub: \(sourceLanguage) → \(targetLanguage)] \(text)"
        #endif
    }

    /// Translates text with streaming token generation.
    func translateStream(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) -> AsyncThrowingStream<String, any Error> {
        guard currentModelID != nil else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LlamaError.noModelLoaded)
            }
        }

        #if canImport(LocalLLMClient) && !targetEnvironment(simulator)
        guard let session else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LlamaError.noModelLoaded)
            }
        }
        let prompt = buildPrompt(text, from: sourceLanguage, to: targetLanguage)
        return session.streamResponse(to: prompt)
        #else
        // Simulator stub — yield placeholder tokens
        return AsyncThrowingStream { continuation in
            Task {
                let stub = "[Simulator: \(sourceLanguage) → \(targetLanguage)] \(text)"
                for char in stub {
                    continuation.yield(String(char))
                    try await Task.sleep(for: .milliseconds(20))
                }
                continuation.finish()
            }
        }
        #endif
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
