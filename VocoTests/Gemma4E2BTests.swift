import Foundation
import Testing
@testable import Voco

extension Tag {
    @Tag static var integration: Self
}

@Suite("Gemma 4 E2B Integration", .tags(.integration))
@MainActor
struct Gemma4E2BTests {

    @Test("Gemma 4 E2B translates with BOS disabled")
    func gemma4E2BTranslation() async throws {
        let model = TranslationModel.availableModels.first { $0.id == "gemma-4-e2b-q4km" }
        #expect(model != nil, "Gemma 4 E2B model should be in catalog")

        guard let model = model else { return }

        #expect(model.config == .gemma4Raw, "Should use gemma4Raw config")
        #expect(model.config.prompt.addBos == true, "Should have addBos = true")
        #expect(model.config.prompt.strategy == .raw, "Should use raw prompt strategy")

        let lifecycle = ModelLifecycleManager()
        try await lifecycle.activate(model)
        let result = try await lifecycle.translate("Hello", from: "English", to: "Spanish")
        #expect(!result.isEmpty, "Translation should not be empty")
        #expect(!result.contains("Hello\nSpanish:"), "Should not echo the prompt")
        await lifecycle.deactivate()
    }
}
