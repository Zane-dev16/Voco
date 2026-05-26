//
//  ModelConfiguration.swift
//  Voco
//
//  Per-model runtime configuration for LlamaService.
//  Each TranslationModel carries its own config so the engine
//  adapts batch size, sampling params, context length, and prompt format.
//

import Foundation

struct ModelConfiguration: Sendable, Hashable, Equatable {
    enum PromptStrategy: Sendable, Hashable {
        /// Raw prompt — bypasses chat template. Tokenizer-specific tokens included in template.
        case raw
        /// Chat template with system + user messages.
        case chatWithSystem
        /// Chat template with user-only message (system role confuses this model family).
        case chatUserOnly
    }

    let promptStrategy: PromptStrategy
    let batchSize: Int
    let maxTokenCount: Int
    let threadCount: Int
    let threadCountBatch: Int
    let temperature: Float
    let topP: Float
    let topK: Int32
    let seed: UInt32
    let useGPU: Bool
    let systemPrompt: String
    let userPromptTemplate: String

    // MARK: - Presets

    /// Small models ~300-500 MB. Chat template path.
    static let compact = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 512, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}"
    )

    /// Tencent Hy-MT1.5 — raw SentencePiece prompt format.
    static let hunyuanMT = ModelConfiguration(
        promptStrategy: .raw,
        batchSize: 512, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: false,
        systemPrompt: "",
        userPromptTemplate: "<｜hy_begin▁of▁sentence｜><｜hy_place▁holder▁no▁3｜>\n<｜hy_begin▁of▁sentence｜>\n<｜hy_User｜>Translate the following segment into {target}, without additional explanation.\n\n{text}\n<｜hy_Assistant｜>"
    )

    /// Llama 3.2 Instruct — chat template with translation system prompt.
    static let llamaInstruct = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary, notes, or explanations.",
        userPromptTemplate: "{text}"
    )

    /// Qwen2.5 Instruct — ChatML format via chat template.
    static let qwenInstruct = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary, notes, or explanations.",
        userPromptTemplate: "{text}"
    )

    /// Gemma 4 (E2B, E4B) — raw prompt to bypass broken gemma4 chat template detection.
    /// These GGUFs lack a tokenizer.chat_template; the fallback works for gemma3
    /// (TranslateGemma) but fails silently for gemma4 architecture.
    static let gemma4Raw = ModelConfiguration(
        promptStrategy: .raw,
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: false,
        systemPrompt: "",
        userPromptTemplate: "<start_of_turn>user\nTranslate to {target}: {text}<end_of_turn>\n<start_of_turn>model\n"
    )

    /// Gemma 3 / TranslateGemma — chat template path. No system prompt (Gemma merges poorly).
    static let gemmaInstruct = ModelConfiguration(
        promptStrategy: .chatUserOnly,
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: false,
        systemPrompt: "",
        userPromptTemplate: "Translate to {target}: {text}"
    )

    /// NLLB-200 — dedicated translation model with language token prefix.
    /// NLLB requires source language token prefix: __en__ → __es__ etc.
    static let nllbTranslate = ModelConfiguration(
        promptStrategy: .raw,
        batchSize: 256, maxTokenCount: 256, threadCount: 2, threadCountBatch: 2,
        temperature: 0.1, topP: 0.95, topK: 20, seed: 1234, useGPU: true,
        systemPrompt: "",
        userPromptTemplate: "__{source_code}__ __{target_code}__ {text}"
    )

    /// Medium-large models ~600 MB-1.5 GB.
    static let standard = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}"
    )

    /// High-quality config for devices with ≥4GB free RAM.
    static let quality = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 2048, maxTokenCount: 2048, threadCount: 3, threadCountBatch: 3,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}"
    )
}
