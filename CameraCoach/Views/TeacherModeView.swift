// TeacherModeView.swift
// Teacher HUD overlay (the camera preview + face box live in ContentView and
// stay mounted across mode switches). The teacher frames the shot, optionally
// records spoken instructions, and locks it in with the Camera Control button or
// the on-screen Capture button — which builds a ReferenceFrame and hands it up.

import SwiftUI

struct TeacherModeView: View {

    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var motionManager: MotionManager
    let router: CaptureRouter
    var onOpenSettings: () -> Void
    var onReferenceCaptured: (ReferenceFrame) -> Void

    @StateObject private var voiceRecorder = VoiceRecorder()
    @State private var selectedMode: CameraMode = .photo

    init(cameraManager: CameraManager,
         motionManager: MotionManager,
         router: CaptureRouter,
         onOpenSettings: @escaping () -> Void,
         onReferenceCaptured: @escaping (ReferenceFrame) -> Void) {
        _cameraManager = ObservedObject(wrappedValue: cameraManager)
        _motionManager = ObservedObject(wrappedValue: motionManager)
        self.router = router
        self.onOpenSettings = onOpenSettings
        self.onReferenceCaptured = onReferenceCaptured
    }

    var body: some View {
        VStack {
            topBar
            Spacer()
            captureControls
        }
        .padding(.horizontal, 16)
        .onAppear {
            voiceRecorder.requestPermissions()
            // Register hardware Camera Control to capture the reference.
            router.action = captureReference
        }
    }

    // MARK: - Top bar: settings + mode picker + live stats

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(radius: 3)
                }
            }

            Picker("Mode", selection: $selectedMode) {
                ForEach(CameraMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 14) {
                stat("Dist", cameraManager.subjectDistance.map { String(format: "%.1fm", $0) } ?? "—")
                stat("Lum", cameraManager.brightness.map { String(format: "%.0f%%", $0 / 255 * 100) } ?? "—")
                stat("Tilt", String(format: "%+.0f°", motionManager.roll))

                if let hist = cameraManager.histogram {
                    HistogramView(bins: hist)
                        .frame(width: 70, height: 28)
                }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.white)
            .padding(8)
            .background(.black.opacity(0.55))
            .cornerRadius(10)
        }
        .padding(.top, 8)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).foregroundColor(.white.opacity(0.6))
            Text(value)
        }
    }

    // MARK: - Capture controls

    private var captureControls: some View {
        VStack(spacing: 12) {
            if !voiceRecorder.transcript.isEmpty || voiceRecorder.isRecording {
                Text(voiceRecorder.transcript.isEmpty ? "Listening…" : voiceRecorder.transcript)
                    .font(.callout)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.black.opacity(0.55))
                    .cornerRadius(10)
            }

            if !voiceRecorder.statusMessage.isEmpty {
                Text(voiceRecorder.statusMessage)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            HStack(spacing: 16) {
                Button(action: voiceRecorder.toggle) {
                    Label(voiceRecorder.isRecording ? "Stop" : "Record",
                          systemImage: voiceRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(voiceRecorder.isRecording ? Color.red : Color.white.opacity(0.2))
                        .cornerRadius(12)
                }

                Button(action: captureReference) {
                    Label("Capture", systemImage: "camera.aperture")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.yellow)
                        .cornerRadius(12)
                }
            }

            Text("Tip: press the Camera Control button to capture")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.bottom, 28)
    }

    // MARK: - Capture

    private func captureReference() {
        let state = cameraManager.currentFrameState(
            pitch: Float(motionManager.pitchRad),
            roll:  Float(motionManager.rollRad),
            yaw:   Float(motionManager.yawRad)
        )

        if voiceRecorder.isRecording { voiceRecorder.toggle() }

        let reference = ReferenceFrame(
            state: state,
            cameraMode: selectedMode,
            voiceTranscript: voiceRecorder.transcript,
            capturedAt: Date()
        )

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onReferenceCaptured(reference)
    }
}
