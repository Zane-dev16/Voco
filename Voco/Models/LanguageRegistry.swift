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
    let nllbCode: String?    // NLLB-200 language code, nil if unsupported

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
                 hunyuan: String? = nil, nllb: String? = nil) {
            list.append(SupportedLanguage(
                id: id, displayName: name, promptName: name,
                flag: flag, hunyuanName: hunyuan, nllbCode: nllb
            ))
        }

        // --- European Languages ---
        add("en", "English", "\u{1F1EC}\u{1F1E7}", hunyuan: "English", nllb: "eng_Latn")
        add("es", "Spanish", "\u{1F1EA}\u{1F1F8}", hunyuan: "Spanish", nllb: "spa_Latn")
        add("fr", "French", "\u{1F1EB}\u{1F1F7}", hunyuan: "French", nllb: "fra_Latn")
        add("de", "German", "\u{1F1E9}\u{1F1EA}", hunyuan: "German", nllb: "deu_Latn")
        add("it", "Italian", "\u{1F1EE}\u{1F1F9}", hunyuan: "Italian", nllb: "ita_Latn")
        add("pt", "Portuguese", "\u{1F1E7}\u{1F1F7}", hunyuan: "Portuguese", nllb: "por_Latn")
        add("nl", "Dutch", "\u{1F1F3}\u{1F1F1}", nllb: "nld_Latn")
        add("pl", "Polish", "\u{1F1F5}\u{1F1F1}", nllb: "pol_Latn")
        add("ru", "Russian", "\u{1F1F7}\u{1F1FA}", hunyuan: "Russian", nllb: "rus_Cyrl")
        add("uk", "Ukrainian", "\u{1F1FA}\u{1F1E6}", nllb: "ukr_Cyrl")
        add("ro", "Romanian", "\u{1F1F7}\u{1F1F4}", nllb: "ron_Latn")
        add("cs", "Czech", "\u{1F1E8}\u{1F1FF}", nllb: "ces_Latn")
        add("sv", "Swedish", "\u{1F1F8}\u{1F1EA}", nllb: "swe_Latn")
        add("da", "Danish", "\u{1F1E9}\u{1F1F0}", nllb: "dan_Latn")
        add("fi", "Finnish", "\u{1F1EB}\u{1F1EE}", nllb: "fin_Latn")
        add("nb", "Norwegian", "\u{1F1F3}\u{1F1F4}", nllb: "nob_Latn")
        add("el", "Greek", "\u{1F1EC}\u{1F1F7}", nllb: "ell_Grek")
        add("hu", "Hungarian", "\u{1F1ED}\u{1F1FA}", nllb: "hun_Latn")
        add("bg", "Bulgarian", "\u{1F1E7}\u{1F1EC}", nllb: "bul_Cyrl")
        add("sr", "Serbian", "\u{1F1F7}\u{1F1F8}", nllb: "srp_Cyrl")
        add("hr", "Croatian", "\u{1F1ED}\u{1F1F7}", nllb: "hrv_Latn")
        add("sk", "Slovak", "\u{1F1F8}\u{1F1F0}", nllb: "slk_Latn")
        add("sl", "Slovenian", "\u{1F1F8}\u{1F1EE}", nllb: "slv_Latn")
        add("et", "Estonian", "\u{1F1EA}\u{1F1EA}", nllb: "est_Latn")
        add("lv", "Latvian", "\u{1F1F1}\u{1F1FB}", nllb: "lvs_Latn")
        add("lt", "Lithuanian", "\u{1F1F1}\u{1F1F9}", nllb: "lit_Latn")
        add("tr", "Turkish", "\u{1F1F9}\u{1F1F7}", nllb: "tur_Latn")
        add("ca", "Catalan", "\u{1F1E8}\u{1F1F4}", nllb: "cat_Latn")
        add("gl", "Galician", "\u{1F1EC}\u{1F1FA}", nllb: "glg_Latn")

        // --- Asian Languages ---
        add("zh", "Chinese (Simplified)", "\u{1F1E8}\u{1F1F3}", hunyuan: "Chinese", nllb: "zho_Hans")
        add("zh-TW", "Chinese (Traditional)", "\u{1F1F9}\u{1F1FC}", nllb: "zho_Hant")
        add("ja", "Japanese", "\u{1F1EF}\u{1F1F5}", hunyuan: "Japanese", nllb: "jpn_Jpan")
        add("ko", "Korean", "\u{1F1F0}\u{1F1F7}", hunyuan: "Korean", nllb: "kor_Hang")
        add("th", "Thai", "\u{1F1F9}\u{1F1ED}", nllb: "tha_Thai")
        add("vi", "Vietnamese", "\u{1F1FB}\u{1F1F3}", nllb: "vie_Latn")
        add("id", "Indonesian", "\u{1F1EE}\u{1F1E9}", nllb: "ind_Latn")
        add("ms", "Malay", "\u{1F1F2}\u{1F1FE}", nllb: "zsm_Latn")
        add("tl", "Filipino", "\u{1F1F5}\u{1F1ED}", nllb: "tgl_Latn")
        add("my", "Burmese", "\u{1F1E7}\u{1F1F2}", nllb: "mya_Mymr")
        add("km", "Khmer", "\u{1F1F0}\u{1F1ED}", nllb: "khm_Khmr")
        add("lo", "Lao", "\u{1F1F1}\u{1F1E6}", nllb: "lao_Laoo")

        // --- South Asian Languages ---
        add("hi", "Hindi", "\u{1F1EE}\u{1F1F3}", hunyuan: "Hindi", nllb: "hin_Deva")
        add("bn", "Bengali", "\u{1F1E7}\u{1F1E9}", nllb: "ben_Beng")
        add("ta", "Tamil", "\u{1F1F9}\u{1F1F1}", nllb: "tam_Taml")
        add("te", "Telugu", "\u{1F1F9}\u{1F1F0}", nllb: "tel_Telu")
        add("mr", "Marathi", "\u{1F1F2}\u{1F1F8}", nllb: "mar_Deva")
        add("ur", "Urdu", "\u{1F1FA}\u{1F1F2}", nllb: "urd_Arab")
        add("gu", "Gujarati", "\u{1F1EC}\u{1F1F2}", nllb: "guj_Gujr")
        add("kn", "Kannada", "\u{1F1F0}\u{1F1F3}", nllb: "kan_Knda")
        add("ml", "Malayalam", "\u{1F1F2}\u{1F1F1}", nllb: "mal_Mlym")
        add("pa", "Punjabi", "\u{1F1F5}\u{1F1F0}", nllb: "pan_Guru")
        add("ne", "Nepali", "\u{1F1F3}\u{1F1F5}", nllb: "npi_Deva")
        add("si", "Sinhala", "\u{1F1F1}\u{1F1F0}", nllb: "sin_Sinh")

        // --- Middle Eastern & African Languages ---
        add("ar", "Arabic", "\u{1F1F8}\u{1F1E6}", hunyuan: "Arabic", nllb: "arb_Arab")
        add("he", "Hebrew", "\u{1F1EE}\u{1F1F1}", nllb: "heb_Hebr")
        add("fa", "Persian", "\u{1F1EE}\u{1F1F7}", nllb: "pes_Arab")
        add("sw", "Swahili", "\u{1F1F8}\u{1F1FF}", nllb: "swh_Latn")
        add("am", "Amharic", "\u{1F1EA}\u{1F1F9}", nllb: "amh_Ethi")
        add("yo", "Yoruba", "\u{1F1F3}\u{1F1EC}", nllb: "yor_Latn")
        add("ig", "Igbo", "\u{1F1EE}\u{1F1EC}", nllb: "ibo_Latn")
        add("ha", "Hausa", "\u{1F1ED}\u{1F1F3}", nllb: "hau_Latn")
        add("zu", "Zulu", "\u{1F1FF}\u{1F1E6}", nllb: "zul_Latn")
        add("af", "Afrikaans", "\u{1F1E6}\u{1F1FF}", nllb: "afr_Latn")

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
    /// Returns the model-specific name (hunyuanName, nllbCode, or promptName).
    func languageName(for lang: SupportedLanguage, config: ModelConfiguration) -> String {
        if config == .hunyuanMT, let hunyuan = lang.hunyuanName {
            return hunyuan
        }
        if config == .nllbTranslate, let nllb = lang.nllbCode {
            return nllb
        }
        return lang.promptName
    }

    /// Get the appropriate source language name for a given model config.
    func sourceLanguageName(for lang: SupportedLanguage, config: ModelConfiguration) -> String {
        if config == .nllbTranslate, let nllb = lang.nllbCode {
            return nllb
        }
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
