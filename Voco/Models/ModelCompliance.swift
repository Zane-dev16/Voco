//
//  ModelCompliance.swift
//  Voco
//
//  Structured compliance metadata for every downloadable model.
//  Drives the Models & Licenses screen in Settings.
//

import Foundation

struct ModelCompliance: Identifiable, Sendable {
    let id: String                    // matches TranslationModel.id
    let displayName: String
    let provider: String
    let baseModelName: String
    let baseModelURL: String?         // original model page on HF or official site
    let baseModelCardURL: String?     // HF model card URL if different
    let ggufRepoURL: String           // our GGUF repo URL
    let licenseName: String
    let licenseURL: String?
    let quantization: String
    let parameterCount: String
    let conversionSummary: String
    let runtimeNotes: String?
    let attributionText: String?
    let noticeText: String?
    let requiresBuiltWithLlamaAttribution: Bool
    let isDownloadable: Bool
    let isVisibleToUsers: Bool

    // Convenience: create from TranslationModel
    var modelID: String { id }
}

// MARK: - Compliance Registry

extension ModelCompliance {
    /// All model compliance records for user-downloadable models.
    /// Ordered by provider, then size.
    static let allRecords: [ModelCompliance] = [
        // ── Tencent ──────────────────────────────────────────
        ModelCompliance(
            id: "hy-mt1.5-1.8b-stq",
            displayName: "Hy-MT1.5 1.8B",
            provider: "Tencent",
            baseModelName: "Hy-MT1.5 1.8B",
            baseModelURL: "https://huggingface.co/tencent/Hy-MT1.5-1.8B",
            baseModelCardURL: nil,
            ggufRepoURL: "https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF",
            licenseName: "Tencent Hunyuan Model License (custom)",
            licenseURL: nil,
            quantization: "1.25-bit STQ1_0",
            parameterCount: "1.8B",
            conversionSummary: "1.25-bit AngelSlim STQ1_0 GGUF by Tencent. Optimised for ARM NEON on Apple Silicon.",
            runtimeNotes: "CPU/NEON only (GPU disabled). ~44 tok/s on M2. Uses raw SentencePiece prompt.",
            attributionText: nil,
            noticeText: nil,
            requiresBuiltWithLlamaAttribution: false,
            isDownloadable: true,
            isVisibleToUsers: true
        ),
        ModelCompliance(
            id: "hy-mt2-1.8b-stq",
            displayName: "Hy-MT2 1.8B",
            provider: "Tencent",
            baseModelName: "Hy-MT2 1.8B",
            baseModelURL: "https://huggingface.co/tencent/Hy-MT2-1.8B",
            baseModelCardURL: nil,
            ggufRepoURL: "https://huggingface.co/AngelSlim/Hy-MT2-1.8B-1.25Bit-GGUF",
            licenseName: "Tencent Hunyuan Model License (custom)",
            licenseURL: nil,
            quantization: "1.25-bit STQ1_0",
            parameterCount: "1.8B",
            conversionSummary: "1.25-bit AngelSlim STQ1_0 GGUF by Tencent. Next-gen 33-language model.",
            runtimeNotes: "CPU/NEON only (GPU disabled). Uses raw SentencePiece prompt.",
            attributionText: nil,
            noticeText: nil,
            requiresBuiltWithLlamaAttribution: false,
            isDownloadable: true,
            isVisibleToUsers: true
        ),
        ModelCompliance(
            id: "hy-mt1.5-1.8b-q4km",
            displayName: "Hy-MT1.5 1.8B HQ",
            provider: "Tencent",
            baseModelName: "Hy-MT1.5 1.8B",
            baseModelURL: "https://huggingface.co/tencent/Hy-MT1.5-1.8B",
            baseModelCardURL: nil,
            ggufRepoURL: "https://huggingface.co/tencent/HY-MT1.5-1.8B-GGUF",
            licenseName: "Tencent Hunyuan Model License (custom)",
            licenseURL: nil,
            quantization: "Q4_K_M",
            parameterCount: "1.8B",
            conversionSummary: "Q4_K_M GGUF for maximum quality. Converted by Tencent.",
            runtimeNotes: "CPU/NEON only. Uses raw SentencePiece prompt.",
            attributionText: nil,
            noticeText: nil,
            requiresBuiltWithLlamaAttribution: false,
            isDownloadable: true,
            isVisibleToUsers: true
        ),

        // ── Meta (Llama) ─────────────────────────────────────
        ModelCompliance(
            id: "llama-3.2-1b-q8",
            displayName: "Llama 3.2 1B",
            provider: "Meta",
            baseModelName: "Llama 3.2 1B Instruct",
            baseModelURL: "https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct",
            baseModelCardURL: nil,
            ggufRepoURL: "https://huggingface.co/zanish-labs/Llama-3.2-1B-Instruct-Q8_0-gguf",
            licenseName: "Llama 3.2 Community License",
            licenseURL: "https://www.llama.com/llama3_2/license/",
            quantization: "Q8_0",
            parameterCount: "1B",
            conversionSummary: "Converted to GGUF and quantised to Q8_0 by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: "Built with Llama",
            noticeText: """
Llama 3.2 Community License Notice
Copyright © Meta Platforms, Inc. All Rights Reserved.

Use of this model is governed by the Llama 3.2 Community License.
See https://www.llama.com/llama3_2/license/ for full terms.
""",
            requiresBuiltWithLlamaAttribution: true,
            isDownloadable: true,
            isVisibleToUsers: true
        ),
        ModelCompliance(
            id: "llama-3.2-3b-iq3m",
            displayName: "Llama 3.2 3B",
            provider: "Meta",
            baseModelName: "Llama 3.2 3B Instruct",
            baseModelURL: "https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct",
            baseModelCardURL: nil,
            ggufRepoURL: "https://huggingface.co/zanish-labs/Llama-3.2-3B-Instruct-IQ3_M-gguf",
            licenseName: "Llama 3.2 Community License",
            licenseURL: "https://www.llama.com/llama3_2/license/",
            quantization: "IQ3_M",
            parameterCount: "3B",
            conversionSummary: "Converted to GGUF and quantised to IQ3_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: "Built with Llama",
            noticeText: """
Llama 3.2 Community License Notice
Copyright © Meta Platforms, Inc. All Rights Reserved.

Use of this model is governed by the Llama 3.2 Community License.
See https://www.llama.com/llama3_2/license/ for full terms.
""",
            requiresBuiltWithLlamaAttribution: true,
            isDownloadable: true,
            isVisibleToUsers: true
        ),

        // ── Qwen ─────────────────────────────────────────────
        ModelCompliance(
            id: "qwen3.5-0.8b-q8",
            displayName: "Qwen3.5 0.8B",
            provider: "Qwen",
            baseModelName: "Qwen3.5 0.8B",
            baseModelURL: "https://huggingface.co/Qwen/Qwen3.5-0.8B",
            baseModelCardURL: nil,
            ggufRepoURL: "https://huggingface.co/zanish-labs/qwen3.5-0.8b-q8_0-gguf",
            licenseName: "Apache 2.0",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0",
            quantization: "Q8_0",
            parameterCount: "0.8B",
            conversionSummary: "Converted to GGUF and quantised to Q8_0 by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil,
            noticeText: nil,
            requiresBuiltWithLlamaAttribution: false,
            isDownloadable: true,
            isVisibleToUsers: true
        ),
        ModelCompliance(
            id: "qwen3.5-2b-q4km",
            displayName: "Qwen3.5 2B",
            provider: "Qwen",
            baseModelName: "Qwen3.5 2B",
            baseModelURL: "https://huggingface.co/Qwen/Qwen3.5-2B",
            baseModelCardURL: nil,
            ggufRepoURL: "https://huggingface.co/zanish-labs/qwen3.5-2b-q4_k_m-gguf",
            licenseName: "Apache 2.0",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0",
            quantization: "Q4_K_M",
            parameterCount: "2B",
            conversionSummary: "Converted to GGUF and quantised to Q4_K_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil,
            noticeText: nil,
            requiresBuiltWithLlamaAttribution: false,
            isDownloadable: true,
            isVisibleToUsers: true
        ),
        ModelCompliance(
            id: "qwen3.5-4b-q4km",
            displayName: "Qwen3.5 4B",
            provider: "Qwen",
            baseModelName: "Qwen3.5 4B",
            baseModelURL: "https://huggingface.co/Qwen/Qwen3.5-4B",
            baseModelCardURL: nil,
            ggufRepoURL: "https://huggingface.co/zanish-labs/qwen3.5-4b-q4_k_m-gguf",
            licenseName: "Apache 2.0",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0",
            quantization: "Q4_K_M",
            parameterCount: "4B",
            conversionSummary: "Converted to GGUF and quantised to Q4_K_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil,
            noticeText: nil,
            requiresBuiltWithLlamaAttribution: false,
            isDownloadable: true,
            isVisibleToUsers: true
        ),

        // ── Google (Gemma) ───────────────────────────────────
        ModelCompliance(
            id: "gemma-4-e2b-q4km",
            displayName: "Gemma 4 E2B",
            provider: "Google",
            baseModelName: "Gemma 4 E2B Instruct",
            baseModelURL: "https://huggingface.co/google/gemma-4-E2B-it",
            baseModelCardURL: nil,
            ggufRepoURL: "https://huggingface.co/zanish-labs/gemma-4-E2B-it-Q4_K_M-gguf",
            licenseName: "Gemma License (custom)",
            licenseURL: "https://ai.google.dev/gemma/terms",
            quantization: "Q4_K_M",
            parameterCount: "2B",
            conversionSummary: "Converted to GGUF and quantised to Q4_K_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil,
            noticeText: nil,
            requiresBuiltWithLlamaAttribution: false,
            isDownloadable: true,
            isVisibleToUsers: true
        ),
        ModelCompliance(
            id: "gemma-4-e4b-q4km",
            displayName: "Gemma 4 E4B",
            provider: "Google",
            baseModelName: "Gemma 4 E4B Instruct",
            baseModelURL: "https://huggingface.co/google/gemma-4-E4B-it",
            baseModelCardURL: nil,
            ggufRepoURL: "https://huggingface.co/zanish-labs/gemma-4-E4B-it-Q4_K_M-gguf",
            licenseName: "Gemma License (custom)",
            licenseURL: "https://ai.google.dev/gemma/terms",
            quantization: "Q4_K_M",
            parameterCount: "4B",
            conversionSummary: "Converted to GGUF and quantised to Q4_K_M by Zanish Labs for on-device use.",
            runtimeNotes: nil,
            attributionText: nil,
            noticeText: nil,
            requiresBuiltWithLlamaAttribution: false,
            isDownloadable: true,
            isVisibleToUsers: true
        ),
        ModelCompliance(
            id: "translategemma-4b-q2k",
            displayName: "TranslateGemma 4B",
            provider: "Google",
            baseModelName: "TranslateGemma 4B Instruct",
            baseModelURL: "https://huggingface.co/google/TranslateGemma-4B-it",
            baseModelCardURL: nil,
            ggufRepoURL: "https://huggingface.co/zanish-labs/translategemma-4b-it-Q2_K-gguf",
            licenseName: "Gemma License (custom)",
            licenseURL: "https://ai.google.dev/gemma/terms",
            quantization: "Q2_K",
            parameterCount: "4B",
            conversionSummary: "Converted to GGUF and quantised to Q2_K by Zanish Labs for on-device use.",
            runtimeNotes: "Translation-specialist Gemma variant. Optimised for direct translation tasks.",
            attributionText: nil,
            noticeText: nil,
            requiresBuiltWithLlamaAttribution: false,
            isDownloadable: true,
            isVisibleToUsers: true
        ),
    ]
}
