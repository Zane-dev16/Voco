//
//  TranslationInputCard.swift
//  Voco
//
//  Rounded input card: text editor with placeholder, mic / clear / paste row.
//

import SwiftUI
import UIKit

struct TranslationInputCard: View {
    @Binding var inputText: String
    @FocusState.Binding var isInputFocused: Bool
    /// Dynamic Type-scaled font size shared with the output card.
    let workspaceTextSize: CGFloat
    let isRecording: Bool
    let supportsSTT: Bool
    /// Right-to-left script for the source language — aligns the editor.
    var isRTL: Bool = false
    let onToggleRecording: () -> Void
    /// Parent-side clear side effects (cancel translation, reset output/error).
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $inputText)
                .font(.system(size: workspaceTextSize, weight: .regular, design: .rounded))
                .focused($isInputFocused)
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                .scrollContentBackground(.hidden)
                // minHeight instead of fixed height so input isn't clipped
                // at large Dynamic Type sizes.
                .frame(minHeight: 140)
                .accessibilityLabel("Text to translate")
                .overlay(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Enter text to translate...")
                            .font(.system(size: workspaceTextSize, weight: .regular, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

            actionRow
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
        )
    }

    private var actionRow: some View {
        HStack(spacing: 16) {
            // Mic button — only shown if source language supports STT
            if supportsSTT {
                Button {
                    onToggleRecording()
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
            }

            Spacer()

            if !inputText.isEmpty {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear text")
            } else {
                pasteButton
            }
        }
    }

    private var pasteButton: some View {
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
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paste from clipboard")
    }
}
