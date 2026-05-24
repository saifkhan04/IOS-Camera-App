// ContentView.swift
// Root view. Day 2 adds:
//   - Green bounding box drawn around the detected face
//   - "Subject: X.Xm" distance label from LiDAR
//
// The face rect arrives as normalised coordinates [0,1] in portrait space
// (top-left origin, y-down). Multiplying by the canvas size gives screen
// points. This is an approximation: AVCaptureVideoPreviewLayer uses
// resizeAspectFill, which crops the camera frame's left and right edges to
// fill the portrait screen. The box is therefore slightly inaccurate
// horizontally for off-centre subjects (~10-15% error). Day 3 adds the
// exact transform via AVCaptureVideoPreviewLayer coordinate conversion.

import SwiftUI

struct ContentView: View {

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var motionManager = MotionManager()

    var body: some View {
        ZStack {

            // --- Layer 1: Full-screen camera preview ---
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            // --- Layer 2: Face bounding box ---
            // Canvas is an efficient 2D drawing surface. Its closure receives
            // `ctx` (the drawing context) and `size` (the canvas's own bounds).
            // We fill the screen so canvas size == screen size, then scale
            // the normalised [0,1] rect to screen points.
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

            // --- Layer 3: Data overlay ---
            VStack {
                Spacer()

                VStack(spacing: 6) {

                    // ── Subject distance (LiDAR) ──────────────────────────
                    // Green when reading, dimmed dash when no face or LiDAR
                    // returns NaN (hair, glasses on the face centre pixel).
                    if let dist = cameraManager.subjectDistance {
                        Text("Subject: \(dist, specifier: "%.1f")m")
                            .foregroundColor(.green)
                    } else {
                        Text("Subject: —")
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Divider()
                        .background(Color.white.opacity(0.4))
                        .padding(.vertical, 2)

                    // ── Orientation (CoreMotion) ──────────────────────────
                    Text("Pitch: \(motionManager.pitch, specifier: "%+.1f")°")
                    Text("Roll:  \(motionManager.roll,  specifier: "%+.1f")°")
                    Text("Yaw:   \(motionManager.yaw,   specifier: "%+.1f")°")
                }
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                .padding(12)
                .background(.black.opacity(0.65))
                .cornerRadius(12)
                .padding(.bottom, 50)
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
