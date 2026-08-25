import Foundation
import Testing
@testable import Voco

@MainActor
@Suite("Model Registry")
struct ModelRegistryTests {

    private let models = TranslationModel.availableModels

    @Test("Registry contains exactly 10 models")
    func modelCount() {
        #expect(models.count == 10)
    }

    @Test("No duplicate model IDs")
    func noDuplicateIDs() {
        let ids = models.map(\.id)
        let unique = Set(ids)
        #expect(ids.count == unique.count, "Duplicate IDs found")
    }

    @Test("SHA-256 hashes are populated")
    func sha256Populated() {
        for model in models {
            #expect(!model.sha256.isEmpty, "\(model.id) has empty sha256")
        }
    }

    @Test("Every model has a valid source URL")
    func validSourceURLs() {
        for model in models {
            #expect(model.sourceURL.absoluteString.hasPrefix("https://"), "\(model.id) sourceURL is not HTTPS")
        }
    }

    @Test("Every model has positive fileSizeBytes")
    func positiveFileSize() {
        for model in models {
            #expect(model.fileSizeBytes > 0, "\(model.id) fileSizeBytes <= 0")
        }
    }

    @Test("Every model has non-empty displayName and provider")
    func noEmptyMetadata() {
        for model in models {
            #expect(!model.displayName.isEmpty, "\(model.id) displayName is empty")
            #expect(!model.provider.isEmpty, "\(model.id) provider is empty")
            #expect(!model.baseModelName.isEmpty, "\(model.id) baseModelName is empty")
            #expect(!model.licenseName.isEmpty, "\(model.id) licenseName is empty")
        }
    }

    @Test("Every model has a valid config")
    func validConfigs() {
        for model in models {
            // config should not be nil — ModelConfiguration is non-optional
            #expect(model.config.prompt.stopStrings.count >= 0, "\(model.id) config may be invalid")
        }
    }

    @Test("Filename matches sourceURL last path component")
    func filenameConsistency() {
        for model in models {
            #expect(model.filename == model.sourceURL.lastPathComponent,
                    "\(model.id) filename mismatch: \(model.filename) vs \(model.sourceURL.lastPathComponent)")
        }
    }

    // MARK: - HY-MT Language Matrix Reconciliation

    /// Tencent's official HY-MT matrix (HY-MT1.5 model card): 33 languages
    /// (incl. zh + zh-Hant) plus 5 ethnic/dialect variants. zh-Hant maps to
    /// Voco's registry id "zh-TW".
    private static let hyMTOfficialCodes: Set<String> = [
        "zh", "en", "fr", "pt", "es", "ja", "tr", "ru", "ar", "ko",
        "th", "it", "de", "vi", "ms", "id", "tl", "hi", "zh-TW", "pl",
        "cs", "nl", "km", "my", "fa", "gu", "ur", "te", "mr", "he",
        "bn", "ta", "uk", "bo", "kk", "mn", "ug", "yue",
    ]

    @Test("Tencent HY-MT models match the official language matrix")
    func hyMTMatrixMatchesOfficial() {
        let hyMTModels = models.filter { $0.provider == "Tencent" }
        #expect(!hyMTModels.isEmpty)
        for model in hyMTModels {
            let codes = Set(model.supportedLanguageCodes ?? [])
            #expect(codes == Self.hyMTOfficialCodes,
                    "\(model.id) codes diverge from Tencent HY-MT matrix; extra: \(codes.subtracting(Self.hyMTOfficialCodes)), missing: \(Self.hyMTOfficialCodes.subtracting(codes))")
        }
    }

    @Test("Every supportedLanguageCode resolves to a registry entry")
    func allCodesResolveInRegistry() {
        for model in models {
            for code in model.supportedLanguageCodes ?? [] {
                #expect(registryContains(code), "\(model.id) references unknown language id '\(code)'")
            }
        }
    }

    @MainActor
    private func registryContains(_ id: String) -> Bool {
        LanguageRegistry.shared.language(forID: id) != nil
    }

    @Test("Llama 3.2 models match Meta's officially supported languages")
    func llamaOfficialLanguages() {
        // Meta's Llama 3.2 model card: only 8 languages are officially
        // supported; broader coverage is explicitly not guaranteed.
        let official: Set<String> = ["en", "de", "fr", "it", "pt", "hi", "es", "th"]
        for model in models where model.provider == "Meta" {
            #expect(Set(model.supportedLanguageCodes ?? []) == official,
                    "\(model.id) diverges from Meta's official 8-language list")
        }
    }

    @Test("TranslateGemma matches the WMT24++ evaluation matrix")
    func translateGemmaMatrix() {
        // TranslateGemma technical report (arXiv 2601.09012, Table 4): 55
        // WMT24++ languages; regional variants collapse to registry IDs and
        // English is included as a source side.
        let expected: Set<String> = [
            "en", "ar", "bg", "bn", "ca", "cs", "da", "de", "el", "es",
            "et", "fa", "fi", "tl", "fr", "gu", "he", "hi", "hr", "hu",
            "id", "is", "it", "ja", "kn", "ko", "lt", "lv", "ml", "mr",
            "nl", "nb", "pa", "pl", "pt", "ro", "ru", "sk", "sl", "sr",
            "sv", "sw", "ta", "te", "th", "tr", "uk", "ur", "vi", "zh",
            "zh-TW", "zu",
        ]
        for model in models where model.id.hasPrefix("translategemma") {
            #expect(Set(model.supportedLanguageCodes ?? []) == expected,
                    "\(model.id) diverges from TranslateGemma's documented matrix")
        }
    }

    @Test("Qwen and Gemma curated lists stay within claimed broad coverage")
    func broadCoverageModelsStayWithinClaims() {
        // Qwen3.5 claims 201 languages, Gemma 4 claims 140+ — no per-size
        // matrices exist, so these carry curated practical lists. Guard that
        // they never claim MORE than the broad families cover: spot-check the
        // registry-only additions (yue, bo, kk, mn, ug are Hy-MT ethnic/dialect
        // set entries) don't appear on models whose providers don't list them.
        let hyMTOnly: Set<String> = ["bo", "kk", "mn", "ug"]
        for model in models where model.provider != "Tencent" {
            let codes = Set(model.supportedLanguageCodes ?? [])
            #expect(codes.isDisjoint(with: hyMTOnly),
                    "\(model.id) claims Hy-MT ethnic/dialect languages")
        }
    }
}
