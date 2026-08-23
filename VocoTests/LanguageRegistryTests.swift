//
//  LanguageRegistryTests.swift
//  VocoTests
//
//  Coverage for the dynamic language registry (LanguageRegistry /
//  SupportedLanguage) powering LanguageSelectionView.
//
//  Capability-dependent assertions intentionally avoid device-specific
//  expectations: offline STT/TTS availability varies by device and installed
//  speech packs, so these tests validate structural invariants and lookup APIs
//  rather than which languages happen to be voice-capable on the host.
//

import Foundation
import Testing
@testable import Voco

@MainActor
@Suite("LanguageRegistry")
struct LanguageRegistryTests {

    private var registry: LanguageRegistry { LanguageRegistry.shared }

    // MARK: - Registry Contents

    @Test("Registry contains all 68 built-in languages")
    func registryCount() {
        #expect(registry.languages.count == 68)
    }

    @Test("Language IDs are unique")
    func uniqueIDs() {
        let ids = registry.languages.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Languages are sorted by display name")
    func sortedByDisplayName() {
        let names = registry.languages.map(\.displayName)
        #expect(names == names.sorted())
    }

    @Test("Every entry has well-formed metadata")
    func wellFormedEntries() {
        for lang in registry.languages {
            #expect(!lang.id.isEmpty)
            #expect(!lang.displayName.isEmpty)
            #expect(!lang.promptName.isEmpty)
            #expect(!lang.flag.isEmpty)
            #expect(lang.languageCode.count == 2, "\(lang.id) should derive a 2-letter code")
        }
    }

    @Test("languageCode is derived from the id prefix")
    func languageCodePrefix() {
        #expect(registry.language(forID: "zh-TW")?.languageCode == "zh")
        #expect(registry.language(forID: "en")?.languageCode == "en")
    }

    // MARK: - Lookups

    @Test("language(forID:) resolves known IDs and rejects unknown ones")
    func lookupByID() {
        for id in ["en", "es", "zh-TW", "ar"] {
            let lang = registry.language(forID: id)
            #expect(lang != nil, "Expected '\(id)' in registry")
            #expect(lang?.id == id)
        }
        #expect(registry.language(forID: "xx") == nil)
    }

    @Test("language(byName:) matches display and prompt names case-insensitively")
    func lookupByName() {
        #expect(registry.language(byName: "spanish")?.id == "es")
        #expect(registry.language(byName: "SPANISH")?.id == "es")
        #expect(registry.language(byName: "No Such Language") == nil)
    }

    @Test("language(forLegacy:) maps every legacy Language enum value")
    func lookupByLegacy() {
        for legacy in Language.allCases {
            let resolved = registry.language(forLegacy: legacy)
            #expect(resolved != nil, "Legacy \(legacy.rawValue) should resolve")
            #expect(resolved?.id == legacy.rawValue)
        }
    }

    @Test("languages(for:) respects model supportedLanguageCodes")
    func modelFiltering() {
        let unrestricted = TranslationModel.availableModels.first {
            $0.supportedLanguageCodes == nil
        }
        if let model = unrestricted {
            #expect(
                registry.languages(for: model).count == registry.languages.count,
                "Models without code restrictions see every language"
            )
        }

        for model in TranslationModel.availableModels {
            guard let codes = model.supportedLanguageCodes else { continue }
            let filtered = registry.languages(for: model)
            #expect(!filtered.isEmpty, "\(model.id) filtered list must not be empty")
            for lang in filtered {
                #expect(codes.contains(lang.id), "\(lang.id) unexpected for \(model.id)")
            }
        }
    }

    // MARK: - Capability Partitioning

    @Test("Voice and text-only lists partition the registry")
    func capabilityPartition() {
        let all = Set(registry.languages.map(\.id))
        let voice = Set(registry.voiceLanguages.map(\.id))
        let textOnly = Set(registry.textOnlyLanguages.map(\.id))

        #expect(voice.isDisjoint(with: textOnly))
        #expect(voice.union(textOnly) == all)

        for lang in registry.voiceLanguages {
            #expect(lang.supportsVoice)
        }
        for lang in registry.textOnlyLanguages {
            #expect(!lang.supportsVoice)
        }
    }

    @Test("Capability ID sets stay within the registry")
    func capabilityIDScopes() {
        let all = Set(registry.languages.map(\.id))
        #expect(registry.sttSupportedIDs.isSubset(of: all))
        #expect(registry.ttsSupportedIDs.isSubset(of: all))

        for lang in registry.languages where lang.supportsOfflineSTT {
            #expect(registry.sttSupportedIDs.contains(lang.id))
        }
        for lang in registry.languages where lang.supportsOfflineTTS {
            #expect(registry.ttsSupportedIDs.contains(lang.id))
        }
    }

    @Test("supportsVoice requires both offline STT and TTS")
    func supportsVoiceLogic() {
        var lang = SupportedLanguage(
            id: "zz", displayName: "Testish", promptName: "Testish",
            flag: "🏳️", hunyuanName: nil
        )
        #expect(!lang.supportsVoice)
        lang.supportsOfflineSTT = true
        #expect(!lang.supportsVoice, "STT alone must not enable voice mode")
        lang.supportsOfflineTTS = true
        #expect(lang.supportsVoice)
    }

    @Test("Comparable ordering follows display name")
    func comparableOrdering() {
        guard let english = registry.language(forID: "en"),
              let arabic = registry.language(forID: "ar") else {
            Issue.record("Expected en/ar entries in the registry")
            return
        }
        #expect(arabic < english) // "Arabic" < "English"
    }

    // MARK: - Config-Aware Naming

    @Test("Hunyuan configs prefer hunyuanName with promptName fallback")
    func configNaming() {
        guard let spanish = registry.language(forID: "es"),
              let dutch = registry.language(forID: "nl") else {
            Issue.record("Expected es/nl entries in the registry")
            return
        }
        // Spanish carries a Hunyuan-specific name; Dutch does not.
        #expect(registry.languageName(for: spanish, config: .hunyuanMT) == "Spanish")
        #expect(registry.languageName(for: dutch, config: .hunyuanMT) == "Dutch")

        // Non-Hunyuan configs always use the prompt name.
        #expect(registry.languageName(for: spanish, config: .qwenInstruct) == "Spanish")
        #expect(registry.sourceLanguageName(for: spanish, config: .hunyuanMT) == "Spanish")
    }
}
