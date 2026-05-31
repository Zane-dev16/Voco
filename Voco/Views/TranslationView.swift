//
//  TranslationView.swift
//  Voco
//
//  Main translation workspace with input, streaming output, and actions.
//  Clean, minimal, full-screen layout with large tappable areas,
//  soft shadows, and floating action buttons.
//

import SwiftUI
import UIKit
import OSLog

struct TranslationView: View {
    @Binding var selectedModelID: String
    @Environment(\.lifecycleManager) private var lifecycleManager
    @Environment(\.downloadManager) private var downloadManager

    // MARK: - State

    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var sourceLanguage: Language = .english
    @State private var targetLanguage: Language = .spanish
    @State private var isTranslating: Bool = false
    @State private var showShareSheet = false
    @State private var showCopyToast = false
    @State private var errorMessage: String?
    @State private var isRecording = false
    @State private var speechService: SpeechService?
    @State private var swapRotation: Double = 0
    @FocusState private var isInputFocused: Bool

    // MARK: - Services

    private let haptic = UIImpactFeedbackGenerator(style: .soft)
    private let ttsService = TTSService()

    // MARK: - Computed

    private var activeModel: TranslationModel? {
        TranslationModel.availableModels.first { $0.id == lifecycleManager.activeModelID }
    }

    private var canTranslate: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isTranslating
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Language selector
                    languageSelector
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    // Input area
                    inputArea
                        .padding(.horizontal, 20)

                    // Translate button
                    translateButton
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)

                    // Output area
                    outputArea
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)

            // Copy toast
            VStack {
                Spacer()
                if showCopyToast {
                    CopyToast()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 24)
                }
            }

            // Error overlay
            if let error = errorMessage {
                VStack {
                    errorBanner(message: error)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    Spacer()
                }
            }
        }
        .onAppear { haptic.prepare() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isInputFocused = false }
                    .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [outputText])
        }
    }

    // MARK: - Language Selector

    private var languageSelector: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(Language.allCases) { lang in
                    Button {
                        sourceLanguage = lang
                    } label: {
                        HStack {
                            Text(lang.displayName)
                            if lang == sourceLanguage {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            } label: {
                Text(sourceLanguage.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 130, alignment: .center)
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Source language")

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    swapRotation += 180
                    swapLanguages()
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(swapRotation))
            }
            .buttonStyle(.plain)
            .frame(width: 52)
            .accessibilityLabel("Swap languages")

            Menu {
                ForEach(Language.allCases) { lang in
                    Button {
                        targetLanguage = lang
                    } label: {
                        HStack {
                            Text(lang.displayName)
                            if lang == targetLanguage {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            } label: {
                Text(targetLanguage.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 130, alignment: .center)
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Target language")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $inputText)
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .focused($isInputFocused)
                .scrollContentBackground(.hidden)
                .frame(height: 140)
                .accessibilityLabel("Text to translate")
                .overlay(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Enter text to translate...")
                            .font(.system(size: 22, weight: .regular, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

            HStack(spacing: 16) {
                // Mic button
                Button {
                    toggleRecording()
                } label: {
                    Image(systemName: isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isRecording ? .red : .blue)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(isRecording ? Color.red.opacity(0.12) : Color.blue.opacity(0.12))
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .symbolEffect(.pulse, options: .repeating, value: isRecording)
                .accessibilityLabel(isRecording ? "Stop recording" : "Dictate text")

                Spacer()

                // Clear / Paste
                if !inputText.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            inputText = ""
                            outputText = ""
                            isTranslating = false
                            errorMessage = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear text")
                } else {
                    Button {
                        if let pasted = UIPasteboard.general.string {
                            withAnimation(.spring(response: 0.3)) {
                                inputText = pasted
                            }
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 18))
                            .foregroundStyle(.blue)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Paste from clipboard")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - Translate Button

    private var translateButton: some View {
        Button {
            performTranslation()
        } label: {
            HStack(spacing: 10) {
                if isTranslating {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                    Text("Translating...")
                        .font(.headline.weight(.semibold))
                } else {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.headline)
                    Text("Translate")
                        .font(.headline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(canTranslate ? Color.blue : Color.blue.opacity(0.3))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(
                color: canTranslate ? .blue.opacity(0.3) : .clear,
                radius: 12, y: 6
            )
        }
        .disabled(!canTranslate)
        .scaleEffect(canTranslate ? 1.0 : 0.97)
        .animation(.spring(response: 0.2), value: canTranslate)
    }

    // MARK: - Output Area

    private var outputArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            if outputText.isEmpty && !isTranslating {
                placeholderOutput
            } else if isTranslating && outputText.isEmpty {
                translatingState
            } else {
                resultOutput
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
        )
    }

    private var placeholderOutput: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.blue.opacity(0.2))
            Text("Translation will appear here")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.vertical, 32)
    }

    private var translatingState: some View {
        VStack(spacing: 20) {
            TranslatingDots()
                .frame(height: 40)

            Text("Translating with \(activeModel?.displayName ?? "AI")...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.vertical, 32)
    }

    private var resultOutput: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(outputText)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(6)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                        .id("output-end")
                }
                .onChange(of: outputText) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("output-end", anchor: .bottom)
                    }
                }
            }
            .frame(minHeight: 80, maxHeight: 220)

            // Action bar
            HStack(spacing: 0) {
                actionButton(icon: "speaker.wave.2.fill", label: "Speak translation", action: speakOutput)
                Divider().frame(height: 24)
                actionButton(icon: "doc.on.doc", label: "Copy translation", action: copyOutput)
                Divider().frame(height: 24)
                actionButton(icon: "square.and.arrow.up", label: "Share translation", action: { showShareSheet = true })
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3)) {
                    errorMessage = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func swapLanguages() {
        let temp = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = temp
        if !outputText.isEmpty && !isTranslating {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                inputText = outputText
                outputText = ""
                errorMessage = nil
            }
        }
    }

    private func copyOutput() {
        UIPasteboard.general.string = outputText
        withAnimation(.spring(response: 0.3)) {
            showCopyToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3)) {
                showCopyToast = false
            }
        }
    }

    private func speakOutput() {
        guard !outputText.isEmpty else { return }
        let voices = ttsService.availableVoices(forLanguage: targetLanguage.code)
        ttsService.speak(outputText, voice: voices.first)
    }

    private func toggleRecording() {
        guard !isRecording else {
            stopRecording()
            return
        }
        startRecording()
    }

    private func startRecording() {
        Task {
            let granted = await SpeechService.requestPermissions()
            guard granted else { return }

            do {
                let locale = Locale(identifier: sourceLanguage.code)
                let service = try SpeechService(locale: locale)
                service.onTranscription = { text in
                    Task { @MainActor in
                        self.inputText = text
                    }
                }
                service.onComplete = { text in
                    Task { @MainActor in
                        if let text { self.inputText = text }
                        self.isRecording = false
                    }
                }
                service.onError = { _ in
                    Task { @MainActor in
                        self.isRecording = false
                    }
                }
                try service.startRecording()
                await MainActor.run {
                    self.speechService = service
                    self.isRecording = true
                }
            } catch {
VocoLog.speech.error("[TranslationView] Speech error: \\(error)")
                isRecording = false
            }
        }
    }

    private func stopRecording() {
        speechService?.stopRecording()
        speechService = nil
        isRecording = false
    }

    // MARK: - Translation Logic
    // NOTE: Preserved exactly for hy-mt1.5-1.8b-stq STQ1_0 compatibility.

    private func performTranslation() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTranslating else { return }

        isTranslating = true
        outputText = ""
        errorMessage = nil

        let targetLang = targetLanguage.hunyuanTargetName

        Task {
            var fullOutput = ""
            var tokenCount = 0

            let stream = lifecycleManager.translateStream(
                text,
                from: sourceLanguage.displayName,
                to: targetLang
            )

            do {
                for try await chunk in stream {
                    fullOutput += chunk
                    tokenCount += 1

                    await MainActor.run {
                        outputText = fullOutput

                        if tokenCount % 3 == 0 {
                            haptic.impactOccurred(intensity: 0.4)
                        }
                    }
                }

                await MainActor.run {
                    isTranslating = false
                    haptic.impactOccurred(intensity: 0.8)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isTranslating = false
                }
            }
        }
    }
}

// MARK: - Translating Dots Animation

private struct TranslatingDots: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<5) { i in
                PulsingDot(delay: Double(i) * 0.1)
            }
        }
    }
}

private struct PulsingDot: View {
    let delay: Double
    @State private var isActive = false

    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 8, height: 8)
            .opacity(isActive ? 1.0 : 0.25)
            .offset(y: isActive ? -6 : 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.45)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    isActive = true
                }
            }
    }
}

// MARK: - Copy Toast

private struct CopyToast: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Copied to clipboard")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    TranslationView(selectedModelID: .constant("hy-mt1.5-1.8b-stq"))
        .environment(\.lifecycleManager, ModelLifecycleManager())
        .environment(\.downloadManager, ModelManagerService())
}
