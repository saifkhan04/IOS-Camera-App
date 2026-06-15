// ImageProcessor.mm
// Objective-C++ implementation — the only file in the project where
// both Objective-C and C++ coexist. The .mm extension tells the
// compiler to treat this as Objective-C++.
//
// What Objective-C++ means in practice:
//   - You can write Objective-C class implementations (@implementation)
//   - You can #include C++ headers and call C++ functions freely
//   - You can even mix Objective-C objects and C++ objects in the same scope
//   - The resulting object code links cleanly with both Swift and C++
//
// This file is intentionally thin — it just translates types and
// forwards calls. Heavy logic lives in the C++ files (HistogramEngine.cpp,
// LuminanceAnalyzer.cpp) keeping them testable in isolation.

#import "ImageProcessor.h"
#include "HistogramEngine.hpp"
#include "LuminanceAnalyzer.hpp"
#include "FrameComparator.hpp"

// ── FrameStats ────────────────────────────────────────────────────────
// The @property declarations in the header are readonly. We redeclare them
// here in a class extension as readwrite so this file (and only this file)
// can set them. Callers still see them as readonly.
@interface FrameStats ()
@property (nonatomic, readwrite) float averageBrightness;
@property (nonatomic, readwrite) float contrast;
@property (nonatomic, readwrite) NSData *histogram;
@end

@implementation FrameStats
@end

// ── CCGuidanceResult ──────────────────────────────────────────────────
@interface CCGuidanceResult ()
@property (nonatomic, readwrite) float matchScore;
@property (nonatomic, readwrite) NSString *primaryMessage;
@property (nonatomic, readwrite, nullable) NSString *secondaryMessage;
@property (nonatomic, readwrite) CCArrowDirection arrowDirection;
@property (nonatomic, readwrite) float arrowMagnitude;
@property (nonatomic, readwrite) BOOL isAligned;
@end

@implementation CCGuidanceResult
@end

@implementation ImageProcessor

// ── Live luminance + histogram ────────────────────────────────────────
+ (nullable FrameStats *)analyzeFrame:(CVPixelBufferRef)pixelBuffer {
    if (pixelBuffer == nullptr) { return nil; }

    // Lock the buffer's memory before reading it. The camera writes frames
    // on its own schedule; locking guarantees the bytes don't change or get
    // recycled under us mid-read. kCVPixelBufferLock_ReadOnly tells CoreVideo
    // we won't modify the data, which lets it skip a cache flush on unlock.
    CVReturn lockResult =
        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    if (lockResult != kCVReturnSuccess) { return nil; }

    // We must always unlock, on every return path. A C++ scope guard or
    // Obj-C @try/@finally would work; here a simple goto-free structure with
    // an explicit unlock before each return keeps it readable.

    // Plane 0 of a 4:2:0 biplanar buffer is the full-resolution Y (luma)
    // plane — exactly the brightness map we want. Plane 1 is the half-res
    // interleaved CbCr (colour), which we ignore for luminance work.
    const int planeIndex = 0;

    // Verify this really is a planar buffer. If a non-planar format ever
    // sneaks in, GetBaseAddressOfPlane returns null and we bail safely.
    if (!CVPixelBufferIsPlanar(pixelBuffer) ||
        CVPixelBufferGetPlaneCount(pixelBuffer) < 1) {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        return nil;
    }

    const uint8_t* yPlane = static_cast<const uint8_t*>(
        CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIndex));
    const int width  = static_cast<int>(CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex));
    const int height = static_cast<int>(CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex));
    const int bytesPerRow = static_cast<int>(CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, planeIndex));

    if (yPlane == nullptr) {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        return nil;
    }

    // --- The actual C++ work ---
    HistogramEngine::Histogram hist =
        HistogramEngine::compute(yPlane, width, height, bytesPerRow);
    LuminanceStats stats = LuminanceAnalyzer::fromHistogram(hist);

    // We've copied everything we need out of the pixel buffer; unlock now.
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    // --- Normalise the histogram for display ---
    // Find the tallest bin and scale every bin to [0, 1] against it, so the
    // chart always fills its vertical space regardless of frame resolution.
    uint32_t maxBin = 1;   // start at 1 to avoid divide-by-zero on a blank frame
    for (uint32_t c : hist) { if (c > maxBin) maxBin = c; }

    float normalised[256];
    for (int i = 0; i < 256; ++i) {
        normalised[i] = static_cast<float>(hist[i]) / static_cast<float>(maxBin);
    }

    // Package results. NSData copies the 256 floats into its own buffer, so
    // the stack array going out of scope here is fine.
    FrameStats* result = [[FrameStats alloc] init];
    result.averageBrightness = stats.averageBrightness;
    result.contrast          = stats.contrast;
    result.histogram         = [NSData dataWithBytes:normalised
                                              length:sizeof(normalised)];
    return result;
}

// ── Frame comparison / guidance ───────────────────────────────────────
+ (CCGuidanceResult *)compareReference:(CCFrameState)reference
                               current:(CCFrameState)current {
    // Translate the C structs into C++ structs (field-for-field, same layout).
    cc::FrameState ref;
    ref.pitch = reference.pitch; ref.roll = reference.roll; ref.yaw = reference.yaw;
    ref.faceX = reference.faceX; ref.faceY = reference.faceY;
    ref.depthMeters = reference.depthMeters; ref.luminance = reference.luminance;

    cc::FrameState cur;
    cur.pitch = current.pitch; cur.roll = current.roll; cur.yaw = current.yaw;
    cur.faceX = current.faceX; cur.faceY = current.faceY;
    cur.depthMeters = current.depthMeters; cur.luminance = current.luminance;

    cc::GuidanceResult g = cc::FrameComparator::compare(ref, cur);

    // Map the C++ arrow enum to the bridged Objective-C enum.
    CCArrowDirection arrow = CCArrowDirectionNone;
    switch (g.arrowDirection) {
        case cc::ArrowDir::Up:    arrow = CCArrowDirectionUp;    break;
        case cc::ArrowDir::Down:  arrow = CCArrowDirectionDown;  break;
        case cc::ArrowDir::Left:  arrow = CCArrowDirectionLeft;  break;
        case cc::ArrowDir::Right: arrow = CCArrowDirectionRight; break;
        case cc::ArrowDir::None:  arrow = CCArrowDirectionNone;  break;
    }

    CCGuidanceResult* out = [[CCGuidanceResult alloc] init];
    out.matchScore       = g.matchScore;
    // std::string -> NSString (UTF-8). Empty secondary becomes nil.
    out.primaryMessage   = [NSString stringWithUTF8String:g.primaryMessage.c_str()];
    out.secondaryMessage = g.secondaryMessage.empty()
        ? nil
        : [NSString stringWithUTF8String:g.secondaryMessage.c_str()];
    out.arrowDirection   = arrow;
    out.arrowMagnitude   = g.arrowMagnitude;
    out.isAligned        = g.isAligned;
    return out;
}

@end
