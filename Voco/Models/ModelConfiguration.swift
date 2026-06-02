//
//  ModelConfiguration.swift
//  Voco
//
//  Per-model runtime configuration for LlamaService.
//  Targeted changes:
//    - temperature: 0.0 (was 0.3) — greedy, prevents creative detours
//    - llamaInstruct: stopStrings ["<|im_end|>"] — fixes chat artifact leak
//    - gemmaInstruct: chatUserOnly, maxTokens=32 — fixes TranslateGemma verbosity
//    - qwenInstruct: user-message-level constraint — prevents alternatives on long text
//

import Foundation

struct ModelConfiguration: Sendable, Hashable, Equatable {
    enum PromptStrategy: Sendable, Hashable {
        case raw
        case chatWithSystem
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
    let addBos: Bool?
    let stopStrings: [String]

    // MARK: - Presets

    /// Small models ~300-500 MB. Chat template path.
    static let compact = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 512, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}",
        addBos: nil,
        stopStrings: []
    )

    /// Tencent Hy-MT1.5 — raw SentencePiece prompt format.
    static let hunyuanMT = ModelConfiguration(
        promptStrategy: .raw,
        batchSize: 512, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: false,
        systemPrompt: "",
        userPromptTemplate: "<｜hy_begin▁of▁sentence｜><｜hy_place▁holder▁no▁3｜>\n<｜hy_begin▁of▁sentence｜>\n<｜hy_User｜>Translate the following segment into {target}, without additional explanation.\n\n{text}\n<｜hy_Assistant｜>",
        addBos: nil,
        stopStrings: []
    )

    /// Llama 3.2 Instruct — chat template with translation system prompt.
    /// stopStrings: Llama 3.2 generates beyond <|im_end|> on some inputs.
    static let llamaInstruct = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary, notes, or explanations.",
        userPromptTemplate: "{text}",
        addBos: nil,
        stopStrings: ["<|im_end|>"]
    )

    /// Qwen2.5 / Qwen3.5 Instruct — ChatML format.
    /// Constraint is in the user message because Qwen follows user-level
    /// instructions more strictly than system prompts for longer text.
    /// The "Translate to X:\n\ntext\n\nTranslation:" completion format
    /// makes Qwen fill in one slot instead of producing alternatives.
    static let qwenInstruct = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a translator. Output the translation and nothing else.",
        userPromptTemplate: "Translate to {target}:\n\n{text}\n\nTranslation:",
        addBos: nil,
        stopStrings: ["\n\n"]
    )

    /// Gemma 4 (E2B, E4B) — raw prompt to bypass broken gemma4 chat template detection.
    static let gemma4Raw = ModelConfiguration(
        promptStrategy: .raw,
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: false,
        systemPrompt: "",
        userPromptTemplate: "Translate to {target}: {text}\n{target}:",
        addBos: true,
        stopStrings: ["\n\n", "\n{", "\n<"]
    )

    /// TranslateGemma 4B — chatUserOnly with tight token limit.
    /// This model produces explanations and alternatives without aggressive constraints.
    static let gemmaInstruct = ModelConfiguration(
        promptStrategy: .chatUserOnly,
        batchSize: 256, maxTokenCount: 32, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: false,
        systemPrompt: "",
        userPromptTemplate: "Translate to {target}: {text}",
        addBos: nil,
        stopStrings: ["\n\n"]
    )

    /// NLLB-200 — dedicated translation model with language token prefix.
    static let nllbTranslate = ModelConfiguration(
        promptStrategy: .raw,
        batchSize: 256, maxTokenCount: 256, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.95, topK: 20, seed: 1234, useGPU: true,
        systemPrompt: "",
        userPromptTemplate: "__{source_code}__ __{target_code}__ {text}",
        addBos: nil,
        stopStrings: []
    )

    /// Medium-large models ~600 MB-1.5 GB.
    static let standard = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}",
        addBos: nil,
        stopStrings: []
    )

    /// High-quality config for devices with ≥4GB free RAM.
    static let quality = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 2048, maxTokenCount: 2048, threadCount: 3, threadCountBatch: 3,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}",
        addBos: nil,
        stopStrings: []
    )
}
