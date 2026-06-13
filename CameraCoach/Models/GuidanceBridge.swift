// GuidanceBridge.swift
// Thin adapters between the app's Swift models and the Objective-C++ bridge
// types (CCFrameState / CCGuidanceResult). Keeps the bridge details out of the
// views — they work purely in Swift FrameState / GuidanceResult.

import Foundation

extension FrameState {
    // Swift FrameState → C struct the comparator expects.
    var bridged: CCFrameState {
        CCFrameState(
            pitch: pitch,
            roll: roll,
            yaw: yaw,
            faceX: faceX,
            faceY: faceY,
            depthMeters: depthMeters,
            luminance: luminance
        )
    }
}

extension ArrowDirection {
    // Objective-C enum → Swift enum.
    init(_ d: CCArrowDirection) {
        switch d {
        case .up:    self = .up
        case .down:  self = .down
        case .left:  self = .left
        case .right: self = .right
        default:     self = .none
        }
    }
}

extension GuidanceResult {
    // CCGuidanceResult (bridge) → Swift GuidanceResult (app model).
    init(_ r: CCGuidanceResult) {
        self.init(
            matchScore: r.matchScore,
            primaryMessage: r.primaryMessage,
            secondaryMessage: r.secondaryMessage,   // already nil when empty
            arrowDirection: ArrowDirection(r.arrowDirection),
            arrowMagnitude: r.arrowMagnitude,
            isAligned: r.isAligned
        )
    }
}

// Convenience: compare two Swift FrameStates straight through the C++ engine.
enum Guidance {
    static func compare(reference: FrameState, current: FrameState) -> GuidanceResult {
        GuidanceResult(
            ImageProcessor.compareReference(reference.bridged, current: current.bridged)
        )
    }
}
