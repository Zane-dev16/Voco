//
//  SettingsView.swift
//  Voco
//
//  Clean settings with model management and storage info.
//

import SwiftUI
import OSLog

struct SettingsView: View {
    @Binding var selectedModelID: String
    @Environment(\.lifecycleManager) private var lifecycleManager
    @Environment(\.downloadManager) private var downloadManager

    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: TranslationModel?
    @State private var showModelSheet = false

    private var downloadedModels: [TranslationModel] {
        TranslationModel.availableModels.filter { downloadManager.isModelDownloaded($0) }
    }

    var body: some View {
        List {
            // Active model
            activeModelSection

            // Downloaded models
            downloadedModelsSection

            // Browse more models
            browseMoreSection

            // Storage
            storageSection

            // About
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showModelSheet) {
            NavigationStack {
                ModelCatalogView(selectedModelID: $selectedModelID)
            }
        }
        .confirmationDialog(
            "Delete Model?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible,
            presenting: modelToDelete
        ) { model in
            Button("Delete \(model.formattedSize)", role: .destructive) {
                Task { await performDelete(model) }
            }
            Button("Keep", role: .cancel) {}
        } message: { model in
            Text("Remove \(model.displayName) from your device? You can re-download it anytime.")
        }
    }

    // MARK: - Active Model

    private var activeModelSection: some View {
        Section {
            if let model = activeModel {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName)
                            .font(.body)
                        Text(model.provider)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("Active")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("No model active")
                            .font(.body)
                        Text("Download a model to start translating")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Downloaded Models

    private var downloadedModelsSection: some View {
        Section("Downloaded Models") {
            if downloadedModels.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("No models downloaded")
                            .font(.body)
                        Text("Browse the model hub to download offline engines.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(downloadedModels) { model in
                    modelRow(model)
                }
            }
        }
    }

    private func modelRow(_ model: TranslationModel) -> some View {
        HStack(spacing: 12) {
            Button {
                selectModel(model)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName).font(.body).foregroundStyle(.primary)
                        Text("\(model.formattedSize)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if lifecycleManager.activeModelID == model.id && lifecycleManager.isModelReady {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    } else if model.id == selectedModelID {
                        Image(systemName: "checkmark").foregroundStyle(.blue).font(.caption.weight(.semibold))
                    }
                }
            }
            .buttonStyle(.plain)
            Button(role: .destructive) { confirmDelete(model) } label: {
                Image(systemName: "trash").font(.caption).foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(model.displayName)")
        }
    }

    // MARK: - Browse More Models

    private var browseMoreSection: some View {
        Section {
            Button {
                showModelSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Circle())

                    Text("Browse Models")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Download Models")
        } footer: {
            Text("Download more models to translate offline.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        Section("Storage") {
            HStack {
                Text("Models on device")
                    .font(.subheadline)
                Spacer()
                Text(formattedTotalStorage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 2)

            if !downloadedModels.isEmpty {
                ForEach(downloadedModels) { model in
                    HStack {
                        Text(model.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(model.formattedSize)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("All translations run on-device. No data leaves your iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            NavigationLink {
                ModelLicensesView()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("Models & Licenses")
                }
            }
        } header: {
            Text("About")
        } footer: {
            Text("Voco · Offline Translation")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private var activeModel: TranslationModel? {
        guard let id = lifecycleManager.activeModelID else { return nil }
        return TranslationModel.availableModels.first { $0.id == id }
    }

    private var isActive: Bool {
        if case .ready = lifecycleManager.lifecycleState { return true }
        return false
    }

    private var formattedTotalStorage: String {
        ByteCountFormatter.string(fromByteCount: downloadManager.totalDiskUsage(), countStyle: .file)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    // MARK: - Actions

    @State private var loadTask: Task<Void, Never>?

    private func selectModel(_ model: TranslationModel) {
        guard model.id != selectedModelID else { return }
        loadTask?.cancel()
        selectedModelID = model.id
        guard downloadManager.isModelDownloaded(model) else { return }
        loadTask = Task {
            try? await lifecycleManager.switchTo(model)
        }
    }

    private func confirmDelete(_ model: TranslationModel) {
        modelToDelete = model
        showDeleteConfirmation = true
    }

    private func performDelete(_ model: TranslationModel) async {
        if lifecycleManager.activeModelID == model.id {
            await lifecycleManager.deactivate()
        }
        do {
            try downloadManager.deleteModel(model)
        } catch {
VocoLog.models.error("[Settings] Delete error: \(error)")
        }
    }
}
