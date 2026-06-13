// TeacherModeView.swift
// The teacher's screen: frame the shot, speak the instructions, and lock it
// all in with one press of the Camera Control button (or the on-screen
// button). The captured ReferenceFrame is what the shooter will chase.
//
// This view owns the three live data sources:
//   CameraManager  — video + face + LiDAR depth + C++ luminance/histogram
//   MotionManager  — pitch/roll/yaw
//   VoiceRecorder  — on-device transcription of spoken instructions
//
// Capture flow:
//   press Camera Control / "Capture Reference"
//     → snapshot the current FrameState (CameraManager.currentFrameState)
//     → bundle it with the selected mode + transcript into a ReferenceFrame
//     → haptic + show the saved-reference card

import SwiftUI

struct TeacherModeView: View {

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var motionManager = MotionManager()
    @StateObject private var voiceRecorder = VoiceRecorder()

    @State private var selectedMode: CameraMode = .photo
    @State private var capturedReference: ReferenceFrame?

    var body: some View {
        ZStack {
            // --- Live camera + Camera Control trigger ---
            CameraPreviewView(
                session: cameraManager.session,
                onCameraControl: captureReference
            )
            .ignoresSafeArea()

            // --- Face bounding box ---
            Canvas { ctx, size in
                guard let rect = cameraManager.faceNormRect else { return }
                let screenRect = CGRect(
                    x: rect.origin.x * size.width,
                    y: rect.origin.y * size.height,
                    width: rect.width  * size.width,
                    height: rect.height * size.height
                )
                ctx.stroke(Path(screenRect), with: .color(.green), lineWidth: 2)
            }
            .ignoresSafeArea()

            // --- Controls ---
            VStack {
                topBar
                Spacer()
                bottomControls
            }
            .padding(.horizontal, 16)

            // --- Saved reference card (modal-ish overlay) ---
            if let ref = capturedReference {
                referenceCard(ref)
            }
        }
        .onAppear {
            cameraManager.start()
            motionManager.start()
            voiceRecorder.requestPermissions()
        }
        .onDisappear {
            motionManager.stop()
        }
    }

    // MARK: - Top bar: mode picker + live stats

    private var topBar: some View {
        VStack(spacing: 8) {
            // Capture mode (Photo / Portrait / Live)
            Picker("Mode", selection: $selectedMode) {
                ForEach(CameraMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Compact live readouts
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

    // MARK: - Bottom controls: voice + capture

    private var bottomControls: some View {
        VStack(spacing: 12) {
            // Live transcript (only while there's something to show)
            if !voiceRecorder.transcript.isEmpty || voiceRecorder.isRecording {
                Text(voiceRecorder.transcript.isEmpty
                     ? "Listening…"
                     : voiceRecorder.transcript)
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
                // Record / stop voice instructions
                Button(action: voiceRecorder.toggle) {
                    Label(
                        voiceRecorder.isRecording ? "Stop" : "Record",
                        systemImage: voiceRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                    )
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(voiceRecorder.isRecording ? Color.red : Color.white.opacity(0.2))
                    .cornerRadius(12)
                }

                // Capture the reference frame
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

            // Hint about the hardware button
            Text("Tip: press the Camera Control button to capture")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.bottom, 28)
    }

    // MARK: - Saved reference card

    private func referenceCard(_ ref: ReferenceFrame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reference Captured ✓")
                .font(.title3).bold()
                .foregroundColor(.green)

            Group {
                row("Mode", ref.cameraMode.rawValue)
                row("Distance", String(format: "%.2f m", ref.state.depthMeters))
                row("Face", String(format: "x %.2f  y %.2f", ref.state.faceX, ref.state.faceY))
                row("Tilt", String(format: "roll %+.0f°  pitch %+.0f°",
                                   ref.state.roll * 180 / .pi,
                                   ref.state.pitch * 180 / .pi))
                row("Lum", String(format: "%.0f / 255", ref.state.luminance))
            }
            .font(.system(.subheadline, design: .monospaced))
            .foregroundColor(.white)

            if !ref.voiceTranscript.isEmpty {
                Text("“\(ref.voiceTranscript)”")
                    .font(.callout).italic()
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.top, 2)
            }

            Button("Clear & Re-capture") {
                capturedReference = nil
            }
            .font(.headline)
            .foregroundColor(.black)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.yellow)
            .cornerRadius(12)
            .padding(.top, 4)
        }
        .padding(20)
        .background(.black.opacity(0.85))
        .cornerRadius(16)
        .padding(.horizontal, 28)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
        }
    }

    // MARK: - Capture

    private func captureReference() {
        // Snapshot the live state. Orientation comes from MotionManager (in
        // radians); everything else from the camera's latest published values.
        let state = cameraManager.currentFrameState(
            pitch: Float(motionManager.pitchRad),
            roll:  Float(motionManager.rollRad),
            yaw:   Float(motionManager.yawRad)
        )

        // If still recording, stop so the final transcript is captured.
        if voiceRecorder.isRecording { voiceRecorder.toggle() }

        capturedReference = ReferenceFrame(
            state: state,
            cameraMode: selectedMode,
            voiceTranscript: voiceRecorder.transcript,
            capturedAt: Date()
        )

        // Confirmation haptic — same feel as a shutter.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
