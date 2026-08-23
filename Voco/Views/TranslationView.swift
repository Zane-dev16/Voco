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
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.lifecycleManager) private var lifecycleManager
    @Environment(\.downloadManager) private var downloadManager
    @EnvironmentObject private var languageRegistry: LanguageRegistry

    // MARK: - State

    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var sourceLanguage: Language = .english
    @State private var targetLanguage: Language = .spanish
    @State private var isTranslating: Bool = false
    @State private var showShareSheet = false
    @State private var showCopyToast = false
    /// Hide timer for the copy toast — cancelled and replaced on repeat taps,
    /// and invalidated when the view disappears.
    @State private var copyToastHideTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var isRecording = false
    @State private var speechService: SpeechService?
    @State private var translationTask: Task<Void, Never>?
    @State private var swapRotation: Double = 0
    @State private var translationComplete: Bool = false
    @State private var showSourceLanguagePicker = false
    @State private var showTargetLanguagePicker = false

    /// Dynamic Type scaling for the large rounded input/output text.
    @ScaledMetric(relativeTo: .largeTitle) private var workspaceTextSize: CGFloat = 22
    /// Tracks the length at which the output last auto-scrolled, so we don't
    /// fire an animated scroll (and disturb VoiceOver) on every stream chunk.
    @State private var lastAutoScrollLength = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Language Capability Helpers

    /// Whether the source language supports offline STT (microphone input).
    private var sourceSupportsSTT: Bool {
        languageRegistry.language(forID: sourceLanguage.rawValue)?.supportsOfflineSTT ?? false
    }

    /// Whether the target language supports offline TTS (speech output).
    private var targetSupportsTTS: Bool {
        languageRegistry.language(forID: targetLanguage.rawValue)?.supportsOfflineTTS ?? false
    }

    // MARK: - Services

    // @State keeps these instances alive across View struct re-inits. Plain
    // `let`s were recreated on every generation — each one allocating a fresh
    // AVSpeechSynthesizer (resetting published TTS state mid-speech) and a new
    // haptics generator.
    @State private var haptic = UIImpactFeedbackGenerator(style: .soft)
    @State private var ttsService = TTSService()

    // MARK: - Computed

    private var activeModel: TranslationModel? {
        TranslationModel.availableModels.first { $0.id == lifecycleManager.activeModelID }
    }

    private var canTranslate: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isTranslating
    }

    /// Button is visually dimmed after translation completes; reappears on input change.
    private var buttonDimmed: Bool {
        translationComplete || !canTranslate
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Language selector
                    LanguageSelectorBar(
                        sourceLanguage: $sourceLanguage,
                        targetLanguage: $targetLanguage,
                        onSwap: swapLanguages
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                    // Input area
                    TranslationInputCard(
                        inputText: $inputText,
                        isInputFocused: $isInputFocused,
                        workspaceTextSize: workspaceTextSize,
                        isRecording: isRecording,
                        supportsSTT: sourceSupportsSTT,
                        onToggleRecording: toggleRecording,
                        onClear: clearInput
                    )
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
                .contentShape(Rectangle())
                .onTapGesture { isInputFocused = false }
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
                    ErrorBanner(message: error) {
                        errorMessage = nil
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    Spacer()
                }
            }
        }
        .onAppear { haptic.prepare() }
        .onDisappear {
            // Stop the toast hide timer so it can't fire after the view is gone.
            copyToastHideTask?.cancel()
        }
        .onChange(of: inputText) { _, _ in
            translationComplete = false
        }
        .onChange(of: sourceLanguage) { _, _ in
            translationComplete = false
        }
        .onChange(of: targetLanguage) { _, _ in
            translationComplete = false
        }
        .onChange(of: selectedModelID) { _, _ in
            // Switching models tears the engine down (lifecycle manager cancels
            // in-flight producers before unload) — cancel the consumer-side task
            // too so UI state resets deterministically instead of racing the
            // stream's natural end.
            translationTask?.cancel()
            translationTask = nil
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isTranslating = false
                translationComplete = false
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [outputText])
        }
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
            .background(buttonDimmed ? Color.blue.opacity(0.3) : Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(
                color: buttonDimmed ? .clear : .blue.opacity(0.3),
                radius: 12, y: 6
            )
        }
        .disabled(!canTranslate)
        .scaleEffect(buttonDimmed ? 0.97 : 1.0)
        .animation(.spring(response: 0.2), value: buttonDimmed)
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
                        .font(.system(size: workspaceTextSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(6)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                        .id("output-end")
                        // VoiceOver reads the full translation when focused;
                        // completion is announced separately in performTranslation().
                        .accessibilityLabel(outputText)
                }
                .onChange(of: outputText) { _, newText in
                    // Throttle auto-scroll so streaming chunks don't fire an
                    // animated scroll (and shift focus) on every token.
                    guard abs(newText.count - lastAutoScrollLength) >= 40 || newText.count < 40 else { return }
                    lastAutoScrollLength = newText.count
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo("output-end", anchor: .bottom)
                    }
                }
            }
            .frame(minHeight: 80, maxHeight: 220)

            // Action bar
            HStack(spacing: 0) {
                // Speaker button — only shown if target language supports TTS
                if targetSupportsTTS {
                    actionButton(icon: "speaker.wave.2.fill", label: "Speak translation", action: speakOutput)
                    Divider().frame(height: 24)
                }
                actionButton(icon: "doc.on.doc", label: "Copy translation", action: copyOutput)
                Divider().frame(height: 24)
                actionButton(icon: "square.and.arrow.up", label: "Share translation", action: { showShareSheet = true })
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func actionButton(icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: - Actions

    /// Clear button side effects — the input card owns the button, this view
    /// owns cancelling in-flight work and resetting results.
    private func clearInput() {
        translationTask?.cancel()
        translationTask = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            inputText = ""
            outputText = ""
            isTranslating = false
            errorMessage = nil
        }
    }

    private func swapLanguages() {
        // S7-06: cancel any in-flight stream first — otherwise old-direction
        // chunks keep appending while the header shows the swapped pair,
        // presenting the finished translation under the wrong language.
        if isTranslating {
            translationTask?.cancel()
            translationTask = nil
            isTranslating = false
        }
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
        UIAccessibility.post(notification: .announcement,
                             argument: NSLocalizedString("Copied to clipboard", comment: "Copy confirmation"))
        // Cancel any pending hide task so repeated taps don't stack timers
        // (which caused flicker and premature hides).
        copyToastHideTask?.cancel()
        withAnimation(.spring(response: 0.3)) {
            showCopyToast = true
        }
        copyToastHideTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
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
                        // Release mic + service (S7-05): belt-and-braces with
                        // SpeechService's own isFinal cleanup.
                        self.speechService?.stopRecording()
                        self.speechService = nil
                    }
                }
                service.onError = { _ in
                    Task { @MainActor in
                        self.isRecording = false
                        self.speechService?.stopRecording()
                        self.speechService = nil
                    }
                }
                try service.startRecording()
                await MainActor.run {
                    self.speechService = service
                    self.isRecording = true
                }
            } catch {
VocoLog.speech.error("[TranslationView] Speech error: \(error)")
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

    private func performTranslation() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Cancel any in-flight translation before starting a new one
        translationTask?.cancel()

        isTranslating = true
        outputText = ""
        errorMessage = nil

        let targetLang = targetLanguage.hunyuanTargetName

        translationTask = Task {
            // Accumulate chunks in an array instead of `fullOutput += chunk` —
            // repeated string concatenation is O(n²) for large outputs.
            var chunks: [String] = []
            var chunkCount = 0
            // Coalesced flush state: at most one UI update (~100 ms) / haptic
            // (~350 ms) per window, instead of per-token re-layout of the
            // entire Text(outputText) body.
            var lastFlush = ContinuousClock.now
            var lastHaptic = ContinuousClock.now

            do {
                let stream = lifecycleManager.translateStream(
                    text,
                    from: sourceLanguage.displayName,
                    to: targetLang
                )

                for try await chunk in stream {
                    try Task.checkCancellation()
                    chunks.append(chunk)
                    chunkCount += 1

                    let now = ContinuousClock.now
                    // First chunk renders immediately; afterwards coalesce to
                    // ~100 ms windows (or every 8th chunk on fast models).
                    guard chunkCount == 1
                            || now - lastFlush >= .milliseconds(100)
                            || chunkCount % 8 == 0 else { continue }
                    lastFlush = now
                    outputText = chunks.joined()

                    // Time-throttled haptic (~2.9 impacts/s max) replaces the
                    // tokenCount % 3 gate, which fired ~1.7×/s continuously.
                    if now - lastHaptic >= .milliseconds(350) {
                        lastHaptic = now
                        haptic.impactOccurred(intensity: 0.4)
                    }
                }

                // Only finalize if not cancelled
                if !Task.isCancelled {
                    outputText = chunks.joined()
                    isTranslating = false
                    translationComplete = true
                    haptic.impactOccurred(intensity: 0.8)
                    // VoiceOver: announce once at completion rather than per chunk.
                    UIAccessibility.post(notification: .announcement,
                                         argument: NSLocalizedString("Translation complete", comment: "Streaming finished"))
                }
            } catch is CancellationError {
                // Swallow — new translation replaced this one
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    isTranslating = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    @FocusState var focused: Bool
    return TranslationView(selectedModelID: .constant("hy-mt2-1.8b-stq"), isInputFocused: $focused)
        .environment(\.lifecycleManager, ModelLifecycleManager())
        .environment(\.downloadManager, ModelManagerService())
}
