//
//  HyModelTest.swift
//  Voco
//
//  Temporary integration test for Hy-MT1.5 model.
//  Run once then remove.
//

import Foundation
import SwiftLlama

@MainActor
func runHyModelTest() async {
    let testID = UUID().uuidString.prefix(8)
    NSLog("[HY-TEST-\(testID)] === Starting Hy-MT1.5 model integration test ===")

    // 1. Find the model in registry
    guard let model = TranslationModel.availableModels.first(where: { $0.id == "hy-mt1.5-1.8b-2bit" }) else {
        NSLog("[HY-TEST-\(testID)] FAIL: Model 'hy-mt1.5-1.8b-2bit' not found in registry")
        writeResult("FAIL: Model not found")
        return
    }
    NSLog("[HY-TEST-\(testID)] Found model: \(model.displayName) (\(model.formattedSize))")

    // 2. Check if already downloaded
    let manager = ModelManagerService()
    var localURL: URL? = manager.localURL(for: model)

    if localURL == nil {
        NSLog("[HY-TEST-\(testID)] Downloading model via URLSession...")
        manager.download(model)

        // Poll download state (max 10 min)
        var attempts = 0
        while attempts < 600 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            if let url = manager.localURL(for: model) {
                localURL = url
                NSLog("[HY-TEST-\(testID)] Download complete")
                break
            }

            if case .failed(let msg) = manager.downloadStates[model.id] {
                NSLog("[HY-TEST-\(testID)] FAIL: Download failed: \(msg)")
                writeResult("FAIL: Download error: \(msg)")
                return
            }

            attempts += 1
        }
    } else {
        NSLog("[HY-TEST-\(testID)] Model already downloaded at: \(localURL!.path)")
    }

    guard let finalURL = localURL else {
        NSLog("[HY-TEST-\(testID)] FAIL: Timeout waiting for download")
        writeResult("FAIL: Download timeout")
        return
    }

    // Verify file size
    let attrs = try? FileManager.default.attributesOfItem(atPath: finalURL.path)
    let actualSize = (attrs?[.size] as? Int64) ?? 0
    NSLog("[HY-TEST-\(testID)] File size: \(actualSize) bytes (expected: \(model.fileSizeBytes))")

    // 3. Load model into LlamaService
    let service = LlamaService()
    do {
        try await service.loadModel(model, at: finalURL)
        NSLog("[HY-TEST-\(testID)] Model loaded successfully")
    } catch {
        NSLog("[HY-TEST-\(testID)] FAIL: Model load error: \(error)")
        writeResult("FAIL: Model load error: \(error)")
        return
    }

    // 4. Test translation EN -> ES
    let testPhrase = "Hello, how are you today?"
    NSLog("[HY-TEST-\(testID)] Translating: '\(testPhrase)'")
    do {
        let result = try await service.translate(testPhrase, from: "English", to: "Spanish")
        NSLog("[HY-TEST-\(testID)] Raw result: '\(result)'")

        // Basic sanity check: output should be non-empty and different from input
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            NSLog("[HY-TEST-\(testID)] FAIL: Empty translation output")
            writeResult("FAIL: Empty output")
        } else if trimmed.lowercased() == testPhrase.lowercased() {
            NSLog("[HY-TEST-\(testID)] FAIL: Output identical to input (no translation)")
            writeResult("FAIL: No translation occurred")
        } else {
            NSLog("[HY-TEST-\(testID)] PASS: Translation produced valid output")
            writeResult("PASS: '\(trimmed)'")
        }
    } catch {
        NSLog("[HY-TEST-\(testID)] FAIL: Translation error: \(error)")
        let nsError = error as NSError
        NSLog("[HY-TEST-\(testID)] Error domain: \(nsError.domain), code: \(nsError.code)")
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            NSLog("[HY-TEST-\(testID)] Underlying error: \(underlying)")
        }
        writeResult("FAIL: Translation error: \(error)")
    }

    // Unload to free memory
    service.unloadModel()
    NSLog("[HY-TEST-\(testID)] === Test complete ===")
}

private func writeResult(_ message: String) {
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let file = docs.appendingPathComponent("hy_test_result.txt")
    try? message.write(to: file, atomically: true, encoding: .utf8)
}
