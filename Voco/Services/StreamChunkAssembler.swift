//
//  StreamChunkAssembler.swift
//  Voco
//
//  Pure incremental buffer state machine shared by both streaming translation
//  producer paths. Tokens flow in; only text that can never still become part
//  of a partially-received marker (prompt-echo marker, stop strings,
//  <think> tags) flows out. This closes the chunk-boundary leak where a stop
//  string or tag split across two chunks was never matched and leaked verbatim
//  into the translation output.
//

import Foundation

/// Incremental assembler for streamed translation tokens.
///
/// Feed every token via ``append(_:)`` and handle the returned events in order.
/// The assembler owns the pending buffer: completed markers are consumed and
/// reported as events, and text is emitted only once no suffix of it could
/// still grow into a watched marker.
///
/// Explicitly `nonisolated`: the project compiles with
/// SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor, but this type is pure value
/// logic with no shared mutable state — usable from any isolation domain.
nonisolated struct StreamChunkAssembler {
    enum Event: Equatable {
        /// Text safe to display now (never empty).
        case emitted(String)
        /// The prompt-echo marker was found; everything through it was dropped.
        case echoStripped
        /// A `<think>` block opened; carries the text that preceded the tag.
        case thinkOpened(before: String)
        /// The matching `</think>` closed; following text resumes normal flow.
        case thinkClosed
        /// A completed stop string ended generation; carries the text before it.
        case stopHit(before: String)
    }

    /// Pending, not-yet-emitted text.
    private(set) var buffer = ""
    /// True once the prompt-echo marker has been consumed (or none configured).
    private(set) var echoConsumed: Bool
    /// True after a stop string fired; further appends are ignored.
    private(set) var didStop = false
    /// Think-block depth state (instruction models that emit reasoning).
    private(set) var inThinkBlock = false

    private let stopStrings: [String]
    private let echoMarker: String?
    private let watchesThinkTags: Bool

    /// - Parameters:
    ///   - stopStrings: Strings that terminate generation when completed.
    ///   - echoMarker: Optional prompt-echo marker consumed before any output.
    ///   - watchesThinkTags: Whether `<think>`/`</think>` transitions apply.
    init(stopStrings: [String], echoMarker: String? = nil, watchesThinkTags: Bool = false) {
        self.stopStrings = stopStrings
        self.echoMarker = echoMarker
        self.watchesThinkTags = watchesThinkTags
        self.echoConsumed = (echoMarker == nil)
    }

    /// Feed one token; returns the resulting events in processing order.
    mutating func append(_ token: String) -> [Event] {
        guard !didStop else { return [] }
        buffer += token
        var events: [Event] = []

        // Phase 1: prompt-echo gate (raw-format translation models).
        guard consumeEchoMarkerIfNeeded(into: &events) else { return events }

        // Phase 2: a completed stop string outranks everything else. Scanned
        // regardless of think state (matches historical behavior).
        if let range = Self.firstStopRange(in: buffer, stopStrings: stopStrings) {
            let before = String(buffer[..<range.lowerBound])
            buffer = ""
            didStop = true
            events.append(.stopHit(before: before))
            return events
        }

        // Phase 3: think-tag transitions.
        if watchesThinkTags {
            if !inThinkBlock, let range = buffer.range(of: "<think>") {
                let before = String(buffer[..<range.lowerBound])
                buffer = String(buffer[range.upperBound...])
                inThinkBlock = true
                events.append(.thinkOpened(before: before))
            } else if inThinkBlock, let range = buffer.range(of: "</think>") {
                buffer = String(buffer[range.upperBound...])
                inThinkBlock = false
                events.append(.thinkClosed)
            }
        }

        // Phase 4: partial-safe flush — hold back any suffix that could still
        // complete a watched marker split across chunk boundaries.
        //
        // Stop strings stay watched inside think blocks: without them, the
        // aggressive per-token flush would discard their fragments before a
        // later chunk could complete them (e.g. "<|im_end|>"). Text destined
        // for display while inside a think block is dropped outright —
        // reasoning must never reach the user.
        let watchList: [String]
        if watchesThinkTags {
            watchList = inThinkBlock ? ["</think>"] + stopStrings : stopStrings + ["<think>"]
        } else {
            watchList = stopStrings
        }
        let hold = Self.holdbackLength(of: buffer, markers: watchList)
        let emitCount = buffer.count - hold
        if emitCount > 0 {
            if !inThinkBlock {
                events.append(.emitted(String(buffer.prefix(emitCount))))
            }
            buffer = String(buffer.dropFirst(emitCount))
        }

        return events
    }

    /// Consumes the prompt-echo marker when present. Returns false while still
    /// waiting for it (buffer retained, bounded so a missing marker can't grow
    /// the buffer without limit).
    private mutating func consumeEchoMarkerIfNeeded(into events: inout [Event]) -> Bool {
        guard !echoConsumed else { return true }
        if let marker = echoMarker, let range = buffer.range(of: marker) {
            buffer = String(buffer[range.upperBound...])
            echoConsumed = true
            events.append(.echoStripped)
            return true
        }
        if buffer.count > 500 {
            buffer = String(buffer.suffix(200))
        }
        return false
    }

    /// Remaining buffered text at end-of-stream. Always drain this after the
    /// token loop (when the stream wasn't stopped early) or tails get lost.
    mutating func flushRemaining() -> String {
        defer { buffer = "" }
        return buffer
    }

    // MARK: - Buffer Analysis

    /// First completed stop-string occurrence in `buffer`, if any.
    static func firstStopRange(in buffer: String, stopStrings: [String]) -> Range<String.Index>? {
        guard !stopStrings.isEmpty else { return nil }
        for stop in stopStrings where buffer.contains(stop) {
            if let range = buffer.range(of: stop) {
                return range
            }
        }
        return nil
    }

    /// Length of the longest suffix of `text` that is a proper prefix of some
    /// marker — that suffix might still grow into a full marker arriving in a
    /// later chunk, so it must stay buffered instead of being emitted.
    ///
    /// Example: buffer `"abc\n"` with stop `"\nTranslate to"` keeps the `"\n"`
    /// (1 char); emitting it wholesale would make the stop string permanently
    /// unmatched, because later chunks land in a fresh buffer.
    static func holdbackLength(of text: String, markers: [String]) -> Int {
        guard !markers.isEmpty else { return 0 }
        let longestMarker = markers.map(\.count).max() ?? 0
        // Whole-buffer holds are valid: "<|" is entirely a partial "<|im_end|>".
        // Completed markers never reach here — containment is handled earlier.
        let limit = min(longestMarker - 1, text.count)
        guard limit >= 1 else { return 0 }
        // Longest-first: hold as little as possible.
        for candidate in stride(from: limit, through: 1, by: -1) {
            let suffix = String(text.suffix(candidate))
            if markers.contains(where: { $0.hasPrefix(suffix) }) {
                return candidate
            }
        }
        return 0
    }
}
