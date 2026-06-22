//
//  ContentView.swift
//  Voco
//
//  Single-page root. Settings accessed via top-right gear.
//  Managers injected via @Environment — no prop drilling.
//  Handles memory lifecycle: unloads model when app is backgrounded.
//

import SwiftUI

struct ContentView: View {
    @State private var lifecycleManager = ModelLifecycleManager()
    @State private var downloadManager = ModelManagerService()
    @StateObject private var languageRegistry = LanguageRegistry.shared
    @State private var selectedModelID: String = "hy-mt2-1.8b-stq"
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            TranslateRoot(selectedModelID: $selectedModelID)
        }   
        .environment(\.lifecycleManager, lifecycleManager)
        .environment(\.downloadManager, downloadManager)
        .environmentObject(languageRegistry)
        .onAppear {
            autoActivateModel(selectedModelID)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task { await lifecycleManager.deactivate() }
            }
        }
    }

    private func autoActivateModel(_ modelID: String) {
        guard let model = TranslationModel.availableModels.first(where: { $0.id == modelID }) else { return }
        guard downloadManager.isModelDownloaded(model) else { return }
        guard lifecycleManager.activeModelID != modelID else { return }
        Task { try? await lifecycleManager.activate(model) }
    }
}

// MARK: - Translate Root

private struct TranslateRoot: View {
    @Binding var selectedModelID: String
    @FocusState private var isInputFocused: Bool
    @Environment(\.lifecycleManager) private var lifecycleManager
    @Environment(\.downloadManager) private var downloadManager
    @State private var showModelSheet = false
    @State private var showSettings = false

    private var selectedModel: TranslationModel? {
        TranslationModel.availableModels.first { $0.id == selectedModelID }
    }

    var body: some View {
        Group {
            if let model = selectedModel, isModelReady(for: model.id) {
                TranslationView(selectedModelID: $selectedModelID, isInputFocused: $isInputFocused)
            } else if let model = selectedModel {
                OnboardingView(model: model)
            } else {
                ContentUnavailableView("No Models", systemImage: "square.stack.3d.up",
                    description: Text("No translation models are available."))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { modelPickerButton }
            ToolbarItem(placement: .topBarTrailing) {
                if isInputFocused {
                    Button("Done") { isInputFocused = false }
                        .fontWeight(.semibold)
                } else {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").font(.system(size: 18, weight: .medium)).foregroundStyle(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showModelSheet) {
            NavigationStack { ModelCatalogView(selectedModelID: $selectedModelID) }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView(selectedModelID: $selectedModelID) }
        }
    }

    private var modelPickerButton: some View {
        Button { showModelSheet = true } label: {
            HStack(spacing: 6) {
                Text(selectedModel?.displayName ?? "Select Model").font(.caption.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(.tertiarySystemFill)).clipShape(Capsule())
        }.tint(.primary)
    }

    private func isModelReady(for id: String) -> Bool {
        lifecycleManager.activeModelID == id && lifecycleManager.isModelReady
    }
}
