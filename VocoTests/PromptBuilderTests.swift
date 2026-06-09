import Foundation
import Testing
@testable import Voco

@Suite("PromptBuilder")
struct PromptBuilderTests {

    // MARK: - Chat Messages

    @Test("chatWithSystem returns system + user messages")
    func chatWithSystem() {
        let config = ModelConfiguration.qwenInstruct
        let messages = PromptBuilder.buildMessages(
            text: "Hello", source: "English", target: "Spanish", config: config
        )
        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        #expect(messages[1].role == .user)
        #expect(messages[1].content.contains("Hello"))
        #expect(messages[1].content.contains("Spanish"))
    }

    @Test("chatUserOnly returns only user message")
    func chatUserOnly() {
        let config = ModelConfiguration.gemmaInstruct
        let messages = PromptBuilder.buildMessages(
            text: "Hello", source: "English", target: "French", config: config
        )
        #expect(messages.count == 1)
        #expect(messages[0].role == .user)
        #expect(messages[0].content.contains("Hello"))
        #expect(messages[0].content.contains("French"))
    }

    // MARK: - Raw Prompts

    @Test("formatRawPrompt substitutes placeholders for Tencent config")
    func rawPromptTencent() {
        let config = ModelConfiguration.hunyuanMT
        let prompt = PromptBuilder.formatRawPrompt(
            text: "Good morning", sourceLanguage: "English",
            targetLanguage: "Spanish", config: config
        )
        #expect(prompt.contains("Good morning"))
        #expect(prompt.contains("Spanish"))
        #expect(!prompt.contains("{text}"))
        #expect(!prompt.contains("{target}"))
    }

    @Test("formatRawPrompt substitutes placeholders for Gemma 4 config")
    func rawPromptGemma4() {
        let config = ModelConfiguration.gemma4Raw
        let prompt = PromptBuilder.formatRawPrompt(
            text: "Thank you", sourceLanguage: "English",
            targetLanguage: "German", config: config
        )
        #expect(prompt.contains("Thank you"))
        #expect(prompt.contains("German"))
        #expect(!prompt.contains("{text}"))
        #expect(!prompt.contains("{target}"))
    }
}
