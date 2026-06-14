// ContentView.swift
// Root view and the Teacher ↔ Shooter switcher.
//
// The camera preview is rendered ONCE here and stays mounted across the whole
// session — only the overlay HUD swaps between Teacher and Shooter. This avoids
// tearing down / rebuilding the AVCaptureVideoPreviewLayer on every mode change,
// which is what caused the long delay + black frame when switching.
//
// The hardware Camera Control button routes through a CaptureRouter: whichever
// mode is active registers its capture action, and the single preview's button
// handler calls router.action() — always the current mode's action.

import SwiftUI

// Lightweight indirection so the persistent preview's Camera Control handler can
// call whichever capture action the active mode registered. It's a reference
// type, so the handler closure captured once always reads the latest `action`.
final class CaptureRouter: ObservableObject {
    var action: () -> Void = {}
}

struct ContentView: View {

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var motionManager = MotionManager()
    @StateObject private var router = CaptureRouter()

    // nil = Teacher Mode (capturing). non-nil = Shooter Mode (guiding to it).
    @State private var reference: ReferenceFrame?
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Persistent camera preview + face box (never torn down).
            CameraPreviewView(
                session: cameraManager.session,
                onCameraControl: { [router] in router.action() }
            )
            .ignoresSafeArea()

            FaceBoxOverlay(normRect: cameraManager.faceNormRect)

            // Swap only the HUD overlay.
            if let reference {
                ShooterModeView(
                    reference: reference,
                    cameraManager: cameraManager,
                    motionManager: motionManager,
                    router: router,
                    onOpenSettings: { showSettings = true },
                    onExit: { self.reference = nil }
                )
            } else {
                TeacherModeView(
                    cameraManager: cameraManager,
                    motionManager: motionManager,
                    router: router,
                    onOpenSettings: { showSettings = true },
                    onReferenceCaptured: { reference = $0 }
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            cameraManager.start()
            motionManager.start()
        }
        .onDisappear {
            motionManager.stop()
        }
    }
}

// MARK: - Shared overlays

// Green face bounding box. Normalised rect is portrait, top-left origin, 0–1;
// scaled to the canvas size. Used by both Teacher and Shooter.
struct FaceBoxOverlay: View {
    let normRect: CGRect?

    var body: some View {
        Canvas { ctx, size in
            guard let rect = normRect else { return }
            let r = CGRect(
                x: rect.origin.x * size.width,
                y: rect.origin.y * size.height,
                width: rect.width  * size.width,
                height: rect.height * size.height
            )
            ctx.stroke(Path(r), with: .color(.green), lineWidth: 2)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - HistogramView

// 256-bin luminance histogram as a filled curve. Bins are normalised to [0,1]
// by the C++ side (1.0 = tallest bin), so we map index → x and value → height.
struct HistogramView: View {
    let bins: [Float]

    var body: some View {
        Canvas { ctx, size in
            guard !bins.isEmpty else { return }
            let barWidth = size.width / CGFloat(bins.count)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for (i, value) in bins.enumerated() {
                let x = CGFloat(i) * barWidth
                let y = size.height - CGFloat(value) * size.height
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            ctx.fill(path, with: .color(.white.opacity(0.8)))
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(4)
    }
}
