// HistogramEngine.hpp
// Computes a 256-bin luminance histogram from the Y (luma) plane of a
// YCbCr 4:2:0 frame.
//
// What a luminance histogram is:
//   The Y plane is one byte per pixel, each value 0–255 = how bright that
//   pixel is (0 = black, 255 = white). A histogram counts how many pixels
//   fall into each brightness level. Bin[0] = number of pure-black pixels,
//   bin[255] = number of pure-white pixels.
//
// Why it matters for a camera app:
//   - A histogram bunched against the left = underexposed (too dark)
//   - Bunched against the right = overexposed (blown highlights)
//   - Spread evenly = good tonal range
//   This is the same histogram pro cameras overlay on the viewfinder.
//
// This is the ONLY class that iterates the full pixel buffer. Everything
// else (mean, contrast) is derived from the 256-bin result — far cheaper
// than re-scanning millions of pixels.

#pragma once
#include <cstdint>
#include <array>

class HistogramEngine {
public:
    // A fixed 256-element array of unsigned counts. std::array (C++11) is a
    // stack-allocated fixed-size array with bounds you can query — safer than
    // a raw C array and with zero runtime overhead vs one.
    using Histogram = std::array<uint32_t, 256>;

    // Scans the Y plane and returns brightness-level counts.
    //
    // Parameters:
    //   yPlane      — pointer to the first byte of the luma plane
    //   width       — frame width in pixels
    //   height      — frame height in pixels
    //   bytesPerRow — bytes from the start of one row to the next. This is
    //                 often LARGER than width because the hardware pads each
    //                 row to a memory-alignment boundary (e.g. width 1920 but
    //                 bytesPerRow 1920 or 2048). Using width instead of this
    //                 stride is the classic bug that produces a skewed image.
    //   stride      — sample every Nth pixel/row. stride=2 reads 1/4 of the
    //                 pixels for ~4x speed with a histogram that's visually
    //                 identical. Defaults to 2 for live 30fps use.
    static Histogram compute(const uint8_t* yPlane,
                             int width,
                             int height,
                             int bytesPerRow,
                             int stride = 2);
};
