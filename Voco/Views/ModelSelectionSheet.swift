//
//  ModelSelectionSheet.swift
//  Voco
//
//  Model hub: browse, download, and activate all models in one sheet.
//  Replaces the standalone Models tab.
//

import SwiftUI

struct ModelSelectionSheet: View {
    @Binding var selectedModelID: String
    @Environment(\.lifecycleManager) private var lifecycleManager
    @Environment(\.downloadManager) private var downloadManager
    @Environment(\.dismiss) private var dismiss

    @State private var isActivating = false
    @State private var activatedModelID: String?

    private var downloadedModels: [TranslationModel] {
        TranslationModel.availableModels
            .filter { downloadManager.isModelDownloaded($0) }
            .sorted { $0.provider < $1.provider }
    }

    private var availableModels: [TranslationModel] {
        TranslationModel.availableModels
            .filter { !downloadManager.isModelDownloaded($0) }
            .sorted { $0.provider < $1.provider }
    }

    var body: some View {
        NavigationStack {
            List {
                if !downloadedModels.isEmpty {
                    Section("Downloaded") {
                        ForEach(downloadedModels) { model in
                            downloadedRow(model)
                        }
                    }
                }

                if !availableModels.isEmpty {
                    Section("Available") {
                        ForEach(availableModels) { model in
                            availableRow(model)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Downloaded Row

    private func downloadedRow(_ model: TranslationModel) -> some View {
        Button {
            selectDownloaded(model)
        } label: {
            HStack(spacing: 12) {
                providerIcon(for: model)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.subheadline.bold())
                    HStack(spacing: 6) {
                        Text(model.quantization)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\u{00B7}")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(model.formattedSize)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if model.id == selectedModelID && lifecycleManager.activeModelID == model.id {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Active")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                    }
                } else if model.id == selectedModelID {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                } else {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isActivating)
    }

    // MARK: - Available Row

    private func availableRow(_ model: TranslationModel) -> some View {
        HStack(spacing: 12) {
            providerIcon(for: model)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.subheadline.bold())
                HStack(spacing: 6) {
                    Text(model.quantization)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\u{00B7}")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(model.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            downloadControl(for: model)
        }
    }

    @ViewBuilder
    private func downloadControl(for model: TranslationModel) -> some View {
        let state = downloadManager.downloadStates[model.id] ?? .notDownloaded

        switch state {
        case .notDownloaded, .failed:
            Button {
                downloadManager.download(model)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(model.providerColor)
            }
            .buttonStyle(.plain)

        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .tint(model.providerColor)
                    .frame(width: 40)
                Text("\(Int(progress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                Button {
                    downloadManager.cancelDownload(for: model.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

        case .processing:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Processing")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        }
    }

    // MARK: - Actions

    private func selectDownloaded(_ model: TranslationModel) {
        guard model.id != selectedModelID else {
            dismiss()
            return
        }

        isActivating = true
        activatedModelID = model.id

        if lifecycleManager.activeModelID != nil {
            Task {
                await lifecycleManager.deactivate()
                await activateAndDismiss(model)
            }
        } else {
            Task {
                await activateAndDismiss(model)
            }
        }
    }

    private func activateAndDismiss(_ model: TranslationModel) async {
        do {
            try await lifecycleManager.activate(model)
            await MainActor.run {
                selectedModelID = model.id
                isActivating = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                isActivating = false
                activatedModelID = nil
            }
        }
    }

    // MARK: - Helpers

    private func providerIcon(for model: TranslationModel) -> some View {
        Image(systemName: model.providerIcon)
            .font(.system(size: 16))
            .foregroundStyle(model.providerColor)
            .frame(width: 36, height: 36)
            .background(model.providerColor.opacity(0.12))
            .clipShape(Circle())
    }
}
