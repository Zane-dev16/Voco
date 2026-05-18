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
        batchSize: 512, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}"
    )

    /// Tencent Hy-MT1.5 — raw SentencePiece prompt format.
    static let hunyuanMT = ModelConfiguration(
        batchSize: 512, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: false,
        systemPrompt: "",
        userPromptTemplate: "<｜hy_begin▁of▁sentence｜><｜hy_place▁holder▁no▁3｜>\n<｜hy_begin▁of▁sentence｜>\n<｜hy_User｜>Translate the following segment into {target}, without additional explanation.\n\n{text}\n<｜hy_Assistant｜>"
    )

    /// Llama 3.2 Instruct — chat template with translation system prompt.
    static let llamaInstruct = ModelConfiguration(
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary, notes, or explanations.",
        userPromptTemplate: "{text}"
    )

    /// Qwen2.5 Instruct — ChatML format via chat template.
    static let qwenInstruct = ModelConfiguration(
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary, notes, or explanations.",
        userPromptTemplate: "{text}"
    )

    /// Gemma / TranslateGemma — Gemma turn format via chat template.
    static let gemmaInstruct = ModelConfiguration(
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary, notes, or explanations.",
        userPromptTemplate: "{text}"
    )

    /// NLLB-200 — dedicated translation model with language token prefix.
    /// NLLB requires source language token prefix: __en__ → __es__ etc.
    static let nllbTranslate = ModelConfiguration(
        batchSize: 256, maxTokenCount: 256, threadCount: 2, threadCountBatch: 2,
        temperature: 0.1, topP: 0.95, topK: 20, seed: 1234, useGPU: true,
        systemPrompt: "",
        userPromptTemplate: "__{source_code}__ __{target_code}__ {text}"
    )

    /// Medium-large models ~600 MB-1.5 GB.
    static let standard = ModelConfiguration(
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}"
    )

    /// High-quality config for devices with ≥4GB free RAM.
    static let quality = ModelConfiguration(
        batchSize: 2048, maxTokenCount: 2048, threadCount: 3, threadCountBatch: 3,
        temperature: 0.3, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}"
    )
}
