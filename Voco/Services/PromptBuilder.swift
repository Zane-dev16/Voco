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
    /// Used for models with custom prompt formats (Tencent, Gemma 4, NLLB).
    static func formatRawPrompt(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        config: ModelConfiguration
    ) -> String {
        let resolvedTarget: String
        let resolvedSource: String
        if config == .nllbTranslate {
            resolvedSource = Language.find(byCode: sourceLanguage)?.code ?? "en"
            resolvedTarget = Language.find(byDisplayOrHunyuanName: targetLanguage)?.code ?? "es"
        } else {
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

    /// Formats a raw prompt for streaming (simpler language resolution than batch translate).
    static func formatRawPromptForStream(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        config: ModelConfiguration
    ) -> String {
        let resolvedTarget = Language.find(byDisplayOrHunyuanName: targetLanguage)?.hunyuanTargetName ?? targetLanguage
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
