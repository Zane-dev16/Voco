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

    var flag: String {
        switch self {
        case .english:    return "\u{1F1EC}\u{1F1E7}"
        case .spanish:    return "\u{1F1EA}\u{1F1F8}"
        case .french:     return "\u{1F1EB}\u{1F1F7}"
        case .german:     return "\u{1F1E9}\u{1F1EA}"
        case .italian:    return "\u{1F1EE}\u{1F1F9}"
        case .portuguese: return "\u{1F1E7}\u{1F1F7}"
        case .chinese:    return "\u{1F1E8}\u{1F1F3}"
        case .japanese:   return "\u{1F1EF}\u{1F1F5}"
        case .korean:     return "\u{1F1F0}\u{1F1F7}"
        case .arabic:     return "\u{1F1F8}\u{1F1E6}"
        case .hindi:      return "\u{1F1EE}\u{1F1F3}"
        case .russian:    return "\u{1F1F7}\u{1F1FA}"
        }
    }

    var code: String { rawValue }

    /// Look up a Language by its display name or hunyuan target name.
    /// Used by LlamaService to resolve user-facing language names to enum values.
    static func find(byDisplayOrHunyuanName name: String) -> Language? {
        allCases.first(where: { $0.displayName == name || $0.hunyuanTargetName == name })
    }

    /// Look up a Language by its ISO 639-1 code.
    static func find(byCode code: String) -> Language? {
        allCases.first(where: { $0.code == code })
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
