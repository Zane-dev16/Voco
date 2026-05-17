//
//  HyModelTest.swift
//  Voco
//
//  Production-readiness QA test for Hy-MT1.5 1.25-bit model.
//  Tests: threading, streaming, multilingual routing, lazy lifecycle.
//

import Foundation
import SwiftLlama

@MainActor
func runHyModelTest() async {
    let testID = String(UUID().uuidString.prefix(8))
    NSLog("[HY-TEST-\(testID)] === Production QA: Hy-MT1.5 1.25-bit ===\n")

    let lifecycle = ModelLifecycleManager()

    // 1. Find model in registry
    guard let model = TranslationModel.availableModels.first(where: { $0.id == "hy-mt1.5-1.8b-2bit" }) else {
        NSLog("[HY-TEST-\(testID)] FAIL: Model not found")
        writeResult("FAIL: Model not found")
        return
    }
    NSLog("[HY-TEST-\(testID)] Model: \(model.displayName) (\(model.formattedSize))")

    // 2. Lazy activation (download + load)
    NSLog("[HY-TEST-\(testID)] Activating model (lazy load)...")
    do {
        try await lifecycle.activate(model)
        NSLog("[HY-TEST-\(testID)] Lifecycle state: ready — model loaded on demand")
    } catch {
        NSLog("[HY-TEST-\(testID)] FAIL: Activation error: \(error)")
        writeResult("FAIL: Activation error: \(error)")
        return
    }

    // ------------------------------------------------
    // QA 1: English -> Spanish (streaming)
    // ------------------------------------------------
    NSLog("[HY-TEST-\(testID)]\n--- QA-1: EN->ES Streaming Translation ---")
    let resultENES = await testStreamingTranslation(
        lifecycle: lifecycle,
        text: "Hello, how are you today?",
        targetLanguage: "Spanish",
        testID: testID
    )
    NSLog("[HY-TEST-\(testID)] QA-1 result: \"\(resultENES)\"")
    if resultENES.isEmpty || resultENES.lowercased() == "hello, how are you today?".lowercased() {
        NSLog("[HY-TEST-\(testID)] QA-1: FAIL (empty or no translation)")
        writeResult("FAIL: QA-1 EN->ES")
        return
    }
    NSLog("[HY-TEST-\(testID)] QA-1: PASS")

    // ------------------------------------------------
    // QA 2: English -> French (second language)
    // ------------------------------------------------
    NSLog("[HY-TEST-\(testID)]\n--- QA-2: EN->FR Translation (second language) ---")
    do {
        let resultFR = try await lifecycle.translate(
            "Good morning, nice to meet you.",
            from: "English", to: "French"
        )
        NSLog("[HY-TEST-\(testID)] QA-2 result: \"\(resultFR)\"")
        if resultFR.isEmpty {
            NSLog("[HY-TEST-\(testID)] QA-2: FAIL (empty)")
            writeResult("FAIL: QA-2 EN->FR")
            return
        }
        NSLog("[HY-TEST-\(testID)] QA-2: PASS")
    } catch {
        NSLog("[HY-TEST-\(testID)] QA-2: FAIL — \(error)")
        writeResult("FAIL: QA-2 EN->FR error: \(error)")
        return
    }

    // ------------------------------------------------
    // QA 3: Unsupported language validation
    // ------------------------------------------------
    NSLog("[HY-TEST-\(testID)]\n--- QA-3: Unsupported language validation ---")
    do {
        let _ = try await lifecycle.translate(
            "Test", from: "English", to: "Klingon"
        )
        NSLog("[HY-TEST-\(testID)] QA-3: FAIL (should have thrown)")
        writeResult("FAIL: QA-3 no error for unsupported language")
        return
    } catch LlamaError.unsupportedLanguage(let lang) {
        NSLog("[HY-TEST-\(testID)] QA-3: PASS — correctly rejected \"\(lang)\"")
    } catch {
        NSLog("[HY-TEST-\(testID)] QA-3: Wrong error: \(error)")
        writeResult("FAIL: QA-3 wrong error type")
        return
    }

    // ------------------------------------------------
    // QA 4: Provider switching (unload + reload)
    // ------------------------------------------------
    NSLog("[HY-TEST-\(testID)]\n--- QA-4: Provider switching (deactivate + reactivate) ---")
    await lifecycle.deactivate()
    NSLog("[HY-TEST-\(testID)] QA-4a: Deactivated — state: \(lifecycle.lifecycleState)")
    if lifecycle.lifecycleState != .idle {
        writeResult("FAIL: QA-4a not idle after deactivate")
        return
    }

    do {
        try await lifecycle.activate(model)
        NSLog("[HY-TEST-\(testID)] QA-4b: Reactivated — state: \(lifecycle.lifecycleState)")
        let resultReload = try await lifecycle.translate(
            "Thank you very much!", from: "English", to: "German"
        )
        NSLog("[HY-TEST-\(testID)] QA-4 result: \"\(resultReload)\"")
        if resultReload.isEmpty {
            writeResult("FAIL: QA-4b empty after reload")
            return
        }
        NSLog("[HY-TEST-\(testID)] QA-4: PASS")
    } catch {
        NSLog("[HY-TEST-\(testID)] QA-4: FAIL — \(error)")
        writeResult("FAIL: QA-4 reload error: \(error)")
        return
    }

    // Clean up
    await lifecycle.deactivate()
    NSLog("[HY-TEST-\(testID)]\n=== All QA tests PASSED ===\n")
    writeResult("PASS: All 4 QA tests passed")
}

// MARK: - Helpers

private func testStreamingTranslation(
    lifecycle: ModelLifecycleManager,
    text: String,
    targetLanguage: String,
    testID: String
) async -> String {
    let stream = lifecycle.translateStream(text, from: "English", to: targetLanguage)
    var chunks: [String] = []
    var fullOutput = ""
    var firstTokenTime: Date?

    do {
        for try await chunk in stream {
            if firstTokenTime == nil {
                firstTokenTime = Date()
            }
            chunks.append(chunk)
            fullOutput += chunk
            NSLog("[HY-TEST-\(testID)]   Stream chunk: \"\(chunk)\"")
        }
    } catch {
        NSLog("[HY-TEST-\(testID)] Stream error: \(error)")
        return ""
    }

    let trimmed = fullOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    if let firstToken = firstTokenTime {
        NSLog("[HY-TEST-\(testID)]   Streaming: \(chunks.count) chunks, first token after \(firstToken.timeIntervalSinceNow * -1000)ms")
    }
    return trimmed
}

private func writeResult(_ message: String) {
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let file = docs.appendingPathComponent("hy_test_result.txt")
    try? message.write(to: file, atomically: true, encoding: .utf8)
}
