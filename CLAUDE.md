# CameraCoach — Project Context

## Instructions for Claude

- Read this file at the start of every session before doing anything else.
- At the end of every session (or when the user says "we're done for today"),
  update this file to reflect: what was completed, any new decisions made,
  any problems encountered and how they were resolved, and what's next.
- Keep the "Current Progress" section accurate at all times — it is the
  single source of truth for where the project stands.
- Never ask the user to update this file themselves. That's Claude's job.

---

Read this at the start of every session. It captures decisions made and
reasoning from earlier conversations so context is never lost.

## What This App Does

Two-role camera guidance app for iPhone 17 Pro:

- **Teacher mode**: records voice instructions + physically frames the shot,
  presses Camera Control button to lock a reference frame
- **Shooter mode**: real-time overlay guides them to replicate that exact
  frame — "Step 0.4m closer", "Tilt right a little", "You're there — shoot!"

The core loop: capture reference state → compare live camera to it → guide.

## Key Decisions Made (and why)

**C++ for image processing** — not just for learning. C++ is the actual
industry standard for camera pipelines (ARM NEON SIMD, direct memory
access, no ARC overhead). Swift would work for this MVP but C++ is the
right long-term architecture. Learning goal is a bonus, not the reason.

**iPhone 17 Pro only, no fallbacks** — LiDAR gives real metric depth
(AVCaptureDepthDataOutput, float32 meters), far better than face-size proxy.
Camera Control button (AVCaptureEventInteraction) is the natural trigger.
Single-target keeps code cleaner.

**Distance via LiDAR, not face size** — faceSizeRatio was the v1 plan.
LiDAR replaced it. Guidance messages say "Step 0.4m closer" not "move closer".
Sample a 5×5 patch around the face center (not single pixel) to handle NaN
from hair/glasses on specular surfaces.

**AVCaptureDataOutputSynchronizer** required for depth + video — the two
outputs arrive on different queues and can drift. The synchronizer bundles
matched pairs. This is Day 2's key challenge.

**Photo quality** — AVCapturePhotoOutput with photoQualityPrioritization = .quality
+ 48MP HEIF. Apple's ISP pipeline runs on our captures too — quality is
indistinguishable from native Camera app in normal light. Night mode is the
one gap (post-MVP).

**Portrait mode** — depth blur is post-capture only, not live preview.
In MVP, portrait mode is a reminder label for the shooter, not a camera
behavior change.

**Native Camera app integration** — NOT possible for real-time guidance.
Apple doesn't allow third-party UI overlay on the native Camera app viewfinder.
Camera Extensions (iOS 17+) add custom capture modes but can't overlay the
existing viewfinder. Building our own camera app is the right call.

**xcodegen** — project.yml is source of truth, not the .xcodeproj.
Run `xcodegen generate` from repo root after pulling. The .xcodeproj is
not committed (too much generated XML, merge conflict prone).

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Camera | AVFoundation |
| LiDAR Depth | AVCaptureDepthDataOutput |
| Face Detection | Vision Framework |
| Orientation | CoreMotion (CMMotionManager) |
| Camera Control button | AVCaptureEventInteraction |
| Voice input | SFSpeechRecognizer (on-device) |
| Image processing core | C++ via Objective-C++ (.mm) bridge |
| Photo capture | PhotoKit + AVCapturePhotoOutput |

## Current Progress

**Day 1 — DONE (files written, pending git push)**

Files created:
- `project.yml` — xcodegen spec, iOS 18, iPhone only, C++17
- `CameraCoach/App/CameraCoachApp.swift` — @main entry point
- `CameraCoach/App/ContentView.swift` — camera feed + orientation overlay + C++ test
- `CameraCoach/Camera/CameraPreviewView.swift` — UIViewRepresentable for AVCaptureVideoPreviewLayer
- `CameraCoach/Camera/CameraManager.swift` — AVCaptureSession with video + depth outputs
- `CameraCoach/Camera/MotionManager.swift` — CoreMotion pitch/roll/yaw at 30Hz
- `CameraCoach/ImageProcessing/CameraCoach-Bridging-Header.h` — Swift→ObjC++ bridge
- `CameraCoach/ImageProcessing/ImageProcessor.h` — ObjC++ bridge header
- `CameraCoach/ImageProcessing/ImageProcessor.mm` — ObjC++ bridge implementation
- `CameraCoach/ImageProcessing/MathBridge.hpp` — C++ smoke test header
- `CameraCoach/ImageProcessing/MathBridge.cpp` — C++ smoke test (add two ints)
- `CameraCoach/Resources/Assets.xcassets/` — app icon stub + root catalog
- `setup.sh` — one-time script to clear git locks, commit, push, install xcodegen, generate project

**To complete Day 1:**
Run `./setup.sh` from the repo root on Mac terminal. This clears stale git
lock files (left by sandbox), commits, pushes to GitHub, installs xcodegen,
generates .xcodeproj, and opens Xcode. Then set Team in Signing & Capabilities.

Expected Day 1 result on device: full-screen camera + pitch/roll/yaw updating
at 30Hz + "C++ bridge: 3 + 4 = 7" in yellow (proves Swift→ObjC++→C++ chain).

## Day 2 Plan — Face Detection + LiDAR Depth Fusion

- `FaceDetector.swift` — VNDetectFaceRectanglesRequest on each video frame
- `DepthManager.swift` — AVCaptureDataOutputSynchronizer, sample depth at face center
- Draw face bounding box overlay (SwiftUI Canvas)
- Display "Subject: 1.3m" from LiDAR
- Compute normalised faceX, faceY from bounding box center
- Key challenge: Vision uses bottom-left origin, AVFoundation uses top-left

## Day 3 Plan — C++ Image Processing Module

- `LuminanceAnalyzer.hpp/cpp` — read Y plane of CVPixelBuffer, compute avg brightness + contrast
- `HistogramEngine.hpp/cpp` — 256-bin luminance histogram
- Wire through ImageProcessor.mm bridge
- Display live luminance + mini histogram in SwiftUI
- Key learning: YCbCr 4:2:0 biplanar format, bytesPerRow padding, Y plane = brightness map

## Days 4–7 Plan

See MVP_Plan.md for full day-by-day breakdown.

## File Structure

```
CameraCoach/
├── App/            — SwiftUI entry point and root view
├── Camera/         — AVFoundation, Vision, CoreMotion managers
├── Voice/          — SFSpeechRecognizer wrapper (Day 4)
├── Models/         — ReferenceFrame, FrameState, GuidanceResult (Day 4)
├── Views/          — TeacherModeView, ShooterModeView, overlays (Days 4–6)
└── ImageProcessing/— C++ pipeline + Obj-C++ bridge
```

## GitHub

https://github.com/saifkhan04/IOS-Camera-App.git
Branch: main

## Saif's Background

Learning image processing pipelines and computational photography as a
secondary goal. Explain all code — what it does and why it's required.
Unfamiliar with Objective-C++ bridge patterns and AVFoundation internals.
Primary language comfort: Swift and modern iOS patterns.
