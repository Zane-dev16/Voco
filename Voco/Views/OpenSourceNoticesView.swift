//
//  OpenSourceNoticesView.swift
//  Voco
//
//  Renders the bundled ThirdPartyNotices.txt so open-source attributions
//  are actually visible in-app, not just shipped in the bundle.
//

import SwiftUI

struct OpenSourceNoticesView: View {
    private let noticesText: String

    init() {
        // Bundled via filesystem-synchronized group; fall back to a short
        // pointer if the resource is ever missing.
        if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            noticesText = text
        } else {
            noticesText = "Full notices are distributed with the app bundle and at\nhttps://github.com/Zane-dev16/Voco"
        }
    }

    var body: some View {
        ScrollView {
            Text(noticesText)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle(Text("Open-Source Notices"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { OpenSourceNoticesView() }
}
