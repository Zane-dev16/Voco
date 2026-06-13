import Foundation
import Testing
@testable import Voco

@Suite("Hy-MT1.5 Q4_K_M Integration", .tags(.integration))
@MainActor
struct HyMT15Tests {

    @Test("Hy-MT1.5 translates correctly")
    func hyMT15Translation() async throws {
        let model = TranslationModel.availableModels.first { $0.id == "hy-mt1.5-1.8b-q4km" }
        #expect(model != nil, "Hy-MT1.5 model should be in catalog")

        guard let model = model else { return }

        #expect(model.config == .hunyuanMT, "Should use hunyuanMT config")

        let lifecycle = ModelLifecycleManager()
        try await lifecycle.activate(model)

        let result = try await lifecycle.translate("Hello", from: "English", to: "Spanish")

        print("[HyMT15Test] Raw output: \"\(result)\"")
        print("[HyMT15Test] Output length: \(result.count)")

        #expect(!result.isEmpty, "Translation should not be empty")

        await lifecycle.deactivate()
    }
}
