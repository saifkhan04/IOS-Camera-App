// ShooterModeView.swift
// Shooter HUD overlay (camera preview + face box live in ContentView). Every
// render we run the C++ FrameComparator (live FrameState vs the reference) and
// draw the guidance. Capture is manual by default (shutter / Camera Control);
// auto-capture (1.5s hold while aligned) is opt-in via Settings.
//
// performCapture() takes a real still via AVCapturePhotoOutput and saves it to
// Photos (see CameraManager.capturePhoto), driving the screen flash on exposure
// and a success/failure toast on completion.

import SwiftUI
import os

struct ShooterModeView: View {

    let reference: ReferenceFrame
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var motionManager: MotionManager
    let router: CaptureRouter
    var onOpenSettings: () -> Void
    var onExit: () -> Void

    @AppStorage(SettingsKeys.autoCapture) private var autoCapture = false
    @AppStorage(SettingsKeys.ghostOverlay) private var ghostOverlay = false

    // Auto-capture + feedback state
    @State private var holdProgress: CGFloat = 0
    @State private var captureWork: DispatchWorkItem?
    @State private var showFlash = false
    @State private var showToast = false
    @State private var toastMessage = "Saved to Photos"
    @State private var toastSuccess = true
    @State private var isCapturing = false
    @State private var showReview = false
    @State private var showTarget = false

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
            // Story 3: ghost overlay sits below the HUD, on top of the live
            // preview. Rendered first so the guidance arrows/text stay on top.
            ghostLayer

            GuidanceOverlayView(
                guidance: guidance,
                holdProgress: holdProgress,
                autoCapturing: autoCapture,
                onCapture: performCapture
            )

            topBar

            galleryButton

            targetButton

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
        .fullScreenCover(isPresented: $showReview) {
            if let data = cameraManager.lastCapturedImageData {
                PhotoReviewView(
                    imageData: data,
                    onOpenInPhotos: openPhotosApp,
                    onClose: { showReview = false }
                )
            }
        }
        .fullScreenCover(isPresented: $showTarget) {
            targetViewer
        }
    }

    // MARK: - Visual reference target (stories 2 & 3)

    // Story 3: the teacher's reference shot, faintly overlaid and matching the
    // preview's aspect-fill so it lines up with the live scene. Gated by Settings.
    @ViewBuilder
    private var ghostLayer: some View {
        if ghostOverlay, let image = reference.image {
            // Color.clear takes exactly the screen's space; the image fills it as
            // an overlay and is clipped to those bounds. Without this, a bare
            // scaledToFill image overflows and widens the whole ZStack, shoving
            // the top-bar/HUD off-screen.
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .ignoresSafeArea()
                .opacity(0.3)
                .allowsHitTesting(false)
        }
    }

    // Story 2: bottom-trailing thumbnail of the target framing (mirrors the
    // bottom-leading "last shot" gallery button). Yellow border + label set it
    // apart from the white-bordered gallery thumbnail. Tap to enlarge.
    @ViewBuilder
    private var targetButton: some View {
        if let image = reference.image {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { showTarget = true }) {
                        VStack(spacing: 3) {
                            Text("Target")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(.yellow.opacity(0.9), lineWidth: 1.5)
                                )
                                .shadow(radius: 3)
                        }
                    }
                    .accessibilityLabel("View target shot")
                }
                .padding(.bottom, 62)   // level with the shutter ring
            }
            .padding(.horizontal, 24)
        }
    }

    // Full-screen look at the target framing the shooter is recreating.
    @ViewBuilder
    private var targetViewer: some View {
        if let image = reference.image {
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
                VStack {
                    HStack {
                        Button(action: { showTarget = false }) {
                            Image(systemName: "xmark")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                    Spacer()
                    Text("Target framing")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 32)
                }
            }
        }
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
                // Clear, labeled exit back to Teacher Mode for a new reference.
                Button(action: onExit) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .shadow(radius: 3)
                }

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3).foregroundColor(.white)
                        .padding(8)
                        .background(.black.opacity(0.55), in: Circle())
                        .shadow(radius: 3)
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

    // MARK: - Gallery button (last shot → in-app review)

    // Bottom-leading thumbnail of the most recent saved shot, mirroring the
    // native Camera app. Tapping it opens a full-screen in-app review of that
    // shot (Photos has no public deep-link to a specific asset). Hidden until the
    // first capture of the session succeeds. Sits level with the shutter ring.
    @ViewBuilder
    private var galleryButton: some View {
        if let thumb = cameraManager.lastCapturedThumbnail {
            VStack {
                Spacer()
                HStack {
                    Button(action: { showReview = true }) {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.white.opacity(0.85), lineWidth: 1.5)
                            )
                            .shadow(radius: 3)
                    }
                    .accessibilityLabel("Review last shot")
                    Spacer()
                }
                .padding(.bottom, 62)   // align with the shutter ring row
            }
            .padding(.horizontal, 24)
            .transition(.scale.combined(with: .opacity))
        }
    }

    // Opens the system Photos app. We only have add-only library access, so we
    // hand off to Photos rather than browsing in-app.
    private func openPhotosApp() {
        if let url = URL(string: "photos-redirect://"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Non-blocking toast

    private var toast: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: toastSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(toastSuccess ? .green : .orange)
                Text(toastMessage).foregroundColor(.white)
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
        // Debounce: ignore re-entrant triggers while a capture is in flight
        // (auto-hold + shutter + Camera Control can all fire near-simultaneously).
        guard !isCapturing else { return }
        isCapturing = true
        captureWork?.cancel()
        captureWork = nil
        withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        cameraManager.capturePhoto(
            onWillCapture: {
                // Flash exactly when the sensor exposes, not on button press.
                withAnimation(.easeOut(duration: 0.08)) { showFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeIn(duration: 0.15)) { showFlash = false }
                }
            },
            completion: { result in
                isCapturing = false
                switch result {
                case .success:
                    flashToast("Saved to Photos", success: true)
                case .failure(let error):
                    Logger.capture.error("Capture failed: \(error.localizedDescription, privacy: .public)")
                    flashToast("Couldn’t save photo", success: false)
                }
            }
        )
    }

    private func flashToast(_ message: String, success: Bool) {
        toastMessage = message
        toastSuccess = success
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { showToast = false }
        }
    }
}
