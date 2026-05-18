//
//  ContentView.swift
//  Voco
//
//  Root view with tab navigation. Supports multi-model selection
//  organized by provider with lazy model lifecycle.
//

import SwiftUI

struct ContentView: View {
    @State private var lifecycleManager = ModelLifecycleManager()
    @State private var downloadManager = ModelManagerService()
    @State private var selectedTab = 0
    @State private var selectedModelID: String = {
        TranslationModel.availableModels.first?.id ?? ""
    }()

    private var selectedModel: TranslationModel? {
        TranslationModel.availableModels.first { $0.id == selectedModelID }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TranslateTab(
                lifecycleManager: lifecycleManager,
                downloadManager: downloadManager,
                selectedModelID: $selectedModelID
            )
            .tabItem { Label("Translate", systemImage: "character.bubble.fill") }
            .tag(0)

            SettingsView(lifecycleManager: lifecycleManager,
                        downloadManager: downloadManager)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(1)
        }
        .tint(.indigo)
        .onChange(of: selectedModelID) { _, newID in
            autoActivateModel(newID)
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == 0 { autoActivateModel(selectedModelID) }
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

// MARK: - Translate Tab

private struct TranslateTab: View {
    let lifecycleManager: ModelLifecycleManager
    let downloadManager: ModelManagerService
    @Binding var selectedModelID: String

    private var selectedModel: TranslationModel? {
        TranslationModel.availableModels.first { $0.id == selectedModelID }
    }

    /// Models grouped by provider, sorted.
    private var providerGroups: [(provider: String, models: [TranslationModel])] {
        let grouped = Dictionary(grouping: TranslationModel.availableModels, by: { $0.provider })
        return grouped
            .map { (provider: $0.key, models: $0.value) }
            .sorted { $0.provider < $1.provider }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let model = selectedModel, isModelReady(for: model.id) {
                    TranslationView(lifecycleManager: lifecycleManager)
                } else if let model = selectedModel {
                    OnboardingView(model: model,
                                   lifecycleManager: lifecycleManager,
                                   downloadManager: downloadManager)
                } else {
                    ContentUnavailableView("No Models",
                        systemImage: "square.stack.3d.up",
                        description: Text("No translation models are available."))
                }
            }
            .navigationTitle("Voco")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    modelPickerMenu
                }
            }
        }
    }

    private var modelPickerMenu: some View {
        Menu {
            ForEach(providerGroups, id: \.provider) { group in
                Section(group.provider) {
                    ForEach(group.models) { model in
                        Button {
                            switchToModel(model)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.displayName)
                                        .font(.subheadline)
                                    Text("\(model.quantization) · \(model.formattedSize)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if model.id == selectedModelID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.indigo)
                                }
                                Spacer()
                                // Download/status indicator
                                modelStatusIcon(model)
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "cpu.fill")
                .font(.headline)
        }
    }

    @ViewBuilder
    private func modelStatusIcon(_ model: TranslationModel) -> some View {
        if isModelReady(for: model.id) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else if downloadManager.isModelDownloaded(model) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.indigo)
                .font(.caption)
        } else {
            Image(systemName: "icloud.and.arrow.down")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func switchToModel(_ model: TranslationModel) {
        guard model.id != selectedModelID else { return }
        // If current model is active, deactivate it
        if lifecycleManager.activeModelID != nil {
            Task { await lifecycleManager.deactivate() }
        }
        selectedModelID = model.id
    }

    private func isModelReady(for id: String) -> Bool {
        lifecycleManager.activeModelID == id && lifecycleManager.isModelReady
    }
}
