//
//  OutputProcessor.swift
//  Voco
//
//  Pure-function output post-processing for translation results.
//  No state, no I/O — testable without loading a model.
//

import Foundation

enum OutputProcessor {

    // MARK: - Thinking Tag Stripping

    /// Strips `<think>...</think>` reasoning blocks from model output.
    /// Also handles unclosed `<think>` (model cut off by maxTokenCount).
    static func stripThinkingTags(from text: String) -> String {
        var result = text
        // Strip complete <think>...</think> blocks
        while let start = result.range(of: "<think>"),
              let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        // If an unclosed <think> remains (model hit maxTokenCount mid-thought),
        // strip everything from <think> onward
        if let start = result.range(of: "<think>") {
            result = String(result[..<start.lowerBound])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Stop String Truncation

    /// Truncates output at the first occurrence of any configured stop string.
    /// Returns the text up to (but not including) the stop string, or the original
    /// text if no stop string is found.
    static func truncateAtStopStrings(_ text: String, stopStrings: [String]) -> String {
        guard !stopStrings.isEmpty else { return text }
        var earliestRange: Range<String.Index>?
        for stop in stopStrings {
            guard let range = text.range(of: stop) else { continue }
            if let existing = earliestRange {
                if range.lowerBound < existing.lowerBound {
                    earliestRange = range
                }
            } else {
                earliestRange = range
            }
        }
        guard let range = earliestRange else { return text }
        return String(text[..<range.lowerBound])
    }

    // MARK: - Prompt Marker Detection

    /// Strips prompt echo by finding the rawPromptMarker and returning everything after it.
    /// Returns the original text if no marker is found.
    static func stripPromptEcho(_ text: String, marker: String?) -> String {
        guard let marker = marker, let range = text.range(of: marker) else {
            return text
        }
        return String(text[range.upperBound...])
    }

    // MARK: - String Helpers

    /// Strips leading newlines and whitespace from the start of a string.
    /// Used to remove ChatML template newlines from streaming output.
    static func trimmingLeadingNewlines(_ text: String) -> String {
        var result = text
        while result.hasPrefix("\n") || result.hasPrefix("\r") {
            result = String(result.dropFirst())
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
