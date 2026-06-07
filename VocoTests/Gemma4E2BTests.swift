import Foundation
import Testing
@testable import Voco

@Suite("Gemma 4 E2B Integration", .tags(.translation))
struct Gemma4E2BTests {
    
    @Test("Gemma 4 E2B translates with BOS disabled")
    func gemma4E2BTranslation() async throws {
        // Get the model
        let model = TranslationModel.availableModels.first { $0.id == "gemma-4-e2b-q4km" }
        #expect(model != nil, "Gemma 4 E2B model should be in catalog")
        
        guard let model = model else { return }
        
        // Verify config
        #expect(model.config == .gemma4Raw, "Should use gemma4Raw config")
        #expect(model.config.addBos == false, "Should have addBos = false")
        #expect(model.config.promptStrategy == .raw, "Should use raw prompt strategy")
        
        // Load the model
        let lifecycle = ModelLifecycleManager()
        try await lifecycle.activate(model)
        
        // Test translation
        let result = try await lifecycle.translate("Hello", from: "English", to: "Spanish")
        
        // Should not be empty and should not repeat the prompt
        #expect(!result.isEmpty, "Translation should not be empty")
        #expect(!result.contains("Hello\nSpanish:"), "Should not echo the prompt")
        
        await lifecycle.deactivate()
    }
}
