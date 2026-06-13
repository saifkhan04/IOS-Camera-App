// LuminanceAnalyzer.hpp
// Derives summary brightness statistics from a luminance histogram.
//
// Why take a histogram instead of the raw pixels?
//   The histogram already counted every pixel. Mean and standard deviation
//   can be computed from those 256 counts alone — no need to touch the
//   millions of original pixels a second time. This is the payoff of the
//   "scan once, summarise many times" design: HistogramEngine does the one
//   expensive pass, and any number of analysers read from its cheap output.

#pragma once
#include "HistogramEngine.hpp"

// A small plain-data struct holding the results. Plain structs like this are
// ideal at C++ boundaries: trivial to copy, no ownership questions.
struct LuminanceStats {
    float averageBrightness = 0.0f;  // mean luma, 0–255 (128 ≈ mid-grey)
    float contrast          = 0.0f;  // std deviation of luma, 0–~127
                                     // low = flat/hazy, high = punchy/contrasty
};

class LuminanceAnalyzer {
public:
    // Computes mean and standard deviation directly from the histogram bins.
    //
    // Mean:     Σ (level × count) / totalPixels
    // Variance: Σ (count × (level − mean)²) / totalPixels
    // StdDev:   √variance   ← we call this "contrast"
    //
    // Standard deviation of brightness is a solid proxy for contrast: it
    // measures how far pixels spread from the average. A foggy, low-contrast
    // scene has all pixels near the mean (small spread); a scene with deep
    // shadows and bright highlights has a large spread.
    static LuminanceStats fromHistogram(const HistogramEngine::Histogram& hist);
};
