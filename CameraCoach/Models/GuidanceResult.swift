// GuidanceResult.swift
// The output of the comparison: what to tell the shooter right now.
//
// Day 5 fills this in from the C++ FrameComparator. We define it here in Day 4
// so the data model is complete and the Shooter UI (Day 6) has a type to bind
// to. For now it's only constructed by previews/placeholders.

import Foundation

// Which way to nudge the shooter, for the animated arrow overlay.
enum ArrowDirection {
    case up, down, left, right, none
}

struct GuidanceResult {
    // 0.0 = completely off, 1.0 = perfect match. Drives the match ring.
    var matchScore: Float

    // The single most important instruction, e.g. "Step 0.4m closer".
    var primaryMessage: String

    // Optional follow-up once the primary is close, e.g. "Then tilt right".
    var secondaryMessage: String?

    // Direction + intensity for the on-screen arrow animation.
    var arrowDirection: ArrowDirection
    var arrowMagnitude: Float        // 0…1, scales the animation amplitude

    // True when matchScore has crossed the alignment threshold — triggers the
    // green flash, haptic, and "take the shot" state.
    var isAligned: Bool
}
