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
// forwards calls. Heavy logic lives in the C++ files (MathBridge.cpp,
// and later LuminanceAnalyzer.cpp, HistogramEngine.cpp, etc.)
// keeping them testable in isolation without Objective-C overhead.

#import "ImageProcessor.h"
#include "MathBridge.hpp"       // our C++ code — note #include not #import

@implementation ImageProcessor

// ── Day 1: Bridge verification ────────────────────────────────────────
+ (NSInteger)add:(NSInteger)a to:(NSInteger)b {
    // Type translation:
    //   NSInteger (Objective-C) → int (C++)
    //   int result (C++) → NSInteger (Objective-C) → Int (Swift)
    //
    // static_cast<int> is the C++ way to cast types explicitly.
    // It's safer than C-style casts because it's checked at compile time.
    return static_cast<NSInteger>(
        MathBridge::add(static_cast<int>(a), static_cast<int>(b))
    );
}

@end
