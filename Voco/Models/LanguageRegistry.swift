//
//  LanguageRegistry.swift
//  Voco
//
//  Dynamic language registry with runtime STT/TTS capability detection.
//  Supports 50+ languages with graceful degradation to text-only mode.
//

import Foundation
import Combine
import Speech
import AVFoundation
import SwiftUI

// MARK: - SupportedLanguage

/// A language supported by Voco for translation, with runtime voice capability flags.
struct SupportedLanguage: Identifiable, Hashable, Comparable {
    let id: String           // ISO 639-1 code (e.g., "es") or BCP 47 (e.g., "zh-Hans")
    let displayName: String  // User-facing name (e.g., "Spanish")
    let promptName: String   // Name injected into LLM prompts (e.g., "Spanish")
    let flag: String         // Flag emoji
    let hunyuanName: String? // Tencent Hunyuan-specific name, nil if unsupported

    /// Runtime-detected: source language has offline STT voice pack.
    var supportsOfflineSTT: Bool = false
    /// Runtime-detected: target language has offline TTS voice pack.
    var supportsOfflineTTS: Bool = false

    /// Whether the language fully supports voice input and output.
    var supportsVoice: Bool {
        supportsOfflineSTT && supportsOfflineTTS
    }

    /// ISO 639-1 language code (first two chars of id for most languages).
    var languageCode: String {
        String(id.prefix(2))
    }

    static func < (lhs: SupportedLanguage, rhs: SupportedLanguage) -> Bool {
        lhs.displayName < rhs.displayName
    }
}

// MARK: - LanguageRegistry

/// Singleton registry of all supported languages with runtime capability detection.
/// Publishes language lists so the UI can react to capability changes.
@MainActor
final class LanguageRegistry: ObservableObject {

    static let shared = LanguageRegistry()

    /// All supported languages, sorted by display name.
    @Published private(set) var languages: [SupportedLanguage] = []

    /// Languages that support both STT and TTS (voice mode).
    @Published private(set) var voiceLanguages: [SupportedLanguage] = []

    /// Languages that are text-only (missing STT or TTS).
    @Published private(set) var textOnlyLanguages: [SupportedLanguage] = []

    /// Set of language IDs that support offline STT.
    private(set) var sttSupportedIDs: Set<String> = []

    /// Set of language IDs that support offline TTS.
    private(set) var ttsSupportedIDs: Set<String> = []

    private init() {
        languages = Self.buildLanguageList()
        resolveCapabilities()
    }

    // MARK: - Language List

    /// Builds the comprehensive list of 50+ supported languages.
    private static func buildLanguageList() -> [SupportedLanguage] {
        var list: [SupportedLanguage] = []

        // Helper to add a language
        func add(_ id: String, _ name: String, _ flag: String,
                 hunyuan: String? = nil) {
            list.append(SupportedLanguage(
                id: id, displayName: name, promptName: name,
                flag: flag, hunyuanName: hunyuan
            ))
        }

        // --- European Languages ---
        add("en", "English", "\u{1F1EC}\u{1F1E7}", hunyuan: "English")
        add("es", "Spanish", "\u{1F1EA}\u{1F1F8}", hunyuan: "Spanish")
        add("fr", "French", "\u{1F1EB}\u{1F1F7}", hunyuan: "French")
        add("de", "German", "\u{1F1E9}\u{1F1EA}", hunyuan: "German")
        add("it", "Italian", "\u{1F1EE}\u{1F1F9}", hunyuan: "Italian")
        add("pt", "Portuguese", "\u{1F1E7}\u{1F1F7}", hunyuan: "Portuguese")
        add("nl", "Dutch", "\u{1F1F3}\u{1F1F1}")
        add("pl", "Polish", "\u{1F1F5}\u{1F1F1}")
        add("ru", "Russian", "\u{1F1F7}\u{1F1FA}", hunyuan: "Russian")
        add("uk", "Ukrainian", "\u{1F1FA}\u{1F1E6}")
        add("ro", "Romanian", "\u{1F1F7}\u{1F1F4}")
        add("cs", "Czech", "\u{1F1E8}\u{1F1FF}")
        add("sv", "Swedish", "\u{1F1F8}\u{1F1EA}")
        add("da", "Danish", "\u{1F1E9}\u{1F1F0}")
        add("fi", "Finnish", "\u{1F1EB}\u{1F1EE}")
        add("nb", "Norwegian", "\u{1F1F3}\u{1F1F4}")
        add("el", "Greek", "\u{1F1EC}\u{1F1F7}")
        add("hu", "Hungarian", "\u{1F1ED}\u{1F1FA}")
        add("bg", "Bulgarian", "\u{1F1E7}\u{1F1EC}")
        add("sr", "Serbian", "\u{1F1F7}\u{1F1F8}")
        add("hr", "Croatian", "\u{1F1ED}\u{1F1F7}")
        add("sk", "Slovak", "\u{1F1F8}\u{1F1F0}")
        add("sl", "Slovenian", "\u{1F1F8}\u{1F1EE}")
        add("et", "Estonian", "\u{1F1EA}\u{1F1EA}")
        add("lv", "Latvian", "\u{1F1F1}\u{1F1FB}")
        add("lt", "Lithuanian", "\u{1F1F1}\u{1F1F9}")
        add("tr", "Turkish", "\u{1F1F9}\u{1F1F7}")
        add("ca", "Catalan", "\u{1F1E8}\u{1F1F4}")
        add("gl", "Galician", "\u{1F1EC}\u{1F1FA}")

        // --- Asian Languages ---
        add("zh", "Chinese (Simplified)", "\u{1F1E8}\u{1F1F3}", hunyuan: "Chinese")
        add("zh-TW", "Chinese (Traditional)", "\u{1F1F9}\u{1F1FC}", hunyuan: "Traditional Chinese")
        add("ja", "Japanese", "\u{1F1EF}\u{1F1F5}", hunyuan: "Japanese")
        add("ko", "Korean", "\u{1F1F0}\u{1F1F7}", hunyuan: "Korean")
        add("th", "Thai", "\u{1F1F9}\u{1F1ED}")
        add("vi", "Vietnamese", "\u{1F1FB}\u{1F1F3}")
        add("id", "Indonesian", "\u{1F1EE}\u{1F1E9}")
        add("ms", "Malay", "\u{1F1F2}\u{1F1FE}")
        add("tl", "Filipino", "\u{1F1F5}\u{1F1ED}")
        add("my", "Burmese", "\u{1F1E7}\u{1F1F2}")
        add("km", "Khmer", "\u{1F1F0}\u{1F1ED}")
        add("lo", "Lao", "\u{1F1F1}\u{1F1E6}")

        // --- South Asian Languages ---
        add("hi", "Hindi", "\u{1F1EE}\u{1F1F3}", hunyuan: "Hindi")
        add("bn", "Bengali", "\u{1F1E7}\u{1F1E9}")
        add("ta", "Tamil", "\u{1F1F9}\u{1F1F1}")
        add("te", "Telugu", "\u{1F1F9}\u{1F1F0}")
        add("mr", "Marathi", "\u{1F1F2}\u{1F1F8}")
        add("ur", "Urdu", "\u{1F1FA}\u{1F1F2}")
        add("gu", "Gujarati", "\u{1F1EC}\u{1F1F2}")
        add("kn", "Kannada", "\u{1F1F0}\u{1F1F3}")
        add("ml", "Malayalam", "\u{1F1F2}\u{1F1F1}")
        add("pa", "Punjabi", "\u{1F1F5}\u{1F1F0}")
        add("ne", "Nepali", "\u{1F1F3}\u{1F1F5}")
        add("si", "Sinhala", "\u{1F1F1}\u{1F1F0}")

        // --- Middle Eastern & African Languages ---
        add("ar", "Arabic", "\u{1F1F8}\u{1F1E6}", hunyuan: "Arabic")
        add("he", "Hebrew", "\u{1F1EE}\u{1F1F1}")
        add("fa", "Persian", "\u{1F1EE}\u{1F1F7}")
        add("sw", "Swahili", "\u{1F1F8}\u{1F1FF}")
        add("am", "Amharic", "\u{1F1EA}\u{1F1F9}")
        add("yo", "Yoruba", "\u{1F1F3}\u{1F1EC}")
        add("ig", "Igbo", "\u{1F1EE}\u{1F1EC}")
        add("ha", "Hausa", "\u{1F1ED}\u{1F1F3}")
        add("zu", "Zulu", "\u{1F1FF}\u{1F1E6}")
        add("af", "Afrikaans", "\u{1F1E6}\u{1F1FF}")

        // --- Central Asian Languages (Hy-MT ethnic/dialect set) ---
        add("bo", "Tibetan", "\u{1F1AD}\u{1F1F0}", hunyuan: "Tibetan")
        add("kk", "Kazakh", "\u{1F1F0}\u{1F1FF}", hunyuan: "Kazakh")
        add("mn", "Mongolian", "\u{1F1F2}\u{1F1F3}", hunyuan: "Mongolian")
        add("ug", "Uyghur", "\u{1F1FA}\u{1F1EC}", hunyuan: "Uyghur")

        // --- Chinese variants (HY-MT dialect set) ---
        add("yue", "Cantonese", "\u{1F1ED}\u{1F1F0}", hunyuan: "Cantonese")

        return list.sorted()
    }

    // MARK: - Capability Detection

    /// Resolves STT and TTS availability for all languages.
    /// Call once on app launch.
    func resolveCapabilities() {
        resolveSTTCapabilities()
        resolveTTSCapabilities()
        updateFilteredLists()
    }

    /// Checks which languages have on-device speech recognition.
    private func resolveSTTCapabilities() {
        var supported = Set<String>()

        for lang in languages {
            let locale = Locale(identifier: lang.id)
            if let recognizer = SFSpeechRecognizer(locale: locale),
               recognizer.supportsOnDeviceRecognition {
                supported.insert(lang.id)
            }
        }

        sttSupportedIDs = supported

        // Update language structs
        for i in languages.indices {
            languages[i].supportsOfflineSTT = supported.contains(languages[i].id)
        }
    }

    /// Checks which languages have installed TTS voices.
    private func resolveTTSCapabilities() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        var supported = Set<String>()

        for lang in languages {
            let hasVoice = voices.contains { voice in
                voice.language.hasPrefix(lang.languageCode) ||
                voice.language == lang.id
            }
            if hasVoice {
                supported.insert(lang.id)
            }
        }

        ttsSupportedIDs = supported

        // Update language structs
        for i in languages.indices {
            languages[i].supportsOfflineTTS = supported.contains(languages[i].id)
        }
    }

    /// Splits languages into voice and text-only lists.
    private func updateFilteredLists() {
        voiceLanguages = languages.filter { $0.supportsVoice }
        textOnlyLanguages = languages.filter { !$0.supportsVoice }
    }

    // MARK: - Lookups

    /// Find a language by its ID.
    func language(forID id: String) -> SupportedLanguage? {
        languages.first(where: { $0.id == id })
    }

    /// Find a language by display name or prompt name.
    func language(byName name: String) -> SupportedLanguage? {
        languages.first(where: {
            $0.displayName.lowercased() == name.lowercased() ||
            $0.promptName.lowercased() == name.lowercased()
        })
    }

    /// Find a language by its legacy Language enum value.
    func language(forLegacy legacy: Language) -> SupportedLanguage? {
        language(forID: legacy.rawValue)
    }

    /// Get the appropriate language name for a given model config.
    /// Returns the model-specific name (hunyuanName or promptName).
    func languageName(for lang: SupportedLanguage, config: ModelConfiguration) -> String {
        if config == .hunyuanMT, let hunyuan = lang.hunyuanName {
            return hunyuan
        }
        return lang.promptName
    }

    /// Get the appropriate source language name for a given model config.
    func sourceLanguageName(for lang: SupportedLanguage, config: ModelConfiguration) -> String {
        return lang.promptName
    }

    /// Filter languages to only those supported by a specific model.
    func languages(for model: TranslationModel) -> [SupportedLanguage] {
        guard let codes = model.supportedLanguageCodes else {
            return languages // model supports all
        }
        return languages.filter { codes.contains($0.id) }
    }
}
