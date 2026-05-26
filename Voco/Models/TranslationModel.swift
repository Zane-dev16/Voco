//
//  TranslationModel.swift
//  Voco
//
//  Definitive 2026 Model Catalog — compliance metadata and download info.
//  Single source of truth for the Models & Licenses screen and download pipeline.
//

import Foundation

enum DeviceCapability: String, Sendable {
    case simulatorAndDevice = "Works on simulator & device"
    case deviceRecommended = "Best on physical device"
}

struct TranslationModel: Identifiable, Hashable, Sendable {
    // ── Download / runtime ──
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
    let sha256: String                // SHA-256 of the GGUF file; empty until verified

    // ── Compliance / attribution ──
    let baseModelName: String
    let baseModelURL: String?
    let licenseName: String
    let licenseURL: String?
    let conversionSummary: String
    let runtimeNotes: String?
    let attributionText: String?
    let noticeText: String?
    let requiresBuiltWithLlamaAttribution: Bool

    var modelID: String { id }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
    var filename: String { sourceURL.lastPathComponent }
}

extension TranslationModel {
    static let availableModels: [TranslationModel] = [
        // ── Tencent ──────────────────────────────────────────
        TranslationModel(
            id: "hy-mt1.5-1.8b-stq", displayName: "Hy-MT1.5 1.8B",
            description: "1.25-bit Sherry STQ1_0. CPU/NEON optimized.",
            provider: "Tencent",
            sourceURL: URL(string: "https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit.gguf")!,
            fileSizeBytes: 461_860_704, supportedLanguages: Language.allCases,
            hfRepo: "AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF",
            quantization: "1.25-bit STQ1_0", config: .hunyuanMT,
            capability: .simulatorAndDevice, parameterCount: "1.8B",
            sha256: "",
            baseModelName: "Hy-MT1.5 1.8B",
            baseModelURL: "https://huggingface.co/tencent/Hy-MT1.5-1.8B",
            licenseName: "Tencent Hunyuan Model License (custom)",
            licenseURL: "https://huggingface.co/tencent/Hy-MT1.5-1.8B",
            conversionSummary: "1.25-bit AngelSlim STQ1_0 GGUF by Tencent. Optimised for ARM NEON on Apple Silicon.",
            runtimeNotes: "CPU/NEON only (GPU disabled). ~44 tok/s on M2. Uses raw SentencePiece prompt.",
            attributionText: nil, noticeText: nil,
            requiresBuiltWithLlamaAttribution: false
        ),
        TranslationModel(
            id: "hy-mt2-1.8b-stq", displayName: "Hy-MT2 1.8B",
            description: "1.25-bit STQ1_0. Next-gen 33-language translation.",
            provider: "Tencent",
            sourceURL: URL(string: "https://huggingface.co/AngelSlim/Hy-MT2-1.8B-1.25Bit-GGUF/resolve/main/Hy-MT2-1.8B-1.25Bit.gguf")!,
            fileSizeBytes: 461_860_736, supportedLanguages: Language.allCases,
            hfRepo: "AngelSlim/Hy-MT2-1.8B-1.25Bit-GGUF",
            quantization: "1.25-bit STQ1_0", config: .hunyuanMT,
            capability: .simulatorAndDevice, parameterCount: "1.8B",
            sha256: "",
            baseModelName: "Hy-MT2 1.8B",
            baseModelURL: "https://huggingface.co/tencent/Hy-MT2-1.8B",
            licenseName: "Tencent Hunyuan Model License (custom)",
            licenseURL: "https://huggingface.co/tencent/Hy-MT2-1.8B",
            conversionSummary: "1.25-bit AngelSlim STQ1_0 GGUF by Tencent. Next-gen 33-language model.",
            runtimeNotes: "CPU/NEON only (GPU disabled). Uses raw SentencePiece prompt.",
            attributionText: nil, noticeText: nil,
            requiresBuiltWithLlamaAttribution: false
        ),
        TranslationModel(
            id: "hy-mt1.5-1.8b-q4km", displayName: "Hy-MT1.5 1.8B HQ",
            description: "Q4_K_M quantization for max quality.",
            provider: "Tencent",
            sourceURL: URL(string: "https://huggingface.co/tencent/HY-MT1.5-1.8B-GGUF/resolve/main/HY-MT1.5-1.8B-Q4_K_M.gguf")!,
            fileSizeBytes: 1_133_080_512, supportedLanguages: Language.allCases,
            hfRepo: "tencent/HY-MT1.5-1.8B-GGUF",
            quantization: "Q4_K_M", config: .hunyuanMT,
            capability: .simulatorAndDevice, parameterCount: "1.8B",
            sha256: "",
            baseModelName: "Hy-MT1.5 1.8B",
            baseModelURL: "https://huggingface.co/tencent/Hy-MT1.5-1.8B",
            licenseName: "Tencent Hunyuan Model License (custom)",
            licenseURL: "https://huggingface.co/tencent/Hy-MT1.5-1.8B",
            conversionSummary: "Q4_K_M GGUF for maximum quality. Converted by Tencent.",
            runtimeNotes: "CPU/NEON only. Uses raw SentencePiece prompt.",
            attributionText: nil, noticeText: nil,
            requiresBuiltWithLlamaAttribution: false
        ),

        // ── Meta (Llama) ─────────────────────────────────────
        TranslationModel(
            id: "llama-3.2-1b-q8", displayName: "Llama 3.2 1B",
            description: "Q8_0 — 1.26 GB, fast.",
            provider: "Meta",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/Llama-3.2-1B-Instruct-Q8_0-gguf/resolve/main/Llama-3.2-1B-Instruct-Q8_0.gguf")!,
            fileSizeBytes: 1_321_078_496, supportedLanguages: Language.allCases,
            hfRepo: "zanish-labs/Llama-3.2-1B-Instruct-Q8_0-gguf",
            quantization: "Q8_0", config: .llamaInstruct,
            capability: .deviceRecommended, parameterCount: "1B",
            sha256: "d1bef032cc6690ca579c161e8d0d9f98047e51d6e708e1f131a34454e26cf5b7",
            baseModelName: "Llama 3.2 1B Instruct",
            baseModelURL: "https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct",
            licenseName: "Llama 3.2 Community License",
            licenseURL: "https://www.llama.com/llama3_2/license/",
            conversionSummary: "Converted to GGUF and quantised to Q8_0 by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: "Built with Meta Llama 3.2",
            noticeText: "Llama 3.2 Community License. © Meta Platforms, Inc. See https://www.llama.com/llama3_2/license/",
            requiresBuiltWithLlamaAttribution: true
        ),
        TranslationModel(
            id: "llama-3.2-3b-iq3m", displayName: "Llama 3.2 3B",
            description: "IQ3_M — 1.53 GB.",
            provider: "Meta",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/Llama-3.2-3B-Instruct-IQ3_M-gguf/resolve/main/Llama-3.2-3B-Instruct-IQ3_M.gguf")!,
            fileSizeBytes: 1_599_664_288, supportedLanguages: Language.allCases,
            hfRepo: "zanish-labs/Llama-3.2-3B-Instruct-IQ3_M-gguf",
            quantization: "IQ3_M", config: .llamaInstruct,
            capability: .deviceRecommended, parameterCount: "3B",
            sha256: "c9ce9faa829e0d5f0412d0ebeca66b587ad0ad28607d438a4ab305de1a517e30",
            baseModelName: "Llama 3.2 3B Instruct",
            baseModelURL: "https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct",
            licenseName: "Llama 3.2 Community License",
            licenseURL: "https://www.llama.com/llama3_2/license/",
            conversionSummary: "Converted to GGUF and quantised to IQ3_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: "Built with Meta Llama 3.2",
            noticeText: "Llama 3.2 Community License. © Meta Platforms, Inc. See https://www.llama.com/llama3_2/license/",
            requiresBuiltWithLlamaAttribution: true
        ),

        // ── Qwen ─────────────────────────────────────────────
        TranslationModel(
            id: "qwen3.5-0.8b-q8", displayName: "Qwen3.5 0.8B",
            description: "Q8_0 — 795 MB, all devices.",
            provider: "Qwen",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/qwen3.5-0.8b-q8_0-gguf/resolve/main/qwen3.5-0.8b-q8_0.gguf")!,
            fileSizeBytes: 833_591_648, supportedLanguages: Language.allCases,
            hfRepo: "zanish-labs/qwen3.5-0.8b-q8_0-gguf",
            quantization: "Q8_0", config: .qwenInstruct,
            capability: .simulatorAndDevice, parameterCount: "0.8B",
            sha256: "ea2e5d0848abf21b69f59c5e8c3e2857bfad88db919d485f9e847a1f1e3ce29c",
            baseModelName: "Qwen3.5 0.8B",
            baseModelURL: "https://huggingface.co/Qwen/Qwen3.5-0.8B",
            licenseName: "Apache 2.0",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0",
            conversionSummary: "Converted to GGUF and quantised to Q8_0 by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil, noticeText: nil,
            requiresBuiltWithLlamaAttribution: false
        ),
        TranslationModel(
            id: "qwen3.5-2b-q4km", displayName: "Qwen3.5 2B",
            description: "Q4_K_M — 1.25 GB, sweet spot.",
            provider: "Qwen",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/qwen3.5-2b-q4_k_m-gguf/resolve/main/qwen3.5-2b-q4_k_m.gguf")!,
            fileSizeBytes: 1_312_164_192, supportedLanguages: Language.allCases,
            hfRepo: "zanish-labs/qwen3.5-2b-q4_k_m-gguf",
            quantization: "Q4_K_M", config: .qwenInstruct,
            capability: .deviceRecommended, parameterCount: "2B",
            sha256: "92b61f139fbae199718c0c283df25cb619b1cc57e71faaae5a9a6b06a1842dda",
            baseModelName: "Qwen3.5 2B",
            baseModelURL: "https://huggingface.co/Qwen/Qwen3.5-2B",
            licenseName: "Apache 2.0",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0",
            conversionSummary: "Converted to GGUF and quantised to Q4_K_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil, noticeText: nil,
            requiresBuiltWithLlamaAttribution: false
        ),
        TranslationModel(
            id: "qwen3.5-4b-q4km", displayName: "Qwen3.5 4B",
            description: "Q4_K_M — 2.65 GB, max Qwen quality.",
            provider: "Qwen",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/qwen3.5-4b-q4_k_m-gguf/resolve/main/qwen3.5-4b-q4_k_m.gguf")!,
            fileSizeBytes: 2_783_446_240, supportedLanguages: Language.allCases,
            hfRepo: "zanish-labs/qwen3.5-4b-q4_k_m-gguf",
            quantization: "Q4_K_M", config: .qwenInstruct,
            capability: .deviceRecommended, parameterCount: "4B",
            sha256: "9b1ca7b52bba671bd255e8ae60b3b1d522e21b58a3a1131d293fd96345e8bd22",
            baseModelName: "Qwen3.5 4B",
            baseModelURL: "https://huggingface.co/Qwen/Qwen3.5-4B",
            licenseName: "Apache 2.0",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0",
            conversionSummary: "Converted to GGUF and quantised to Q4_K_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil, noticeText: nil,
            requiresBuiltWithLlamaAttribution: false
        ),

        // ── Google (Gemma) ───────────────────────────────────
        TranslationModel(
            id: "gemma-4-e2b-q4km", displayName: "Gemma 4 E2B",
            description: "Q4_K_M — 3.27 GB.",
            provider: "Google",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/gemma-4-E2B-it-Q4_K_M-gguf/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf")!,
            fileSizeBytes: 3_427_861_088, supportedLanguages: Language.allCases,
            hfRepo: "zanish-labs/gemma-4-E2B-it-Q4_K_M-gguf",
            quantization: "Q4_K_M", config: .gemma4Raw,
            capability: .deviceRecommended, parameterCount: "2B",
            sha256: "8580ede90c6a7fdd5bfee2c016b3a7601d471895b192a0fddaf655d577b12e3b",
            baseModelName: "Gemma 4 E2B Instruct",
            baseModelURL: "https://huggingface.co/google/gemma-4-E2B-it",
            licenseName: "Gemma License (custom)",
            licenseURL: "https://ai.google.dev/gemma/terms",
            conversionSummary: "Converted to GGUF and quantised to Q4_K_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil, noticeText: nil,
            requiresBuiltWithLlamaAttribution: false
        ),
        TranslationModel(
            id: "gemma-4-e4b-q4km", displayName: "Gemma 4 E4B",
            description: "Q4_K_M — 5.09 GB.",
            provider: "Google",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/gemma-4-E4B-it-Q4_K_M-gguf/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf")!,
            fileSizeBytes: 5_335_273_056, supportedLanguages: Language.allCases,
            hfRepo: "zanish-labs/gemma-4-E4B-it-Q4_K_M-gguf",
            quantization: "Q4_K_M", config: .gemma4Raw,
            capability: .deviceRecommended, parameterCount: "4B",
            sha256: "9d23b7b4cd3c6c6c9ffadd7a9b1e16448621005b80a803e85afa3ca2c48714e3",
            baseModelName: "Gemma 4 E4B Instruct",
            baseModelURL: "https://huggingface.co/google/gemma-4-E4B-it",
            licenseName: "Gemma License (custom)",
            licenseURL: "https://ai.google.dev/gemma/terms",
            conversionSummary: "Converted to GGUF and quantised to Q4_K_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil, noticeText: nil,
            requiresBuiltWithLlamaAttribution: false
        ),
        TranslationModel(
            id: "translategemma-4b-q2k", displayName: "TranslateGemma 4B",
            description: "Q2_K — 1.65 GB, translation specialist.",
            provider: "Google",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/translategemma-4b-it-Q2_K-gguf/resolve/main/translategemma-4b-it-Q2_K.gguf")!,
            fileSizeBytes: 1_729_180_160, supportedLanguages: Language.allCases,
            hfRepo: "zanish-labs/translategemma-4b-it-Q2_K-gguf",
            quantization: "Q2_K", config: .gemmaInstruct,
            capability: .deviceRecommended, parameterCount: "4B",
            sha256: "37140b1cd9110a5a5f836d3c6cd2f31d424b5ac726bd043f965e511c67070406",
            baseModelName: "TranslateGemma 4B Instruct",
            baseModelURL: "https://huggingface.co/google/TranslateGemma-4B-it",
            licenseName: "Gemma License (custom)",
            licenseURL: "https://ai.google.dev/gemma/terms",
            conversionSummary: "Converted to GGUF and quantised to Q2_K by Zanish Labs for on-device use.",
            runtimeNotes: "Translation-specialist Gemma variant. Optimised for direct translation tasks.",
            attributionText: nil, noticeText: nil,
            requiresBuiltWithLlamaAttribution: false
        ),
    ]
}
