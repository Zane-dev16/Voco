//
//  OnboardingView.swift
//  Voco
//
//  Download and activation flow for any local translation model.
//

import SwiftUI

struct OnboardingView: View {
    let model: TranslationModel
    @Environment(\.lifecycleManager) private var lifecycleManager
    @Environment(\.downloadManager) private var downloadManager

    @Environment(\.openURL) private var openURL

    @State private var isActivating = false
    @State private var showSuccess = false
    @State private var showCellularWarning = false
    @State private var showStorageWarning = false

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
                Text(model.displayName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Download \(model.provider)'s model and translate anywhere, completely offline and private.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Label(model.formattedSize, systemImage: "internaldrive")
                    Text("·")
                    Label("\(model.parameterCount) params", systemImage: "cpu")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Badge(text: model.quantization, color: model.providerColor)
                    Badge(text: model.speedRating, color: .secondary)
                    Badge(text: model.qualityRating, color: .secondary)
                }
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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(buttonColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .shadow(color: buttonColor.opacity(0.3), radius: 8, y: 4)
            }
            .disabled(isDownloading || isActivating)
            .padding(.horizontal, 32)

            // Progress bar (only visible during download)
            if isDownloading {
                VStack(spacing: 6) {
                    ProgressView(value: downloadProgress)
                        .tint(model.providerColor)
                        .padding(.horizontal, 32)
                        .accessibilityValue("\(Int(downloadProgress * 100)) percent")

                    Text("\(formattedDownloadedBytes) of \(model.formattedSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }

            // Legal
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "doc.text").font(.caption2)
                Text("Model weights are downloaded directly from Hugging Face and are subject to the provider's license.")
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 32)

            Spacer()
        }
        .background(Color(.systemGroupedBackground))
        .alert("Download over cellular?", isPresented: $showCellularWarning) {
            Button("Download Anyway") { performDownload() }
            Button("Cancel", role: .cancel) { isActivating = false }
        } message: {
            Text("This model is \(model.formattedSize). Downloading over cellular may use a significant amount of data. We recommend using Wi-Fi.")
        }
        .alert("Insufficient Storage", isPresented: $showStorageWarning) {
            Button("Try Anyway") { performDownload() }
            Button("Cancel", role: .cancel) { isActivating = false }
        } message: {
            Text("This model requires about \(ByteCountFormatter.string(fromByteCount: model.fileSizeBytes * 2, countStyle: .file)) of free space. Your device may not have enough storage available.")
        }
    }

    // MARK: - Button label

    private var buttonLabel: String {
        if showSuccess { return "Engine Ready" }
        if isDownloading { return "Downloading... \(Int(downloadProgress * 100))%" }
        if isActivating { return "Activating Neural Engine..." }
        if downloadManager.isModelDownloaded(model) { return "Activate" }
        return "Download · \(model.formattedSize)"
    }

    private var buttonColor: Color {
        if showSuccess { return .green }
        if isDownloading || isActivating { return model.providerColor.opacity(0.6) }
        return model.providerColor
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
            let result = await DownloadPreflight.check(modelSizeBytes: model.fileSizeBytes)
            await MainActor.run {
                switch result {
                case .proceed:
                    performDownload()
                case .cellularWarning:
                    showCellularWarning = true
                case .insufficientStorage:
                    showStorageWarning = true
                }
            }
        }
    }

    private func performDownload() {
        showCellularWarning = false
        showStorageWarning = false
        isActivating = true

        Task {
            do {
                if !downloadManager.isModelDownloaded(model) {
                    _ = try await downloadManager.downloadAsync(model)
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
