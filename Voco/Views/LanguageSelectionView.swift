//
//  LanguageSelectionView.swift
//  Voco
//
//  Full-screen language picker with search and voice capability badges.
//  Shows 50+ languages with 🎤 (voice) or ⌨️ (text-only) indicators.
//

import SwiftUI

struct LanguageSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var registry: LanguageRegistry

    let title: String
    let selectedLanguageID: String?
    let onSelect: (SupportedLanguage) -> Void

    @State private var searchText = ""
    @State private var showVoiceOnly = false

    /// Filtered and grouped languages.
    private var filteredLanguages: [SupportedLanguage] {
        var langs = registry.languages

        // Filter by search text
        if !searchText.isEmpty {
            langs = langs.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.id.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Filter by voice capability
        if showVoiceOnly {
            langs = langs.filter { $0.supportsVoice }
        }

        return langs
    }

    /// Languages grouped by voice capability.
    private var groupedLanguages: [(String, [SupportedLanguage])] {
        let voice = filteredLanguages.filter { $0.supportsVoice }
        let textOnly = filteredLanguages.filter { !$0.supportsVoice }

        var groups: [(String, [SupportedLanguage])] = []
        if !voice.isEmpty {
            groups.append(("🎤 Voice & Text", voice))
        }
        if !textOnly.isEmpty {
            groups.append(("⌨️ Text Only", textOnly))
        }
        return groups
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedLanguages, id: \.0) { sectionName, langs in
                    Section(sectionName) {
                        ForEach(langs) { lang in
                            LanguageRow(
                                language: lang,
                                isSelected: lang.id == selectedLanguageID
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(lang)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .searchable(text: $searchText, prompt: "Search languages")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showVoiceOnly.toggle()
                    } label: {
                        Image(systemName: showVoiceOnly ? "mic.fill" : "mic")
                            .foregroundStyle(showVoiceOnly ? .blue : .secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Language Row

private struct LanguageRow: View {
    let language: SupportedLanguage
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(language.flag)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(language.displayName)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)

                Text(language.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if language.supportsVoice {
                Text("🎤")
                    .font(.caption)
            } else {
                Text("⌨️")
                    .font(.caption)
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    LanguageSelectionView(
        title: "Source Language",
        selectedLanguageID: "en",
        onSelect: { _ in }
    )
    .environmentObject(LanguageRegistry.shared)
}
