//
//  ContentView.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = RootViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                    .font(.system(size: 48))

                Text("Voco")
                    .font(.largeTitle.bold())

                Text("Offline translation, privacy first")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Voco")
        }
    }
}

#Preview {
    ContentView()
}
