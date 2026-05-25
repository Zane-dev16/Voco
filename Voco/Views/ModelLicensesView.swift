//
//  ModelLicensesView.swift
//  Voco
//
//  Models & Licenses — compliance disclosure for all downloadable models.
//  Accessible from Settings.
//

import SwiftUI

struct ModelLicensesView: View {
    var body: some View {
        List {
            // Global disclosure
            Section {
                Text("Downloadable models in Voco are derived from third-party base models and converted or quantised for on-device use.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            // Per-model entries
            Section {
                ForEach(ModelCompliance.allRecords.filter(\.isVisibleToUsers)) { record in
                    NavigationLink {
                        ModelDetailView(record: record)
                    } label: {
                        ModelLicenseRow(record: record)
                    }
                }
            } header: {
                Text("Models & Licenses")
            }
        }
        .navigationTitle("Models & Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Row

private struct ModelLicenseRow: View {
    let record: ModelCompliance

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: providerIcon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.displayName)
                        .font(.body.weight(.medium))
                    if record.requiresBuiltWithLlamaAttribution {
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

                Text("\(record.provider) · \(record.baseModelName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(record.parameterCount) · \(record.quantization) · \(record.licenseName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var providerIcon: String {
        switch record.provider {
        case "Tencent": return "building.2"
        case "Meta":    return "flame"
        case "Qwen":    return "sparkles"
        case "Google":  return "brain.head.profile"
        default:        return "questionmark.circle"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ModelLicensesView()
    }
}
