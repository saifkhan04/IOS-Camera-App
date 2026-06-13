// HistogramEngine.cpp
// Implementation of the single full-frame pixel scan.

#include "HistogramEngine.hpp"

HistogramEngine::Histogram HistogramEngine::compute(const uint8_t* yPlane,
                                                    int width,
                                                    int height,
                                                    int bytesPerRow,
                                                    int stride) {
    // Zero-initialise all 256 bins. The {} value-initialises every element
    // to 0 — without it the array would hold garbage and counts would be wrong.
    Histogram hist{};

    if (yPlane == nullptr || width <= 0 || height <= 0 || stride <= 0) {
        return hist;
    }

    // Walk the image row by row, column by column.
    //
    // Row addressing is the crucial part:
    //   row start = yPlane + y * bytesPerRow
    // We multiply by bytesPerRow (the padded stride), NOT width. If we used
    // width and the buffer had row padding, every row after the first would
    // start a few bytes early, shearing the image diagonally.
    for (int y = 0; y < height; y += stride) {
        const uint8_t* row = yPlane + static_cast<size_t>(y) * bytesPerRow;
        for (int x = 0; x < width; x += stride) {
            // row[x] is the luma value 0–255 at this pixel — that value is
            // itself the bin index. Each brightness level maps directly to
            // one of the 256 bins, so we just increment that slot.
            ++hist[row[x]];
        }
    }

    return hist;
}
