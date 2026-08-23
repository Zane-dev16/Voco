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
    /// When set, only these registry IDs are offered — the set of languages
    /// the active model can actually translate.
    var allowedIDs: Set<String>?
    /// Recently used language IDs, most recent first. Shown as a section
    /// while no search filter is active.
    var recentIDs: [String] = []
    let onSelect: (SupportedLanguage) -> Void

    @State private var searchText = ""
    @State private var showVoiceOnly = false

    /// Filtered and grouped languages.
    private var filteredLanguages: [SupportedLanguage] {
        var langs = registry.languages

        // Model support filter (S7-14): never offer a pair the model would botch.
        if let allowedIDs {
            langs = langs.filter { allowedIDs.contains($0.id) }
        }

        // Filter by search text
        if !searchText.isEmpty {
            // Native-script names ("Español", "日本語", "العربية") match too —
            // users of a translation app are multilingual by definition.
            langs = langs.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.effectiveNativeName.localizedCaseInsensitiveContains(searchText) ||
                $0.id.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Filter by voice capability
        if showVoiceOnly {
            langs = langs.filter { $0.supportsVoice }
        }

        return langs
    }

    /// Recent selections resolved against the current list.
    private var recentLanguages: [SupportedLanguage] {
        guard searchText.isEmpty else { return [] }
        return recentIDs.compactMap { id in
            filteredLanguages.first { $0.id == id }
        }
    }

    /// Languages grouped by voice capability, with a recents section on top.
    private var groupedLanguages: [(String, [SupportedLanguage])] {
        let voice = filteredLanguages.filter { $0.supportsVoice }
        let textOnly = filteredLanguages.filter { !$0.supportsVoice }

        var groups: [(String, [SupportedLanguage])] = []

        let recent = recentLanguages
        let recentSet = Set(recent.map(\.id))
        if !recent.isEmpty {
            groups.append(("Recent", recent))
            // Avoid listing recents twice in the sections below.
            if !voice.isEmpty {
                let remaining = voice.filter { !recentSet.contains($0.id) }
                if !remaining.isEmpty { groups.append(("Voice & Text", remaining)) }
            }
            if !textOnly.isEmpty {
                let remaining = textOnly.filter { !recentSet.contains($0.id) }
                if !remaining.isEmpty { groups.append(("Text Only", remaining)) }
            }
            return groups
        }

        if !voice.isEmpty {
            groups.append(("Voice & Text", voice))
        }
        if !textOnly.isEmpty {
            groups.append(("Text Only", textOnly))
        }
        return groups
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedLanguages, id: \.0) { sectionName, langs in
                    // LocalizedStringKey so section titles resolve from
                    // Localizable.xcstrings ("Voice & Text" / "Text Only").
                    Section(LocalizedStringKey(sectionName)) {
                        ForEach(langs) { lang in
                            Button {
                                onSelect(lang)
                                dismiss()
                            } label: {
                                LanguageRow(
                                    language: lang,
                                    isSelected: lang.id == selectedLanguageID
                                )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityAddTraits(
                                lang.id == selectedLanguageID ? [.isSelected] : []
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if groupedLanguages.isEmpty {
                    ContentUnavailableView(
                        "No Matching Languages",
                        systemImage: "globe",
                        description: Text(searchText.isEmpty
                            ? "This model doesn't support any known languages."
                            : "No language matches '\(searchText)'."))
                }
            }
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
                    .accessibilityLabel("Voice-capable languages only")
                    .accessibilityValue(showVoiceOnly ? "On" : "Off")
                    .accessibilityHint("Filters the list to languages that support offline voice input and output.")
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
                .accessibilityHidden(true) // decorative; name carries meaning

            VStack(alignment: .leading, spacing: 2) {
                Text(language.displayName)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)

                Text(language.effectiveNativeName == language.displayName
                     ? language.id : language.effectiveNativeName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if language.supportsVoice {
                Text("🎤")
                    .font(.caption)
                    .accessibilityLabel("Supports voice input")
            } else {
                Text("⌨️")
                    .font(.caption)
                    .accessibilityLabel("Supports typing only")
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
                    .accessibilityHidden(true) // state conveyed via .isSelected
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
