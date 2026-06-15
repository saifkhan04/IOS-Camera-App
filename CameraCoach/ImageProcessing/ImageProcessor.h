// ImageProcessor.h
// The Objective-C++ bridge class — the translator between Swift and C++.
//
// Interface constraints (so Swift can read this header directly):
//   1. Objective-C syntax only — no C++ types in the interface; all C++ lives
//      in ImageProcessor.mm.
//   2. Parameters and return values use only Foundation types (NSInteger,
//      NSString, NSData) or CoreVideo types (CVPixelBufferRef).
// Methods are class methods (+) so callers don't instantiate ImageProcessor.

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

// ── Frame analysis result ─────────────────────────────────────────────
// A plain Objective-C value object carrying the C++ results back to Swift.
// It holds only Foundation types so Swift can read it directly — the C++
// structs (LuminanceStats, the histogram array) never cross into Swift.
@interface FrameStats : NSObject

// Mean luma, 0–255. ~128 is a well-exposed mid-tone; near 0 is too dark,
// near 255 is blown out.
@property (nonatomic, readonly) float averageBrightness;

// Standard deviation of luma, ~0–127. Our proxy for contrast.
@property (nonatomic, readonly) float contrast;

// 256 normalised histogram bins as packed Float32 in the range [0, 1],
// where 1.0 is the tallest bin. Packed into NSData rather than an
// NSArray<NSNumber*> on purpose: an array would box 256 floats into 256
// heap objects every single frame (256 × 30fps = 7680 allocations/sec).
// NSData is one contiguous buffer Swift reads with zero per-element boxing.
@property (nonatomic, readonly) NSData *histogram;

@end

// ── Guidance engine bridge types ──────────────────────────────────────
// A plain C struct mirroring the C++ cc::FrameState. Because it's a C struct
// in a header the bridging header imports, Swift sees it directly with a
// memberwise initialiser — no Objective-C wrapper object needed for input.
typedef struct {
    float pitch;
    float roll;
    float yaw;
    float faceX;
    float faceY;
    float depthMeters;
    float luminance;
} CCFrameState;

// Direction for the on-screen arrow. NS_ENUM bridges to Swift as a typed enum.
typedef NS_ENUM(NSInteger, CCArrowDirection) {
    CCArrowDirectionNone = 0,
    CCArrowDirectionUp,
    CCArrowDirectionDown,
    CCArrowDirectionLeft,
    CCArrowDirectionRight
};

// The result object Swift reads. Carries the C++ comparison output across the
// bridge using only Foundation types.
@interface CCGuidanceResult : NSObject
@property (nonatomic, readonly) float matchScore;            // 0..1
@property (nonatomic, readonly) NSString *primaryMessage;
@property (nonatomic, readonly, nullable) NSString *secondaryMessage;
@property (nonatomic, readonly) CCArrowDirection arrowDirection;
@property (nonatomic, readonly) float arrowMagnitude;        // 0..1
@property (nonatomic, readonly) BOOL isAligned;
@end

@interface ImageProcessor : NSObject

// ── Live luminance + histogram ────────────────────────────────────────
// Reads the Y (luma) plane of a YCbCr 4:2:0 pixel buffer and returns
// brightness, contrast, and a normalised histogram. Returns nil if the
// pixel buffer can't be locked or isn't a biplanar YCbCr format.
//
// The CVPixelBuffer comes straight from the camera's video output. This
// method handles all the locking and plane-pointer arithmetic so the C++
// side just receives a clean (pointer, width, height, stride) tuple.
+ (nullable FrameStats *)analyzeFrame:(CVPixelBufferRef)pixelBuffer;

// ── Frame comparison / guidance ───────────────────────────────────────
// Compares the shooter's current frame against the teacher's reference and
// returns the guidance to show. All logic runs in C++ (FrameComparator).
+ (CCGuidanceResult *)compareReference:(CCFrameState)reference
                               current:(CCFrameState)current;

@end

NS_ASSUME_NONNULL_END
