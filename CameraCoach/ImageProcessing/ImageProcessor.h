// ImageProcessor.h
// The Objective-C++ bridge class — the translator between Swift and C++.
//
// Design rules for this header:
//   1. Pure Objective-C syntax only — no C++ types in the interface.
//      (Swift reads this header and Swift doesn't understand C++ types.)
//   2. All C++ lives in ImageProcessor.mm (the implementation), not here.
//   3. Method signatures use only Foundation types (NSInteger, NSString,
//      NSData, etc.) or CoreVideo types (CVPixelBufferRef) as parameters
//      and return values.
//
// Why @interface / @implementation (Objective-C style)?
// Because this is what makes the class visible to Swift via the bridging
// header. A pure C++ class would be invisible to Swift.
//
// The + prefix on methods means "class method" (static in Swift/C++ terms).
// We use class methods so callers don't need to instantiate ImageProcessor.

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

@interface ImageProcessor : NSObject

// ── Day 1: Bridge verification ────────────────────────────────────────
// Adds two integers using C++ and returns the result.
// This proves the full Swift → Obj-C++ → C++ chain is wired and
// compiling. When we see "3 + 4 = 7" on screen, we know:
//   - The bridging header is set correctly
//   - The .mm file compiles as Objective-C++
//   - The C++ source file is included in the build target
//   - The linker found all the symbols
// Once this works, we never need to second-guess the bridge again.
+ (NSInteger)add:(NSInteger)a to:(NSInteger)b;

@end

NS_ASSUME_NONNULL_END
