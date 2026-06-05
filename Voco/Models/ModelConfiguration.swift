//
//  ModelConfiguration.swift
//  Voco
//
//  Per-model runtime configuration for LlamaService.
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
    let rawPromptMarker: String?

    // MARK: - Presets

    /// Small models ~300-500 MB.
    static let compact = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 512, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}",
        addBos: nil,
        stopStrings: [],
        rawPromptMarker: nil
    )

    /// Tencent Hy-MT1.5 — raw SentencePiece prompt format.
    static let hunyuanMT = ModelConfiguration(
        promptStrategy: .raw,
        batchSize: 512, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: false,
        systemPrompt: "",
        userPromptTemplate: "<｜hy_begin▁of▁sentence｜><｜hy_place▁holder▁no▁3｜>\n<｜hy_begin▁of▁sentence｜>\n<｜hy_User｜>Translate the following segment into {target}, without additional explanation.\n\n{text}\n<｜hy_Assistant｜>",
        addBos: nil,
        stopStrings: [],
        rawPromptMarker: nil
    )

    /// Llama 3.2 Instruct.
    static let llamaInstruct = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary, notes, or explanations.",
        userPromptTemplate: "{text}",
        addBos: nil,
        stopStrings: ["</think>"],
        rawPromptMarker: nil
    )

    /// Qwen2.5 / Qwen3.5 Instruct — ChatML format.
    /// One-line directive format with <|im_end|> stop.
    static let qwenInstruct = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 256, maxTokenCount: 256, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a translator. Output the translation and nothing else.",
        userPromptTemplate: "Translate to {target}: {text}",
        addBos: nil,
        stopStrings: ["<|im_end|>"],
        rawPromptMarker: nil
    )

    /// Gemma 4 (E2B, E4B) — raw prompt with addBos override.
    /// BPE tokenizer's shouldAddBos() returns false; force BOS via addBos: true.
    static let gemma4Raw = ModelConfiguration(
        promptStrategy: .raw,
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: false,
        systemPrompt: "",
        userPromptTemplate: "Translate to {target}: {text}\n{target}:",
        addBos: true,
        stopStrings: [],
        rawPromptMarker: nil
    )

    /// TranslateGemma 4B — chatUserOnly with tight token limit.
    static let gemmaInstruct = ModelConfiguration(
        promptStrategy: .chatUserOnly,
        batchSize: 256, maxTokenCount: 32, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: false,
        systemPrompt: "",
        userPromptTemplate: "Translate to {target}: {text}",
        addBos: nil,
        stopStrings: ["\n\n"],
        rawPromptMarker: nil
    )

    /// NLLB-200 — dedicated translation model.
    static let nllbTranslate = ModelConfiguration(
        promptStrategy: .raw,
        batchSize: 256, maxTokenCount: 256, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.95, topK: 20, seed: 1234, useGPU: true,
        systemPrompt: "",
        userPromptTemplate: "__{source_code}__ __{target_code}__ {text}",
        addBos: nil,
        stopStrings: [],
        rawPromptMarker: nil
    )

    /// Medium-large models ~600 MB-1.5 GB.
    static let standard = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}",
        addBos: nil,
        stopStrings: [],
        rawPromptMarker: nil
    )

    /// High-quality config for devices with ≥4GB free RAM.
    static let quality = ModelConfiguration(
        promptStrategy: .chatWithSystem,
        batchSize: 2048, maxTokenCount: 2048, threadCount: 3, threadCountBatch: 3,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}",
        addBos: nil,
        stopStrings: [],
        rawPromptMarker: nil
    )
}
