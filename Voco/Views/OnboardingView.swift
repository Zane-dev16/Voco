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

    @State private var isActivating = false
    @State private var showSuccess = false

    /// Progress from the live download state (0.0–1.0).
    private var downloadProgress: Double {
        if case .downloading(let p) = downloadManager.downloadStates[model.id] {
            return p
        }
        return 0
    }

    /// Whether a download is currently in flight.
    private var isDownloading: Bool {
        if case .downloading = downloadManager.downloadStates[model.id] {
            return true
        }
        return false
    }

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
                    if showSuccess {
                        Image(systemName: "checkmark.circle.fill")
                    } else if isDownloading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    Text(buttonLabel).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(buttonColor).foregroundStyle(.white)
                .clipShape(Capsule())
                .shadow(color: buttonColor.opacity(0.3), radius: 8, y: 4)
            }
            .disabled(isDownloading || isActivating)
            .padding(.horizontal, 32)

            // Progress bar (only visible during download)
            if isDownloading {
                VStack(spacing: 6) {
                    ProgressView(value: downloadProgress)
                        .tint(.indigo)
                        .padding(.horizontal, 32)

                    Text("\(formattedDownloadedBytes) of \(model.formattedSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }

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

    // MARK: - Button label

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

    /// Bytes downloaded so far based on progress × expected size.
    private var formattedDownloadedBytes: String {
        let bytes = Int64(Double(model.fileSizeBytes) * downloadProgress)
        return ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }

    // MARK: - Action

    private func handleAction() {
        guard !isDownloading, !isActivating else { return }
        isActivating = true

        Task {
            do {
                if !downloadManager.isModelDownloaded(model) {
                    downloadManager.download(model)

                    // Wait for download to finish (or fail)
                    var tries = 0
                    while !downloadManager.isModelDownloaded(model) && tries < 600 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        if case .failed = downloadManager.downloadStates[model.id] {
                            isActivating = false
                            return
                        }
                        tries += 1
                    }
                }

                try await lifecycleManager.activate(model)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    showSuccess = true
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            } catch {
                isActivating = false
            }
        }
    }
}
