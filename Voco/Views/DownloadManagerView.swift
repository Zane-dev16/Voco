//
//  DownloadManagerView.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import SwiftUI

struct DownloadManagerView: View {
    @State private var viewModel: ModelManagerViewModel

    init(modelManager: ModelManagerService) {
        _viewModel = State(wrappedValue: ModelManagerViewModel(modelManager: modelManager))
    }

    var body: some View {
        List {
            Section { diskUsageHeader }
            Section("Available Models") {
                ForEach(viewModel.availableModels) { model in
                    ModelRow(model: model, viewModel: viewModel)
                }
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var diskUsageHeader: some View {
        HStack {
            Image(systemName: "internaldrive").foregroundStyle(.secondary)
            Text("Downloaded models use").foregroundStyle(.secondary)
            Spacer()
            Text(viewModel.formattedDiskUsage).fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}

struct ModelRow: View {
    let model: TranslationModel
    let viewModel: ModelManagerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName).font(.headline)
                    Text(model.quantization).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.formattedSize).font(.caption).foregroundStyle(.secondary)
            }
            Text(model.description).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Text("Languages:").font(.caption2).foregroundStyle(.tertiary)
                Text(model.supportedLanguages.map(\.flag).joined(separator: " ")).font(.caption2)
            }
            actionArea
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var actionArea: some View {
        let state = viewModel.state(for: model)
        switch state {
        case .notDownloaded:
            Button { viewModel.download(model) } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        case .downloading(let progress):
            VStack(spacing: 6) {
                ProgressView(value: progress)
                HStack {
                    Text("Downloading... \\(Int(progress * 100))%").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { viewModel.cancelDownload(model) }
                        .font(.caption).foregroundStyle(.red)
                }
            }
        case .processing:
            HStack(spacing: 8) {
                ProgressView()
                Text("Processing...").font(.caption).foregroundStyle(.secondary)
            }
        case .downloaded:
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Downloaded").font(.subheadline).foregroundStyle(.green)
                Spacer()
                Button(role: .destructive) { viewModel.deleteModel(model) } label: {
                    Label("Delete", systemImage: "trash").font(.caption)
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(message).font(.caption).foregroundStyle(.red)
                }
                Button { viewModel.download(model) } label: {
                    Label("Retry", systemImage: "arrow.clockwise").font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

#Preview {
    NavigationStack { DownloadManagerView(modelManager: ModelManagerService()) }
}
