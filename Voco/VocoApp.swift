//
//  VocoApp.swift
//

import SwiftUI
import os

@main
struct VocoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await testE2B() }
        }
    }
}

private let tlog = Logger(subsystem: "com.zanishlabs.Voco", category: "e2b")

@MainActor
func testE2B() async {
    let fm = FileManager.default
    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
    let logFile = docs.appendingPathComponent("e2b_result.txt")

    var lines: [String] = ["=== E2B: \(Date()) ==="]
    func save(_ m: String) { lines.append(m); try? lines.joined(separator: "\n").write(to: logFile, atomically: true, encoding: .utf8); tlog.info("\(m)") }

    guard let model = TranslationModel.availableModels.first(where: { $0.id == "gemma-4-e2b-q4km" }) else {
        save("FAIL: not found"); return
    }
    save("Config: \(model.config == .gemma4Raw ? "gemma4Raw ✅" : "WRONG ❌")")

    // Stage the GGUF — download from local Mac server (fast) if not already present
    let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let modelsDir = appSupport.appendingPathComponent("Voco/Models")
    try? fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
    let ggufURL = modelsDir.appendingPathComponent("gemma-4-E2B-it-Q4_K_M.gguf")

    if !fm.fileExists(atPath: ggufURL.path) {
        save("Downloading from local server...")
        let sourceURL = URL(string: "http://172.20.10.10:8765/gemma-4-E2B-it-Q4_K_M.gguf")!
        do {
            let (tmpURL, _) = try await URLSession.shared.download(from: sourceURL)
            try fm.moveItem(at: tmpURL, to: ggufURL)
            save("Downloaded (\(ByteCountFormatter.string(fromByteCount: Int64((try? ggufURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), countStyle: .file)))")
        } catch {
            save("Download FAIL: \(error.localizedDescription)"); return
        }
    } else {
        save("GGUF already staged")
    }

    let lifecycle = ModelLifecycleManager()
    let t0 = Date()

    do {
        try await lifecycle.activate(model)
        save("ACTIVATED in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
    } catch {
        save("ACTIVATE FAIL: \(error.localizedDescription)"); return
    }

    for (text, lang) in [("Hello", "Spanish"), ("Good morning", "French"), ("Thank you", "German")] {
        do {
            let r = try await lifecycle.translate(text, from: "English", to: lang)
            let c = r.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "<end_of_turn>", with: "")
                .replacingOccurrences(of: "<start_of_turn>", with: "")
                .replacingOccurrences(of: "model", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            save("EN→\(lang.prefix(2).uppercased()): \"\(c.prefix(50))\" — PASS ✅")
        } catch {
            save("EN→\(lang.prefix(2).uppercased()): FAIL — \(error.localizedDescription)")
        }
    }

    await lifecycle.deactivate()
    save("=== DONE ===")
}
