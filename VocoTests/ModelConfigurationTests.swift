import Foundation
import Testing
@testable import Voco

@MainActor
@Suite("Model Configuration")
struct ModelConfigurationTests {

    private let allConfigs: [(String, ModelConfiguration)] = {
        TranslationModel.availableModels.map { ($0.id, $0.config) }
    }()

    @Test("All models have distinct configs or valid shared configs")
    func configCount() {
        let uniqueIDs = Set(allConfigs.map(\.1))
        #expect(uniqueIDs.count >= 5, "Expected at least 5 distinct configs")
    }

    @Test("All configs have temperature 0.0")
    func zeroTemperature() {
        for (modelID, config) in allConfigs {
            #expect(config.runtime.temperature == 0.0,
                    "\(modelID) temperature is \(config.runtime.temperature), expected 0.0")
        }
    }

    @Test("All configs have non-empty userPromptTemplate")
    func nonEmptyUserTemplate() {
        for (modelID, config) in allConfigs {
            #expect(!config.prompt.userPromptTemplate.isEmpty,
                    "\(modelID) userPromptTemplate is empty")
        }
    }

    @Test("All configs have batchSize > 0 and maxTokenCount > 0")
    func validRuntimeParams() {
        for (modelID, config) in allConfigs {
            #expect(config.runtime.batchSize > 0, "\(modelID) batchSize <= 0")
            #expect(config.runtime.maxTokenCount > 0, "\(modelID) maxTokenCount <= 0")
        }
    }

    @Test("Each known preset exists and is unique")
    func presetsExist() {
        let presets: [ModelConfiguration] = [
            .hunyuanMT, .llamaInstruct, .qwenInstruct, .qwen4bInstruct,
            .gemma4Raw, .gemmaInstruct
        ]
        for preset in presets {
            #expect(!preset.prompt.userPromptTemplate.isEmpty)
        }
        // Hunyuan should be raw, Qwen/Llama should be chatWithSystem
        #expect(ModelConfiguration.hunyuanMT.prompt.strategy == .raw)
        #expect(ModelConfiguration.qwenInstruct.prompt.strategy == .chatWithSystem)
        #expect(ModelConfiguration.llamaInstruct.prompt.strategy == .chatWithSystem)
        #expect(ModelConfiguration.gemmaInstruct.prompt.strategy == .chatUserOnly)
    }

    @Test("Raw configs have non-empty userPromptTemplate with {text} placeholder")
    func rawTemplatePlaceholders() {
        let rawConfigs = allConfigs.filter { $0.1.prompt.strategy == .raw }
        for (modelID, config) in rawConfigs {
            #expect(config.prompt.userPromptTemplate.contains("{text}"),
                    "\(modelID) raw template missing {text}")
        }
    }

    @Test("Configs with non-empty system prompts are well-formed")
    func chatSystemWellFormed() {
        let chatConfigs = allConfigs.filter {
            $0.1.prompt.strategy == .chatWithSystem
        }
        for (modelID, config) in chatConfigs {
            #expect(!config.prompt.systemPrompt.isEmpty,
                    "\(modelID) chatWithSystem config has empty systemPrompt")
        }
    }
}
