//
//  SpeechService.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import AVFoundation
import Speech
import OSLog

// MARK: - SpeechRecognitionError

/// Errors that can occur during speech recognition.
enum SpeechRecognitionError: LocalizedError {
    case notAvailable
    case localeNotSupported(Locale)
    case permissionDenied
    case audioSessionError(Error)
    case recognitionTaskError(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Speech recognition is not available on this device."
        case .localeNotSupported(let locale):
            return "Speech recognition is not supported for \(locale.identifier)."
        case .permissionDenied:
            return "Microphone and speech recognition permissions are required."
        case .audioSessionError(let error):
            return "Audio session error: \(error.localizedDescription)"
        case .recognitionTaskError(let error):
            return "Recognition error: \(error.localizedDescription)"
        }
    }
}

// MARK: - SpeechService

/// Service layer wrapping Apple's SFSpeechRecognizer for offline speech-to-text.
/// Provides async/await API and real-time transcription via a callback.
@MainActor
final class SpeechService {

    // MARK: - Properties

    private let speechRecognizer: SFSpeechRecognizer
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Callback invoked with each transcription update.
    var onTranscription: ((String) -> Void)?

    /// Callback invoked when recognition finishes (final result).
    var onComplete: ((String?) -> Void)?

    /// Callback invoked on error during recognition.
    var onError: ((Error) -> Void)?

    // MARK: - Init

    /// Creates a SpeechService for the given locale.
    /// Falls back to the device's preferred locale if nil.
    /// - Parameter locale: The locale to use for speech recognition. Defaults to `Locale.current`.
    /// - Throws: `SpeechRecognitionError.notAvailable` if on-device recognition is unsupported.
    init(locale: Locale? = nil) throws {
        let targetLocale = locale ?? Locale.current

        guard let recognizer = SFSpeechRecognizer(locale: targetLocale) else {
            throw SpeechRecognitionError.localeNotSupported(targetLocale)
        }

        guard recognizer.isAvailable else {
            throw SpeechRecognitionError.notAvailable
        }

        self.speechRecognizer = recognizer
    }

    // MARK: - Permission

    /// Requests microphone and speech recognition permissions.
    /// - Returns: `true` if both permissions are granted.
    static func requestPermissions() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard granted else { return false }

        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                continuation.resume(returning: audioGranted)
            }
        }
    }

    // MARK: - Availability

    /// Checks if on-device speech recognition is available for the configured locale.
    var isOnDeviceAvailable: Bool {
        speechRecognizer.supportsOnDeviceRecognition
    }

    /// The locale this service is configured for.
    var locale: Locale {
        speechRecognizer.locale
    }

    // MARK: - Real-Time Transcription

    /// Starts real-time transcription.
    /// Calls `onTranscription` with partial results and `onComplete` when done.
    /// - Throws: `SpeechRecognitionError` on failure.
    func startRecording() throws {
        // Cancel any previous task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechRecognitionError.audioSessionError(error)
        }

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        // Get the input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Defensive: remove any stale tap from an aborted previous session
        // before installing (no-op when none exists).
        inputNode.removeTap(onBus: 0)

        // Append directly through the local request: the tap fires on an audio
        // queue and must not touch MainActor-isolated state.
        // SFSpeechAudioBufferRecognitionRequest.append(_:) is thread-safe.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        // Prepare and start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw SpeechRecognitionError.audioSessionError(error)
        }

        // Start recognition
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            // The recognizer invokes this callback on a background queue — extract
            // the values here, then hop to the main actor before touching any
            // MainActor-isolated service state.
            let text = result.map { $0.bestTranscription.formattedString }
            let isFinal = result?.isFinal ?? false

            Task { @MainActor [weak self] in
                guard let self else { return }

                if let text {
                    if isFinal {
                        self.onComplete?(text)
                        // Final result delivered — release the microphone NOW.
                        // Without this the tap stays installed, the engine keeps
                        // running, and the .record session stays active process-wide
                        // (mic indicator lit, other apps' audio ducked).
                        self.stopRecording()
                    } else {
                        self.onTranscription?(text)
                    }
                }

                if let error {
                    self.onError?(error)
                    self.stopRecording()
                }
            }
        }
    }

    /// Stops the current recording session.
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil

        // Deactivate audio session — release the hardware lock so other apps can use it.
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            // Log but don't throw — recording is stopping regardless.
VocoLog.speech.error("[SpeechService] Failed to deactivate audio session: \(error)")
        }
    }
}
