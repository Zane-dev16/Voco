//
//  ModelConfiguration.swift
//  Voco
//
//  Per-model runtime configuration for LlamaService.
//  Each TranslationModel carries its own config so the engine
//  adapts batch size, sampling params, and context length.
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

    /// Balanced config for models ~300-400 MB. Works reliably on simulator.
    static let compact = ModelConfiguration(
        batchSize: 512,
        maxTokenCount: 512,
        threadCount: 2,
        threadCountBatch: 2,
        temperature: 0.3,
        topP: 0.9,
        topK: 40,
        seed: 1234,
        useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally. Output ONLY the translation, with no extra commentary, notes, or explanations.",
        userPromptTemplate: "Translate the following text from {source} to {target}:\n\n{text}"
    )

    /// Config for Tencent Hunyuan MT1.5 models using STQ1_0 quantization.
    /// Uses the model's native SentencePiece prompt format.
    /// Thread counts kept low (CPU/NEON path) for responsiveness and battery.
    static let hunyuanMT = ModelConfiguration(
        batchSize: 512,
        maxTokenCount: 512,
        threadCount: 2,
        threadCountBatch: 2,
        temperature: 0.3,
        topP: 0.9,
        topK: 40,
        seed: 1234,
        useGPU: false,
        systemPrompt: "",
        userPromptTemplate: "<｜hy_begin▁of▁sentence｜><｜hy_place▁holder▁no▁3｜>\n<｜hy_begin▁of▁sentence｜>\n<｜hy_User｜>Translate the following segment into {target}, without additional explanation.\n\n{text}\n<｜hy_Assistant｜>"
    )

    /// Config for models ~600-700 MB. Reduced batch size to stay within simulator RAM.
    static let standard = ModelConfiguration(
        batchSize: 256,
        maxTokenCount: 512,
        threadCount: 2,
        threadCountBatch: 2,
        temperature: 0.3,
        topP: 0.9,
        topK: 40,
        seed: 1234,
        useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally. Output ONLY the translation, with no extra commentary, notes, or explanations.",
        userPromptTemplate: "Translate the following text from {source} to {target}:\n\n{text}"
    )

    /// High-quality config for physical devices with ample RAM.
    static let quality = ModelConfiguration(
        batchSize: 2048,
        maxTokenCount: 2048,
        threadCount: 3,
        threadCountBatch: 3,
        temperature: 0.3,
        topP: 0.9,
        topK: 40,
        seed: 1234,
        useGPU: true,
        systemPrompt: "You are a professional translator. Translate the user's text accurately and naturally. Output ONLY the translation, with no extra commentary, notes, or explanations.",
        userPromptTemplate: "Translate the following text from {source} to {target}:\n\n{text}"
    )
}
