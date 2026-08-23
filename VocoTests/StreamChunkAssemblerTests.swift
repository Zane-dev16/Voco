//
//  StreamChunkAssemblerTests.swift
//  VocoTests
//
//  Chunk-boundary tests: stop strings and <think> tags split across chunk
//  boundaries must never leak into emitted output (S7-03).
//

import XCTest
@testable import Voco

final class StreamChunkAssemblerTests: XCTestCase {

    // MARK: - Holdback Math

    func testHoldbackKeepsPartialStopSuffix() {
        // "\n" is a prefix of "\nTranslate to" — must be held back.
        XCTAssertEqual(StreamChunkAssembler.holdbackLength(of: "abc\n", markers: ["\nTranslate to"]), 1)
    }

    func testHoldbackZeroWhenNoMarkerMatches() {
        XCTAssertEqual(StreamChunkAssembler.holdbackLength(of: "hello", markers: ["\nTranslate to"]), 0)
        XCTAssertEqual(StreamChunkAssembler.holdbackLength(of: "", markers: ["stop"]), 0)
        XCTAssertEqual(StreamChunkAssembler.holdbackLength(of: "x", markers: ["stop"]), 0)
    }

    func testHoldbackPrefersLongestPartialMatch() {
        // "to" and "o" both prefix "Translate to"-style stops; longest wins.
        let markers = ["</think>", "<end>"]
        XCTAssertEqual(StreamChunkAssembler.holdbackLength(of: "text</thin", markers: markers), 6)
    }

    // MARK: - Raw Path: Stop Strings Split Across Chunks

    func testRawStopStringSplitAcrossChunksDoesNotLeak() {
        var asm = StreamChunkAssembler(stopStrings: ["\nTranslate to"], echoMarker: nil)
        var emitted = ""
        // Feed text so that the leading "\n" of the stop lands at a boundary.
        for token in ["Hello", " world", "\n", "Translate", " to", " more"] {
            for event in asm.append(token) {
                if case .emitted(let text) = event { emitted += text }
            }
        }
        _ = asm.flushRemaining()
        XCTAssertFalse(emitted.contains("\n"), "partial stop prefix leaked: \(emitted)")
        XCTAssertTrue(asm.didStop)
        // Everything before the stop string is preserved.
        XCTAssertTrue(emitted.contains("Hello"))
        XCTAssertTrue(emitted.contains("world"))
    }

    func testRawEchoMarkerSplitAcrossChunksIsConsumed() {
        var asm = StreamChunkAssembler(stopStrings: [], echoMarker: "<｜hy_Assistant｜>")
        var emitted = ""
        for token in ["<｜hy_", "Assistant", "｜>", "bonjour"] {
            for event in asm.append(token) {
                if case .emitted(let text) = event { emitted += text }
            }
        }
        emitted += asm.flushRemaining()
        XCTAssertTrue(asm.echoConsumed)
        XCTAssertEqual(emitted, "bonjour")
    }

    func testRawTailFlushedAtEndOfStream() {
        var asm = StreamChunkAssembler(stopStrings: ["\n\n"], echoMarker: nil)
        var emitted = ""
        for event in asm.append("final words") {
            if case .emitted(let text) = event { emitted += text }
        }
        // "words" may be held only if it prefixes a marker; here nothing held,
        // but regardless flushRemaining() must not lose the tail.
        emitted += asm.flushRemaining()
        XCTAssertEqual(emitted, "final words")
    }

    func testBoundedRetentionBeforeEchoMarker() {
        var asm = StreamChunkAssembler(stopStrings: [], echoMarker: "MARKER")
        for chunkIndex in 0..<100 {
            _ = asm.append("chunk-\(chunkIndex)-")
        }
        XCTAssertFalse(asm.echoConsumed)
        XCTAssertLessThanOrEqual(asm.buffer.count, 500, "pre-marker buffer must stay bounded")
    }

    // MARK: - Chat Path: Think Tags Split Across Chunks

    func testThinkTagSplitAcrossChunksIsDetectedAndSuppressed() {
        var asm = StreamChunkAssembler(stopStrings: ["<|im_end|>"], watchesThinkTags: true)
        var emitted = ""
        // Split "<think>" across three chunks.
        for token in ["Hi ", "<thi", "nk>", "reasoning ", "</th", "ink>", "answer"] {
            for event in asm.append(token) {
                switch event {
                case .emitted(let text):
                    emitted += text
                default:
                    break
                }
            }
        }
        emitted += asm.flushRemaining()
        XCTAssertTrue(asm.inThinkBlock == false || !asm.inThinkBlock)
        XCTAssertFalse(emitted.contains("reasoning"), "reasoning leaked: \(emitted)")
        XCTAssertTrue(emitted.contains("answer"))
    }

    func testTextBeforeThinkTagIsEmitted() {
        var asm = StreamChunkAssembler(stopStrings: [], watchesThinkTags: true)
        var events: [StreamChunkAssembler.Event] = []
        events += asm.append("Sure! ")
        events += asm.append("<th")
        events += asm.append("ink>")
        guard case .emitted(let before)? = events.first(where: { if case .emitted = $0 { return true }; return false }) else {
            return XCTFail("expected emitted event for pre-think text, got \(events)")
        }
        XCTAssertTrue(before.contains("Sure!"))
    }

    func testChatStopStringInsideThinkBlockStopsWithoutEmittingReasoning() {
        var asm = StreamChunkAssembler(stopStrings: ["END"], watchesThinkTags: true)
        _ = asm.append("<think>")
        _ = asm.append("secret ")
        let events = asm.append("EN")
        _ = asm.append("D")
        XCTAssertTrue(asm.didStop)
        for event in events {
            if case .stopHit(let before) = event {
                XCTAssertTrue(before.contains("secret"), "stop payload should carry reasoning-era text for caller to suppress")
            }
        }
    }

    func testAppendAfterStopIsIgnored() {
        var asm = StreamChunkAssembler(stopStrings: ["STOP"], echoMarker: nil)
        _ = asm.append("aSTOPb")
        XCTAssertTrue(asm.didStop)
        let events = asm.append("more")
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(asm.buffer, "")
    }

    func testEmittedTextNeverContainsPartialStopPrefix() {
        // Property-style sweep: no emitted fragment may end with a proper
        // prefix of any stop string longer than zero chars.
        let stops = ["\nUser:", "<|im_end|>"]
        var asm = StreamChunkAssembler(stopStrings: stops, echoMarker: nil)
        let tokens = ["A", "\n", "Use", "r:", "B", "<|", "im_en", "d|>", "C"]
        for token in tokens {
            for event in asm.append(token) {
                if case .emitted(let fragment) = event {
                    for stop in stops {
                        for prefixLength in 1..<min(stop.count, fragment.count + 1) {
                            let suffix = String(fragment.suffix(prefixLength))
                            XCTAssertFalse(
                                stop.hasPrefix(suffix) && suffix != stop,
                                "emitted '\(fragment)' ends with partial stop '\(suffix)'"
                            )
                        }
                    }
                }
            }
        }
    }
}
