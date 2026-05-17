//
//  ContentView.swift
//  Voco
//
//  Root view with tab navigation. Wires backend services to UI.
//

import SwiftUI

struct ContentView: View {
    @State private var lifecycleManager = ModelLifecycleManager()
    @State private var downloadManager = ModelManagerService()
    @State private var selectedTab = 0

    /// The Tencent model from the registry.
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
        .onAppear {
            // Pre-scan for downloaded model on launch
            _ = downloadManager
        }
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
