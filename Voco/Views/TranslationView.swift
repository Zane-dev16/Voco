//
//  TranslationView.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import SwiftUI

struct TranslationView: View {
    @State private var viewModel: TranslationViewModel
    @State private var speechVM = SpeechViewModel()
    @State private var ttsVM = TTSViewModel()
    @State private var showSpeechError = false

    init(modelManager: ModelManagerService) {
        _viewModel = State(wrappedValue: TranslationViewModel(modelManager: modelManager, llamaService: LlamaService()))
    }

    var body: some View {
        VStack(spacing: 0) {
            languageSelectorRow
            Divider()
            textArea
            translateButton
        }
        .navigationTitle("Translate")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.models) {
                    Image(systemName: "arrow.down.circle")
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Speech Error", isPresented: $showSpeechError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(speechVM.errorMessage ?? "")
        }
        .onChange(of: speechVM.errorMessage) { oldValue, newValue in
            showSpeechError = newValue != nil
        }
    }

    // MARK: - Language Selector

    private var languageSelectorRow: some View {
        HStack(spacing: 12) {
            LanguagePicker(title: "From", selection: $viewModel.sourceLanguage)
            Button {
                withAnimation(.snappy) { viewModel.swapLanguages() }
            } label: {
                Image(systemName: "arrow.right.arrow.left")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Swap languages")
            LanguagePicker(title: "To", selection: $viewModel.targetLanguage)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Text Area

    private var textArea: some View {
        VStack(spacing: 0) {
            inputSection
            Divider()
            outputSection
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    private var inputSection: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.inputText.isEmpty {
                Text("Enter text to translate...")
                    .foregroundStyle(.tertiary)
                    .padding(12)
            }
            TextEditor(text: $viewModel.inputText)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)

            // STT microphone button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    sttButton
                        .padding(4)
                }
                .padding(.trailing, 4)
                .padding(.bottom, 4)
            }
        }
    }

    private var sttButton: some View {
        Button {
            if speechVM.isRecording {
                speechVM.stopRecording()
            } else {
                speechVM.startRecording()
            }
        } label: {
            Image(systemName: speechVM.isRecording ? "mic.fill" : "mic")
                .font(.caption)
                .padding(6)
                .background(speechVM.isRecording ? Color.red.opacity(0.2) : Color.gray.opacity(0.2))
                .clipShape(Circle())
        }
        .disabled(!speechVM.permissionsGranted && !speechVM.isRecording)
        .accessibilityLabel(speechVM.isRecording ? "Stop recording" : "Start voice input")
    }

    private var outputSection: some View {
        ZStack(alignment: .topLeading) {
            if let translated = viewModel.translatedText {
                Text(translated).padding(12)
            } else {
                Text("Translation will appear here")
                    .foregroundStyle(.tertiary)
                    .padding(12)
            }
            if viewModel.isModelLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(viewModel.modelLoadProgress ?? "Loading model...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            } else if viewModel.isTranslating {
                ProgressView().padding(12)
            }

            // TTS speak button
            if viewModel.translatedText != nil && !viewModel.translatedText!.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ttsButton
                            .padding(4)
                    }
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(minHeight: 120)
        .background(Color(.secondarySystemBackground))
    }

    private var ttsButton: some View {
        Button {
            switch ttsVM.playbackState {
            case .idle:
                ttsVM.speak(viewModel.translatedText ?? "")
            case .speaking:
                ttsVM.pause()
            case .paused:
                ttsVM.resume()
            }
        } label: {
            Image(systemName: ttsIcon)
                .font(.caption)
                .padding(6)
                .background(ttsBackground)
                .clipShape(Circle())
        }
        .accessibilityLabel(ttsAccessibilityLabel)
    }

    private var ttsIcon: String {
        switch ttsVM.playbackState {
        case .idle: return "speaker.wave.2"
        case .speaking: return "pause.fill"
        case .paused: return "play.fill"
        }
    }

    private var ttsBackground: Color {
        switch ttsVM.playbackState {
        case .idle: return Color.blue.opacity(0.2)
        case .speaking: return Color.blue.opacity(0.3)
        case .paused: return Color.gray.opacity(0.2)
        }
    }

    private var ttsAccessibilityLabel: String {
        switch ttsVM.playbackState {
        case .idle: return "Read translation aloud"
        case .speaking: return "Pause reading"
        case .paused: return "Resume reading"
        }
    }

    // MARK: - Translate Button

    private var translateButton: some View {
        Button {
            viewModel.startTranslation()
        } label: {
            Text(viewModel.isModelLoading ? "Loading Model..." : "Translate")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.inputText.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(viewModel.inputText.isEmpty || viewModel.isTranslating)
        .padding(.horizontal)
        .padding(.bottom)
    }
}

// MARK: - Language Picker

struct LanguagePicker: View {
    let title: String
    @Binding var selection: Language

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                ForEach(Language.allCases) { lang in
                    Text("\(lang.flag) \(lang.displayName)").tag(lang)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

#Preview {
    NavigationStack { TranslationView(modelManager: ModelManagerService()) }
}
