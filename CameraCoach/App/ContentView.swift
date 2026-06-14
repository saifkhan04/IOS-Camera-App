// ContentView.swift
// Root view and the Teacher ↔ Shooter switcher.
//
// The camera + motion managers are owned HERE and passed into both modes, so
// the capture session keeps running continuously as we switch between framing
// the reference (Teacher) and chasing it (Shooter) — no session restart, no
// preview flicker. Mode is driven by whether a ReferenceFrame exists yet.

import SwiftUI

struct ContentView: View {

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var motionManager = MotionManager()

    // nil = Teacher Mode (capturing). non-nil = Shooter Mode (guiding to it).
    @State private var reference: ReferenceFrame?

    var body: some View {
        Group {
            if let reference {
                ShooterModeView(
                    reference: reference,
                    cameraManager: cameraManager,
                    motionManager: motionManager,
                    onExit: { withAnimation { self.reference = nil } }
                )
            } else {
                TeacherModeView(
                    cameraManager: cameraManager,
                    motionManager: motionManager,
                    onReferenceCaptured: { ref in withAnimation { reference = ref } }
                )
            }
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
