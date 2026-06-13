// FrameComparator.hpp
// The guidance brain. Given the teacher's reference frame and the shooter's
// current frame, it computes how far off each axis is and turns the biggest
// problems into plain-English, metric instructions.
//
// Design philosophy:
//   - Every axis has a THRESHOLD: differences smaller than this are "good
//     enough" and we stay silent rather than nag (LiDAR is precise to ~1cm,
//     but nobody wants to chase a 2cm difference). Thresholds are a design
//     choice, not a hardware limit — tune them on device.
//   - Problems are PRIORITISED. We only show the one or two that matter most,
//     because a wall of corrections is useless. Lighting first (if the light
//     is wrong, nothing else matters), then distance, then framing, then tilt.
//   - The MATCH SCORE blends all axes into a single 0–1 number for the ring.
//
// Pure C++ — no Objective-C, no Swift. Unit-testable in isolation.

#pragma once
#include <string>

namespace cc {

// Mirrors the Swift FrameState. All Float so the bridge needs no conversion.
struct FrameState {
    float pitch = 0, roll = 0, yaw = 0;   // radians
    float faceX = 0.5f, faceY = 0.5f;     // 0..1, top-left origin
    float depthMeters = 0;                // metres (LiDAR)
    float luminance = 0;                  // 0..255
};

enum class ArrowDir { None, Up, Down, Left, Right };

struct GuidanceResult {
    float matchScore = 0;                 // 0 (off) .. 1 (perfect)
    std::string primaryMessage;           // the single most important nudge
    std::string secondaryMessage;         // next one, or "" if none
    ArrowDir arrowDirection = ArrowDir::None;
    float arrowMagnitude = 0;             // 0..1, scales the arrow animation
    bool isAligned = false;               // all axes within threshold
};

class FrameComparator {
public:
    static GuidanceResult compare(const FrameState& reference,
                                  const FrameState& current);

    // Thresholds — the line between "fix this" and "good enough".
    // All tunable; these are sensible starting points.
    static constexpr float POSITION_THRESHOLD  = 0.05f;  // 5% of frame
    static constexpr float DEPTH_THRESHOLD_M   = 0.05f;  // 5 cm
    static constexpr float TILT_THRESHOLD_RAD  = 0.08f;  // ~4.6 degrees
    static constexpr float LUMINANCE_THRESHOLD = 25.0f;  // out of 255
};

} // namespace cc
