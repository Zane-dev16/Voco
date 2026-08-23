//
//  Language.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import Foundation

/// Supported translation languages.
enum Language: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case arabic = "ar"
    case hindi = "hi"
    case russian = "ru"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:    return "English"
        case .spanish:    return "Spanish"
        case .french:     return "French"
        case .german:     return "German"
        case .italian:    return "Italian"
        case .portuguese: return "Portuguese"
        case .chinese:    return "Chinese (Simplified)"
        case .japanese:   return "Japanese"
        case .korean:     return "Korean"
        case .arabic:     return "Arabic"
        case .hindi:      return "Hindi"
        case .russian:    return "Russian"
        }
    }


    var code: String { rawValue }

    /// Look up a Language by its display name or hunyuan target name.
    /// Used by TranslationService to resolve user-facing language names to enum values.
    static func find(byDisplayOrHunyuanName name: String) -> Language? {
        allCases.first(where: { $0.displayName == name || $0.hunyuanTargetName == name })
    }

    /// Target-language name used in Hunyuan MT1.5 SentencePiece prompts.
    /// HY-MT1.5 understands plain English language names in the prompt.
    var hunyuanTargetName: String {
        switch self {
        case .english:    return "English"
        case .spanish:    return "Spanish"
        case .french:     return "French"
        case .german:     return "German"
        case .italian:    return "Italian"
        case .portuguese: return "Portuguese"
        case .chinese:    return "Chinese"
        case .japanese:   return "Japanese"
        case .korean:     return "Korean"
        case .arabic:     return "Arabic"
        case .hindi:      return "Hindi"
        case .russian:    return "Russian"
        }
    }
}
