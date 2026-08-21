//
//  ContentView.swift
//  Voco
//
//  Single-page root. Settings accessed via top-right gear.
//  Managers injected via @Environment — no prop drilling.
//  Memory policy: keep-resident — the model stays loaded in background for a
//  quick return; it is unloaded only on an iOS memory warning (see
//  ModelLifecycleManager's didReceiveMemoryWarning observer).
//

import SwiftUI
import OSLog

struct ContentView: View {
    @State private var lifecycleManager: ModelLifecycleManager
    @State private var downloadManager: ModelManagerService
    @StateObject private var languageRegistry = LanguageRegistry.shared
    @State private var selectedModelID: String = "hy-mt2-1.8b-stq"
    @Environment(\.scenePhase) private var scenePhase
    @State private var activationErrorMessage: String?
    @State private var showActivationError = false

    init() {
        // One shared ModelManagerService backs both environment values, so
        // lifecycle resolution and UI download state observe the same instance
        // instead of two competing services with separate URLSessions.
        let downloads = ModelManagerService()
        _downloadManager = State(initialValue: downloads)
        _lifecycleManager = State(initialValue: ModelLifecycleManager(downloadManager: downloads))
    }

    var body: some View {
        NavigationStack {
            TranslateRoot(selectedModelID: $selectedModelID)
        }   
        .environment(\.lifecycleManager, lifecycleManager)
        .environment(\.downloadManager, downloadManager)
        .environmentObject(languageRegistry)
        .alert("Couldn't Activate Model", isPresented: $showActivationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(activationErrorMessage ?? "An unknown error occurred while activating the model.")
        }
        .onAppear {
            autoActivateModel(selectedModelID)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Keep-resident: no unload here. Unloading on every backgrounding
                // cost a multi-second model reload on each foreground return; the
                // memory-warning observer in ModelLifecycleManager handles real
                // pressure instead.
                lifecycleManager.handleDidEnterBackground()
            case .active:
                Task { await lifecycleManager.handleWillEnterForeground() }
            default:
                break
            }
        }
    }

    private func autoActivateModel(_ modelID: String) {
        guard let model = TranslationModel.availableModels.first(where: { $0.id == modelID }) else { return }
        guard downloadManager.isModelDownloaded(model) else { return }
        guard lifecycleManager.activeModelID != modelID else { return }
        Task {
            do {
                try await lifecycleManager.activate(model)
            } catch is CancellationError {
                return
            } catch {
                VocoLog.models.error("[ContentView] Auto-activation failed for \(model.id): \(error)")
                activationErrorMessage = "\(model.displayName) could not be activated. \(error.localizedDescription)"
                showActivationError = true
            }
        }
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
                    .accessibilityLabel("Settings")
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
        .accessibilityLabel(selectedModel.map { "Model: \($0.displayName)" } ?? "Select model")
        .accessibilityHint("Opens the model library")
    }

    private func isModelReady(for id: String) -> Bool {
        lifecycleManager.activeModelID == id && lifecycleManager.isModelReady
    }
}
