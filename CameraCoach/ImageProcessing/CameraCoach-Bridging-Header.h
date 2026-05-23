// CameraCoach-Bridging-Header.h
// The Swift-to-Objective-C bridging header.
//
// How the language chain works:
//
//   Swift  ──────────────────────────────────────────────────────────►
//          can call any Objective-C class listed in THIS file
//
//   Objective-C++ (.mm) ──────────────────────────────────────────────►
//          can include both Objective-C AND C++ headers freely
//          (the .mm extension enables C++ compilation in that file)
//
//   C++ (.cpp / .hpp) ───────────────────────────────────────────────►
//          pure C++ — no Objective-C or Swift allowed here
//
// So the full call chain is:
//   Swift → Objective-C++ bridge (.mm) → C++ (.cpp)
//
// This file is the entrance to that chain from Swift's side.
// Every Objective-C (or Objective-C++) class that Swift needs to call
// must be #imported here.
//
// IMPORTANT: This must be a pure Objective-C header. No C++ types
// can appear here because Swift cannot parse C++ syntax directly.
// (Swift 5.9+ has experimental C++ interop, but we use the
//  battle-tested Obj-C++ bridge approach here.)

#import "ImageProcessor.h"
