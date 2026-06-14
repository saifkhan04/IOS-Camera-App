// MotionManager.swift
// Reads the iPhone's 3D orientation using CoreMotion.
//
// The iPhone has a 6-axis IMU (Inertial Measurement Unit):
//   - 3-axis accelerometer: measures linear acceleration (gravity included)
//   - 3-axis gyroscope: measures rotation rate
//
// CMMotionManager fuses these two sensors together using a Kalman filter
// (under the hood — Apple calls it "device motion"). The fusion is necessary
// because:
//   - Gyroscope alone drifts over time (integration error accumulates)
//   - Accelerometer alone is noisy during movement
//   - Combined, they give stable, drift-free orientation at 30–100Hz
//
// The result is a CMAttitude object with three Euler angles:
//
//   PITCH — rotation around the X axis (horizontal axis through the phone)
//           Positive = top of phone tilting toward you (camera angling UP
//                      toward the sky) — VERIFIED on device 2026-06-14
//           Negative = top tilting away (camera angling down toward ground)
//
//   ROLL  — rotation around the Y axis (vertical axis through the phone)
//           Positive = phone tilting to the right
//           Negative = phone tilting to the left
//           (This is what makes the horizon look crooked in a photo)
//
//   YAW   — rotation around the Z axis (axis through the screen)
//           = compass direction the phone faces (spinning on a flat table)
//           We use .xArbitraryZVertical so yaw is relative to app launch,
//           not magnetic north — we only care about delta yaw anyway.

import CoreMotion
import Combine

class MotionManager: ObservableObject {

    // MARK: - Published properties (drive SwiftUI re-renders)

    // Displayed in degrees for the UI overlay.
    @Published var pitch: Double = 0
    @Published var roll:  Double = 0
    @Published var yaw:   Double = 0

    // MARK: - Raw radian values (used by ReferenceFrame and C++ comparator)

    // The C++ FrameComparator works in radians — no conversion needed when
    // building a ReferenceFrame. Radians are the natural unit for trig.
    private(set) var pitchRad: Double = 0
    private(set) var rollRad:  Double = 0
    private(set) var yawRad:   Double = 0

    // MARK: - Private

    private let manager = CMMotionManager()

    // MARK: - Lifecycle

    func start() {
        guard manager.isDeviceMotionAvailable else {
            print("⚠️ MotionManager: Device motion not available")
            return
        }

        // 1/30 second interval = 30Hz updates, matching camera frame rate.
        // There's no benefit to polling faster than the camera for our use case.
        manager.deviceMotionUpdateInterval = 1.0 / 30.0

        // .xArbitraryZVertical is the right reference frame for a camera app:
        //   - "ZVertical" means Z axis stays aligned with gravity regardless
        //     of phone orientation. This keeps pitch/roll stable.
        //   - "xArbitrary" means the X axis (and therefore yaw) is wherever
        //     the phone was pointing when we called startDeviceMotionUpdates.
        //     Yaw = 0 at start, then changes relative to that.
        //   - Alternative is .xMagneticNorthZVertical (true compass heading),
        //     but we only need relative yaw change, not absolute direction.
        manager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main           // deliver on main queue → safe to update @Published
        ) { [weak self] motion, error in
            guard let self, let motion else { return }

            // Use the GRAVITY vector, not CMAttitude's Euler angles.
            //
            // Euler pitch/roll/yaw are coupled and hit a gimbal-lock
            // singularity exactly when the phone is held UPRIGHT for a photo
            // (attitude pitch ≈ 90°). At that singularity roll swings wildly and
            // pitch changes bleed into roll — which made the guidance shout
            // "tilt" constantly and mis-handle aim up/down.
            //
            // Gravity-derived pitch/roll are DECOUPLED and stable in the upright
            // shooting pose. Their only singularity is when the phone lies flat
            // (gravity along z), which we never shoot in. Gravity is a ~unit
            // vector in the device frame: x = right, y = top, z = out of screen.
            let g = motion.gravity

            // roll: rotation about the viewing axis (leveling). Tilt right => +.
            self.rollRad = atan2(g.x, -g.y)
            // pitch: how far the camera aims up/down. Aim up => + .
            // (Gravity's z sign required the +g.z form — verified on device;
            //  the -g.z form read backwards and re-inverted the guidance.)
            self.pitchRad = atan2(g.z, sqrt(g.x * g.x + g.y * g.y))
            // yaw can't come from gravity and the comparator doesn't use it.
            self.yawRad = motion.attitude.yaw

            // Degrees for display. "%+.1f" shows the sign for direction at a glance.
            self.pitch = self.pitchRad * 180 / .pi
            self.roll  = self.rollRad  * 180 / .pi
            self.yaw   = self.yawRad   * 180 / .pi
        }

        print("✅ MotionManager: Device motion started at 30Hz")
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
