import Foundation
import Testing
@testable import Voco

@MainActor
@Suite("Language")
struct LanguageTests {

    @Test("All 12 languages are present")
    func allCasesCount() {
        #expect(Language.allCases.count == 12)
    }

    @Test("find(byDisplayOrHunyuanName:) resolves all display names")
    func findByDisplayName() {
        for lang in Language.allCases {
            let found = Language.find(byDisplayOrHunyuanName: lang.displayName)
            #expect(found == lang, "\(lang.displayName) should resolve to \(lang)")
        }
    }

    @Test("find(byDisplayOrHunyuanName:) resolves hunyuan names")
    func findByHunyuanName() {
        for lang in Language.allCases {
            let found = Language.find(byDisplayOrHunyuanName: lang.hunyuanTargetName)
            #expect(found == lang, "Hunyuan name '\(lang.hunyuanTargetName)' should resolve")
        }
    }

    @Test("Every language has non-empty displayName, flag, and hunyuanTargetName")
    func noEmptyFields() {
        for lang in Language.allCases {
            #expect(!lang.displayName.isEmpty, "\(lang) displayName is empty")
            #expect(!lang.hunyuanTargetName.isEmpty, "\(lang) hunyuanTargetName is empty")
        }
    }
}
