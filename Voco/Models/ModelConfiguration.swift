//
//  ModelConfiguration.swift
//  Voco
//
//  Per-model runtime configuration for TranslationService.
//  Split into prompt and runtime concerns so adding a model
//  only requires understanding the relevant concern.
//

import Foundation

struct ModelConfiguration: Sendable, Hashable, Equatable {

    // MARK: - Nested Types

    struct PromptConfig: Sendable, Hashable {
        let strategy: PromptStrategy
        let systemPrompt: String
        let userPromptTemplate: String
        let addBos: Bool?
        let stopStrings: [String]
        let rawPromptMarker: String?

        init(strategy: PromptStrategy, systemPrompt: String, userPromptTemplate: String, addBos: Bool? = nil, stopStrings: [String] = [], rawPromptMarker: String? = nil) {
            self.strategy = strategy
            self.systemPrompt = systemPrompt
            self.userPromptTemplate = userPromptTemplate
            self.addBos = addBos
            self.stopStrings = stopStrings
            self.rawPromptMarker = rawPromptMarker
        }
    }

    struct RuntimeConfig: Sendable, Hashable {
        let batchSize: Int
        let maxTokenCount: Int
        let threadCount: Int
        let threadCountBatch: Int
        let temperature: Float
        let topP: Float
        let topK: Int32
        let seed: UInt32
        let useGPU: Bool

        init(batchSize: Int, maxTokenCount: Int, threadCount: Int = 2, threadCountBatch: Int = 2,
             temperature: Float = 0.0, topP: Float = 0.9, topK: Int32 = 40, seed: UInt32 = 1234, useGPU: Bool = true) {
            self.batchSize = batchSize
            self.maxTokenCount = maxTokenCount
            self.threadCount = threadCount
            self.threadCountBatch = threadCountBatch
            self.temperature = temperature
            self.topP = topP
            self.topK = topK
            self.seed = seed
            self.useGPU = useGPU
        }
    }

    enum PromptStrategy: Sendable, Hashable {
        case raw
        case chatWithSystem
        case chatUserOnly
    }

    // MARK: - Properties

    let prompt: PromptConfig
    let runtime: RuntimeConfig

    // MARK: - Initializers

    init(prompt: PromptConfig, runtime: RuntimeConfig) {
        self.prompt = prompt
        self.runtime = runtime
    }

    init(promptStrategy: PromptStrategy,
         batchSize: Int, maxTokenCount: Int,
         threadCount: Int = 2, threadCountBatch: Int = 2,
         temperature: Float = 0.0, topP: Float = 0.9, topK: Int32 = 40, seed: UInt32 = 1234, useGPU: Bool = true,
         systemPrompt: String, userPromptTemplate: String,
         addBos: Bool? = nil, stopStrings: [String] = [], rawPromptMarker: String? = nil) {
        self.prompt = PromptConfig(strategy: promptStrategy, systemPrompt: systemPrompt,
                                    userPromptTemplate: userPromptTemplate, addBos: addBos,
                                    stopStrings: stopStrings, rawPromptMarker: rawPromptMarker)
        self.runtime = RuntimeConfig(batchSize: batchSize, maxTokenCount: maxTokenCount,
                                      threadCount: threadCount, threadCountBatch: threadCountBatch,
                                      temperature: temperature, topP: topP, topK: topK, seed: seed, useGPU: useGPU)
    }

    // MARK: - Presets

    private static let defaultRuntime = RuntimeConfig(
        batchSize: 512, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: true
    )

    private static let mediumRuntime = RuntimeConfig(
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: true
    )

    private static let cpuOnlyMedium = RuntimeConfig(
        batchSize: 256, maxTokenCount: 512, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: false
    )

    private static let translateGemmaRuntime = RuntimeConfig(
        batchSize: 256, maxTokenCount: 48, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: false
    )

    private static let nllbRuntime = RuntimeConfig(
        batchSize: 256, maxTokenCount: 256, threadCount: 2, threadCountBatch: 2,
        temperature: 0.0, topP: 0.95, topK: 20, seed: 1234, useGPU: true
    )

    /// Tencent Hy-MT1.5 — raw SentencePiece prompt format.
    static let hunyuanMT = ModelConfiguration(prompt: PromptConfig(
        strategy: .raw,
        systemPrompt: "",
        userPromptTemplate: "<｜hy_begin▁of▁sentence｜><｜hy_place▁holder▁no▁3｜>\n<｜hy_begin▁of▁sentence｜>\n<｜hy_User｜>Translate the following segment into {target}, without additional explanation.\n\n{text}\n<｜hy_Assistant｜>"
    ), runtime: cpuOnlyMedium)

    /// Llama 3.2 Instruct.
    static let llamaInstruct = ModelConfiguration(prompt: PromptConfig(
        strategy: .chatWithSystem,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary, notes, or explanations.",
        userPromptTemplate: "{text}",
        stopStrings: ["<|eot_id|>"]
    ), runtime: mediumRuntime)

    /// Qwen2.5 / Qwen3.5 0.8B & 2B Instruct — ChatML format.
    static let qwenInstruct = ModelConfiguration(prompt: PromptConfig(
        strategy: .chatWithSystem,
        systemPrompt: "You are a translator. Output the translation and nothing else.",
        userPromptTemplate: "Translate to {target}: {text}",
        stopStrings: ["<|im_end|>"]
    ), runtime: mediumRuntime)

    /// Qwen3.5 4B Instruct — thinking model.
    /// Thinking suppressed via </think> prefix in system prompt.
    static let qwen4bInstruct = ModelConfiguration(prompt: PromptConfig(
        strategy: .chatWithSystem,
        systemPrompt: "<think>\n</think>\nYou are a translator. Output only the translated text, nothing else.",
        userPromptTemplate: "Translate to {target}: {text}",
        stopStrings: ["<|im_end|>"]
    ), runtime: mediumRuntime)

    /// Gemma 4 (E2B, E4B) — raw prompt with addBos override.
    /// BPE tokenizer's shouldAddBos() returns false; force BOS via addBos: true.
    static let gemma4Raw = ModelConfiguration(prompt: PromptConfig(
        strategy: .raw,
        systemPrompt: "",
        userPromptTemplate: "Translate to {target}: {text}\n{target}:",
        addBos: true,
        stopStrings: ["\nTranslate to", "\n\n"]
    ), runtime: cpuOnlyMedium)

    /// TranslateGemma 4B — chatUserOnly, translation specialist.
    static let gemmaInstruct = ModelConfiguration(prompt: PromptConfig(
        strategy: .chatUserOnly,
        systemPrompt: "",
        userPromptTemplate: "Translate to {target}. Output only the translation, no explanations.\n{text}",
        stopStrings: ["\n\n"]
    ), runtime: translateGemmaRuntime)

    /// NLLB-200 — dedicated translation model.
    static let nllbTranslate = ModelConfiguration(prompt: PromptConfig(
        strategy: .raw,
        systemPrompt: "",
        userPromptTemplate: "__{source_code}__ __{target_code}__ {text}"
    ), runtime: nllbRuntime)

    // MARK: - Standalone runtime presets

    /// Small models ~300-500 MB.
    static let compact = ModelConfiguration(prompt: PromptConfig(
        strategy: .chatWithSystem,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}"
    ), runtime: defaultRuntime)

    /// Medium-large models ~600 MB-1.5 GB.
    static let standard = ModelConfiguration(prompt: PromptConfig(
        strategy: .chatWithSystem,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}"
    ), runtime: mediumRuntime)

    /// High-quality config for devices with ≥4GB free RAM.
    static let quality = ModelConfiguration(prompt: PromptConfig(
        strategy: .chatWithSystem,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally into {target}. Output ONLY the translation, with no extra commentary.",
        userPromptTemplate: "{text}"
    ), runtime: RuntimeConfig(
        batchSize: 2048, maxTokenCount: 2048, threadCount: 3, threadCountBatch: 3,
        temperature: 0.0, topP: 0.9, topK: 40, seed: 1234, useGPU: true
    ))
}
