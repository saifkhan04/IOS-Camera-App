// ContentView.swift
// The root view of the app. For Day 1 this does three things:
//   1. Shows the live camera feed full-screen
//   2. Overlays the device orientation (pitch/roll/yaw) in real time
//   3. Shows a C++ bridge test: calls C++ code and displays the result
//
// This proves all three major systems — camera, motion, C++ — are working
// before we build anything more complex on top of them.

import SwiftUI

struct ContentView: View {

    // @StateObject creates these objects once when the view appears
    // and keeps them alive for the view's lifetime. The `private`
    // modifier means only this view can create them — they're not
    // passed in from outside.
    //
    // ObservableObject + @Published (inside each manager) means SwiftUI
    // automatically re-renders this view whenever pitch/roll/yaw change.
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var motionManager = MotionManager()

    var body: some View {
        ZStack {
            // --- Layer 1: Full-screen camera preview ---
            // ZStack layers views back-to-front, so this goes on the bottom.
            // .ignoresSafeArea() lets the camera fill the entire screen
            // including the area behind the notch and home indicator.
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            // --- Layer 2: Orientation + C++ data overlay ---
            // VStack(alignment: .center) stacks items top-to-bottom.
            // We push everything to the bottom with Spacer().
            VStack {
                Spacer()

                VStack(spacing: 6) {

                    // ── Orientation data ──────────────────────────────
                    // These come from CoreMotion via MotionManager.
                    // They update at 30Hz, matching the camera frame rate.
                    Text("Pitch: \(motionManager.pitch, specifier: "%+.1f")°")
                    Text("Roll:  \(motionManager.roll,  specifier: "%+.1f")°")
                    Text("Yaw:   \(motionManager.yaw,   specifier: "%+.1f")°")

                    Divider()
                        .background(Color.white.opacity(0.4))
                        .padding(.vertical, 2)

                    // ── C++ bridge test ───────────────────────────────
                    // ImageProcessor is an Objective-C++ class.
                    // Swift can call it because it's declared in the
                    // bridging header. The actual computation (3 + 4)
                    // happens in a .cpp file via Objective-C++.
                    // Seeing "7" here means: Swift → ObjC++ → C++ works.
                    Text("C++ bridge: 3 + 4 = \(ImageProcessor.add(3, to: 4))")
                        .foregroundColor(.yellow)
                }
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                .padding(12)
                .background(.black.opacity(0.65))
                .cornerRadius(12)
                .padding(.bottom, 50)   // sit above the home indicator
            }
        }
        // onAppear fires once when this view is first drawn on screen.
        // We start the camera and motion systems here rather than in
        // init() so they only run when the view is actually visible.
        .onAppear {
            cameraManager.start()
            motionManager.start()
        }
        .onDisappear {
            motionManager.stop()
        }
    }
}
