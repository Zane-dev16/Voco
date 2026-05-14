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

    var sourceLanguage: Language = .english
    var targetLanguage: Language = .spanish
    var inputText: String = ""
    var translatedText: String?
    var isTranslating = false
    var errorMessage: String?
    var showError = false

    init(modelManager: ModelManagerService) {
        self.modelManager = modelManager
    }

    func swapLanguages() {
        let temp = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = temp
        if let output = translatedText {
            inputText = output
            translatedText = nil
        }
    }

    func compatibleModel() -> TranslationModel? {
        for model in TranslationModel.availableModels {
            if model.supportedLanguages.contains(sourceLanguage) &&
                model.supportedLanguages.contains(targetLanguage) &&
                modelManager.isModelDownloaded(model) {
                return model
            }
        }
        return nil
    }

    func translate() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            translatedText = nil
            return
        }

        guard compatibleModel() != nil else {
            errorMessage = "No model downloaded for \\(sourceLanguage.displayName) to \\(targetLanguage.displayName). Download one from Models."
            showError = true
            return
        }

        isTranslating = true
        defer { isTranslating = false }

        // TODO: Wire to actual GGUF model inference via llama-cpp
        try? await Task.sleep(for: .milliseconds(500))
        translatedText = "[Translation placeholder - inference not yet wired]"
    }
}
