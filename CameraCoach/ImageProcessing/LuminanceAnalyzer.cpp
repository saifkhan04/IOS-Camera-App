// LuminanceAnalyzer.cpp
// Two cheap passes over the 256-bin histogram — not the pixels.

#include "LuminanceAnalyzer.hpp"
#include <cmath>    // std::sqrt

LuminanceStats LuminanceAnalyzer::fromHistogram(const HistogramEngine::Histogram& hist) {
    LuminanceStats stats;

    // --- Total pixel count and weighted sum (for the mean) ---
    // We use uint64_t for the accumulators because the products can grow
    // large: a 1920×1440 frame has ~2.7M pixels, and level×count can reach
    // 255 × 2.7M ≈ 700M — still within 32 bits, but 64 bits is safe and free.
    uint64_t totalPixels = 0;
    uint64_t weightedSum = 0;

    for (int level = 0; level < 256; ++level) {
        const uint32_t count = hist[level];
        totalPixels += count;
        weightedSum += static_cast<uint64_t>(level) * count;
    }

    // Guard against an empty histogram (e.g. a null frame) — dividing by
    // zero would produce NaN and poison everything downstream.
    if (totalPixels == 0) {
        return stats;   // all-zero defaults
    }

    const double mean = static_cast<double>(weightedSum) / totalPixels;

    // --- Second pass: variance around the mean ---
    // Variance = average of squared distances from the mean. We weight each
    // squared distance by how many pixels sit at that brightness level.
    double varianceSum = 0.0;
    for (int level = 0; level < 256; ++level) {
        const double diff = static_cast<double>(level) - mean;
        varianceSum += static_cast<double>(hist[level]) * diff * diff;
    }
    const double variance = varianceSum / totalPixels;

    stats.averageBrightness = static_cast<float>(mean);
    stats.contrast          = static_cast<float>(std::sqrt(variance));
    return stats;
}
