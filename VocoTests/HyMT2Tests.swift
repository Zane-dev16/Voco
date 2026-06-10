import Foundation
import Testing
@testable import Voco

@Suite("Hy-MT2 STQ1_0 Integration", .tags(.integration))
@MainActor
struct HyMT2Tests {

    @Test("Hy-MT2 translates correctly via generic kernel")
    func hyMT2Translation() async throws {
        let model = TranslationModel.availableModels.first { $0.id == "hy-mt2-1.8b-stq" }
        #expect(model != nil, "Hy-MT2 model should be in catalog")

        guard let model = model else { return }

        #expect(model.config == .hunyuanMT, "Should use hunyuanMT config")
        #expect(model.config.prompt.strategy == .raw, "Should use raw prompt strategy")

        let lifecycle = ModelLifecycleManager()
        try await lifecycle.activate(model)

        let result = try await lifecycle.translate("Hello", from: "English", to: "Spanish")

        // Should not be empty
        #expect(!result.isEmpty, "Translation should not be empty")

        // Should not contain garbage (Korean, Chinese, Cyrillic characters)
        let hasGarbage = result.unicodeScalars.contains { scalar in
            // Korean Hangul
            (0xAC00...0xD7AF).contains(scalar.value) ||
            // CJK Unified Ideographs
            (0x4E00...0x9FFF).contains(scalar.value) ||
            // Cyrillic
            (0x0400...0x04FF).contains(scalar.value)
        }
        #expect(!hasGarbage, "Should not contain garbage characters (Korean/CJK/Cyrillic). Got: \(result)")

        // Should contain some Latin characters (Spanish is Latin-script)
        let hasLatin = result.unicodeScalars.contains { scalar in
            (0x0041...0x007A).contains(scalar.value) || // A-Z, a-z
            (0x00C0...0x024F).contains(scalar.value)    // Latin Extended
        }
        #expect(hasLatin, "Should contain Latin characters for Spanish. Got: \(result)")

        await lifecycle.deactivate()
    }
}
