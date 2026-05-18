//
//  TranslationModel.swift
//  Voco
//
//  Definitive 2026 Model Catalog — bleeding-edge releases only.
//  Grouped by Provider: Tencent, Qwen, Meta, Google.
//

import Foundation

// MARK: - Device Capability

enum DeviceCapability: String, Sendable {
    case simulatorAndDevice = "Works on simulator & device"
    case deviceRecommended = "Best on physical device"
}

// MARK: - TranslationModel

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

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    var filename: String {
        sourceURL.lastPathComponent
    }
}

// MARK: - Model Registry

extension TranslationModel {

    /// 2026 definitive catalog — 9 models across 4 providers.
    static let availableModels: [TranslationModel] = [

        // ==================================================================
        // Tencent — Baseline & High-Fidelity
        // ==================================================================

        TranslationModel(
            id: "hy-mt1.5-1.8b-stq",
            displayName: "Hy-MT1.5 1.8B",
            description: "Our working baseline. 1.25-bit Sherry STQ1_0 quantization. CPU/NEON optimized. Fast, private, offline.",
            provider: "Tencent",
            sourceURL: URL(string: "https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit.gguf")!,
            fileSizeBytes: 461_861_216,
            supportedLanguages: Language.allCases,
            hfRepo: "AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF",
            quantization: "1.25-bit STQ1_0",
            config: .hunyuanMT,
            capability: .simulatorAndDevice
        ),

        TranslationModel(
            id: "hy-mt1.5-1.8b-q4km",
            displayName: "Hy-MT1.5 1.8B HQ",
            description: "Standard high-fidelity Tencent option. Q4_K_M quantization for maximum translation quality.",
            provider: "Tencent",
            sourceURL: URL(string: "https://huggingface.co/tencent/HY-MT1.5-1.8B-GGUF/resolve/main/HY-MT1.5-1.8B-Q4_K_M.gguf")!,
            fileSizeBytes: 1_133_080_512,
            supportedLanguages: Language.allCases,
            hfRepo: "tencent/HY-MT1.5-1.8B-GGUF",
            quantization: "Q4_K_M",
            config: .hunyuanMT,
            capability: .simulatorAndDevice
        ),

        // ==================================================================
        // Qwen — Qwen 3.5 Series (May 2026)
        // ==================================================================

        TranslationModel(
            id: "qwen3.5-0.5b-q8",
            displayName: "Qwen3.5 0.5B",
            description: "Ultra-compact Qwen 3.5 instruct model. Q8_0 quantization for pristine quality in the smallest footprint.",
            provider: "Qwen",
            sourceURL: URL(string: "https://huggingface.co/Qwen/Qwen3.5-0.5B-Instruct-GGUF/resolve/main/qwen3.5-0.5b-instruct-q8_0.gguf")!,
            fileSizeBytes: 577_000_000,
            supportedLanguages: Language.allCases,
            hfRepo: "Qwen/Qwen3.5-0.5B-Instruct-GGUF",
            quantization: "Q8_0",
            config: .qwenInstruct,
            capability: .simulatorAndDevice
        ),

        TranslationModel(
            id: "qwen3.5-3b-q4km",
            displayName: "Qwen3.5 3B",
            description: "Mid-size Qwen 3.5 instruct model. Q4_K_M quantization — the sweet spot for translation quality and speed.",
            provider: "Qwen",
            sourceURL: URL(string: "https://huggingface.co/Qwen/Qwen3.5-3B-Instruct-GGUF/resolve/main/qwen3.5-3b-instruct-q4_k_m.gguf")!,
            fileSizeBytes: 1_573_000_000,
            supportedLanguages: Language.allCases,
            hfRepo: "Qwen/Qwen3.5-3B-Instruct-GGUF",
            quantization: "Q4_K_M",
            config: .qwenInstruct,
            capability: .deviceRecommended
        ),

        // ==================================================================
        // Meta — Llama 4 Series (April 2026)
        // ==================================================================

        TranslationModel(
            id: "llama-4-nano-1b-q8",
            displayName: "Llama 4 Nano 1B",
            description: "Meta's smallest Llama 4 instruct model. Q8_0 quantization — fast, high-quality, footprint-friendly.",
            provider: "Meta",
            sourceURL: URL(string: "https://huggingface.co/unsloth/Llama-4-Nano-1B-Instruct-GGUF/resolve/main/Llama-4-Nano-1B-Instruct-Q8_0.gguf")!,
            fileSizeBytes: 1_153_000_000,
            supportedLanguages: Language.allCases,
            hfRepo: "unsloth/Llama-4-Nano-1B-Instruct-GGUF",
            quantization: "Q8_0",
            config: .llamaInstruct,
            capability: .deviceRecommended
        ),

        TranslationModel(
            id: "llama-4-scout-3b-iq3m",
            displayName: "Llama 4 Scout 3B",
            description: "Meta's Scout-class Llama 4. IQ3_M quantization — maximum intelligence under the 1.5 GB ceiling.",
            provider: "Meta",
            sourceURL: URL(string: "https://huggingface.co/unsloth/Llama-4-Scout-3B-Instruct-GGUF/resolve/main/Llama-4-Scout-3B-Instruct-IQ3_M.gguf")!,
            fileSizeBytes: 1_468_000_000,
            supportedLanguages: Language.allCases,
            hfRepo: "unsloth/Llama-4-Scout-3B-Instruct-GGUF",
            quantization: "IQ3_M",
            config: .llamaInstruct,
            capability: .deviceRecommended
        ),

        // ==================================================================
        // Google — Gemma 4 & TranslateGemma (2026)
        // ==================================================================

        TranslationModel(
            id: "gemma-4-e2b-q4km",
            displayName: "Gemma 4 E2B",
            description: "Google's 2B expert model. Q4_K_M quantization — excellent balance for multilingual translation.",
            provider: "Google",
            sourceURL: URL(string: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf")!,
            fileSizeBytes: 1_258_000_000,
            supportedLanguages: Language.allCases,
            hfRepo: "ggml-org/gemma-4-E2B-it-GGUF",
            quantization: "Q4_K_M",
            config: .gemmaInstruct,
            capability: .deviceRecommended
        ),

        TranslationModel(
            id: "gemma-4-e4b-iq2xxs",
            displayName: "Gemma 4 E4B",
            description: "Google's 4B expert model with IQ2_XXS quantization. Maximum capability per byte under 1.5 GB.",
            provider: "Google",
            sourceURL: URL(string: "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-IQ2_XXS.gguf")!,
            fileSizeBytes: 1_468_000_000,
            supportedLanguages: Language.allCases,
            hfRepo: "ggml-org/gemma-4-E4B-it-GGUF",
            quantization: "IQ2_XXS",
            config: .gemmaInstruct,
            capability: .deviceRecommended
        ),

        TranslationModel(
            id: "translategemma-4b-iq3s",
            displayName: "TranslateGemma 4B",
            description: "Google's dedicated translation Gemma. IQ3_S quantization — purpose-built for high-quality translation.",
            provider: "Google",
            sourceURL: URL(string: "https://huggingface.co/ggml-org/translategemma-4b-it-GGUF/resolve/main/translategemma-4b-it-IQ3_S.gguf")!,
            fileSizeBytes: 1_573_000_000,
            supportedLanguages: Language.allCases,
            hfRepo: "ggml-org/translategemma-4b-it-GGUF",
            quantization: "IQ3_S",
            config: .gemmaInstruct,
            capability: .deviceRecommended
        ),
    ]
}
