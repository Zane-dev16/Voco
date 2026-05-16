//
//  TranslationViewModel.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import Foundation
import Observation

@Observable
@MainActor
final class TranslationViewModel {
    private let modelManager: ModelManagerService
    private let llamaService: LlamaService
    private var translationTask: Task<Void, Never>?

    var sourceLanguage: Language = .english
    var targetLanguage: Language = .spanish
    var inputText: String = ""
    var translatedText: String?
    var isTranslating = false
    var isModelLoading = false
    var modelLoadProgress: String?
    var errorMessage: String?
    var showError = false

    /// The currently active model for translation, if any.
    var activeModel: TranslationModel? {
        compatibleModel()
    }

    /// Whether a compatible model is downloaded and ready.
    var hasCompatibleModel: Bool {
        compatibleModel() != nil
    }

    init(
        modelManager: ModelManagerService,
        llamaService: LlamaService,
    ) {
        self.modelManager = modelManager
        self.llamaService = llamaService
    }

    // MARK: - Actions

    func swapLanguages() {
        let temp = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = temp
        if let output = translatedText {
            inputText = output
            translatedText = nil
        }
    }

    /// Starts translation as a managed task.
    func startTranslation() {
        translationTask?.cancel()
        translationTask = Task { await translate() }
    }

    /// Loads the compatible model and runs translation with streaming.
    private func translate() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            translatedText = nil
            return
        }

        guard let model = compatibleModel() else {
            errorMessage = "No model downloaded for \(sourceLanguage.displayName) to \(targetLanguage.displayName). Download one from Models."
            showError = true
            return
        }

        isTranslating = true
        translatedText = ""
        defer { isTranslating = false }

        do {
            // Load model if not already loaded
            if llamaService.loadedModelID != model.id {
                isModelLoading = true
                modelLoadProgress = "Loading \(model.displayName)..."
                defer { isModelLoading = false; modelLoadProgress = nil }

                guard let modelURL = modelManager.localURL(for: model) else {
                    errorMessage = "Model file not found. Please re-download."
                    showError = true
                    return  // defer will reset isModelLoading
                }

                try await llamaService.loadModel(model, at: modelURL)
            }

            // Stream translation
            let stream = llamaService.translateStream(
                inputText,
                from: sourceLanguage.displayName,
                to: targetLanguage.displayName
            )

            for try await token in stream {
                // Check for cancellation
                if Task.isCancelled { break }
                translatedText = (translatedText ?? "") + token
            }
        } catch {
            // Non-cancellation error — reset model loading state and report
            isModelLoading = false
            modelLoadProgress = nil
            errorMessage = error.localizedDescription
            showError = true
            translatedText = nil
        }
    }

    /// Cancels any in-progress translation.
    func cancelTranslation() {
        translationTask?.cancel()
        translationTask = nil
    }

    /// Unloads the current model to free memory.
    func unloadModel() {
        llamaService.unloadModel()
    }

    // MARK: - Private

    private func compatibleModel() -> TranslationModel? {
        for model in TranslationModel.availableModels {
            if model.supportedLanguages.contains(sourceLanguage) &&
                model.supportedLanguages.contains(targetLanguage) &&
                modelManager.isModelDownloaded(model) {
                return model
            }
        }
        return nil
    }
}
