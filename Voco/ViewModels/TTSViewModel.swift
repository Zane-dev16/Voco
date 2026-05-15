//
//  TTSViewModel.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import AVFoundation
import Combine

/// View model that exposes offline TTS capabilities to SwiftUI views.
/// Owns a TTSService and translates its callbacks into observable state.
@Observable
@MainActor
final class TTSViewModel {

    // MARK: - Observable state

    /// Current playback state (idle, speaking, paused).
    var playbackState: TTSPlaybackState = .idle

    /// Whether playback is active (speaking or paused).
    var isPlaying: Bool {
        playbackState == .speaking || playbackState == .paused
    }

    /// Whether the engine is currently speaking (not paused).
    var isSpeaking: Bool {
        playbackState == .speaking
    }

    /// Speech rate: 0.0 (slowest) … 1.0 (fastest). Default is AVSpeechUtteranceDefaultSpeechRate.
    var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate

    /// Pitch multiplier: 0.5 (low) … 2.0 (high). Default is 1.0.
    var pitchMultiplier: Float = 1.0

    /// Currently selected language code (e.g. "en-US").
    var selectedLanguageCode: String = "en-US"

    /// Currently selected voice, derived from language code.
    var selectedVoice: AVSpeechSynthesisVoice? {
        availableVoices.first
    }

    /// Voices available for the selected language.
    var availableVoices: [AVSpeechSynthesisVoice] {
        service.availableVoices(forLanguage: String(selectedLanguageCode.prefix(2)))
    }

    /// All languages with installed voices.
    var availableLanguages: [String] {
        service.availableLanguages
    }

    /// Normalised progress (0.0 … 1.0) during playback.
    var progress: Float = 0

    // MARK: - Dependencies

    private let service: TTSService
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    init(service: TTSService = TTSService()) {
        self.service = service

        // Forward playback state from the service.
        service.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.playbackState = state }
            .store(in: &cancellables)

        // Forward progress values.
        service.progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.progress = value }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    /// Speak the given text using current settings.
    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        progress = 0
        service.speak(
            text,
            voice: selectedVoice,
            rate: speechRate,
            pitchMultiplier: pitchMultiplier
        )
    }

    /// Pause at the current word boundary.
    func pause() {
        service.pause()
    }

    /// Resume from a pause.
    func resume() {
        service.resume()
    }

    /// Toggle between pause and resume.
    func togglePauseResume() {
        switch playbackState {
        case .speaking:
            pause()
        case .paused:
            resume()
        case .idle:
            break
        }
    }

    /// Stop playback immediately.
    func stop() {
        service.stop()
        progress = 0
    }
}
