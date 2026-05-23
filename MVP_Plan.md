# CameraCoach — MVP Plan (iPhone 17 Pro Edition)
**"Teach the shot once. Nail it every time."**

---

## The Concept

CameraCoach has two roles in a photo session:

- **Teacher** — someone who knows the shot they want. They voice-record instructions ("make sure the background is blurry, angle slightly down, keep her centered"), then physically frame it exactly how they like it and press the **Camera Control button** to lock in the reference.
- **Shooter** — the person actually holding the phone. The app compares the live camera feed to the saved reference in real time, showing animated guidance overlays and plain-English messages ("Step 0.4m closer", "Tilt right a little", "You're there — shoot!") until the frames match.

---

## Target Device: iPhone 17 Pro

This is a **custom build for your phone**. The plan takes full advantage of hardware that doesn't exist on most iPhones:

| Capability | Hardware | How We Use It |
|---|---|---|
| LiDAR Scanner | iPhone 17 Pro | Real metric depth in meters — replaces face-size guesswork |
| Camera Control button | iPhone 16 Pro+ | Physical trigger for "Capture Reference" and shutter |
| 48MP main sensor | iPhone 17 Pro | Full-resolution final capture |
| ProRAW | iPhone 12 Pro+ | Maximum data for C++ post-processing |
| A19 Pro Neural Engine | iPhone 17 Pro | Core ML inference if we add stretch features |

This means we will **not** add fallback code for non-LiDAR or non-Camera-Control devices. Keeping it single-target makes the MVP cleaner and faster to build.

---

## MVP Scope (20 hours)

### What's In

| Feature | Detail |
|---|---|
| Teacher Mode | Voice record + auto-transcribe via on-device SFSpeechRecognizer |
| Reference Frame Capture | Tilt (pitch/roll/yaw), face position (x/y), **real depth in meters via LiDAR**, lighting level, camera mode |
| Camera Control trigger | Press the physical Camera Control button to capture reference (teacher) or take the shot (shooter) |
| Shooter Guidance | Real-time overlay: directional arrows + messages driven by C++ comparison engine |
| Metric distance guidance | "Step 0.4m closer" or "Back up 0.2m" — exact, not vague |
| Match Indicator | Circular progress ring fills as frame aligns; green flash + haptic at match |
| Photo Capture | Camera Control or on-screen button; saves to Photos library |
| Capture quality | `photoQualityPrioritization = .quality`, full 48MP, HEIF |
| ProRAW option | Toggle to capture ProRAW for maximum C++ pipeline control (stretch Day 7) |
| C++ Image Processing Core | Luminance analysis, histogram computation, frame comparison — all in C++ via Obj-C++ bridge |

### What's Cut

- Fallback for non-LiDAR / non-Camera-Control devices
- Multi-subject / group photo tracking
- Background composition scoring
- Cloud sync of reference frames
- Video guidance / video mode
- AI aesthetic scoring

---

## Technical Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        SwiftUI Views                          │
│   TeacherModeView  │  ShooterModeView  │  GuidanceOverlay    │
└───────────────────────────────┬──────────────────────────────┘
                                │
┌───────────────────────────────▼──────────────────────────────┐
│                      Swift Managers                           │
│                                                               │
│  CameraManager (AVFoundation)                                 │
│   ├── AVCaptureVideoDataOutput  → CVPixelBuffer (30fps)       │
│   ├── AVCaptureDepthDataOutput  → AVDepthData (LiDAR depth)  │
│   └── AVCapturePhotoOutput      → HEIF / ProRAW capture      │
│                                                               │
│  FaceDetector (Vision)          → face x/y position          │
│  MotionManager (CoreMotion)     → pitch / roll / yaw          │
│  DepthManager                   → depth at face center (m)   │
│  VoiceRecorder (SFSpeech)       → transcript string          │
│  CameraControlHandler           → hardware button events     │
└───────────────────────────────┬──────────────────────────────┘
                                │ CVPixelBuffer + metrics
┌───────────────────────────────▼──────────────────────────────┐
│              Objective-C++ Bridge (.mm files)                  │
│                   ImageProcessor (bridge class)                │
└───────────────────────────────┬──────────────────────────────┘
                                │
┌───────────────────────────────▼──────────────────────────────┐
│                    C++ Image Pipeline                          │
│                                                               │
│  LuminanceAnalyzer   → brightness, contrast, exposure state  │
│  HistogramEngine     → 256-bin luminance histogram           │
│  FrameComparator     → delta computation → GuidanceResult    │
└──────────────────────────────────────────────────────────────┘
```

### Tech Stack

| Layer | Technology | Why |
|---|---|---|
| UI | SwiftUI | Modern, declarative, fast to build |
| Camera | AVFoundation | Full camera control, raw frame + depth access |
| LiDAR Depth | `AVCaptureDepthDataOutput` | Metric depth synced with video frames |
| Face Detection | Vision Framework | Real-time face x/y position |
| Device Orientation | CoreMotion (`CMMotionManager`) | Pitch, roll, yaw |
| Camera Control | `AVCaptureEventInteraction` | Physical button as trigger |
| Voice Input | `SFSpeechRecognizer` | On-device, no API key |
| Image Processing | **C++** (custom pipeline) | Performance + learning goal |
| Swift ↔ C++ Bridge | Objective-C++ (.mm files) | Standard iOS interop |
| Photo Capture | PhotoKit + `AVCapturePhotoOutput` | 48MP HEIF / ProRAW |

---

## Project File Structure

```
CameraCoach/
├── App/
│   ├── CameraCoachApp.swift
│   └── ContentView.swift              ← Teacher / Shooter mode switcher
│
├── Views/
│   ├── TeacherModeView.swift          ← voice record + capture reference
│   ├── ShooterModeView.swift          ← live camera + guidance overlay
│   ├── GuidanceOverlayView.swift      ← arrows, messages, match ring
│   └── MatchIndicatorView.swift       ← circular progress ring
│
├── Camera/
│   ├── CameraManager.swift            ← AVFoundation session orchestrator
│   ├── FaceDetector.swift             ← Vision face position pipeline
│   ├── DepthManager.swift             ← AVDepthData → meters at face center
│   ├── MotionManager.swift            ← CoreMotion pitch/roll/yaw
│   └── CameraControlHandler.swift     ← Camera Control button events
│
├── Voice/
│   └── VoiceRecorder.swift            ← SFSpeechRecognizer wrapper
│
├── Models/
│   ├── ReferenceFrame.swift           ← teacher's captured state
│   ├── FrameState.swift               ← live camera snapshot
│   └── GuidanceResult.swift           ← C++ comparator output
│
├── ImageProcessing/                   ← C++ core + Obj-C++ bridge
│   ├── ImageProcessor.h
│   ├── ImageProcessor.mm
│   ├── LuminanceAnalyzer.hpp
│   ├── LuminanceAnalyzer.cpp
│   ├── HistogramEngine.hpp
│   ├── HistogramEngine.cpp
│   ├── FrameComparator.hpp
│   └── FrameComparator.cpp
│
└── Resources/
    └── Assets.xcassets
```

---

## Key Data Models

### ReferenceFrame — what the teacher captures

```swift
struct ReferenceFrame {
    // Motion (from CoreMotion)
    var pitch: Double          // forward/backward tilt (radians)
    var roll: Double           // left/right rotation (radians)
    var yaw: Double            // compass heading (radians)

    // Subject position (from Vision — normalized 0.0–1.0)
    var faceX: Double          // horizontal center of face in frame
    var faceY: Double          // vertical center of face in frame

    // Distance (from LiDAR — real metric depth)
    var depthMeters: Float     // distance from phone to subject

    // Lighting (from C++ LuminanceAnalyzer)
    var luminance: Float       // average Y-plane brightness (0–255)

    // Mode (teacher selects)
    var cameraMode: CameraMode // .photo | .portrait | .live

    // Voice instructions
    var voiceTranscript: String
    var capturedAt: Date
}
```

> **Key upgrade from v1:** `faceSizeRatio` is gone. `depthMeters` is real distance from the LiDAR scanner — precise to ~1cm. The guidance messages can now say "step 0.4m closer" instead of vague arrows.

### FrameState — live camera snapshot (fed to C++ comparator)

```swift
struct FrameState {
    var pitch: Float
    var roll: Float
    var yaw: Float
    var faceX: Float
    var faceY: Float
    var depthMeters: Float     // LiDAR reading at face center
    var luminance: Float
}
```

### GuidanceResult — C++ output, bridged to Swift

```swift
struct GuidanceResult {
    var matchScore: Float          // 0.0 (off) → 1.0 (perfect)
    var primaryMessage: String     // "Step 0.4m closer"
    var secondaryMessage: String?  // "Then tilt slightly right"
    var arrowDirection: ArrowDir   // .up | .down | .left | .right | .none
    var arrowMagnitude: Float      // 0.0–1.0, drives animation intensity
    var isAligned: Bool            // matchScore >= threshold
}
```

---

## LiDAR Integration — How It Works

`AVCaptureDepthDataOutput` delivers `AVDepthData` objects synchronized with video frames. The depth map is a 2D float buffer (same coordinate space as the camera frame) where each pixel value is distance in meters from the camera.

```swift
// DepthManager.swift — core logic
func depthAtFaceCenter(depthData: AVDepthData, faceRect: CGRect) -> Float {
    let depthMap = depthData.converting(toDepthDataType:
        kCVPixelFormatType_DepthFloat32).depthDataMap

    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)

    // Sample depth at the center of the detected face bounding box
    let x = Int(faceRect.midX * CGFloat(width))
    let y = Int(faceRect.midY * CGFloat(height))

    let baseAddress = CVPixelBufferGetBaseAddress(depthMap)!
    let buffer = baseAddress.assumingMemoryBound(to: Float32.self)
    return buffer[y * width + x]
}
```

The session setup needs both outputs synchronized — `AVCaptureDataOutputSynchronizer` handles this so depth and video frames arrive together and are never mismatched.

---

## Camera Control Button Integration

iPhone 16 Pro and 17 Pro have a physical Camera Control button on the right rail. Apple exposes it via `AVCaptureEventInteraction` (iOS 18+).

```swift
// CameraControlHandler.swift
import AVKit

class CameraControlHandler {
    private var interaction: AVCaptureEventInteraction?

    func setup(in view: UIView, onPress: @escaping () -> Void) {
        interaction = AVCaptureEventInteraction { event in
            if event.phase == .ended { onPress() }
        }
        view.addInteraction(interaction!)
    }
}
```

**How we use it:**
- In **Teacher Mode**: pressing Camera Control captures the reference frame
- In **Shooter Mode**: pressing Camera Control takes the photo (same muscle memory as the native Camera app)

This feels completely native — no hunting for an on-screen button.

---

## C++ Image Processing — What You'll Build & Learn

### LuminanceAnalyzer.cpp
**Concept: Raw pixel buffers and the YCbCr color space**

iPhone camera frames are `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`. The Y (luma) plane is a full-resolution brightness map — you read it directly, no color conversion needed.

```cpp
struct LuminanceMetrics {
    float average;       // 0–255
    float contrast;      // max - min luminance in frame
    float overexposed;   // fraction of pixels > 240
    float underexposed;  // fraction of pixels < 15
};

class LuminanceAnalyzer {
public:
    static LuminanceMetrics analyze(const uint8_t* yPlane,
                                    int width, int height,
                                    int bytesPerRow);
};
```

**What you'll learn:** YCbCr color space, planar image buffers, why luminance = 0.299R + 0.587G + 0.114B (perceptual weighting), why cameras don't store RGB.

---

### HistogramEngine.cpp
**Concept: Tonal distribution — the universal tool of all photo processing**

```cpp
class HistogramEngine {
public:
    static std::array<int, 256> compute(const uint8_t* yPlane,
                                         int width, int height,
                                         int bytesPerRow);
    static float computeSkew(const std::array<int, 256>& hist);
    // Skew > 0 = bright scene, Skew < 0 = dark scene
};
```

**What you'll learn:** Every photo editing tool (Lightroom, Darkroom, Final Cut) works by reshaping histograms. Exposure curves, tone mapping, RAW processing — all histogram operations at heart.

---

### FrameComparator.cpp
**Concept: How do you quantify "are these two frames the same?"**

With LiDAR, the depth delta is now metric — we know the subject is 0.4m further away, not just "kind of far". This makes guidance dramatically more precise.

```cpp
struct FrameState {
    float pitch, roll, yaw;      // radians
    float faceX, faceY;          // normalized 0.0–1.0
    float depthMeters;           // real LiDAR distance
    float luminance;             // 0–255
};

struct GuidanceCommand {
    GuidanceType type;   // MOVE_CLOSER_N_METERS, MOVE_LEFT, TILT_RIGHT, etc.
    float magnitude;     // raw delta (meters for depth, radians for tilt, etc.)
    bool isBlocking;     // must fix before others matter
};

class FrameComparator {
public:
    static GuidanceResult compare(const FrameState& reference,
                                   const FrameState& current);

    // Guidance message generator uses real units
    // e.g. depthDelta = 0.4 → "Step 0.4m closer"
    //      depthDelta = 0.1 → "Just a tiny step closer"

private:
    // Thresholds — all tunable
    static constexpr float POSITION_THRESHOLD = 0.05f;   // 5% of frame width
    static constexpr float DEPTH_THRESHOLD_M  = 0.05f;   // 5cm — LiDAR is precise
    static constexpr float TILT_THRESHOLD_RAD = 0.08f;   // ~5 degrees
    static constexpr float LUMINANCE_THRESHOLD = 25.0f;  // out of 255
};
```

**Guidance priority order (most important first):**
1. Lighting (if light is wrong, everything else is wrong)
2. Distance / depth (biggest impact on subject size + bokeh)
3. Vertical position
4. Horizontal position
5. Roll (left/right tilt)
6. Pitch (forward/backward angle)

**What you'll learn:** Threshold engineering, weighting heterogeneous metrics (meters vs radians vs brightness), computing a meaningful 0–1 match score from multiple independent axes.

---

## Day-by-Day Build Plan

### Day 1 — Foundation, Camera, C++ Bridge (2.5h)
**Goal: Live camera feed on screen, orientation data displayed, C++ bridge proven.**

- [ ] Create Xcode project (SwiftUI, iOS 18 minimum, iPhone 17 Pro target)
- [ ] Add C++ source file + Obj-C++ bridge; call a trivial C++ function from Swift → prove the bridge works before depending on it
- [ ] `CameraManager`: set up `AVCaptureSession` with `AVCaptureVideoDataOutput`; display preview
- [ ] `MotionManager`: display pitch/roll/yaw as live text overlay on the preview
- [ ] Add `AVCaptureDepthDataOutput` to the session (display raw depth value in meters from center of frame)

**Learning:** Read how `AVCaptureSession` works — inputs, outputs, the run loop. Understand `CMSampleBuffer` → `CVPixelBuffer` delivery on the capture queue.

---

### Day 2 — Face Detection + LiDAR Depth Fusion (2.5h)
**Goal: Detect a face, draw its bounding box, and read the LiDAR depth at the face's center.**

- [ ] `FaceDetector`: `VNDetectFaceRectanglesRequest` running on each video frame
- [ ] Draw bounding box overlay using SwiftUI `Canvas`
- [ ] `DepthManager`: `AVCaptureDataOutputSynchronizer` to receive video + depth frames together (never mismatched)
- [ ] Sample the depth map at the face bounding box center → display "Subject: 1.3m" on screen
- [ ] Compute normalized `faceX`, `faceY` from bounding box center

**Learning:** Vision framework coordinate systems (0,0 = bottom-left in Vision, top-left in AVFoundation). `AVCaptureDataOutputSynchronizer` — why you need it (depth and color frames arrive on different queues and can drift).

---

### Day 3 — C++ Image Processing Module (2.5h)
**Goal: Pass a live camera frame to C++, compute brightness metrics, display a live histogram.**

- [ ] Implement `LuminanceAnalyzer.cpp` — read Y plane bytes, compute average brightness + contrast
- [ ] Implement `HistogramEngine.cpp` — compute 256-bin luminance histogram
- [ ] Wire through `ImageProcessor.mm` bridge — expose clean Swift API
- [ ] SwiftUI: display live luminance value + a mini 256-bar histogram visualization

**Learning:** Access the Y plane of a `CVPixelBuffer` directly in C++ — this is the same first step every camera RAW processor takes. Understand bytesPerRow padding (frames are not always tightly packed in memory).

---

### Day 4 — Camera Control Button + Reference Frame Capture (2.5h)
**Goal: Teacher Mode is fully functional — press Camera Control to lock in the reference.**

- [ ] `CameraControlHandler`: register `AVCaptureEventInteraction` on the view
- [ ] `VoiceRecorder`: tap-to-record with `SFSpeechRecognizer`, show live transcript while recording
- [ ] Camera mode picker (Photo / Portrait / Live)
- [ ] "Capture Reference" — fires on Camera Control press in Teacher Mode; snapshots all current values (tilt, faceX/Y, depthMeters, luminance, mode, transcript) into `ReferenceFrame`
- [ ] Display saved reference: thumbnail, depth readout, transcript, tilt summary

**Learning:** How `AVCaptureEventInteraction` works — it mirrors exactly how the native Camera app handles Camera Control, so the press-to-capture feel is identical.

---

### Day 5 — C++ Guidance Engine (2.5h)
**Goal: Given two FrameStates, C++ produces correct, metric guidance. Testable in isolation.**

- [ ] Define `FrameState` C++ struct and bridge header
- [ ] Implement `FrameComparator.cpp` — compute deltas, apply thresholds, build `GuidanceResult`
- [ ] Message generation uses real units: `depthDelta = 0.4f` → `"Step 0.4m closer"`, `rollDelta = 0.15f` → `"Tilt right a little"`
- [ ] Match score: weighted average across all axes (depth weight highest, tilt weight lowest)
- [ ] Unit test with hardcoded reference vs current — verify messages, scores, priority ordering
- [ ] Bridge to Swift `GuidanceResult`

**Learning:** Designing thresholds — LiDAR gives ~1cm precision but you don't want to nag the user about 2cm differences. The `DEPTH_THRESHOLD_M = 0.05` (5cm) is a design decision, not a technical one. Threshold engineering is a core computational photography skill.

---

### Day 6 — Guidance Overlay UI (2.5h)
**Goal: Shooter Mode shows animated, real-time guidance that feels great to use.**

- [ ] `GuidanceOverlayView`: directional arrows with bounce animations (magnitude drives amplitude)
- [ ] `MatchIndicatorView`: circular ring filling 0→1 as match improves; color shifts red → amber → green
- [ ] Primary message large and centered, secondary message smaller below
- [ ] Haptic feedback (`UIImpactFeedbackGenerator`) at alignment
- [ ] Green flash + "Take the shot!" when `isAligned == true`
- [ ] Auto-capture after 1.5s hold at alignment (with countdown animation) — Camera Control also fires capture

---

### Day 7 — Integration, Polish + ProRAW (2.5h)
**Goal: End-to-end flow works, demo-ready, and you've touched ProRAW.**

- [ ] Wire Teacher → `ReferenceFrame` → Shooter → Guided capture → save
- [ ] Photo capture: `photoQualityPrioritization = .quality`, full 48MP, HEIF
- [ ] **ProRAW toggle**: `AVCapturePhotoSettings` with `isAppleProRAWEnabled = true` — capture a ProRAW DNG and read its metadata in C++ to see the multi-frame data it contains
- [ ] "Shot taken!" confirmation: show captured photo + voice transcript
- [ ] Smooth Teacher ↔ Shooter mode transition animation
- [ ] Onboarding tip overlay on first launch

**Learning deep-dive:** Open a ProRAW DNG in your C++ pipeline. Inspect the metadata. Compare it to a regular HEIF capture. This is where computational photography becomes concrete — you'll see exactly what Apple bakes into the file and what headroom you have to process it differently.

---

## Guidance Message Reference

| Parameter | Delta | Message |
|---|---|---|
| Luminance | >25 below ref | "Find brighter light" |
| Luminance | >25 above ref | "Move to softer light" |
| depthMeters | >0.3m further than ref | "Step `Xm` closer" |
| depthMeters | >0.3m closer than ref | "Back up `Xm`" |
| depthMeters | 0.05–0.3m off | "Just a tiny step closer/back" |
| faceY | >5% above ref | "Lower the camera" |
| faceY | >5% below ref | "Raise the camera" |
| faceX | >5% right of ref | "Move camera left" |
| faceX | >5% left of ref | "Move camera right" |
| roll | >5° clockwise | "Tilt camera left" |
| roll | >5° counter-clockwise | "Tilt camera right" |
| pitch | >5° down | "Angle camera up" |
| pitch | >5° up | "Angle camera down" |

---

## Photo Quality Strategy

| Setting | Value | Effect |
|---|---|---|
| `photoQualityPrioritization` | `.quality` | Max computational processing time |
| Resolution | 48MP (full sensor) | No pixel binning |
| Format | HEIF (default) / ProRAW (toggle) | HEIF = Apple pipeline; ProRAW = your pipeline |
| HDR | Auto Smart HDR 5 | Apple applies this through `AVCapturePhotoOutput` |
| Stabilization | `.auto` | Apple applies multi-frame stabilization |

For portrait shots in good to decent light, output is indistinguishable from the native Camera app. Night shots will be the one gap — Night Mode's aggressive multi-frame stacking is Camera.app-specific. Post-MVP this could be added manually in C++.

---

## What You'll Learn About Image Processing

By Day 7 you'll have genuine hands-on experience with:

1. **Camera frame buffers** — `CVPixelBuffer`, `CMSampleBuffer`, how frames flow from the sensor to memory at 30fps
2. **YCbCr color space** — why cameras don't use RGB internally, luma vs chroma planes, the luminance formula
3. **LiDAR depth maps** — `AVDepthData`, float32 depth buffers, sampling depth at a 2D screen coordinate
4. **Luminance analysis** — brightness, contrast, exposure warnings — the first pass of every imaging pipeline
5. **Histogram computation** — the universal diagnostic underlying all photo editing and RAW processing
6. **Metric guidance engineering** — threshold design, weighting heterogeneous measurements, producing a 0–1 match score
7. **Real-time pipeline design** — processing every frame at 30fps on a background queue without blocking the UI
8. **C++ / Swift interop** — the Obj-C++ bridge pattern used in production camera apps
9. **ProRAW format** — what's in a DNG, what multi-frame computational data looks like at the file level

**Stretch goals if you finish early:**
- Gaussian blur pass in C++ on a downsampled frame (intro to convolution / spatial filtering)
- Sobel edge detection on the Y plane (intro to derivative filters — the basis of sharpening)
- Night Mode prototype: capture 4 frames at different exposures, align + merge in C++

---

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| C++ bridge setup burns Day 1 time | Medium | Build a trivial "add two ints" bridge first — fail fast before depending on it |
| `AVCaptureDataOutputSynchronizer` is tricky to set up | Medium | Apple's sample code "AVCamFilter" covers this pattern exactly |
| LiDAR returns NaN at face center (specular surface, hair) | Medium | Median-sample a 5×5 patch around the face center rather than a single pixel |
| Camera Control API behaves differently than expected | Low | `AVCaptureEventInteraction` is well-documented since iOS 18 |
| Portrait mode depth blur not in preview | High (known) | Label it — actual portrait rendering is post-capture, not live. The mode is a reminder to the shooter, not a live preview effect |
| 20 hours isn't enough for full polish | Medium | Cut the ProRAW deep-dive to a 20-min exploration if pressed; core loop takes priority |

---

## Success Criteria for MVP

- [ ] Teacher can voice-record instructions and lock a reference with Camera Control in under 30 seconds
- [ ] Shooter sees correct metric guidance messages in real time ("Step 0.4m closer" is accurate to within ~10cm)
- [ ] Frame alignment triggers the match indicator and a haptic
- [ ] Photo is captured at 48MP and saved to Photos
- [ ] C++ pipeline processes every frame at 30fps without dropped frames (measure with Instruments)
- [ ] You can explain what a luminance histogram is, what YCbCr is, and how LiDAR depth data is structured
