//
//  ModelLicensesView.swift
//  Voco
//
//  Models & Licenses — compliance disclosure for all downloadable models.
//  Accessible from Settings → About.
//

import SwiftUI

struct ModelLicensesView: View {
    private let models = TranslationModel.availableModels

    var body: some View {
        List {
            // Global disclosure
            Section {
                Text("Downloadable models in Voco are derived from third-party base models and converted or quantised for on-device use.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            // Per-model list with inline detail (#3 — DisclosureGroup)
            Section {
                ForEach(models) { model in
                    DisclosureGroup {
                        modelDetailContent(model)
                            .padding(.top, 8)
                    } label: {
                        modelRow(model)
                    }
                }
            } header: {
                Text("Models & Licenses")
            }
        }
        .navigationTitle("Models & Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Row

    private func modelRow(_ model: TranslationModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: providerIcon(for: model.provider))
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.body.weight(.medium))
                    if model.requiresBuiltWithLlamaAttribution {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                            Text("Built with Llama")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text("\(model.provider) · \(model.baseModelName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(model.parameterCount) · \(model.quantization) · \(model.licenseName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail (inline)

    private func modelDetailContent(_ model: TranslationModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Provider + base model
            detailRow("Provider", model.provider)
            detailRow("Base Model", model.baseModelName)
            detailRow("Parameters", model.parameterCount)
            detailRow("Quantization", model.quantization)
            detailRow("License", model.licenseName)

            Divider()

            Text(model.conversionSummary)
                .font(.subheadline)

            if let notes = model.runtimeNotes {
                detailRow("Runtime Notes", notes)
            }

            // Links
            VStack(alignment: .leading, spacing: 4) {
                if let url = model.baseModelURL, let link = URL(string: url) {
                    Link(destination: link) {
                        Label("Original Model", systemImage: "arrow.up.right").font(.caption)
                    }
                }
                if let url = URL(string: "https://huggingface.co/" + model.hfRepo) {
                    Link(destination: url) {
                        Label("GGUF Repository", systemImage: "arrow.up.right").font(.caption)
                    }
                }
                if let url = model.licenseURL, let link = URL(string: url) {
                    Link(destination: link) {
                        Label("License", systemImage: "arrow.up.right").font(.caption)
                    }
                }
            }

            // Llama attribution
            if model.requiresBuiltWithLlamaAttribution, let attr = model.attributionText {
                Divider()
                Text(attr)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            // Notice text
            if let notice = model.noticeText {
                Divider()
                Text(notice)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption)
            Spacer()
        }
    }

    private func providerIcon(for provider: String) -> String {
        switch provider {
        case "Tencent": return "building.2"
        case "Meta":    return "flame"
        case "Qwen":    return "sparkles"
        case "Google":  return "brain.head.profile"
        default:        return "questionmark.circle"
        }
    }
}

#Preview {
    NavigationStack { ModelLicensesView() }
}
