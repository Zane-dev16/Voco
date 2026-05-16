//
//  TranslationModel.swift
//  Voco
//
//  Modular model registry. Adding a new model is a single entry
//  in the registry array below — no other files need changing.
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

    /// Central registry of all downloadable models.
    /// To add a model, append a new `TranslationModel(...)` entry here.
    static let availableModels: [TranslationModel] = [

        // ------------------------------------------------------------------
        // 1. Alibaba Qwen3 0.6B — verified working on simulator
        // ------------------------------------------------------------------
        TranslationModel(
            id: "qwen3-0.6b-q4km",
            displayName: "Qwen3 0.6B",
            description: "Ultra-compact multilingual model. Fastest and most reliable on any device.",
            provider: "Alibaba",
            sourceURL: URL(string: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf")!,
            fileSizeBytes: 396_705_472,
            supportedLanguages: [.english, .spanish, .french, .german, .italian, .portuguese, .chinese, .japanese, .korean, .arabic, .hindi, .russian],
            hfRepo: "unsloth/Qwen3-0.6B-GGUF",
            quantization: "Q4_K_M",
            config: .compact,
            capability: .simulatorAndDevice
        ),

        // ------------------------------------------------------------------
        // 2. Tencent Hunyuan 0.5B — small enough for simulator
        // ------------------------------------------------------------------
        TranslationModel(
            id: "hunyuan-0.5b-q3km",
            displayName: "Tencent Hunyuan 0.5B",
            description: "Tencent's compact instruction-tuned model. Good quality for its size.",
            provider: "Tencent",
            sourceURL: URL(string: "https://huggingface.co/bartowski/tencent_Hunyuan-0.5B-Instruct-GGUF/resolve/main/tencent_Hunyuan-0.5B-Instruct-Q3_K_M.gguf")!,
            fileSizeBytes: 307_669_856,
            supportedLanguages: Language.allCases,
            hfRepo: "bartowski/tencent_Hunyuan-0.5B-Instruct-GGUF",
            quantization: "Q3_K_M",
            config: .compact,
            capability: .simulatorAndDevice
        ),

        // ------------------------------------------------------------------
        // 3. Google Gemma 3 1B — larger, best on physical device
        // ------------------------------------------------------------------
        TranslationModel(
            id: "gemma-3-1b-q2k",
            displayName: "Google Gemma 3 1B",
            description: "Google's latest lightweight model. High quality but requires more RAM. Use on physical device for best experience.",
            provider: "Google",
            sourceURL: URL(string: "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q2_K.gguf")!,
            fileSizeBytes: 689_814_560,
            supportedLanguages: [.english, .spanish, .french, .german, .italian, .portuguese, .chinese, .japanese, .korean, .russian],
            hfRepo: "unsloth/gemma-3-1b-it-GGUF",
            quantization: "Q2_K",
            config: .standard,
            capability: .deviceRecommended
        ),
        // ------------------------------------------------------------------
        // 4. Tencent Hy-MT1.5 1.8B 1.25bit — dedicated translation model
        // ------------------------------------------------------------------
        TranslationModel(
            id: "hy-mt1.5-1.8b-1.25bit",
            displayName: "Tencent Hy-MT1.5 1.8B",
            description: "Dedicated translation model from Tencent at aggressive 1.25-bit quantization. Good balance of size and quality for multilingual translation.",
            provider: "Tencent",
            sourceURL: URL(string: "https://huggingface.co/tencent/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit.gguf")!,
            fileSizeBytes: 461_861_216,
            supportedLanguages: Language.allCases,
            hfRepo: "tencent/Hy-MT1.5-1.8B-1.25bit-GGUF",
            quantization: "1.25bit",
            config: .compact,
            capability: .simulatorAndDevice
        )
    ]
}
