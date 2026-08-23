//
//  LanguageSelectorBar.swift
//  Voco
//
//  Source ⇄ target language row with pickers, capability glyphs, and the
//  swap button. Owns its own presentation state; text-move side effects of a
//  swap are delegated to the parent via onSwap.
//

import SwiftUI

struct LanguageSelectorBar: View {
    @Binding var sourceLanguage: Language
    @Binding var targetLanguage: Language
    /// Parent-side swap side effects (moving output back to input, etc.).
    /// Called inside the same animation block as the rotation.
    let onSwap: () -> Void

    @EnvironmentObject private var languageRegistry: LanguageRegistry
    @State private var showSourceLanguagePicker = false
    @State private var showTargetLanguagePicker = false
    @State private var swapRotation: Double = 0

    /// Whether the source language supports offline STT (microphone input).
    private var sourceSupportsSTT: Bool {
        languageRegistry.language(forID: sourceLanguage.rawValue)?.supportsOfflineSTT ?? false
    }

    /// Whether the target language supports offline TTS (speech output).
    private var targetSupportsTTS: Bool {
        languageRegistry.language(forID: targetLanguage.rawValue)?.supportsOfflineTTS ?? false
    }

    var body: some View {
        HStack(spacing: 0) {
            sourceButton

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    swapRotation += 180
                    onSwap()
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(minWidth: 44, minHeight: 44)
                    .rotationEffect(.degrees(swapRotation))
            }
            .buttonStyle(.plain)
            .frame(width: 52)
            .accessibilityLabel("Swap languages")
            .accessibilityValue("\(sourceLanguage.displayName) to \(targetLanguage.displayName)")
            .accessibilityHint("Swaps the source and target languages")

            targetButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }

    private var sourceButton: some View {
        Button {
            showSourceLanguagePicker = true
        } label: {
            HStack(spacing: 4) {
                Text(sourceLanguage.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if !sourceSupportsSTT {
                    Text("⌨️")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Source language")
        .accessibilityValue(
            sourceSupportsSTT ? sourceLanguage.displayName : "\(sourceLanguage.displayName), typing only")
        .accessibilityHint("Changes the language text is translated from")
        .sheet(isPresented: $showSourceLanguagePicker) {
            LanguageSelectionView(
                title: "Source Language",
                selectedLanguageID: sourceLanguage.rawValue,
                onSelect: { lang in
                    if let legacy = Language(rawValue: lang.id) {
                        sourceLanguage = legacy
                    }
                }
            )
            .environmentObject(languageRegistry)
        }
    }

    private var targetButton: some View {
        Button {
            showTargetLanguagePicker = true
        } label: {
            HStack(spacing: 4) {
                Text(targetLanguage.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                if !targetSupportsTTS {
                    Text("⌨️")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .sheet(isPresented: $showTargetLanguagePicker) {
            LanguageSelectionView(
                title: "Target Language",
                selectedLanguageID: targetLanguage.rawValue,
                onSelect: { lang in
                    if let legacy = Language(rawValue: lang.id) {
                        targetLanguage = legacy
                    }
                }
            )
            .environmentObject(languageRegistry)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Target language")
        .accessibilityValue(
            targetSupportsTTS ? targetLanguage.displayName : "\(targetLanguage.displayName), no voice output")
        .accessibilityHint("Changes the language text is translated to")
    }
}
