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
/// Explicitly `nonisolated`: a pure value type consulted from background
/// capability probes as well as the main actor.
nonisolated struct SupportedLanguage: Identifiable, Hashable, Comparable {
    let id: String           // ISO 639-1 code (e.g., "es") or BCP 47 (e.g., "zh-Hans")
    let displayName: String  // User-facing name (e.g., "Spanish")
    let promptName: String   // Name injected into LLM prompts (e.g., "Spanish")
    let flag: String         // Flag emoji
    let hunyuanName: String? // Tencent Hunyuan-specific name, nil if unsupported

    /// Native-script name (e.g. "Español", "日本語") for multilingual search.
    /// nil falls back to displayName.
    var nativeName: String?

    /// BCP-47 tag for speech services when it differs from `id`
    /// (tl → "fil-PH", zh → "zh-CN", yue → "zh-HK"). nil means use `id`.
    var bcp47Tag: String?

    /// Right-to-left script (Arabic, Hebrew, Persian, Urdu, Uyghur).
    var isRTL: Bool = false

    /// The native name to display/search, falling back to displayName.
    var effectiveNativeName: String {
        guard let nativeName, !nativeName.isEmpty else { return displayName }
        return nativeName
    }

    /// The tag speech services should use for this language.
    var speechLocaleID: String {
        bcp47Tag ?? id
    }

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

    /// Set of language IDs that support offline STT.
    private(set) var sttSupportedIDs: Set<String> = []

    /// Set of language IDs that support offline TTS.
    private(set) var ttsSupportedIDs: Set<String> = []

    private init() {
        languages = Self.buildLanguageList()
        probeCapabilitiesInBackground()
    }

    /// Probes speech capabilities off the main thread (S7-20): ~70 recognizer
    /// constructions plus voice scans cost hundreds of milliseconds at first
    /// frame otherwise. The static language list is available synchronously;
    /// capability flags fill in shortly after launch (UI already renders
    /// transient text-only states).
    private func probeCapabilitiesInBackground() {
        lastProbeStarted = ContinuousClock.now
        let langs = languages
        Task.detached(priority: .userInitiated) {
            let sttIDs = Self.detectSTTCapabilities(for: langs)
            let ttsIDs = Self.detectTTSCapabilities(for: langs)
            await self.applyCapabilities(sttIDs: sttIDs, ttsIDs: ttsIDs)
        }
    }

    /// When the last probe started, to throttle foreground refreshes.
    private var lastProbeStarted = ContinuousClock.now

    /// Re-runs capability detection (R7-10): iOS can install voice packs or
    /// change speech availability while we run, leaving the 🎤/⌨️ glyphs stale.
    /// Throttled — the probe constructs ~70 recognizers.
    func refreshCapabilitiesIfNeeded(minInterval: Duration = .seconds(60)) {
        guard ContinuousClock.now - lastProbeStarted >= minInterval else { return }
        probeCapabilitiesInBackground()
    }

    // MARK: - Language List

    /// Builds the comprehensive list of 50+ supported languages.
    private static func buildLanguageList() -> [SupportedLanguage] {
        var list: [SupportedLanguage] = []

        // Helper to add a language
        func add(_ id: String, _ name: String, _ flag: String,
                 hunyuan: String? = nil, native: String? = nil,
                 bcp47: String? = nil, rtl: Bool = false) {
            list.append(SupportedLanguage(
                id: id, displayName: name, promptName: name,
                flag: flag, hunyuanName: hunyuan,
                nativeName: native, bcp47Tag: bcp47, isRTL: rtl
            ))
        }

        // --- European Languages ---
        add("en", "English", "\u{1F1EC}\u{1F1E7}", hunyuan: "English", native: "English")
        add("es", "Spanish", "\u{1F1EA}\u{1F1F8}", hunyuan: "Spanish", native: "Español")
        add("fr", "French", "\u{1F1EB}\u{1F1F7}", hunyuan: "French", native: "Français")
        add("de", "German", "\u{1F1E9}\u{1F1EA}", hunyuan: "German", native: "Deutsch")
        add("it", "Italian", "\u{1F1EE}\u{1F1F9}", hunyuan: "Italian", native: "Italiano")
        add("pt", "Portuguese", "\u{1F1E7}\u{1F1F7}", hunyuan: "Portuguese", native: "Português")
        add("nl", "Dutch", "\u{1F1F3}\u{1F1F1}", native: "Nederlands")
        add("pl", "Polish", "\u{1F1F5}\u{1F1F1}", native: "Polski")
        add("ru", "Russian", "\u{1F1F7}\u{1F1FA}", hunyuan: "Russian", native: "Русский")
        add("uk", "Ukrainian", "\u{1F1FA}\u{1F1E6}", native: "Українська")
        add("ro", "Romanian", "\u{1F1F7}\u{1F1F4}", native: "Română")
        add("cs", "Czech", "\u{1F1E8}\u{1F1FF}", native: "Čeština")
        add("sv", "Swedish", "\u{1F1F8}\u{1F1EA}", native: "Svenska")
        add("da", "Danish", "\u{1F1E9}\u{1F1F0}", native: "Dansk")
        add("fi", "Finnish", "\u{1F1EB}\u{1F1EE}", native: "Suomi")
        add("nb", "Norwegian", "\u{1F1F3}\u{1F1F4}", native: "Norsk bokmål")
        add("el", "Greek", "\u{1F1EC}\u{1F1F7}", native: "Ελληνικά")
        add("hu", "Hungarian", "\u{1F1ED}\u{1F1FA}", native: "Magyar")
        add("bg", "Bulgarian", "\u{1F1E7}\u{1F1EC}", native: "Български")
        add("sr", "Serbian", "\u{1F1F7}\u{1F1F8}", native: "Српски")
        add("hr", "Croatian", "\u{1F1ED}\u{1F1F7}", native: "Hrvatski")
        add("sk", "Slovak", "\u{1F1F8}\u{1F1F0}", native: "Slovenčina")
        add("sl", "Slovenian", "\u{1F1F8}\u{1F1EE}", native: "Slovenščina")
        add("et", "Estonian", "\u{1F1EA}\u{1F1EA}", native: "Eesti")
        add("lv", "Latvian", "\u{1F1F1}\u{1F1FB}", native: "Latviešu")
        add("lt", "Lithuanian", "\u{1F1F1}\u{1F1F9}", native: "Lietuvių")
        add("tr", "Turkish", "\u{1F1F9}\u{1F1F7}", hunyuan: "Turkish", native: "Türkçe")
        add("ca", "Catalan", "\u{1F1E8}\u{1F1F4}", native: "Català")
        add("gl", "Galician", "\u{1F1EC}\u{1F1FA}", native: "Galego")

        // --- Asian Languages ---
        add("zh", "Chinese (Simplified)", "\u{1F1E8}\u{1F1F3}", hunyuan: "Chinese", native: "简体中文", bcp47: "zh-CN")
        add("zh-TW", "Chinese (Traditional)", "\u{1F1F9}\u{1F1FC}", hunyuan: "Traditional Chinese", native: "繁體中文")
        add("ja", "Japanese", "\u{1F1EF}\u{1F1F5}", hunyuan: "Japanese", native: "日本語")
        add("ko", "Korean", "\u{1F1F0}\u{1F1F7}", hunyuan: "Korean", native: "한국어")
        add("th", "Thai", "\u{1F1F9}\u{1F1ED}", native: "ไทย")
        add("vi", "Vietnamese", "\u{1F1FB}\u{1F1F3}", native: "Tiếng Việt")
        add("id", "Indonesian", "\u{1F1EE}\u{1F1E9}", native: "Bahasa Indonesia")
        add("ms", "Malay", "\u{1F1F2}\u{1F1FE}", native: "Bahasa Melayu")
        add("tl", "Filipino", "\u{1F1F5}\u{1F1ED}", native: "Filipino", bcp47: "fil-PH")
        add("my", "Burmese", "\u{1F1E7}\u{1F1F2}", native: "မြန်မာ")
        add("km", "Khmer", "\u{1F1F0}\u{1F1ED}", native: "ខ្មែរ")
        add("lo", "Lao", "\u{1F1F1}\u{1F1E6}", native: "ລາວ")

        // --- South Asian Languages ---
        add("hi", "Hindi", "\u{1F1EE}\u{1F1F3}", hunyuan: "Hindi", native: "हिन्दी")
        add("bn", "Bengali", "\u{1F1E7}\u{1F1E9}", native: "বাংলা")
        add("ta", "Tamil", "\u{1F1F9}\u{1F1F1}", native: "தமிழ்")
        add("te", "Telugu", "\u{1F1F9}\u{1F1F0}", native: "తెలుగు")
        add("mr", "Marathi", "\u{1F1F2}\u{1F1F8}", native: "मराठी")
        add("ur", "Urdu", "\u{1F1FA}\u{1F1F2}", native: "اردو", rtl: true)
        add("gu", "Gujarati", "\u{1F1EC}\u{1F1F2}", native: "ગુજરાતી")
        add("kn", "Kannada", "\u{1F1F0}\u{1F1F3}", native: "ಕನ್ನಡ")
        add("ml", "Malayalam", "\u{1F1F2}\u{1F1F1}", native: "മലയാളം")
        add("pa", "Punjabi", "\u{1F1F5}\u{1F1F0}", native: "ਪੰਜਾਬੀ")
        add("ne", "Nepali", "\u{1F1F3}\u{1F1F5}", native: "नेपाली")
        add("si", "Sinhala", "\u{1F1F1}\u{1F1F0}", native: "සිංහල")

        // --- Middle Eastern & African Languages ---
        add("ar", "Arabic", "\u{1F1F8}\u{1F1E6}", hunyuan: "Arabic", native: "العربية", rtl: true)
        add("he", "Hebrew", "\u{1F1EE}\u{1F1F1}", native: "עברית", rtl: true)
        add("fa", "Persian", "\u{1F1EE}\u{1F1F7}", native: "فارسی", rtl: true)
        add("sw", "Swahili", "\u{1F1F8}\u{1F1FF}", native: "Kiswahili")
        add("am", "Amharic", "\u{1F1EA}\u{1F1F9}", native: "አማርኛ")
        add("yo", "Yoruba", "\u{1F1F3}\u{1F1EC}", native: "Yorùbá")
        add("ig", "Igbo", "\u{1F1EE}\u{1F1EC}", native: "Igbo")
        add("ha", "Hausa", "\u{1F1ED}\u{1F1F3}", native: "Hausa")
        add("zu", "Zulu", "\u{1F1FF}\u{1F1E6}", native: "isiZulu")
        add("af", "Afrikaans", "\u{1F1E6}\u{1F1FF}", native: "Afrikaans")

        // --- Central Asian Languages (Hy-MT ethnic/dialect set) ---
        add("bo", "Tibetan", "\u{1F1AD}\u{1F1F0}", hunyuan: "Tibetan", native: "བོད་སྐད་")
        add("kk", "Kazakh", "\u{1F1F0}\u{1F1FF}", hunyuan: "Kazakh", native: "Қазақ тілі")
        add("mn", "Mongolian", "\u{1F1F2}\u{1F1F3}", hunyuan: "Mongolian", native: "Монгол")
        add("ug", "Uyghur", "\u{1F1FA}\u{1F1EC}", hunyuan: "Uyghur", native: "ئۇيغۇرچە", rtl: true)

        // --- Chinese variants (HY-MT dialect set) ---
        add("yue", "Cantonese", "\u{1F1ED}\u{1F1F0}", hunyuan: "Cantonese", native: "廣東話", bcp47: "zh-HK")

        return list.sorted()
    }

    // MARK: - Capability Detection

    /// Publishes probed capability sets on the main actor.
    private func applyCapabilities(sttIDs: Set<String>, ttsIDs: Set<String>) {
        sttSupportedIDs = sttIDs
        ttsSupportedIDs = ttsIDs
        for i in languages.indices {
            languages[i].supportsOfflineSTT = sttIDs.contains(languages[i].id)
            languages[i].supportsOfflineTTS = ttsIDs.contains(languages[i].id)
        }
    }

    /// Checks which languages have on-device speech recognition.
    /// nonisolated: runs on a utility executor away from the main actor.
    nonisolated private static func detectSTTCapabilities(for languages: [SupportedLanguage]) -> Set<String> {
        var supported = Set<String>()
        for lang in languages {
            let locale = Locale(identifier: lang.speechLocaleID)
            if let recognizer = SFSpeechRecognizer(locale: locale),
               recognizer.supportsOnDeviceRecognition {
                supported.insert(lang.id)
            }
        }
        return supported
    }

    /// Checks which languages have installed TTS voices.
    nonisolated private static func detectTTSCapabilities(for languages: [SupportedLanguage]) -> Set<String> {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        var supported = Set<String>()
        for lang in languages {
            // Variant-tagged languages (zh-CN vs zh-TW vs zh-HK, fil-PH) match
            // exactly so Chinese variants don't conflate; plain ISO codes keep
            // the broad prefix match.
            let hasVoice: Bool
            if lang.bcp47Tag != nil || lang.id.contains("-") {
                hasVoice = voices.contains { $0.language == lang.speechLocaleID }
                    || voices.contains { $0.language.hasPrefix(lang.speechLocaleID) }
            } else {
                hasVoice = voices.contains { $0.language.hasPrefix(lang.languageCode) }
            }
            if hasVoice {
                supported.insert(lang.id)
            }
        }
        return supported
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
