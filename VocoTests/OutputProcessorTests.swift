import Foundation
import Testing
@testable import Voco

@MainActor
@Suite("OutputProcessor")
struct OutputProcessorTests {

    // MARK: - Thinking Tag Stripping

    @Test("Strips complete thinking blocks")
    func stripCompleteThinking() {
        let input = "<think>Let me think about this.</think>Hola"
        let result = OutputProcessor.stripThinkingTags(from: input)
        #expect(result == "Hola")
    }

    @Test("Strips unclosed thinking block (model hit maxTokenCount)")
    func stripUnclosedThinking() {
        let input = "<think>Let me think about this more carefully and"
        let result = OutputProcessor.stripThinkingTags(from: input)
        #expect(result == "")
    }

    @Test("Passes through text with no thinking tags")
    func noThinkingTags() {
        let input = "Hola, ¿cómo estás?"
        let result = OutputProcessor.stripThinkingTags(from: input)
        #expect(result == "Hola, ¿cómo estás?")
    }

    @Test("Strips multiple thinking blocks")
    func multipleThinkingBlocks() {
        let input = "<think>first<think>second</think>Hola"
        let result = OutputProcessor.stripThinkingTags(from: input)
        #expect(result == "Hola")
    }

    // MARK: - Stop String Truncation

    @Test("Truncates at first stop string")
    func truncateAtStop() {
        let result = OutputProcessor.truncateAtStopStrings(
            "Hola\nSpanish:", stopStrings: ["\nSpanish:", "\nFrench:"]
        )
        #expect(result == "Hola")
    }

    @Test("Returns original when no stop string matches")
    func noStopMatch() {
        let result = OutputProcessor.truncateAtStopStrings(
            "Hola", stopStrings: ["\nSpanish:"]
        )
        #expect(result == "Hola")
    }

    @Test("Returns original when stop strings is empty")
    func emptyStopStrings() {
        let result = OutputProcessor.truncateAtStopStrings("Hola", stopStrings: [])
        #expect(result == "Hola")
    }

    @Test("Truncates at earliest stop string when multiple match")
    func earliestStop() {
        let result = OutputProcessor.truncateAtStopStrings(
            "Hello STOP World STOP", stopStrings: ["STOP", "World"]
        )
        #expect(result == "Hello ")
    }

    // MARK: - Prompt Echo Stripping

    @Test("Strips prompt echo with marker")
    func stripPromptEcho() {
        let input = "English → Spanish:\nHola"
        let result = OutputProcessor.stripPromptEcho(input, marker: "English → Spanish:\n")
        #expect(result == "Hola")
    }

    @Test("Returns original when no marker")
    func noMarker() {
        let result = OutputProcessor.stripPromptEcho("Hola", marker: nil)
        #expect(result == "Hola")
    }

    @Test("Returns original when marker not found")
    func markerNotFound() {
        let result = OutputProcessor.stripPromptEcho("Hola", marker: "XYZ")
        #expect(result == "Hola")
    }

    // MARK: - Leading Newlines

    @Test("Strips leading newlines")
    func leadingNewlines() {
        let result = OutputProcessor.trimmingLeadingNewlines("\n\n\nHola")
        #expect(result == "Hola")
    }

    @Test("Passes through text without leading newlines")
    func noLeadingNewlines() {
        let result = OutputProcessor.trimmingLeadingNewlines("Hola")
        #expect(result == "Hola")
    }
}
