//
//  TranslationModel.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import Foundation

struct TranslationModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let description: String
    let sourceURL: URL
    let fileSizeBytes: Int64
    let supportedLanguages: [Language]
    let hfModel: String
    let quantization: String

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    var filename: String {
        sourceURL.lastPathComponent
    }
}

extension TranslationModel {
    static let availableModels: [TranslationModel] = [
        TranslationModel(
            id: "hunyuan-1.5b-q4km",
            displayName: "Tencent Hunyuan 1.5B",
            description: "Tencent's compact multilingual translation model. Fast on-device translation for 12 languages.",
            sourceURL: URL(string: "https://huggingface.co/tencent/Hunyuan-Translation-1.5B-Instruct-GGUF/resolve/main/Hunyuan-Translation-1.5B-Instruct-Q4_K_M.gguf")!,
            fileSizeBytes: 1_073_741_824,
            supportedLanguages: Language.allCases,
            hfModel: "tencent/Hunyuan-Translation-1.5B-Instruct-GGUF",
            quantization: "Q4_K_M"
        ),
        TranslationModel(
            id: "gemma-3-1b-q4km",
            displayName: "Google Gemma 3 1B",
            description: "Google's lightweight Gemma 3 model. Good general translation quality with strong English performance.",
            sourceURL: URL(string: "https://huggingface.co/google/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf")!,
            fileSizeBytes: 900_000_000,
            supportedLanguages: [.english, .spanish, .french, .german, .portuguese, .chinese, .japanese, .korean],
            hfModel: "google/gemma-3-1b-it-GGUF",
            quantization: "Q4_K_M"
        ),
        TranslationModel(
            id: "qwen3-0.6b-q4km",
            displayName: "Alibaba Qwen3 0.6B",
            description: "Ultra-compact Qwen3 model. Fastest option, ideal for quick translations on any device.",
            sourceURL: URL(string: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf")!,
            fileSizeBytes: 500_000_000,
            supportedLanguages: [.english, .spanish, .french, .german, .italian, .portuguese, .chinese, .japanese, .korean, .arabic, .hindi, .russian],
            hfModel: "unsloth/Qwen3-0.6B-GGUF",
            quantization: "Q4_K_M"
        )
    ]
}
