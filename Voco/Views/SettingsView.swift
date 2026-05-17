//
//  SettingsView.swift
//  Voco
//
//  Model status and storage management.
//

import SwiftUI

struct SettingsView: View {
    let lifecycleManager: ModelLifecycleManager
    let downloadManager: ModelManagerService

    @State private var showDeleteConfirmation: Bool = false
    @State private var deleteSuccess: Bool = false

    private var tencentModel: TranslationModel? {
        TranslationModel.availableModels.first { $0.id == "hy-mt1.5-1.8b-2bit" }
    }

    var body: some View {
        List {
            // MARK: - Engine Status
            Section {
                engineStatusRow
            } header: {
                Text("Translation Engine")
            } footer: {
                Text("Translations run entirely on-device using the STQ1_0 quantized model. No data leaves your iPhone.")
                    .font(.caption)
            }

            // MARK: - Storage
            if let model = tencentModel, downloadManager.isModelDownloaded(model) {
                Section {
                    storageRow(model: model)
                } header: {
                    Text("Storage")
                } footer: {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Total app storage: \(formattedTotalStorage)")
                    }
                    .font(.caption)
                }
            } else {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.title3)
                            .foregroundStyle(.indigo)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("No model downloaded")
                                .font(.body)
                            Text("Visit the Translate tab to download the offline engine.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Storage")
                }
            }

            // MARK: - Technical Info
            Section {
                LabeledContent("Backend", value: "llama.cpp PR #22836 (stq-kernel)")
                LabeledContent("Quantization", value: "STQ1_0 (1.25-bit Sherry)")
                LabeledContent("Compute", value: "CPU / ARM NEON")
                LabeledContent("Metal GPU", value: "Disabled (CPU-optimized)")
            } header: {
                Text("Technical Info")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Engine Status Row

    @ViewBuilder
    private var engineStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .font(.title3)
                .foregroundStyle(isActive ? .green : .indigo)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tencent Hy-MT1.5 1.8B")
                    .font(.body)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if deleteSuccess {
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
            }
        }
    }

    private var isActive: Bool {
        if case .ready = lifecycleManager.lifecycleState { return true }
        return false
    }

    private var statusText: String {
        if isActive {
            return "Active — Model loaded in memory"
        } else if let model = tencentModel, downloadManager.isModelDownloaded(model) {
            return "Ready — \(model.formattedSize) downloaded"
        } else {
            return "Not downloaded — Tap Translate tab to download"
        }
    }

    // MARK: - Storage Row

    private func storageRow(model: TranslationModel) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "internaldrive.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.body)

                    Text("\(model.formattedSize) · 1.25-bit STQ1_0")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(.tertiarySystemFill))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange.opacity(0.7))
                                .frame(width: storageBarWidth(in: geo.size.width), height: 6)
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, 4)
                }
            }

            // Delete button
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Model")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderless)
            .padding(.top, 12)
        }
        .confirmationDialog(
            "Delete Translation Engine?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(model.formattedSize)", role: .destructive) {
                performDelete(model)
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This will remove the offline translation engine from your device. You can re-download it anytime.")
        }
    }

    // MARK: - Helpers

    private var formattedTotalStorage: String {
        ByteCountFormatter.string(fromByteCount: downloadManager.totalDiskUsage(), countStyle: .file)
    }

    private func storageBarWidth(in totalWidth: CGFloat) -> CGFloat {
        guard let model = tencentModel else { return 0 }
        let totalBytes = downloadManager.totalDiskUsage()
        guard totalBytes > 0 else { return 0 }
        let ratio = CGFloat(model.fileSizeBytes) / CGFloat(totalBytes)
        return max(ratio * totalWidth, 4)
    }

    private func performDelete(_ model: TranslationModel) {
        // Unload if active
        if lifecycleManager.activeModelID == model.id {
            Task { await lifecycleManager.deactivate() }
        }

        // Delete file
        do {
            try downloadManager.deleteModel(model)
            withAnimation {
                deleteSuccess = true
            }
            // Reset after a moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                deleteSuccess = false
            }
        } catch {
            print("[Settings] Delete error: \(error)")
        }
    }
}
