// FrameState.swift
// A single instantaneous snapshot of everything the guidance engine cares
// about. The teacher captures one of these as the reference; the shooter's
// live camera produces a fresh one every frame. Day 5's C++ FrameComparator
// takes two FrameStates (reference + current) and computes the deltas.
//
// All numeric fields are Float to line up with the C++ struct we'll bridge
// to in Day 5 — no Double↔float conversion at the boundary.

import Foundation

struct FrameState {
    // Orientation, in RADIANS (CoreMotion's native unit; what trig wants).
    var pitch: Float        // forward/back tilt
    var roll:  Float        // left/right rotation
    var yaw:   Float        // heading relative to app launch

    // Subject position — normalised 0…1 in the frame (top-left origin).
    var faceX: Float        // 0 = left edge, 1 = right edge
    var faceY: Float        // 0 = top edge,  1 = bottom edge

    // Distance from phone to subject, in METRES (LiDAR). 0 = no reading.
    var depthMeters: Float

    // Average scene brightness from the C++ LuminanceAnalyzer, 0…255.
    var luminance: Float

    // Whether a face was actually detected this frame. When false, faceX/faceY
    // and depthMeters are placeholders, not real measurements — the guidance
    // layer uses this to avoid falsely "matching" empty scenes.
    var hasFace: Bool = false
}
