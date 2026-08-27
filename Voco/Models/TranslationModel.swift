//
//  TranslationModel.swift
//  Voco
//
//  Definitive 2026 Model Catalog — compliance metadata and download info.
//  Single source of truth for the Models & Licenses screen and download pipeline.
//

import Foundation

struct TranslationModel: Identifiable, Hashable, Sendable {
    // ── Download / runtime ──
    let id: String
    let displayName: String
    let description: String
    let provider: String
    let sourceURL: URL
    let fileSizeBytes: Int64
    /// Language IDs this model supports well. nil = supports all languages.
    /// Used by LanguageRegistry to filter the language picker.
    let supportedLanguageCodes: Set<String>?
    let hfRepo: String
    let quantization: String
    let config: ModelConfiguration
    let parameterCount: String
    let sha256: String                // SHA-256 of the GGUF file; empty until verified

    // ── Compliance / attribution ──
    let baseModelName: String
    let baseModelURL: String?
    let licenseName: String
    let licenseURL: String?
    let usePolicyURL: String?          // Prohibited use / acceptable use policy URL
    let conversionSummary: String
    let runtimeNotes: String?
    let attributionText: String?
    let noticeText: String?
    let requiresBuiltWithLlamaAttribution: Bool

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
    var filename: String { sourceURL.lastPathComponent }
}

extension TranslationModel {
    static let availableModels: [TranslationModel] = [
        // ── Tencent ──────────────────────────────────────────
        TranslationModel(
            id: "hy-mt2-1.8b-stq", displayName: "Hy-MT2 1.8B",
            description: "1.25-bit STQ1_0. Next-gen 33-language translation.",
            provider: "Tencent",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/Hy-MT2-1.8B-1.25Bit-GGUF/resolve/main/Hy-MT2-1.8B-1.25Bit.gguf")!,
            fileSizeBytes: 461_860_736, supportedLanguageCodes: ["ar", "bn", "bo", "cs", "de", "en", "es", "fa", "fr", "gu", "he", "hi", "id", "it", "ja", "kk", "km", "ko", "mn", "mr", "ms", "my", "nl", "pl", "pt", "ru", "ta", "te", "th", "tl", "tr", "uk", "ur", "vi", "yue", "zh", "zh-TW"],
            hfRepo: "zanish-labs/Hy-MT2-1.8B-1.25Bit-GGUF",
            quantization: "1.25-bit STQ1_0", config: .hunyuanMT, parameterCount: "1.8B",
            sha256: "fda3e7462018e35188356b2cbb0726ea18ec9c4f104c357f6232c3f780df4135",
            baseModelName: "Hy-MT2 1.8B",
            baseModelURL: "https://huggingface.co/tencent/Hy-MT2-1.8B",
            licenseName: "Tencent Hunyuan Model License (custom)",
            licenseURL: "https://huggingface.co/tencent/Hy-MT2-1.8B/blob/main/LICENSE.txt",
            usePolicyURL: nil,
            conversionSummary: "1.25-bit AngelSlim STQ1_0 GGUF by Tencent. Next-gen 33-language model.",
            runtimeNotes: "CPU/NEON only (GPU disabled). Uses raw SentencePiece prompt.",
            attributionText: nil, noticeText: nil,
            requiresBuiltWithLlamaAttribution: false
        ),
        TranslationModel(
            id: "hy-mt1.5-1.8b-q4km", displayName: "Hy-MT1.5 1.8B HQ",
            description: "Q4_K_M quantization for max quality.",
            provider: "Tencent",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/HY-MT1.5-1.8B-GGUF/resolve/main/HY-MT1.5-1.8B-Q4_K_M.gguf")!,
            fileSizeBytes: 1_133_080_512, supportedLanguageCodes: ["ar", "bn", "bo", "cs", "de", "en", "es", "fa", "fr", "gu", "he", "hi", "id", "it", "ja", "km", "ko", "mn", "mr", "ms", "my", "nl", "pl", "pt", "ru", "ta", "te", "th", "tl", "tr", "ug", "uk", "ur", "vi", "zh", "zh-TW"],
            hfRepo: "zanish-labs/HY-MT1.5-1.8B-GGUF",
            quantization: "Q4_K_M", config: .hunyuanMT, parameterCount: "1.8B",
            sha256: "4383ac0c3c8e476de98ff979c2a3f069f8c4fb385e7860cf2d28da896cc477c7",
            baseModelName: "Hy-MT1.5 1.8B",
            baseModelURL: "https://huggingface.co/tencent/Hy-MT1.5-1.8B",
            licenseName: "Tencent Hunyuan Model License (custom)",
            licenseURL: "https://huggingface.co/tencent/HY-MT1.5-1.8B/blob/main/License.txt",
            usePolicyURL: nil,
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
            fileSizeBytes: 1_321_078_496, supportedLanguageCodes: ["en", "de", "fr", "it", "pt", "hi", "es", "th"],
            hfRepo: "zanish-labs/Llama-3.2-1B-Instruct-Q8_0-gguf",
            quantization: "Q8_0", config: .llamaInstruct, parameterCount: "1B",
            sha256: "d1bef032cc6690ca579c161e8d0d9f98047e51d6e708e1f131a34454e26cf5b7",
            baseModelName: "Llama 3.2 1B Instruct",
            baseModelURL: "https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct",
            licenseName: "Llama 3.2 Community License",
            licenseURL: "https://www.llama.com/llama3_2/license/",
            usePolicyURL: "https://www.llama.com/llama3_2/use-policy/",
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
            fileSizeBytes: 1_599_664_288, supportedLanguageCodes: ["en", "de", "fr", "it", "pt", "hi", "es", "th"],
            hfRepo: "zanish-labs/Llama-3.2-3B-Instruct-IQ3_M-gguf",
            quantization: "IQ3_M", config: .llamaInstruct, parameterCount: "3B",
            sha256: "c9ce9faa829e0d5f0412d0ebeca66b587ad0ad28607d438a4ab305de1a517e30",
            baseModelName: "Llama 3.2 3B Instruct",
            baseModelURL: "https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct",
            licenseName: "Llama 3.2 Community License",
            licenseURL: "https://www.llama.com/llama3_2/license/",
            usePolicyURL: "https://www.llama.com/llama3_2/use-policy/",
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
            fileSizeBytes: 833_591_648, supportedLanguageCodes: ["en", "es", "fr", "de", "it", "pt", "nl", "pl", "tr", "id", "ms", "tl"], // trimmed: zh/zh-TW/ja/ko/bn/hi/ta/ur/ru/ar/vi/th return empty on-device 2/2 runs (device-matrix-logs, 2026-08-27)
            hfRepo: "zanish-labs/qwen3.5-0.8b-q8_0-gguf",
            quantization: "Q8_0", config: .qwenInstruct, parameterCount: "0.8B",
            sha256: "ea2e5d0848abf21b69f59c5e8c3e2857bfad88db919d485f9e847a1f1e3ce29c",
            baseModelName: "Qwen3.5 0.8B",
            baseModelURL: "https://huggingface.co/Qwen/Qwen3.5-0.8B",
            licenseName: "Apache License 2.0",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0",
            usePolicyURL: nil,
            conversionSummary: "Converted to GGUF and quantised to Q8_0 by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil,
            noticeText: "Apache License 2.0. © Qwen Team, Alibaba Cloud. See https://www.apache.org/licenses/LICENSE-2.0",
            requiresBuiltWithLlamaAttribution: false
        ),
        TranslationModel(
            id: "qwen3.5-2b-q4km", displayName: "Qwen3.5 2B",
            description: "Q4_K_M — 1.25 GB, sweet spot.",
            provider: "Qwen",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/qwen3.5-2b-q4_k_m-gguf/resolve/main/qwen3.5-2b-q4_k_m.gguf")!,
            fileSizeBytes: 1_312_164_192, supportedLanguageCodes: ["en", "es", "fr", "de", "it", "pt", "nl", "pl", "tr", "id", "ms", "tl"], // trimmed: zh/zh-TW/ja/ko/bn/hi/ta/ur/ru/ar/vi/th return empty on-device 2/2 runs (device-matrix-logs, 2026-08-27)
            hfRepo: "zanish-labs/qwen3.5-2b-q4_k_m-gguf",
            quantization: "Q4_K_M", config: .qwenInstruct, parameterCount: "2B",
            sha256: "92b61f139fbae199718c0c283df25cb619b1cc57e71faaae5a9a6b06a1842dda",
            baseModelName: "Qwen3.5 2B",
            baseModelURL: "https://huggingface.co/Qwen/Qwen3.5-2B",
            licenseName: "Apache License 2.0",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0",
            usePolicyURL: nil,
            conversionSummary: "Converted to GGUF and quantised to Q4_K_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil,
            noticeText: "Apache License 2.0. © Qwen Team, Alibaba Cloud. See https://www.apache.org/licenses/LICENSE-2.0",
            requiresBuiltWithLlamaAttribution: false
        ),
        TranslationModel(
            id: "qwen3.5-4b-q4km", displayName: "Qwen3.5 4B",
            description: "Q4_K_M — 2.65 GB, max Qwen quality.",
            provider: "Qwen",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/qwen3.5-4b-q4_k_m-gguf/resolve/main/qwen3.5-4b-q4_k_m.gguf")!,
            fileSizeBytes: 2_783_446_240, supportedLanguageCodes: ["en", "es", "fr", "de", "it", "pt", "nl", "pl", "tr", "id", "ms", "tl"], // trimmed: zh/zh-TW/ja/ko/bn/hi/ta/ur/ru/ar/vi/th return empty on-device 2/2 runs (device-matrix-logs, 2026-08-27)
            hfRepo: "zanish-labs/qwen3.5-4b-q4_k_m-gguf",
            quantization: "Q4_K_M", config: .qwen4bInstruct, parameterCount: "4B",
            sha256: "9b1ca7b52bba671bd255e8ae60b3b1d522e21b58a3a1131d293fd96345e8bd22",
            baseModelName: "Qwen3.5 4B",
            baseModelURL: "https://huggingface.co/Qwen/Qwen3.5-4B",
            licenseName: "Apache License 2.0",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0",
            usePolicyURL: nil,
            conversionSummary: "Converted to GGUF and quantised to Q4_K_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil,
            noticeText: "Apache License 2.0. © Qwen Team, Alibaba Cloud. See https://www.apache.org/licenses/LICENSE-2.0",
            requiresBuiltWithLlamaAttribution: false
        ),

        // ── Google (Gemma) ───────────────────────────────────
        TranslationModel(
            id: "gemma-4-e2b-q4km", displayName: "Gemma 4 E2B",
            description: "Q4_K_M — 3.27 GB.",
            provider: "Google",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/gemma-4-E2B-it-Q4_K_M-gguf/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf")!,
            fileSizeBytes: 3_427_861_088, supportedLanguageCodes: ["en", "es", "fr", "de", "it", "pt", "nl", "pl", "ru", "uk", "ro", "cs", "sv", "da", "fi", "nb", "el", "hu", "tr", "zh", "zh-TW", "ja", "ko", "th", "vi", "id", "ms", "ar", "hi", "bn", "he", "fa"],
            hfRepo: "zanish-labs/gemma-4-E2B-it-Q4_K_M-gguf",
            quantization: "Q4_K_M", config: .gemma4Raw, parameterCount: "2B",
            sha256: "8580ede90c6a7fdd5bfee2c016b3a7601d471895b192a0fddaf655d577b12e3b",
            baseModelName: "Gemma 4 E2B Instruct",
            baseModelURL: "https://huggingface.co/google/gemma-4-E2B-it",
            licenseName: "Gemma License (custom)",
            licenseURL: "https://ai.google.dev/gemma/terms",
            usePolicyURL: "https://ai.google.dev/gemma/prohibited_use_policy",
            conversionSummary: "Converted to GGUF and quantised to Q4_K_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil,
            noticeText: "Gemma Terms of Use. © Google LLC. See https://ai.google.dev/gemma/terms",
            requiresBuiltWithLlamaAttribution: false
        ),
        TranslationModel(
            id: "gemma-4-e4b-q4km", displayName: "Gemma 4 E4B",
            description: "Q4_K_M — 5.09 GB.",
            provider: "Google",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/gemma-4-E4B-it-Q4_K_M-gguf/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf")!,
            fileSizeBytes: 5_335_273_056, supportedLanguageCodes: ["en", "es", "fr", "de", "it", "pt", "nl", "pl", "ru", "uk", "ro", "cs", "sv", "da", "fi", "nb", "el", "hu", "tr", "zh", "zh-TW", "ja", "ko", "th", "vi", "id", "ms", "ar", "hi", "bn", "he", "fa"],
            hfRepo: "zanish-labs/gemma-4-E4B-it-Q4_K_M-gguf",
            quantization: "Q4_K_M", config: .gemma4Raw, parameterCount: "4B",
            sha256: "9d23b7b4cd3c6c6c9ffadd7a9b1e16448621005b80a803e85afa3ca2c48714e3",
            baseModelName: "Gemma 4 E4B Instruct",
            baseModelURL: "https://huggingface.co/google/gemma-4-E4B-it",
            licenseName: "Gemma License (custom)",
            licenseURL: "https://ai.google.dev/gemma/terms",
            usePolicyURL: "https://ai.google.dev/gemma/prohibited_use_policy",
            conversionSummary: "Converted to GGUF and quantised to Q4_K_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil,
            noticeText: "Gemma Terms of Use. © Google LLC. See https://ai.google.dev/gemma/terms",
            requiresBuiltWithLlamaAttribution: false
        ),
        TranslationModel(
            id: "translategemma-4b-q2k", displayName: "TranslateGemma 4B",
            description: "Q2_K — 1.65 GB, translation specialist.",
            provider: "Google",
            sourceURL: URL(string: "https://huggingface.co/zanish-labs/translategemma-4b-it-Q2_K-gguf/resolve/main/translategemma-4b-it-Q2_K.gguf")!,
            fileSizeBytes: 1_729_180_160, supportedLanguageCodes: ["en", "ar", "bg", "bn", "ca", "cs", "da", "de", "el", "es", "et", "fa", "fi", "tl", "fr", "gu", "he", "hi", "hr", "hu", "id", "is", "it", "ja", "kn", "ko", "lt", "lv", "ml", "mr", "nl", "nb", "pa", "pl", "pt", "ro", "ru", "sk", "sl", "sr", "sv", "sw", "ta", "te", "th", "tr", "uk", "ur", "vi", "zh", "zh-TW", "zu"],
            hfRepo: "zanish-labs/translategemma-4b-it-Q2_K-gguf",
            quantization: "Q2_K", config: .gemmaInstruct, parameterCount: "4B",
            sha256: "37140b1cd9110a5a5f836d3c6cd2f31d424b5ac726bd043f965e511c67070406",
            baseModelName: "TranslateGemma 4B Instruct",
            baseModelURL: "https://huggingface.co/google/translategemma-4b-it",
            licenseName: "Gemma License (custom)",
            licenseURL: "https://ai.google.dev/gemma/terms",
            usePolicyURL: "https://ai.google.dev/gemma/prohibited_use_policy",
            conversionSummary: "Converted to GGUF and quantised to Q2_K by Zanish Labs for on-device use.",
            runtimeNotes: "Translation-specialist Gemma variant. Optimised for direct translation tasks.",
            attributionText: nil,
            noticeText: "Gemma Terms of Use. © Google LLC. See https://ai.google.dev/gemma/terms",
            requiresBuiltWithLlamaAttribution: false
        ),
    ]
}
