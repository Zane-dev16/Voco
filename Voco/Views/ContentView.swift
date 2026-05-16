//
//  ContentView.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = RootViewModel()
    @State private var modelManager = ModelManagerService()
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 24) {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                    .font(.system(size: 48))

                Text("Voco").font(.largeTitle.bold())
                Text("Offline translation, privacy first")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                NavigationLink(value: AppRoute.translation) {
                    Label("Start Translating", systemImage: "text.bubble")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
            .navigationTitle("Voco")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.models) {
                        Label("Models", systemImage: "square.stack.3d.up")
                    }
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .translation:
                    TranslationView(modelManager: modelManager)
                case .models:
                    DownloadManagerView(modelManager: modelManager)
                }
            }
        }
    }
}

enum AppRoute: Hashable {
    case translation
    case models
}

#Preview { ContentView() }
