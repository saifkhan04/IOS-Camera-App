// TeacherModeView.swift
// The teacher frames the shot, optionally records spoken instructions, and locks
// it in with the Camera Control button or the on-screen Capture button. On
// capture it builds a ReferenceFrame and hands it up to ContentView, which
// switches into Shooter Mode.
//
// The camera + motion managers are injected (owned by ContentView) so the
// session keeps running across the Teacher → Shooter transition. The voice
// recorder is Teacher-only, so it's owned here.

import SwiftUI

struct TeacherModeView: View {

    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var motionManager: MotionManager
    var onReferenceCaptured: (ReferenceFrame) -> Void

    @StateObject private var voiceRecorder = VoiceRecorder()
    @State private var selectedMode: CameraMode = .photo

    init(cameraManager: CameraManager,
         motionManager: MotionManager,
         onReferenceCaptured: @escaping (ReferenceFrame) -> Void) {
        _cameraManager = ObservedObject(wrappedValue: cameraManager)
        _motionManager = ObservedObject(wrappedValue: motionManager)
        self.onReferenceCaptured = onReferenceCaptured
    }

    var body: some View {
        ZStack {
            CameraPreviewView(
                session: cameraManager.session,
                onCameraControl: captureReference
            )
            .ignoresSafeArea()

            FaceBoxOverlay(normRect: cameraManager.faceNormRect)

            VStack {
                topBar
                Spacer()
                captureControls
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            voiceRecorder.requestPermissions()
        }
    }

    // MARK: - Top bar: mode picker + live stats

    private var topBar: some View {
        VStack(spacing: 8) {
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
