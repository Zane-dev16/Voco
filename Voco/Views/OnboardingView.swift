//
//  OnboardingView.swift
//  Voco
//
//  Download and activation flow for the local Tencent engine.
//

import SwiftUI

struct OnboardingView: View {
    let model: TranslationModel
    let lifecycleManager: ModelLifecycleManager
    let downloadManager: ModelManagerService

    @Environment(\.openURL) private var openURL

    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    @State private var isActivating = false
    @State private var showSuccess = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Hero
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(.indigo.opacity(0.12)).frame(width: 120, height: 120)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.indigo)
                        .symbolEffect(.bounce, value: showSuccess)
                }
                Text("Unlock Offline AI").font(.title2.bold())
                Text("Download the translation engine and translate anywhere, completely offline and private.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Label(model.formattedSize, systemImage: "internaldrive")
                    Text("·")
                    Label("1.8B params", systemImage: "cpu")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            // Button
            Button { handleAction() } label: {
                HStack(spacing: 12) {
                    if showSuccess { Image(systemName: "checkmark.circle.fill") }
                    else if isDownloading || isActivating { ProgressView().tint(.white) }
                    else { Image(systemName: "arrow.down.circle.fill") }
                    Text(buttonLabel).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(buttonColor).foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .disabled(isDownloading || isActivating)
            .padding(.horizontal, 32)

            // Legal
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "doc.text").font(.caption2)
                Text("Model weights are downloaded directly from Hugging Face and are subject to the ")
                    .font(.footnote)
                + Text("Tencent HY Community License.")
                    .font(.footnote).underline().foregroundStyle(.indigo)
            }
            .foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 32)
            .onTapGesture {
                openURL(URL(string: "https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/blob/main/License.txt")!)
            }

            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var buttonLabel: String {
        if showSuccess { return "Engine Ready" }
        if isDownloading { return "Downloading... \(Int(downloadProgress * 100))%" }
        if isActivating { return "Activating Neural Engine..." }
        if downloadManager.isModelDownloaded(model) { return "Activate Offline Engine" }
        return "Download Offline Engine (\(model.formattedSize))"
    }

    private var buttonColor: Color {
        if showSuccess { return .green }
        if isDownloading || isActivating { return .indigo.opacity(0.6) }
        return .indigo
    }

    private func handleAction() {
        guard !isDownloading, !isActivating else { return }
        isActivating = true

        Task {
            do {
                if !downloadManager.isModelDownloaded(model) {
                    isDownloading = true
                    downloadManager.download(model)
                    var tries = 0
                    while !downloadManager.isModelDownloaded(model) && tries < 600 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        if case .failed = downloadManager.downloadStates[model.id] {
                            isDownloading = false; isActivating = false; return
                        }
                        tries += 1
                    }
                    isDownloading = false
                }
                try await lifecycleManager.activate(model)
                withAnimation { showSuccess = true }
                try? await Task.sleep(nanoseconds: 800_000_000)
            } catch {
                isDownloading = false; isActivating = false
            }
        }
    }
}
