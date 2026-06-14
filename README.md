# CameraCoach

**Teach the shot once. Nail it every time.**

CameraCoach is an iPhone 17 Pro app that lets one person frame the perfect shot and guide another person to replicate it exactly — in real time.

---

## How It Works

**Teacher Mode** — the person who knows the shot they want:
1. Voice-record instructions ("keep her centered, background blurry, angle slightly down")
2. Physically frame the shot exactly how you want it
3. Press the **Camera Control button** to lock in the reference frame

**Shooter Mode** — the person holding the phone:
- The app compares the live camera feed to the saved reference continuously
- Real-time overlay shows animated guidance: "Step 0.4m closer", "Tilt right a little"
- A match ring fills as the frames align — green flash + haptic when you're there
- Camera Control or the on-screen button captures the shot

---

## Target Device

**iPhone 17 Pro only.** This app is built specifically for hardware that isn't available on most iPhones:

| Capability | Use |
|---|---|
| LiDAR Scanner | Real metric depth in meters — "Step 0.4m closer" is exact |
| Camera Control button | Physical trigger for reference capture and final shot |
| 48MP main sensor | Full-resolution capture via `AVCapturePhotoOutput` |
| A19 Pro Neural Engine | Available for future Core ML features |

No fallback code for non-LiDAR or non-Camera-Control devices. Single-target keeps the codebase clean.

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Camera | AVFoundation |
| LiDAR depth | `AVCaptureDepthDataOutput` + `AVCaptureDataOutputSynchronizer` |
| Face detection | Vision Framework (`VNDetectFaceRectanglesRequest`) |
| Device orientation | CoreMotion (`CMMotionManager`) |
| Camera Control button | `AVCaptureEventInteraction` (iOS 18+) |
| Voice input | `SFSpeechRecognizer` (on-device) |
| Image processing core | C++ via Objective-C++ (`.mm`) bridge |
| Photo capture | `AVCapturePhotoOutput` — 48MP HEIF / ProRAW |

---

## Project Structure

```
CameraCoach/
├── App/                — SwiftUI entry point and root view
├── Camera/             — AVFoundation, Vision, CoreMotion managers
├── Voice/              — SFSpeechRecognizer wrapper
├── Models/             — ReferenceFrame, FrameState, GuidanceResult
├── Views/              — TeacherModeView, ShooterModeView, overlays
└── ImageProcessing/    — C++ pipeline + Objective-C++ bridge
```

---

## Building

This project uses [xcodegen](https://github.com/yonaskolb/XcodeGen). `project.yml` is the source of truth — the `.xcodeproj` is not committed.

**Requirements:**
- macOS 15+
- Xcode 16+
- iPhone 17 Pro (Simulator lacks LiDAR and Camera Control)

**First-time setup:**

```bash
brew install xcodegen
xcodegen generate
open CameraCoach.xcodeproj
```

Then in Xcode: **Signing & Capabilities → Team** → set your Apple Developer account, then **⌘R**.

**After pulling changes that touch `project.yml`:**

```bash
xcodegen generate
```

---

## Architecture Notes

**C++ for image processing** — `LuminanceAnalyzer`, `HistogramEngine`, and `FrameComparator` live in C++ for direct memory access and ARM NEON SIMD compatibility. They communicate with Swift through an Objective-C++ bridge (`ImageProcessor.mm`).

**LiDAR depth sampling** — `AVCaptureDataOutputSynchronizer` bundles matched video + depth frame pairs. Depth at the face center is sampled over a 5×5 patch (not a single pixel) to handle NaN returns from specular surfaces like hair.

**Guidance priority order** — the C++ comparator checks axes in this order: lighting → distance → camera angle (pitch) → vertical position → horizontal position → roll (leveling). Fix the most important axis first. Aim (pitch) is checked before vertical framing because tilting the camera also moves the subject in the frame — correcting the angle fixes both, so the framing message is suppressed while the aim is off.
