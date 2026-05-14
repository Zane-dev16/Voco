//
//  SpeechViewModel.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import SwiftUI

// MARK: - SpeechViewModel

/// ViewModel managing speech recognition state and user interactions.
@Observable
@MainActor
final class SpeechViewModel {

    // MARK: - State

    /// Current transcription text (updates in real time).
    var transcription: String = ""

    /// Whether speech recognition is currently active.
    var isRecording: Bool = false

    /// Error message to display to the user, if any.
    var errorMessage: String?

    /// Whether permissions have been requested.
    var permissionsGranted: Bool = false

    /// Whether on-device recognition is available.
    var isOnDeviceAvailable: Bool = false

    // MARK: - Properties

    private var speechService: SpeechService?

    // MARK: - Permission Management

    /// Requests microphone and speech recognition permissions.
    func requestPermissions() async {
        let granted = await SpeechService.requestPermissions()
        permissionsGranted = granted

        if !granted {
            errorMessage = "Microphone and speech recognition permissions are required. Please enable them in Settings."
        } else {
            errorMessage = nil
            setupService()
        }
    }

    // MARK: - Recording Controls

    /// Toggles recording on/off.
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// Starts real-time speech recognition.
    func startRecording() {
        guard permissionsGranted else {
            Task { await requestPermissions() }
            return
        }

        guard let service = speechService else {
            setupService()
            guard let service = speechService else { return }
            startRecordingWith(service)
            return
        }

        startRecordingWith(service)
    }

    /// Stops the current speech recognition session.
    func stopRecording() {
        speechService?.stopRecording()
        isRecording = false
    }

    /// Clears the current transcription and any error.
    func clearTranscription() {
        transcription = ""
        errorMessage = nil
    }

    // MARK: - Private

    private func setupService() {
        do {
            let service = try SpeechService()
            service.onTranscription = { [weak self] text in
                Task { @MainActor in
                    self?.transcription = text
                }
            }
            service.onComplete = { [weak self] text in
                Task { @MainActor in
                    if let text {
                        self?.transcription = text
                    }
                    self?.isRecording = false
                }
            }
            service.onError = { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = error.localizedDescription
                    self?.isRecording = false
                }
            }
            self.speechService = service
            self.isOnDeviceAvailable = service.isOnDeviceAvailable
            self.permissionsGranted = true
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func startRecordingWith(_ service: SpeechService) {
        do {
            try service.startRecording()
            isRecording = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            isRecording = false
        }
    }
}
