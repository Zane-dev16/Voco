//
//  ContentView.swift
//  Voco
//
//  Single-page root. No tabs. Settings accessed via top-right gear.
//

import SwiftUI

struct ContentView: View {
    @State private var lifecycleManager = ModelLifecycleManager()
    @State private var downloadManager = ModelManagerService()
    @State private var selectedModelID: String = "hy-mt1.5-1.8b-stq"

    var body: some View {
        NavigationStack {
            TranslateRoot(
                lifecycleManager: lifecycleManager,
                downloadManager: downloadManager,
                selectedModelID: $selectedModelID
            )
        }
        .onChange(of: selectedModelID) { _, newID in
            autoActivateModel(newID)
        }
        .onAppear {
            autoActivateModel(selectedModelID)
        }
    }

    private func autoActivateModel(_ modelID: String) {
        guard let model = TranslationModel.availableModels.first(where: { $0.id == modelID }) else { return }
        guard downloadManager.isModelDownloaded(model) else { return }
        guard lifecycleManager.activeModelID != modelID else { return }

        Task {
            try? await lifecycleManager.activate(model)
        }
    }
}

// MARK: - Translate Root

private struct TranslateRoot: View {
    let lifecycleManager: ModelLifecycleManager
    let downloadManager: ModelManagerService
    @Binding var selectedModelID: String

    @State private var showModelSheet = false
    @State private var showSettings = false

    private var selectedModel: TranslationModel? {
        TranslationModel.availableModels.first { $0.id == selectedModelID }
    }

    var body: some View {
        Group {
            if let model = selectedModel, isModelReady(for: model.id) {
                TranslationView(
                    lifecycleManager: lifecycleManager,
                    downloadManager: downloadManager,
                    selectedModelID: $selectedModelID
                )
            } else if let model = selectedModel {
                OnboardingView(
                    model: model,
                    lifecycleManager: lifecycleManager,
                    downloadManager: downloadManager
                )
            } else {
                ContentUnavailableView(
                    "No Models",
                    systemImage: "square.stack.3d.up",
                    description: Text("No translation models are available.")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                modelPickerButton
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showModelSheet) {
            NavigationStack {
                ModelSelectionSheet(
                    lifecycleManager: lifecycleManager,
                    downloadManager: downloadManager,
                    selectedModelID: $selectedModelID
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(
                    lifecycleManager: lifecycleManager,
                    downloadManager: downloadManager,
                    selectedModelID: $selectedModelID
                )
            }
        }
    }

    private var modelPickerButton: some View {
        Button {
            showModelSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectedModel?.providerIcon ?? "cpu")
                    .font(.caption)
                Text(selectedModel?.displayName ?? "Select Model")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
        }
        .tint(.primary)
    }

    private func isModelReady(for id: String) -> Bool {
        lifecycleManager.activeModelID == id && lifecycleManager.isModelReady
    }
}
