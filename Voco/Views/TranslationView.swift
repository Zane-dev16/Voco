//
//  TranslationView.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import SwiftUI

struct TranslationView: View {
    @State private var viewModel: TranslationViewModel

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
    }

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

    private var textArea: some View {
        VStack(spacing: 0) {
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
            }
            Divider()
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
            }
            .frame(minHeight: 120)
            .background(Color(.secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }

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
