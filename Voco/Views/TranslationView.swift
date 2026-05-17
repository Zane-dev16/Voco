//
//  TranslationView.swift
//  Voco
//
//  Main translation workspace with streaming output,
//  language picker, and micro-interactions.
//

import SwiftUI
import UIKit

struct TranslationView: View {
    let lifecycleManager: ModelLifecycleManager

    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var selectedLanguage: Language = .spanish
    @State private var isTranslating: Bool = false
    @State private var showShimmer: Bool = false

    /// Haptic generator for streaming feedback.
    private let haptic = UIImpactFeedbackGenerator(style: .soft)

    var body: some View {
        VStack(spacing: 0) {
            // Input section
            inputSection

            Divider()
                .padding(.horizontal)

            // Language picker
            languagePicker

            Divider()
                .padding(.horizontal)

            // Output section
            outputSection
        }
        .background(Color(.systemBackground))
        .onAppear { haptic.prepare() }
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Input")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if !inputText.isEmpty {
                    Button("Clear") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            inputText = ""
                            outputText = ""
                            isTranslating = false
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.indigo)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            TextEditor(text: $inputText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Enter text to translate...")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 100, maxHeight: 180)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Translate button
            translateButton
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private var translateButton: some View {
        Button {
            performTranslation()
        } label: {
            HStack(spacing: 8) {
                if isTranslating {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                    Text("Translating...")
                        .font(.subheadline.bold())
                } else {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.subheadline)
                    Text("Translate")
                        .font(.subheadline.bold())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.indigo.opacity(0.3)
                        : Color.indigo)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .indigo.opacity(0.2), radius: 4, y: 2)
        }
        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
    }

    // MARK: - Language Picker

    private var languagePicker: some View {
        HStack(spacing: 12) {
            Label("English", systemImage: "textformat")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Capsule())

            Image(systemName: "arrow.right")
                .font(.caption.bold())
                .foregroundStyle(.indigo)

            Menu {
                ForEach(Language.allCases.filter { $0 != .english }) { lang in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedLanguage = lang
                        }
                    } label: {
                        HStack {
                            Text("\(lang.flag) \(lang.displayName)")
                            if lang == selectedLanguage {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(selectedLanguage.displayName, systemImage: "globe")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(Color.indigo.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Output

    private var outputSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Translation")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if isTranslating {
                    ShimmerText()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if outputText.isEmpty && !isTranslating {
                            placeholderOutput
                        } else if outputText.isEmpty && isTranslating {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .tint(.indigo)
                                Text("Waking up AI...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            Text(outputText)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 4)
                                .id("output-bottom")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .onChange(of: outputText) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("output-bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var placeholderOutput: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.indigo.opacity(0.4))
            Text("Your translation will appear here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    // MARK: - Translation Logic

    private func performTranslation() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTranslating else { return }

        isTranslating = true
        outputText = ""
        showShimmer = true

        let targetLang = selectedLanguage.hunyuanTargetName

        Task {
            var fullOutput = ""
            var tokenCount = 0

            let stream = lifecycleManager.translateStream(
                text,
                from: "English",
                to: targetLang
            )

            do {
                for try await chunk in stream {
                    fullOutput += chunk
                    tokenCount += 1

                    await MainActor.run {
                        outputText = fullOutput

                        // Light haptic every ~3 tokens (like ChatGPT)
                        if tokenCount % 3 == 0 {
                            haptic.impactOccurred(intensity: 0.4)
                        }
                    }
                }

                await MainActor.run {
                    isTranslating = false
                    showShimmer = false
                    // Final strong haptic
                    haptic.impactOccurred(intensity: 0.8)
                }
            } catch {
                await MainActor.run {
                    outputText = "Error: \(error.localizedDescription)"
                    isTranslating = false
                    showShimmer = false
                }
            }
        }
    }
}

// MARK: - Shimmer Effect

private struct ShimmerText: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        Text("AI translating...")
            .font(.caption)
            .foregroundStyle(.indigo.opacity(0.6))
            .overlay {
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .indigo.opacity(0.3), .clear],
                                startPoint: UnitPoint(x: phase, y: 0.5),
                                endPoint: UnitPoint(x: phase + 0.2, y: 0.5)
                            )
                        )
                        .frame(width: geo.size.width * 0.6)
                }
            }
            .mask { Text("AI translating...").font(.caption) }
            .onAppear {
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
    }
}
