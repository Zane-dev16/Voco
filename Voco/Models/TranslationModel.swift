//
//  TranslationModel.swift
//  Voco
//
//  Definitive 2026 Model Catalog — all models hosted at zanish-labs on HF.
//  10 models across 4 providers.

import Foundation

enum DeviceCapability: String, Sendable {
    case simulatorAndDevice = "Works on simulator & device"
    case deviceRecommended = "Best on physical device"
}

struct TranslationModel: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let provider: String
    let sourceURL: URL
    let fileSizeBytes: Int64
    let supportedLanguages: [Language]
    let hfRepo: String
    let quantization: String
    let config: ModelConfiguration
    let capability: DeviceCapability
    let parameterCount: String

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
    var filename: String { sourceURL.lastPathComponent }
}

extension TranslationModel {
    static let availableModels: [TranslationModel] = [
        // Tencent
        TranslationModel(id: "hy-mt1.5-1.8b-stq", displayName: "Hy-MT1.5 1.8B", description: "1.25-bit Sherry STQ1_0. CPU/NEON optimized.", provider: "Tencent", sourceURL: URL(string: "https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit.gguf")!, fileSizeBytes: 461_861_216, supportedLanguages: Language.allCases, hfRepo: "AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF", quantization: "1.25-bit STQ1_0", config: .hunyuanMT, capability: .simulatorAndDevice, parameterCount: "1.8B"),
        TranslationModel(id: "hy-mt2-1.8b-stq", displayName: "Hy-MT2 1.8B", description: "1.25-bit STQ1_0. Next-gen 33-language translation.", provider: "Tencent", sourceURL: URL(string: "https://huggingface.co/AngelSlim/Hy-MT2-1.8B-1.25Bit-GGUF/resolve/main/Hy-MT2-1.8B-1.25Bit.gguf")!, fileSizeBytes: 456_714_240, supportedLanguages: Language.allCases, hfRepo: "AngelSlim/Hy-MT2-1.8B-1.25Bit-GGUF", quantization: "1.25-bit STQ1_0", config: .hunyuanMT, capability: .simulatorAndDevice, parameterCount: "1.8B"),
        TranslationModel(id: "hy-mt1.5-1.8b-q4km", displayName: "Hy-MT1.5 1.8B HQ", description: "Q4_K_M quantization for max quality.", provider: "Tencent", sourceURL: URL(string: "https://huggingface.co/tencent/HY-MT1.5-1.8B-GGUF/resolve/main/HY-MT1.5-1.8B-Q4_K_M.gguf")!, fileSizeBytes: 1_133_080_512, supportedLanguages: Language.allCases, hfRepo: "tencent/HY-MT1.5-1.8B-GGUF", quantization: "Q4_K_M", config: .hunyuanMT, capability: .simulatorAndDevice, parameterCount: "1.8B"),
        // Qwen
        TranslationModel(id: "qwen3.5-0.8b-q8", displayName: "Qwen3.5 0.8B", description: "Q8_0 — 795 MB, all devices.", provider: "Qwen", sourceURL: URL(string: "https://huggingface.co/zanish-labs/qwen3.5-0.8b-q8_0-gguf/resolve/main/qwen3.5-0.8b-q8_0.gguf")!, fileSizeBytes: 833_000_000, supportedLanguages: Language.allCases, hfRepo: "zanish-labs/qwen3.5-0.8b-q8_0-gguf", quantization: "Q8_0", config: .qwenInstruct, capability: .simulatorAndDevice, parameterCount: "0.8B"),
        TranslationModel(id: "qwen3.5-2b-q4km", displayName: "Qwen3.5 2B", description: "Q4_K_M — 1.3 GB, sweet spot.", provider: "Qwen", sourceURL: URL(string: "https://huggingface.co/zanish-labs/qwen3.5-2b-q4_k_m-gguf/resolve/main/qwen3.5-2b-q4_k_m.gguf")!, fileSizeBytes: 1_360_000_000, supportedLanguages: Language.allCases, hfRepo: "zanish-labs/qwen3.5-2b-q4_k_m-gguf", quantization: "Q4_K_M", config: .qwenInstruct, capability: .deviceRecommended, parameterCount: "2B"),
        TranslationModel(id: "qwen3.5-4b-q4km", displayName: "Qwen3.5 4B", description: "Q4_K_M — 2.6 GB, max Qwen quality.", provider: "Qwen", sourceURL: URL(string: "https://huggingface.co/zanish-labs/qwen3.5-4b-q4_k_m-gguf/resolve/main/qwen3.5-4b-q4_k_m.gguf")!, fileSizeBytes: 2_726_000_000, supportedLanguages: Language.allCases, hfRepo: "zanish-labs/qwen3.5-4b-q4_k_m-gguf", quantization: "Q4_K_M", config: .qwenInstruct, capability: .deviceRecommended, parameterCount: "4B"),
        // Meta
        TranslationModel(id: "llama-3.2-1b-q8", displayName: "Llama 3.2 1B", description: "Q8_0 — 1.3 GB, fast.", provider: "Meta", sourceURL: URL(string: "https://huggingface.co/zanish-labs/Llama-3.2-1B-Instruct-Q8_0-gguf/resolve/main/Llama-3.2-1B-Instruct-Q8_0.gguf")!, fileSizeBytes: 1_385_000_000, supportedLanguages: Language.allCases, hfRepo: "zanish-labs/Llama-3.2-1B-Instruct-Q8_0-gguf", quantization: "Q8_0", config: .llamaInstruct, capability: .deviceRecommended, parameterCount: "1B"),
        TranslationModel(id: "llama-3.2-3b-iq3m", displayName: "Llama 3.2 3B", description: "IQ3_M — 1.5 GB.", provider: "Meta", sourceURL: URL(string: "https://huggingface.co/zanish-labs/Llama-3.2-3B-Instruct-IQ3_M-gguf/resolve/main/Llama-3.2-3B-Instruct-IQ3_M.gguf")!, fileSizeBytes: 1_609_000_000, supportedLanguages: Language.allCases, hfRepo: "zanish-labs/Llama-3.2-3B-Instruct-IQ3_M-gguf", quantization: "IQ3_M", config: .llamaInstruct, capability: .deviceRecommended, parameterCount: "3B"),
        // Google
        TranslationModel(id: "gemma-4-e2b-q4km", displayName: "Gemma 4 E2B", description: "Q4_K_M — 3.2 GB.", provider: "Google", sourceURL: URL(string: "https://huggingface.co/zanish-labs/gemma-4-E2B-it-Q4_K_M-gguf/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf")!, fileSizeBytes: 3_411_000_000, supportedLanguages: Language.allCases, hfRepo: "zanish-labs/gemma-4-E2B-it-Q4_K_M-gguf", quantization: "Q4_K_M", config: .gemmaInstruct, capability: .deviceRecommended, parameterCount: "2B"),
        TranslationModel(id: "gemma-4-e4b-q4km", displayName: "Gemma 4 E4B", description: "Q4_K_M — 5.0 GB.", provider: "Google", sourceURL: URL(string: "https://huggingface.co/zanish-labs/gemma-4-E4B-it-Q4_K_M-gguf/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf")!, fileSizeBytes: 5_360_000_000, supportedLanguages: Language.allCases, hfRepo: "zanish-labs/gemma-4-E4B-it-Q4_K_M-gguf", quantization: "Q4_K_M", config: .gemmaInstruct, capability: .deviceRecommended, parameterCount: "4B"),
        TranslationModel(id: "translategemma-4b-q2k", displayName: "TranslateGemma 4B", description: "Q2_K — 1.7 GB, translation specialist.", provider: "Google", sourceURL: URL(string: "https://huggingface.co/zanish-labs/translategemma-4b-it-Q2_K-gguf/resolve/main/translategemma-4b-it-Q2_K.gguf")!, fileSizeBytes: 1_817_000_000, supportedLanguages: Language.allCases, hfRepo: "zanish-labs/translategemma-4b-it-Q2_K-gguf", quantization: "Q2_K", config: .gemmaInstruct, capability: .deviceRecommended, parameterCount: "4B"),
    ]
}
