//
//  SettingsView.swift
//  Voco
//
//  Provider selection and storage management.
//

import SwiftUI

struct SettingsView: View {
    let lifecycleManager: ModelLifecycleManager
    let downloadManager: ModelManagerService

    @State private var useLocalEngine: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    private var tencentModel: TranslationModel? {
        TranslationModel.availableModels.first { $0.id == "hy-mt1.5-1.8b-2bit" }
    }

    var body: some View {
        List {
            // MARK: - Providers Section
            Section {
                Toggle(isOn: $useLocalEngine) {
                    HStack(spacing: 12) {
                        Image(systemName: "cpu.fill")
                            .font(.title3)
                            .foregroundStyle(.indigo)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Local Tencent Engine")
                                .font(.body)
                            Text("Offline · Private · 440 MB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.indigo)
                .onChange(of: useLocalEngine) { _, enabled in
                    handleProviderToggle(enabled: enabled)
                }
            } header: {
                Text("Translation Provider")
            } footer: {
                Text(useLocalEngine
                     ? "Translations run entirely on-device using the STQ1_0 quantized model. No data leaves your iPhone."
                     : "Cloud models are available for comparison and fallback.")
                    .font(.caption)
            }

            // MARK: - Storage Section
            if let model = tencentModel, downloadManager.isModelDownloaded(model) {
                Section {
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

                            // Storage bar
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .confirmationDialog(
                        "Delete Translation Engine?",
                        isPresented: $showDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete \(model.formattedSize)", role: .destructive) {
                            deleteModel(model)
                        }
                        Button("Keep", role: .cancel) {}
                    } message: {
                        Text("This will remove the offline translation engine from your device. You can re-download it anytime.")
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Total app storage: \(formattedTotalStorage)")
                    }
                    .font(.caption)
                }
            } else if let _ = tencentModel {
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

            // MARK: - Info Section
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

    private func handleProviderToggle(enabled: Bool) {
        guard let model = tencentModel else { return }

        Task {
            if enabled {
                // Activate local engine
                if !downloadManager.isModelDownloaded(model) {
                    // Need to download first — handled by onboarding
                    useLocalEngine = false
                    return
                }
                try? await lifecycleManager.activate(model)
            } else {
                // Deactivate local engine
                await lifecycleManager.deactivate()
            }
        }
    }

    private func deleteModel(_ model: TranslationModel) {
        Task {
            // Unload if active
            if lifecycleManager.activeModelID == model.id {
                await lifecycleManager.deactivate()
            }

            // Delete file
            try? downloadManager.deleteModel(model)
            useLocalEngine = false
        }
    }
}
