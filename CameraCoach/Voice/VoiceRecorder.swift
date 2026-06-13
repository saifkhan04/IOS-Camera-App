// VoiceRecorder.swift
// Wraps SFSpeechRecognizer for on-device transcription of the teacher's
// spoken framing instructions.
//
// How the pieces fit together:
//   AVAudioEngine        — taps the microphone and hands us raw audio buffers
//   SFSpeechAudioBufferRecognitionRequest — the live audio stream to transcribe
//   SFSpeechRecognitionTask — the running recognition job; calls us back with
//                             partial results as the user keeps talking
//
// Two separate permissions are required, each with its own Info.plist string:
//   - Speech recognition  (NSSpeechRecognitionUsageDescription)
//   - Microphone          (NSMicrophoneUsageDescription)
//
// On-device recognition (requiresOnDeviceRecognition = true) keeps audio off
// Apple's servers — private, offline, and no network latency. Supported on
// A12+ devices, so the iPhone 17 Pro handles it easily.

import Foundation
import Speech
import AVFoundation

final class VoiceRecorder: ObservableObject {

    // MARK: - Published state (drives the Teacher UI)

    @Published var transcript = ""        // grows live as the user speaks
    @Published var isRecording = false
    @Published var statusMessage = ""     // surfaced to the user on errors

    // MARK: - Speech / audio plumbing

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Permissions

    // Call once (e.g. on view appear). Prompts for Speech access; the mic
    // prompt fires the first time the audio engine starts.
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.statusMessage = (status == .authorized)
                    ? ""
                    : "Speech permission denied — enable it in Settings."
            }
        }
    }

    // MARK: - Control

    func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        guard let recognizer, recognizer.isAvailable else {
            statusMessage = "Speech recognizer unavailable."
            return
        }

        // Clear any previous run.
        transcript = ""
        task?.cancel()
        task = nil

        do {
            // Configure the shared audio session for recording. .measurement
            // mode disables system-added processing (AGC/EQ) for cleaner input.
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true   // stream partial text live
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            // Tap the mic. The input node delivers PCM buffers on an audio
            // thread; we forward each one into the recognition request.
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            statusMessage = ""

            // Start recognition. Callback fires repeatedly with better guesses.
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    DispatchQueue.main.async {
                        self.transcript = result.bestTranscription.formattedString
                    }
                }
                // End on error or when the recognizer marks the result final.
                if error != nil || (result?.isFinal ?? false) {
                    DispatchQueue.main.async { self.stop() }
                }
            }
        } catch {
            statusMessage = "Audio error: \(error.localizedDescription)"
            stop()
        }
    }

    private func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false

        // Release the audio session so the camera/other audio can resume.
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }
}
