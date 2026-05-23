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
//           Positive = top of phone tilting toward you (camera angling down)
//           Negative = top tilting away (camera angling up toward sky)
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

            let att = motion.attitude

            // Store raw radians for use in ReferenceFrame / comparator
            self.pitchRad = att.pitch
            self.rollRad  = att.roll
            self.yawRad   = att.yaw

            // Convert to degrees for display (× 180 / π)
            // specifier "%+.1f" adds a + sign for positive values,
            // making it easy to see direction at a glance (+12.3° vs -5.6°)
            self.pitch = att.pitch * 180 / .pi
            self.roll  = att.roll  * 180 / .pi
            self.yaw   = att.yaw   * 180 / .pi
        }

        print("✅ MotionManager: Device motion started at 30Hz")
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
