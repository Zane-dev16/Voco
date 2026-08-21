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
/// Delivers delegate callbacks via a Combine publisher.
final class TTSService: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var state: TTSPlaybackState = .idle

    // MARK: - Private

    private let synthesizer = AVSpeechSynthesizer()
    private var progressSubject = PassthroughSubject<Float, Never>()

    /// A stream of 0…1 progress values while speech is active.
    var progress: AnyPublisher<Float, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    // MARK: - Init

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// Available voices filtered to the given language code (e.g. "en", "fr").
    /// Returns all matching voices sorted by quality.
    func availableVoices(forLanguage languageCode: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languageCode) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    /// All available languages that have at least one voice installed.
    var availableLanguages: [String] {
        let codes = Set(AVSpeechSynthesisVoice.speechVoices().map { $0.language })
        return codes.sorted()
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

    /// Pause at the current boundary. No-op if not speaking.
    func pause() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.pauseSpeaking(at: .word)
    }

    /// Resume after a pause. No-op if not paused.
    func resume() {
        guard synthesizer.isPaused else { return }
        synthesizer.continueSpeaking()
    }

    /// Stop playback immediately.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSService: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { self.state = .speaking }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async {
            self.state = .idle
            self.progressSubject.send(1.0)
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didPause utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { self.state = .paused }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didContinue utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { self.state = .speaking }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async {
            self.state = .idle
            self.progressSubject.send(0)
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        // characterRange is UTF-16 based (NSRange) — measure the string the same
        // way so progress stays correct for text with multi-unit characters.
        let total = (utterance.speechString as NSString).length
        let progress = total > 0
            ? Float(characterRange.location + characterRange.length) / Float(total)
            : 0
        DispatchQueue.main.async { self.progressSubject.send(progress) }
    }
}
