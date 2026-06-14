// TeacherModeView.swift
// The teacher's screen: frame the shot, speak the instructions, and lock it
// all in with one press of the Camera Control button (or the on-screen
// button). The captured ReferenceFrame is what the shooter will chase.
//
// Day 5 addition: once a reference is captured, this screen flips into a LIVE
// GUIDANCE PREVIEW — it runs the C++ FrameComparator every frame against the
// saved reference and shows the resulting message + match score. This is a
// stand-in to prove the guidance engine works end-to-end on device; Day 6
// builds the real Shooter Mode UI (arrows, match ring, haptics, auto-capture).

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
                // Before a reference exists: capture controls.
                // After: live guidance preview against that reference.
                if capturedReference == nil {
                    captureControls
                } else {
                    guidancePanel
                }
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            cameraManager.start()
            motionManager.start()
            voiceRecorder.requestPermissions()
            #if DEBUG
            runGuidanceSelfTest()
            #endif
        }
        .onDisappear {
            motionManager.stop()
        }
    }

    // MARK: - Live guidance (Day 5)

    // Recomputed on every re-render (motion publishes at 30Hz), so the banner
    // updates live as the phone moves. nil until a reference is captured.
    private var liveGuidance: GuidanceResult? {
        guard let ref = capturedReference else { return nil }
        let live = cameraManager.currentFrameState(
            pitch: Float(motionManager.pitchRad),
            roll:  Float(motionManager.rollRad),
            yaw:   Float(motionManager.yawRad)
        )
        return Guidance.compare(reference: ref.state, current: live)
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
            .disabled(capturedReference != nil)   // mode is locked once captured

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

            #if DEBUG
            debugOrientation
            #endif
        }
        .padding(.top, 8)
    }

    #if DEBUG
    // Temporary direction-verification readout. Aim the camera up at the
    // ceiling and watch whether `pitch` goes + or −; aim down and confirm it
    // flips. Same for roll (tilt left/right). Once a reference is captured the
    // Δ lines show current-minus-reference, so you can see exactly which sign
    // the comparator is acting on. Remove once directions are confirmed.
    private var debugOrientation: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(String(format: "pitch %+.1f°   roll %+.1f°   yaw %+.1f°",
                        motionManager.pitch, motionManager.roll, motionManager.yaw))
            if let ref = capturedReference {
                let dPitch = motionManager.pitch - Double(ref.state.pitch) * 180 / .pi
                let dRoll  = motionManager.roll  - Double(ref.state.roll)  * 180 / .pi
                Text(String(format: "Δpitch %+.1f°   Δroll %+.1f°", dPitch, dRoll))
                    .foregroundColor(.cyan)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.yellow)
        .padding(6)
        .background(.black.opacity(0.6))
        .cornerRadius(8)
    }
    #endif

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).foregroundColor(.white.opacity(0.6))
            Text(value)
        }
    }

    // MARK: - Capture controls (no reference yet)

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

    // MARK: - Live guidance preview (reference captured)

    private var guidancePanel: some View {
        VStack(spacing: 10) {
            if let g = liveGuidance {
                // One clear action at a time. The engine works in a fixed
                // priority order, so as you resolve each step the next appears
                // — leading you in sequence to the shot.
                Text(g.primaryMessage)
                    .font(.title).bold()
                    .foregroundColor(g.isAligned ? .green : .white)
                    .multilineTextAlignment(.center)

                // The next step, shown faintly so you can see the path ahead
                // without it competing with the current action.
                if !g.isAligned, let secondary = g.secondaryMessage {
                    Text("then \(secondary.lowercasedFirstLetter)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                }

                ProgressView(value: Double(max(0, min(1, g.matchScore))))
                    .tint(g.isAligned ? .green : .yellow)

                Text("Match \(Int((g.matchScore * 100).rounded()))%")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            if let ref = capturedReference {
                Text("Reference: \(ref.cameraMode.rawValue) · \(String(format: "%.2fm", ref.state.depthMeters))"
                     + (ref.voiceTranscript.isEmpty ? "" : " · “\(ref.voiceTranscript)”"))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            Button("Clear Reference") {
                capturedReference = nil
            }
            .font(.headline)
            .foregroundColor(.black)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.yellow)
            .cornerRadius(12)
        }
        .padding(16)
        .background(.black.opacity(0.7))
        .cornerRadius(16)
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

        capturedReference = ReferenceFrame(
            state: state,
            cameraMode: selectedMode,
            voiceTranscript: voiceRecorder.transcript,
            capturedAt: Date()
        )

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Debug self-test (Day 5)

    #if DEBUG
    // Runs a few hardcoded reference-vs-current scenarios through the C++
    // engine and prints the results — deterministic verification that the
    // comparator logic and the full Swift→ObjC++→C++ bridge are correct.
    private func runGuidanceSelfTest() {
        let ref = FrameState(pitch: 0, roll: 0, yaw: 0,
                             faceX: 0.5, faceY: 0.5, depthMeters: 1.0, luminance: 128)
        func show(_ name: String, _ cur: FrameState) {
            let g = Guidance.compare(reference: ref, current: cur)
            print(String(format: "🧪 [%@] score=%.2f aligned=%@ primary='%@' secondary='%@'",
                         name, g.matchScore, g.isAligned ? "Y" : "N",
                         g.primaryMessage, g.secondaryMessage ?? ""))
        }
        show("perfect",   ref)
        show("too far",   FrameState(pitch: 0, roll: 0, yaw: 0, faceX: 0.5, faceY: 0.5, depthMeters: 1.5, luminance: 128))
        show("too close", FrameState(pitch: 0, roll: 0, yaw: 0, faceX: 0.5, faceY: 0.5, depthMeters: 0.6, luminance: 128))
        show("dark+left", FrameState(pitch: 0, roll: 0, yaw: 0, faceX: 0.35, faceY: 0.5, depthMeters: 1.0, luminance: 90))
        show("tilted",    FrameState(pitch: 0, roll: 0.2, yaw: 0, faceX: 0.5, faceY: 0.5, depthMeters: 1.0, luminance: 128))
    }
    #endif
}

private extension String {
    // "Move camera left" -> "move camera left", for the "then …" hint.
    var lowercasedFirstLetter: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
