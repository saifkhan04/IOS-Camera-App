// ShooterModeView.swift
// The shooter chases the teacher's reference. Every frame we run the C++
// FrameComparator (live FrameState vs the reference) and render the guidance
// overlay. When the shooter holds the alignment for 1.5s we auto-capture; the
// Camera Control button and the on-screen shutter also fire capture manually.
//
// Day 6 scope: the full guidance + capture-trigger experience. The actual photo
// (AVCapturePhotoOutput + save to Photos) is wired in Day 7 — performCapture()
// currently flashes and confirms as a placeholder.

import SwiftUI

struct ShooterModeView: View {

    let reference: ReferenceFrame
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var motionManager: MotionManager
    var onExit: () -> Void

    // Auto-capture state
    @State private var holdProgress: CGFloat = 0
    @State private var captureWork: DispatchWorkItem?
    @State private var didCapture = false
    @State private var showFlash = false

    init(reference: ReferenceFrame,
         cameraManager: CameraManager,
         motionManager: MotionManager,
         onExit: @escaping () -> Void) {
        self.reference = reference
        _cameraManager = ObservedObject(wrappedValue: cameraManager)
        _motionManager = ObservedObject(wrappedValue: motionManager)
        self.onExit = onExit
    }

    var body: some View {
        // Compute live guidance for this render (motion publishes ~30Hz).
        let guidance = liveGuidance

        ZStack {
            CameraPreviewView(
                session: cameraManager.session,
                onCameraControl: performCapture
            )
            .ignoresSafeArea()

            FaceBoxOverlay(normRect: cameraManager.faceNormRect)

            GuidanceOverlayView(guidance: guidance, holdProgress: holdProgress)

            topBar
            shutterButton

            if showFlash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }
            if didCapture {
                shotConfirmation
            }
        }
        // React to crossing the alignment threshold.
        .onChange(of: guidance.isAligned) { _, aligned in
            handleAlignmentChange(aligned)
        }
        .onDisappear { captureWork?.cancel() }
    }

    // MARK: - Live guidance

    private var liveGuidance: GuidanceResult {
        let live = cameraManager.currentFrameState(
            pitch: Float(motionManager.pitchRad),
            roll:  Float(motionManager.rollRad),
            yaw:   Float(motionManager.yawRad)
        )
        return Guidance.compare(reference: reference.state, current: live)
    }

    // MARK: - Top bar (exit + reference reminder)

    private var topBar: some View {
        VStack {
            HStack(alignment: .top) {
                Button(action: onExit) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(radius: 3)
                }

                Spacer()

                // The teacher's spoken instructions, as a reminder.
                if !reference.voiceTranscript.isEmpty {
                    Text("“\(reference.voiceTranscript)”")
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .padding(8)
                        .background(.black.opacity(0.5))
                        .cornerRadius(8)
                        .frame(maxWidth: 240)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Manual shutter

    private var shutterButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: performCapture) {
                    ZStack {
                        Circle().fill(.white).frame(width: 64, height: 64)
                        Circle().stroke(.white, lineWidth: 3).frame(width: 76, height: 76)
                    }
                }
                .padding(.trailing, 24)
                .padding(.bottom, 36)
            }
        }
    }

    // MARK: - Shot confirmation (placeholder until Day 7 real capture)

    private var shotConfirmation: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64)).foregroundColor(.green)
            Text("Shot taken!").font(.title2).bold().foregroundColor(.white)
            Text("(photo capture + save lands in Day 7)")
                .font(.caption).foregroundColor(.white.opacity(0.6))

            HStack(spacing: 14) {
                Button("Shoot again") { resetForAnotherShot() }
                    .buttonStyle(.borderedProminent)
                Button("New reference") { onExit() }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        }
        .padding(24)
        .background(.black.opacity(0.85))
        .cornerRadius(16)
        .padding(.horizontal, 36)
    }

    // MARK: - Auto-capture logic

    private func handleAlignmentChange(_ aligned: Bool) {
        guard !didCapture else { return }
        if aligned {
            // Reached alignment — confirm with a haptic and begin the 1.5s hold.
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            withAnimation(.linear(duration: 1.5)) { holdProgress = 1 }
            let work = DispatchWorkItem { performCapture() }
            captureWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        } else {
            // Lost alignment before the hold completed — cancel and reset.
            captureWork?.cancel()
            captureWork = nil
            withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
        }
    }

    private func performCapture() {
        guard !didCapture else { return }
        captureWork?.cancel()
        captureWork = nil
        didCapture = true

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.08)) { showFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.15)) { showFlash = false }
        }
        // TODO Day 7: AVCapturePhotoOutput capture (48MP HEIF / ProRAW) + save to Photos.
    }

    private func resetForAnotherShot() {
        didCapture = false
        holdProgress = 0
    }
}
