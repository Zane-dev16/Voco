//
//  TranslationModel.swift
//  Voco
//
//  Modular model registry — organized by provider.
//  Adding a new model is a single entry in the registry array below.
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

    /// Central registry of all downloadable models, grouped by provider.
    static let availableModels: [TranslationModel] = [

        // ==================================================================
        // Qwen
        // ==================================================================

        TranslationModel(
            id: "qwen2.5-0.5b-q8",
            displayName: "Qwen2.5 0.5B",
            description: "Ultra-compact instruction model. Q8_0 quantization for maximum quality.",
            provider: "Qwen",
            sourceURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q8_0.gguf")!,
            fileSizeBytes: 675_710_816,
            supportedLanguages: Language.allCases,
            hfRepo: "Qwen/Qwen2.5-0.5B-Instruct-GGUF",
            quantization: "Q8_0",
            config: .qwenInstruct,
            capability: .simulatorAndDevice
        ),

        TranslationModel(
            id: "qwen2.5-1.5b-q4km",
            displayName: "Qwen2.5 1.5B",
            description: "Mid-size instruction model. Q4_K_M quantization balances quality and speed.",
            provider: "Qwen",
            sourceURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
            fileSizeBytes: 1_117_320_736,
            supportedLanguages: Language.allCases,
            hfRepo: "Qwen/Qwen2.5-1.5B-Instruct-GGUF",
            quantization: "Q4_K_M",
            config: .qwenInstruct,
            capability: .deviceRecommended
        ),

        // ==================================================================
        // Meta
        // ==================================================================

        TranslationModel(
            id: "nllb-600m-q8",
            displayName: "NLLB-200 600M",
            description: "Meta's dedicated multilingual translation model. 200 languages. Q8_0 quantization.",
            provider: "Meta",
            sourceURL: URL(string: "https://huggingface.co/acceldium/nllb-200-distilled-600M-GGUF/resolve/main/nllb-600m.gguf")!,
            fileSizeBytes: 1_766_299_648,
            supportedLanguages: Language.allCases,
            hfRepo: "acceldium/nllb-200-distilled-600M-GGUF",
            quantization: "Q8_0",
            config: .nllbTranslate,
            capability: .deviceRecommended
        ),

        TranslationModel(
            id: "llama-3.2-1b-q8",
            displayName: "Llama 3.2 1B",
            description: "Meta's latest lightweight instruction model. Q8_0 for pristine output quality.",
            provider: "Meta",
            sourceURL: URL(string: "https://huggingface.co/unsloth/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q8_0.gguf")!,
            fileSizeBytes: 1_321_082_528,
            supportedLanguages: Language.allCases,
            hfRepo: "unsloth/Llama-3.2-1B-Instruct-GGUF",
            quantization: "Q8_0",
            config: .llamaInstruct,
            capability: .deviceRecommended
        ),

        // ==================================================================
        // Google
        // ==================================================================

        TranslationModel(
            id: "translategemma-4b-q2k",
            displayName: "TranslateGemma 4B",
            description: "Google's dedicated translation Gemma model. Q2_K quantization — near the 1.5 GB limit.",
            provider: "Google",
            sourceURL: URL(string: "https://huggingface.co/mradermacher/translategemma-4b-it-GGUF/resolve/main/translategemma-4b-it.Q2_K.gguf")!,
            fileSizeBytes: 1_729_180_160,
            supportedLanguages: Language.allCases,
            hfRepo: "mradermacher/translategemma-4b-it-GGUF",
            quantization: "Q2_K",
            config: .gemmaInstruct,
            capability: .deviceRecommended
        ),

        // ==================================================================
        // Tencent
        // ==================================================================

        TranslationModel(
            id: "hy-mt1.5-1.8b-2bit",
            displayName: "Hy-MT1.5 1.8B",
            description: "Dedicated translation model with 1.25-bit Sherry STQ1_0 quantization. CPU/NEON optimized. 12-language support.",
            provider: "Tencent",
            sourceURL: URL(string: "https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit.gguf")!,
            fileSizeBytes: 461_861_216,
            supportedLanguages: Language.allCases,
            hfRepo: "AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF",
            quantization: "1.25-bit STQ1_0",
            config: .hunyuanMT,
            capability: .simulatorAndDevice
        ),
    ]
}
