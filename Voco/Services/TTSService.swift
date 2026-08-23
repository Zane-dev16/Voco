//
//  TTSService.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import AVFoundation
import Combine

/// Playback state for the text-to-speech engine.
enum TTSPlaybackState: Equatable {
    case idle
    case speaking
    case paused
}

/// Lightweight service wrapping AVSpeechSynthesizer.
///
/// MainActor-isolated: all mutable state (`state`) is protected by the main
/// actor, which also makes the class implicitly `Sendable`. Delegate callbacks
/// arrive on an arbitrary queue, so each witness below is explicitly
/// `nonisolated` and hops back to the main actor via `Task { @MainActor in … }`.
@MainActor
final class TTSService: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var state: TTSPlaybackState = .idle

    // MARK: - Private

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Init

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// Available voices filtered to the given language tag (e.g. "en", "fil-PH").
    /// Returns all matching voices sorted by quality.
    func availableVoices(forLanguage languageCode: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languageCode) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    /// Speak the given text with optional voice, rate, and pitch overrides.
    func speak(
        _ text: String,
        voice: AVSpeechSynthesisVoice? = nil,
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pitchMultiplier: Float = 1.0
    ) {
        // Stop any current speech before starting new
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.pitchMultiplier = pitchMultiplier
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.05

        synthesizer.speak(utterance)
    }

    /// Stop playback immediately.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

// AVSpeechSynthesizerDelegate requirements are nonisolated (callbacks arrive
// on an arbitrary queue), so each witness must be explicitly `nonisolated`
// rather than inheriting the class's MainActor isolation.
extension TTSService: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.state = .speaking }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.state = .idle }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didPause utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.state = .paused }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didContinue utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.state = .speaking }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.state = .idle }
    }
}
