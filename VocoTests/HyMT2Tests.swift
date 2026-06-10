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

        // Print actual output for diagnosis
        print("[HyMT2Test] Raw output: \"\(result)\"")
        print("[HyMT2Test] Output length: \(result.count)")
        print("[HyMT2Test] Output bytes: \(Array(result.utf8))")

        // Should not be empty
        #expect(!result.isEmpty, "Translation should not be empty")

        await lifecycle.deactivate()
    }
}
