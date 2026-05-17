//
//  ContentView.swift
//  Voco
//
//  Root view with tab navigation. Wires backend services to UI.
//  Auto-loads the local model when the Translate tab is opened.
//

import SwiftUI

struct ContentView: View {
    @State private var lifecycleManager = ModelLifecycleManager()
    @State private var downloadManager = ModelManagerService()
    @State private var selectedTab = 0

    private var tencentModel: TranslationModel? {
        TranslationModel.availableModels.first { $0.id == "hy-mt1.5-1.8b-2bit" }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TranslateTab(lifecycleManager: lifecycleManager,
                         downloadManager: downloadManager)
                .tabItem {
                    Label("Translate", systemImage: "character.bubble.fill")
                }
                .tag(0)

            SettingsTab(lifecycleManager: lifecycleManager,
                       downloadManager: downloadManager)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(1)
        }
        .tint(.indigo)
        .onChange(of: selectedTab) { _, newTab in
            if newTab == 0 { autoActivateIfReady() }
        }
        .onAppear {
            autoActivateIfReady()
        }
    }

    /// If the model is downloaded but not loaded, load it automatically.
    private func autoActivateIfReady() {
        guard let model = tencentModel else { return }
        guard downloadManager.isModelDownloaded(model) else { return }
        guard !isModelReady else { return }

        Task {
            try? await lifecycleManager.activate(model)
        }
    }

    private var isModelReady: Bool {
        if case .ready = lifecycleManager.lifecycleState { return true }
        return false
    }
}

// MARK: - Translate Tab

private struct TranslateTab: View {
    let lifecycleManager: ModelLifecycleManager
    let downloadManager: ModelManagerService

    private var tencentModel: TranslationModel? {
        TranslationModel.availableModels.first { $0.id == "hy-mt1.5-1.8b-2bit" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isModelReady {
                    TranslationView(lifecycleManager: lifecycleManager)
                } else if let model = tencentModel {
                    OnboardingView(model: model,
                                   lifecycleManager: lifecycleManager,
                                   downloadManager: downloadManager)
                } else {
                    ContentUnavailableView("Model Not Available",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text("The Tencent translation model could not be found in the registry."))
                }
            }
            .navigationTitle("Voco")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var isModelReady: Bool {
        if case .ready = lifecycleManager.lifecycleState { return true }
        return false
    }
}

// MARK: - Settings Tab

private struct SettingsTab: View {
    let lifecycleManager: ModelLifecycleManager
    let downloadManager: ModelManagerService

    var body: some View {
        NavigationStack {
            SettingsView(lifecycleManager: lifecycleManager,
                        downloadManager: downloadManager)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}
