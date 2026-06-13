// FrameComparator.cpp
// The comparison logic. Read top-to-bottom it's: compute deltas → build a
// prioritised list of problems → pick the top one or two for messages →
// blend everything into a match score.

#include "FrameComparator.hpp"
#include <vector>
#include <algorithm>
#include <cmath>
#include <cstdio>

namespace cc {
namespace {

// Clamp a value into [0, 1].
inline float clamp01(float v) {
    return v < 0 ? 0 : (v > 1 ? 1 : v);
}

// Normalise an absolute error against a "this much is totally wrong" scale.
inline float norm(float absError, float scale) {
    return clamp01(absError / scale);
}

// Format metres to one decimal, e.g. 0.43 -> "0.4m".
std::string meters(float m) {
    float rounded = std::round(m * 10.0f) / 10.0f;
    char buf[16];
    std::snprintf(buf, sizeof(buf), "%.1fm", rounded);
    return std::string(buf);
}

// One candidate instruction. Lower `priority` = more important.
struct Problem {
    int priority;
    std::string message;
    ArrowDir arrow;
    float magnitude;   // 0..1
};

} // anonymous namespace

GuidanceResult FrameComparator::compare(const FrameState& ref, const FrameState& cur) {
    // --- Signed deltas (current minus reference) ---
    const float dDepth = cur.depthMeters - ref.depthMeters; // + => shooter too far
    const float dLum   = cur.luminance   - ref.luminance;   // + => too bright
    const float dFaceY = cur.faceY       - ref.faceY;        // + => subject lower in frame
    const float dFaceX = cur.faceX       - ref.faceX;        // + => subject to the right
    const float dRoll  = cur.roll        - ref.roll;
    const float dPitch = cur.pitch       - ref.pitch;

    std::vector<Problem> problems;

    // Priority 1 — Lighting. If the light is wrong, everything else is wrong.
    if (std::fabs(dLum) > LUMINANCE_THRESHOLD) {
        if (dLum < 0)
            problems.push_back({1, "Find brighter light", ArrowDir::None, norm(std::fabs(dLum), 100.0f)});
        else
            problems.push_back({1, "Move to softer light", ArrowDir::None, norm(std::fabs(dLum), 100.0f)});
    }

    // Priority 2 — Distance. Biggest effect on subject size and bokeh.
    if (std::fabs(dDepth) > DEPTH_THRESHOLD_M) {
        std::string msg;
        if (dDepth > 0.3f)        msg = "Step " + meters(dDepth) + " closer";
        else if (dDepth < -0.3f)  msg = "Back up " + meters(-dDepth);
        else                      msg = (dDepth > 0) ? "Just a tiny step closer"
                                                     : "Just a tiny step back";
        problems.push_back({2, msg, ArrowDir::None, norm(std::fabs(dDepth), 1.0f)});
    }

    // Priority 3 — Vertical framing (faceY). Subject too high => lower camera.
    if (std::fabs(dFaceY) > POSITION_THRESHOLD) {
        if (dFaceY < 0)  // current face is higher in frame than reference
            problems.push_back({3, "Lower the camera", ArrowDir::Down, norm(std::fabs(dFaceY), 0.3f)});
        else
            problems.push_back({3, "Raise the camera", ArrowDir::Up, norm(std::fabs(dFaceY), 0.3f)});
    }

    // Priority 4 — Horizontal framing (faceX). Subject to the right => pan left.
    if (std::fabs(dFaceX) > POSITION_THRESHOLD) {
        if (dFaceX > 0)
            problems.push_back({4, "Move camera left", ArrowDir::Left, norm(std::fabs(dFaceX), 0.3f)});
        else
            problems.push_back({4, "Move camera right", ArrowDir::Right, norm(std::fabs(dFaceX), 0.3f)});
    }

    // Priority 5 — Roll (left/right tilt — the crooked-horizon axis).
    if (std::fabs(dRoll) > TILT_THRESHOLD_RAD) {
        if (dRoll > 0)
            problems.push_back({5, "Tilt camera left", ArrowDir::None, norm(std::fabs(dRoll), 0.5f)});
        else
            problems.push_back({5, "Tilt camera right", ArrowDir::None, norm(std::fabs(dRoll), 0.5f)});
    }

    // Priority 6 — Pitch (forward/back angle).
    if (std::fabs(dPitch) > TILT_THRESHOLD_RAD) {
        if (dPitch > 0)  // angled down more than reference
            problems.push_back({6, "Angle camera up", ArrowDir::None, norm(std::fabs(dPitch), 0.5f)});
        else
            problems.push_back({6, "Angle camera down", ArrowDir::None, norm(std::fabs(dPitch), 0.5f)});
    }

    // --- Match score: weighted blend of per-axis normalised error ---
    // Each axis error is normalised against a "fully wrong" scale, then
    // weighted by how much that axis matters. Depth dominates; tilt least.
    const float eDepth = norm(std::fabs(dDepth), 1.0f);
    const float eLum   = norm(std::fabs(dLum),   100.0f);
    const float eFaceY = norm(std::fabs(dFaceY), 0.3f);
    const float eFaceX = norm(std::fabs(dFaceX), 0.3f);
    const float eRoll  = norm(std::fabs(dRoll),  0.5f);
    const float ePitch = norm(std::fabs(dPitch), 0.5f);

    const float weightedError =
        0.30f * eDepth +
        0.20f * eLum   +
        0.15f * eFaceY +
        0.15f * eFaceX +
        0.10f * eRoll  +
        0.10f * ePitch;

    GuidanceResult result;
    result.matchScore = clamp01(1.0f - weightedError);

    if (problems.empty()) {
        // Every axis within threshold — the shooter has nailed it.
        result.primaryMessage   = "You're there — shoot!";
        result.secondaryMessage = "";
        result.arrowDirection   = ArrowDir::None;
        result.arrowMagnitude   = 0.0f;
        result.isAligned        = true;
        return result;
    }

    // Most important problem first.
    std::sort(problems.begin(), problems.end(),
              [](const Problem& a, const Problem& b) { return a.priority < b.priority; });

    result.primaryMessage   = problems[0].message;
    result.arrowDirection   = problems[0].arrow;
    result.arrowMagnitude   = problems[0].magnitude;
    result.secondaryMessage = problems.size() > 1 ? problems[1].message : "";
    result.isAligned        = false;
    return result;
}

} // namespace cc
