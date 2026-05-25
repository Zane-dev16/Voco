//
//  ModelDetailView.swift
//  Voco
//
//  Full compliance disclosure for a single downloadable model.
//

import SwiftUI

struct ModelDetailView: View {
    let record: ModelCompliance

    var body: some View {
        List {
            // ── Header card ──
            Section {
                VStack(spacing: 8) {
                    Text(record.displayName)
                        .font(.title2.weight(.bold))
                    Text(record.provider)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if record.requiresBuiltWithLlamaAttribution {
                        Label("Built with Llama", systemImage: "flame.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            // ── Model info ──
            Section("Model Information") {
                row("Provider", record.provider)
                row("Base Model", record.baseModelName)
                row("Parameters", record.parameterCount)
                row("Quantization", record.quantization)
                row("License", record.licenseName)
            }

            // ── Conversion ──
            Section("Conversion") {
                Text(record.conversionSummary)
                    .font(.subheadline)
                if let notes = record.runtimeNotes {
                    row("Runtime Notes", notes)
                }
            }

            // ── Links ──
            Section("Links") {
                if let url = record.baseModelURL, let linkURL = URL(string: url) {
                    Link(destination: linkURL) {
                        HStack { Text("Original Model"); Spacer(); Image(systemName: "arrow.up.right") }
                    }
                }
                if let url = record.baseModelCardURL, let linkURL = URL(string: url) {
                    Link(destination: linkURL) {
                        HStack { Text("Model Card"); Spacer(); Image(systemName: "arrow.up.right") }
                    }
                }
                if let url = URL(string: record.ggufRepoURL) {
                    Link(destination: url) {
                        HStack { Text("GGUF Repository"); Spacer(); Image(systemName: "arrow.up.right") }
                    }
                }
                if let urlString = record.licenseURL, let url = URL(string: urlString) {
                    Link(destination: url) {
                        HStack { Text("License"); Spacer(); Image(systemName: "arrow.up.right") }
                    }
                }
            }

            // ── Attribution ──
            if let attr = record.attributionText, record.requiresBuiltWithLlamaAttribution {
                Section("Required Attribution") {
                    Text(attr)
                        .font(.body.weight(.semibold))
                    Text("This attribution must appear prominently in any UI, documentation, or product surface that references Llama-based models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // ── Notice ──
            if let notice = record.noticeText {
                Section("NOTICE") {
                    Text(notice)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(record.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.subheadline)
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        ModelDetailView(record: ModelCompliance.allRecords.first { $0.id == "llama-3.2-1b-q8" }!)
    }
}
