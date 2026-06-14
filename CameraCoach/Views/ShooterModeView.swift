// ShooterModeView.swift
// Shooter HUD overlay (camera preview + face box live in ContentView). Every
// render we run the C++ FrameComparator (live FrameState vs the reference) and
// draw the guidance. Capture is manual by default (shutter / Camera Control);
// auto-capture (1.5s hold while aligned) is opt-in via Settings.
//
// Day 6 scope: full guidance + capture trigger. Real photo capture
// (AVCapturePhotoOutput + save to Photos) is Day 7 — performCapture() flashes
// and shows a brief toast as a placeholder.

import SwiftUI

struct ShooterModeView: View {

    let reference: ReferenceFrame
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var motionManager: MotionManager
    let router: CaptureRouter
    var onOpenSettings: () -> Void
    var onExit: () -> Void

    @AppStorage(SettingsKeys.autoCapture) private var autoCapture = false

    // Auto-capture + feedback state
    @State private var holdProgress: CGFloat = 0
    @State private var captureWork: DispatchWorkItem?
    @State private var showFlash = false
    @State private var showToast = false

    init(reference: ReferenceFrame,
         cameraManager: CameraManager,
         motionManager: MotionManager,
         router: CaptureRouter,
         onOpenSettings: @escaping () -> Void,
         onExit: @escaping () -> Void) {
        self.reference = reference
        _cameraManager = ObservedObject(wrappedValue: cameraManager)
        _motionManager = ObservedObject(wrappedValue: motionManager)
        self.router = router
        self.onOpenSettings = onOpenSettings
        self.onExit = onExit
    }

    var body: some View {
        let guidance = liveGuidance

        ZStack {
            GuidanceOverlayView(
                guidance: guidance,
                holdProgress: holdProgress,
                autoCapturing: autoCapture
            )

            topBar
            shutterButton

            if showToast { toast }

            if showFlash {
                Color.white.ignoresSafeArea().transition(.opacity).allowsHitTesting(false)
            }
        }
        .onAppear { router.action = performCapture }
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

    // MARK: - Top bar (exit + settings + reference reminder)

    private var topBar: some View {
        VStack {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onExit) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundColor(.white.opacity(0.85)).shadow(radius: 3)
                }
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3).foregroundColor(.white.opacity(0.85)).shadow(radius: 3)
                }

                Spacer()

                if !reference.voiceTranscript.isEmpty {
                    Text("“\(reference.voiceTranscript)”")
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .padding(8)
                        .background(.black.opacity(0.5))
                        .cornerRadius(8)
                        .frame(maxWidth: 220)
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

    // MARK: - Non-blocking toast

    private var toast: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("Shot taken").foregroundColor(.white)
            }
            .font(.subheadline.bold())
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.75))
            .cornerRadius(20)
            .padding(.top, 70)
            .transition(.move(edge: .top).combined(with: .opacity))
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - Auto-capture logic

    private func handleAlignmentChange(_ aligned: Bool) {
        if aligned {
            // Reached alignment — confirm with a haptic.
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            // Only auto-fire if the user opted in.
            guard autoCapture else { return }
            withAnimation(.linear(duration: 1.5)) { holdProgress = 1 }
            let work = DispatchWorkItem { performCapture() }
            captureWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        } else {
            captureWork?.cancel()
            captureWork = nil
            withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
        }
    }

    private func performCapture() {
        // Debounce: ignore if a capture just happened (flash still showing).
        guard !showFlash else { return }
        captureWork?.cancel()
        captureWork = nil
        withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.08)) { showFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.15)) { showFlash = false }
        }

        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { showToast = false }
        }
        // TODO Day 7: AVCapturePhotoOutput capture (48MP HEIF / ProRAW) + save to Photos.
    }
}
