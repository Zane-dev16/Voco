//
//  LlamaService.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import Foundation
import LocalLLMClient
import LocalLLMClientLlama
import Observation

/// Manages GGUF model loading and text generation via llama.cpp.
///
/// Wraps `LocalLLMClient` to provide a clean interface for
/// on-device translation inference. Models are loaded from
/// local GGUF files managed by `ModelManagerService`.
@Observable
@MainActor
final class LlamaService {
    private var session: LLMSession?
    private var currentModelID: String?

    /// Whether a model is currently loaded and ready for inference.
    var isModelLoaded: Bool {
        session != nil
    }

    /// The ID of the currently loaded model, if any.
    var loadedModelID: String? {
        currentModelID
    }

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

    // MARK: - Model Lifecycle

    /// Loads a GGUF model from a local file URL.
    ///
    /// If a different model is already loaded, it is released first.
    /// - Parameters:
    ///   - url: File URL pointing to the `.gguf` file.
    ///   - modelID: A string identifier for tracking which model is loaded.
    func loadModel(at url: URL, modelID: String) async throws {
        // Skip if same model already loaded
        if currentModelID == modelID, session != nil {
            return
        }

        // Release previous model
        unloadModel()

        let localModel = LLMSession.LocalModel.llama(
            url: url,
            parameter: parameters
        )
        let newSession = LLMSession(model: localModel)
        newSession.messages = [
            .system("You are a professional translator. Translate the user's text accurately and naturally. Output ONLY the translated text with no explanations, notes, or additional content.")
        ]

        // Prewarm to load model into memory
        try await newSession.prewarm()

        self.session = newSession
        self.currentModelID = modelID
    }

    /// Releases the currently loaded model to free memory.
    func unloadModel() {
        session = nil
        currentModelID = nil
    }

    // MARK: - Translation

    /// Translates text using the loaded model.
    ///
    /// - Parameters:
    ///   - text: The source text to translate.
    ///   - sourceLanguage: The source language name (e.g. "English").
    ///   - targetLanguage: The target language name (e.g. "Spanish").
    /// - Returns: The translated text.
    func translate(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> String {
        guard let session else {
            throw LlamaError.noModelLoaded
        }

        let prompt = "Translate the following text from \(sourceLanguage) to \(targetLanguage). Output ONLY the translation:\n\n\(text)"

        let response = try await session.respond(to: prompt)
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Translates text with streaming token generation.
    ///
    /// Returns an `AsyncThrowingStream` that yields translation tokens
    /// as they are generated, enabling real-time UI updates.
    ///
    /// - Parameters:
    ///   - text: The source text to translate.
    ///   - sourceLanguage: The source language name (e.g. "English").
    ///   - targetLanguage: The target language name (e.g. "Spanish").
    /// - Returns: A stream of translated text chunks.
    func translateStream(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) -> AsyncThrowingStream<String, any Error> {
        guard let session else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LlamaError.noModelLoaded)
            }
        }

        let prompt = "Translate the following text from \(sourceLanguage) to \(targetLanguage). Output ONLY the translation:\n\n\(text)"

        return session.streamResponse(to: prompt)
    }
}

// MARK: - Errors

enum LlamaError: LocalizedError {
    case noModelLoaded
    case modelLoadFailed(String)
    case translationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No model loaded. Download and select a model first."
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .translationFailed(let reason):
            return "Translation failed: \(reason)"
        }
    }
}
