//
//  ModelCatalogView.swift
//  Voco
//
//  Rich model browser with provider-grouped cards, download management,
//  delete, and one-tap activation. The central hub for Voco's offline
//  translation engine. Replaces ModelSelectionSheet.
//

import SwiftUI
import OSLog

struct ModelCatalogView: View {
    @Binding var selectedModelID: String
    @Environment(\.lifecycleManager) private var lifecycleManager
    @Environment(\.downloadManager) private var downloadManager
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: TranslationModel?
    @State private var showActivateSuccess = false
    @State private var lastActivatedModel: String?

    /// Models grouped by provider.
    private var providerGroups: [(provider: String, models: [TranslationModel])] {
        let grouped = Dictionary(grouping: TranslationModel.availableModels, by: { $0.provider })
        let providerOrder = ["Tencent", "Google"]
        return grouped
            .map { (provider: $0.key, models: $0.value.sorted { $0.fileSizeBytes < $1.fileSizeBytes }) }
            .sorted { a, b in
                let aIdx = providerOrder.firstIndex(of: a.provider) ?? providerOrder.count
                let bIdx = providerOrder.firstIndex(of: b.provider) ?? providerOrder.count
                if aIdx != bIdx { return aIdx < bIdx }
                return a.provider < b.provider
            }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                catalogHeader
                    .padding(.horizontal, 16)

                ForEach(providerGroups, id: \.provider) { group in
                    ProviderSection(
                        provider: group.provider,
                        models: group.models,
                        selectedModelID: selectedModelID,
                        onSelect: { model in selectModel(model) },
                        onDelete: { model in
                            modelToDelete = model
                            showDeleteConfirmation = true
                        }
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Model Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
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
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text("This will remove \(model.displayName) from your device. You can re-download it anytime.")
        }
        .overlay {
            if showActivateSuccess, let name = lastActivatedModel {
                ToastView(message: "\(name) is ready", systemImage: "checkmark.circle.fill")
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { showActivateSuccess = false }
                        }
                    }
            }
        }
    }

    // MARK: - Header

    private var catalogHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(downloadedCount) of \(TranslationModel.availableModels.count) models")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "cpu.fill")
                        .font(.caption)
                    Text(activeModelName)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(downloadedCount) of \(TranslationModel.availableModels.count) models downloaded")
    }

    // MARK: - Actions

    @State private var loadTask: Task<Void, Never>?

    private func selectModel(_ model: TranslationModel) {
        guard model.id != selectedModelID else { return }
        // Cancel any in-flight load to prevent overlapping model loads
        loadTask?.cancel()
        selectedModelID = model.id

        guard downloadManager.isModelDownloaded(model) else {
            dismiss()
            return
        }

        loadTask = Task {
            // Sequentially deactivate old model, then activate new one
            if lifecycleManager.activeModelID != nil {
                await lifecycleManager.deactivate()
            }
            guard !Task.isCancelled else { return }
            try? await lifecycleManager.activate(model)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                lastActivatedModel = model.displayName
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showActivateSuccess = true
                }
            }
        }
    }

    private func performDelete(_ model: TranslationModel) async {
        if lifecycleManager.activeModelID == model.id {
            await lifecycleManager.deactivate()
        }
        do {
            try downloadManager.deleteModel(model)
        } catch {
VocoLog.models.error("[ModelCatalog] Delete error: \(error)")
        }
    }

    // MARK: - Helpers

    private var downloadedCount: Int {
        TranslationModel.availableModels.filter { downloadManager.isModelDownloaded($0) }.count
    }

    private var activeModelName: String {
        if let id = lifecycleManager.activeModelID,
           let model = TranslationModel.availableModels.first(where: { $0.id == id }) {
            return model.displayName
        }
        return "No model active"
    }

}

// MARK: - Provider Section

private struct ProviderSection: View {
    let provider: String
    let models: [TranslationModel]
    let selectedModelID: String
    let onSelect: (TranslationModel) -> Void
    let onDelete: (TranslationModel) -> Void

    @Environment(\.lifecycleManager) private var lifecycleManager
    @Environment(\.downloadManager) private var downloadManager

    var providerColor: Color {
        models.first?.providerColor ?? .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(provider)
                    .font(.headline)
                Spacer()
                Text("\(models.count) models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(models) { model in
                ModelCard(
                    model: model,
                    isSelected: model.id == selectedModelID && downloadManager.isModelDownloaded(model),
                    isActive: lifecycleManager.activeModelID == model.id && lifecycleManager.isModelReady,
                    isDownloaded: downloadManager.isModelDownloaded(model),
                    downloadState: downloadManager.downloadStates[model.id] ?? .notDownloaded,
                    onSelect: { onSelect(model) },
                    onDelete: { onDelete(model) },
                    onDownload: { downloadManager.download(model) },
                    onCancel: { downloadManager.cancelDownload(for: model.id) }
                )
            }
        }
    }
}

// MARK: - Model Card

private struct ModelCard: View {
    let model: TranslationModel
    let isSelected: Bool
    let isActive: Bool
    let isDownloaded: Bool
    let downloadState: DownloadState
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void

    @State private var isPressed = false
    @State private var showCellularWarning = false
    @State private var showStorageWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.subheadline.bold())

                        if isActive {
                            StatusDot(color: .green)
                                .accessibilityLabel("Active")
                        } else if isSelected {
                            StatusDot(color: .blue)
                                .accessibilityLabel("Selected")
                        }
                    }

                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Badge(text: model.quantization, color: model.providerColor)
                        Badge(text: model.formattedSize, color: .secondary)
                        if model.capability == .simulatorAndDevice {
                            Badge(text: "Simulator OK", color: .green)
                        }
                        if model.id == "hy-mt2-1.8b-stq" {
                            Badge(text: "Recommended", color: .orange)
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                        .symbolEffect(.bounce, options: .nonRepeating, value: isSelected)
                }
            }
            .padding(14)
            .background(cardBackground)

            HStack(spacing: 0) {
                actionBarContent
            }
            .frame(height: 40)
            .background(Color(.tertiarySystemGroupedBackground))
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.01, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .alert("Download over cellular?", isPresented: $showCellularWarning) {
            Button("Download Anyway") { onDownload() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This model is \(model.formattedSize). Downloading over cellular may use a significant amount of data.")
        }
        .alert("Insufficient Storage", isPresented: $showStorageWarning) {
            Button("Try Anyway") { onDownload() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This model requires about \(ByteCountFormatter.string(fromByteCount: model.fileSizeBytes * 2, countStyle: .file)) of free space.")
        }
    }

    private func startDownload() {
        Task {
            let result = await DownloadPreflight.check(modelSizeBytes: model.fileSizeBytes)
            await MainActor.run {
                switch result {
                case .proceed:
                    onDownload()
                case .cellularWarning:
                    showCellularWarning = true
                case .insufficientStorage:
                    showStorageWarning = true
                }
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isSelected {
            Color.blue.opacity(0.04)
        } else {
            Color(.secondarySystemGroupedBackground)
        }
    }

    @ViewBuilder
    private var actionBarContent: some View {
        switch downloadState {
        case .notDownloaded:
            Button(action: startDownload) {
                Label("Download", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.providerColor)

        case .downloading(let progress):
            HStack(spacing: 12) {
                ProgressView(value: progress)
                    .tint(model.providerColor)
                    .frame(maxWidth: .infinity)
                Text("\(Int(progress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36)
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
            }
            .padding(.horizontal, 14)

        case .processing:
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Processing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)

        case .downloaded:
            HStack(spacing: 0) {
                if isActive {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Active")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                } else {
                    Button(action: onSelect) {
                        Label("Use Model", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                }

                Divider()
                    .frame(height: 20)

                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.8))
                .frame(maxWidth: .infinity)
            }

        case .failed:
            HStack(spacing: 0) {
                Button(action: onDownload) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 20)

                Button(action: onDelete) {
                    Label("Clear", systemImage: "xmark")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.8))
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Badge

private struct StatusDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: 2)
                    .scaleEffect(pulse ? 1.6 : 1.0)
                    .opacity(pulse ? 0 : 0.6)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Toast

private struct ToastView: View {
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.green)
            Text(message)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .padding(.top, 8)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ModelCatalogView(selectedModelID: .constant("hy-mt2-1.8b-stq"))
    }
    .environment(\.lifecycleManager, ModelLifecycleManager())
    .environment(\.downloadManager, ModelManagerService())
}
