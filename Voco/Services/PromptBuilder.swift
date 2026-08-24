//
//  PromptBuilder.swift
//  Voco
//
//  Pure-function prompt construction for translation models.
//  No state, no I/O — testable without loading a model.
//

import Foundation
import SwiftLlama

enum PromptBuilder {

    // MARK: - Chat Messages

    /// Builds chat messages for the chat-template path (chatWithSystem / chatUserOnly).
    /// Delegates to the model's chat template via LlamaEngine.
    static func buildMessages(
        text: String,
        source: String,
        target: String,
        config: ModelConfiguration
    ) -> [LlamaChatMessage] {
        let userPrompt = config.prompt.userPromptTemplate
            .replacingOccurrences(of: "{source}", with: source)
            .replacingOccurrences(of: "{target}", with: target)
            .replacingOccurrences(of: "{text}", with: text)
        // Gemma-family models: chatUserOnly — no system role
        if config.prompt.strategy == .chatUserOnly {
            return [LlamaChatMessage(role: .user, content: userPrompt)]
        }
        let sys = config.prompt.systemPrompt.replacingOccurrences(of: "{target}", with: target)
        return [LlamaChatMessage(role: .system, content: sys), LlamaChatMessage(role: .user, content: userPrompt)]
    }

    // MARK: - Raw Prompts

    /// Formats a raw prompt by substituting language and text placeholders.
    /// Used for models with custom prompt formats (Tencent, Gemma 4).
    /// Uses LanguageRegistry for model-specific language name resolution.
    static func formatRawPrompt(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        config: ModelConfiguration,
        registry: LanguageRegistry? = nil
    ) -> String {
        let resolvedTarget: String
        let resolvedSource: String

        if let registry = registry,
           let sourceLang = registry.language(byName: sourceLanguage),
           let targetLang = registry.language(byName: targetLanguage) {
            // Use LanguageRegistry for model-specific resolution
            resolvedSource = registry.sourceLanguageName(for: sourceLang, config: config)
            resolvedTarget = registry.languageName(for: targetLang, config: config)
        } else {
            // Fallback: legacy Language enum lookup
            resolvedSource = sourceLanguage
            resolvedTarget = Language.find(byDisplayOrHunyuanName: targetLanguage)?.hunyuanTargetName ?? targetLanguage
        }
        return config.prompt.userPromptTemplate
            .replacingOccurrences(of: "{source}", with: resolvedSource)
            .replacingOccurrences(of: "{source_code}", with: resolvedSource)
            .replacingOccurrences(of: "{target}", with: resolvedTarget)
            .replacingOccurrences(of: "{target_code}", with: resolvedTarget)
            .replacingOccurrences(of: "{text}", with: text)
    }

    /// Formats a raw prompt for streaming. Mirrors formatRawPrompt's registry
    /// resolution so both raw paths name languages consistently (R7-06) — the
    /// legacy 12-case enum lookup silently rewrote "Chinese (Simplified)" to
    /// "Chinese" while passing Traditional Chinese/Cantonese through verbatim.
    static func formatRawPromptForStream(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        config: ModelConfiguration,
        registry: LanguageRegistry? = nil
    ) -> String {
        let resolvedTarget: String
        if let registry,
           let targetLang = registry.language(byName: targetLanguage) {
            resolvedTarget = registry.languageName(for: targetLang, config: config)
        } else {
            resolvedTarget = targetLanguage
        }
        return config.prompt.userPromptTemplate
            .replacingOccurrences(of: "{source}", with: sourceLanguage)
            .replacingOccurrences(of: "{target}", with: resolvedTarget)
            .replacingOccurrences(of: "{text}", with: text)
    }

    // MARK: - Sampling

    /// Converts ModelConfiguration sampling parameters to LlamaSamplingConfig.
    static func samplingConfig(from config: ModelConfiguration) -> LlamaSamplingConfig {
        LlamaSamplingConfig(
            temperature: config.runtime.temperature,
            seed: config.runtime.seed,
            topP: config.runtime.topP,
            topK: config.runtime.topK
        )
    }
}
