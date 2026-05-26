//
//  ModelCatalogView.swift
//  Voco
//
//  Rich model browser with provider-grouped cards, download management,
//  delete, and one-tap activation. The central hub for Voco's offline
//  translation engine. Replaces ModelSelectionSheet.
//

import SwiftUI

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
        return grouped
            .map { (provider: $0.key, models: $0.value.sorted { $0.fileSizeBytes < $1.fileSizeBytes }) }
            .sorted { $0.provider < $1.provider }
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
                performDelete(model)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(downloadedCount) of \(TranslationModel.availableModels.count) models")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Total: \(formattedTotalStorage)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 8)

                    let usedWidth = geo.size.width * storageRatio
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.indigo, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(usedWidth, 4), height: 8)
                        .animation(.spring(response: 0.4), value: usedWidth)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Actions

    private func selectModel(_ model: TranslationModel) {
        guard model.id != selectedModelID else { return }

        if lifecycleManager.activeModelID != nil {
            Task { await lifecycleManager.deactivate() }
        }
        selectedModelID = model.id

        if downloadManager.isModelDownloaded(model) {
            Task {
                try? await lifecycleManager.activate(model)
                await MainActor.run {
                    lastActivatedModel = model.displayName
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        showActivateSuccess = true
                    }
                }
            }
        }
    }

    private func performDelete(_ model: TranslationModel) {
        if lifecycleManager.activeModelID == model.id {
            Task { await lifecycleManager.deactivate() }
        }
        do {
            try downloadManager.deleteModel(model)
        } catch {
            print("[ModelCatalog] Delete error: \(error)")
        }
    }

    // MARK: - Helpers

    private var downloadedCount: Int {
        TranslationModel.availableModels.filter { downloadManager.isModelDownloaded($0) }.count
    }

    private var formattedTotalStorage: String {
        ByteCountFormatter.string(fromByteCount: downloadManager.totalDiskUsage(), countStyle: .file)
    }

    private var activeModelName: String {
        if let id = lifecycleManager.activeModelID,
           let model = TranslationModel.availableModels.first(where: { $0.id == id }) {
            return model.displayName
        }
        return "No model active"
    }

    private var storageRatio: CGFloat {
        let baseline: Int64 = 8_000_000_000
        return min(CGFloat(downloadManager.totalDiskUsage()) / CGFloat(baseline), 1.0)
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
                Image(systemName: models.first?.providerIcon ?? "cpu")
                    .foregroundStyle(providerColor)
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
                    isSelected: model.id == selectedModelID,
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(model.providerColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: model.providerIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(model.providerColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.subheadline.bold())

                        if isActive {
                            StatusDot(color: .green)
                                .accessibilityLabel("Active")
                        } else if isSelected {
                            StatusDot(color: .indigo)
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
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.indigo)
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
                .stroke(isSelected ? Color.indigo.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.01, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isSelected {
            Color.indigo.opacity(0.04)
        } else {
            Color(.secondarySystemGroupedBackground)
        }
    }

    @ViewBuilder
    private var actionBarContent: some View {
        switch downloadState {
        case .notDownloaded:
            Button(action: onDownload) {
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
                    .foregroundStyle(.indigo)
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
        ModelCatalogView(selectedModelID: .constant("hy-mt1.5-1.8b-stq"))
    }
    .environment(\.lifecycleManager, ModelLifecycleManager())
    .environment(\.downloadManager, ModelManagerService())
}
