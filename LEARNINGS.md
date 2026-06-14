# CameraCoach — Engineering Learnings & Notable Fixes

A running log of the non-obvious problems hit while building this app and how
they were solved. Written interview-style (Challenge → Symptom → Root cause →
Fix → Takeaway) so the reasoning is easy to recall and retell.

---

## 1. Swift ↔ C++ interop via an Objective-C++ bridge

**Challenge:** Run the image-processing core in C++ but call it from SwiftUI.

**Approach:** Swift can't call C++ directly (in this project we use the
battle-tested bridge rather than Swift's experimental C++ interop). The chain is:

```
Swift → Objective-C++ (.mm) → C++ (.cpp/.hpp)
```

- A bridging header (`CameraCoach-Bridging-Header.h`) exposes Objective-C classes to Swift.
- The `.mm` file compiles as Objective-C++ and can `#include` C++ freely.
- The Obj-C interface (`ImageProcessor.h`) must stay **pure Objective-C/C** — no
  C++ types — because Swift parses it. C++ types live only in the `.mm`/`.hpp`.

**Takeaway:** De-risk the bridge first with a trivial "add two ints" call before
building anything real on top of it. The boundary discipline (no C++ in headers
Swift sees) is the whole game.

---

## 2. LiDAR depth: the wide-angle camera reports zero depth formats

**Symptom:** On iPhone 17 Pro, `.builtInWideAngleCamera` (and ultra-wide,
telephoto) returned an **empty** `supportedDepthDataFormats` array, so depth
never arrived and the distance readout stayed blank.

**Root cause:** The individual back cameras don't carry LiDAR depth on their own.
Depth comes from `.builtInLiDARDepthCamera` — a **virtual device** that fuses a
YUV camera with the LiDAR scanner. It's the only back-camera device type that
exposes non-empty `supportedDepthDataFormats` (39 of 45 formats on this device).

**Fix:** Use `.builtInLiDARDepthCamera` as the *sole* session input (gives video
+ depth from one input, no `AVCaptureMultiCamSession` needed). Trying to add it
*alongside* the wide camera in a regular session fails — that needs multi-cam.

**Takeaway:** Enumerate `AVCaptureDevice.DiscoverySession` and inspect
`supportedDepthDataFormats` per device instead of assuming the default camera can
do depth. The diagnostic logging that printed each device's format counts is what
made this obvious.

---

## 3. AVCaptureDataOutputSynchronizer crash on missing connection

**Symptom:** App crashed at launch: *"dataOutputs must all contain a valid
connection."*

**Root cause:** The synchronizer requires **every** output it's given to already
have a live session connection. The `.photo` preset could select a format
(e.g. 48 MP) that doesn't support simultaneous depth, leaving the depth output
with no connection.

**Fix:** After `commitConfiguration`, check
`depthOutput.connection(with: .depthData) != nil` and only include depth in the
synchronizer when it's actually connected; otherwise fall back to video-only.
Also stopped relying on the preset and **manually selected** the highest-res
depth-capable `activeFormat`.

**Takeaway:** `AVCaptureDataOutputSynchronizer` is strict and fails hard. Verify
connections after the session commits, and never assume a preset gives you the
format you need — enumerate and set it yourself.

---

## 4. Reading the Y plane: bytesPerRow padding & format choice

**Concept:** iPhone frames are `420YpCbCr8BiPlanarFullRange`. Plane 0 is the
full-resolution **Y (luma)** plane — a ready-made brightness map, no color
conversion needed.

**Trap:** Rows are **not** tightly packed. `bytesPerRow` can exceed `width`
because the hardware pads each row to an alignment boundary. Addressing rows with
`width` instead of `bytesPerRow` shears the image diagonally.

**Fix:** Always step rows by `bytesPerRow` (or `bytesPerRow / sizeof(element)`
for the depth float plane). Lock the buffer read-only before access; unlock on
every return path.

**Takeaway:** Raw pixel access is the first step of every RAW pipeline — and row
stride padding is the classic first bug.

---

## 5. Scan once, summarise many times

**Decision:** The histogram is the only pass over the (millions of) pixels. Mean
brightness and contrast (std-dev) are then derived from the **256-bin histogram**,
not by re-scanning pixels.

- Mean = Σ(level × count) / total
- Variance = Σ(count × (level − mean)²) / total → std-dev = "contrast"

**Takeaway:** This is the standard camera-pipeline pattern — do the one expensive
pass, then read cheap summaries off its small output. Cut per-frame work ~2×.

---

## 6. Histogram across the bridge: NSData, not NSArray<NSNumber*>

**Trap:** Returning 256 bins as `NSArray<NSNumber*>` boxes 256 floats into 256
heap objects **every frame** — 256 × 30 fps ≈ 7,680 allocations/sec.

**Fix:** Pack the 256 normalised floats into one `NSData` buffer; Swift reads it
with `withUnsafeBytes` — zero per-element boxing.

**Takeaway:** At 30 fps, per-frame allocations matter. Prefer contiguous buffers
over boxed collections on hot paths.

---

## 7. Performance: strided sampling for the histogram

**Decision:** Sample every 2nd pixel and every 2nd row (`stride = 2`) — reads
1/4 of the pixels for a visually identical histogram, ~4× faster. Keeps the live
pipeline comfortably within the 30 fps frame budget.

**Takeaway:** Histograms are statistical; you rarely need every pixel. Subsample
deliberately and measure.

---

## 8. Vision face coordinates: origin flip

**Trap:** Vision returns bounding boxes in CoreGraphics space (origin
**bottom-left**, y-up). AVFoundation / UIKit use **top-left**, y-down. Also the
sensor buffer is landscape, so Vision needs an orientation hint (`.right`) in
portrait or detection rate drops.

**Fix:** Convert once in `FaceDetector`: `y = 1 - origin.y - height`, pass
`orientation: .right`.

**Takeaway:** Always nail down each framework's coordinate origin before drawing
overlays. Convert at the boundary so the rest of the app uses one convention.

---

## 9. Code signing: the Team ID is the cert's OU field

**Symptom:** Build failed: *"No Account for Team Y54VJGTWH9."*

**Root cause:** `Y54VJGTWH9` is the code in parentheses from
`security find-identity` — that's the cert's **common-name identifier**, NOT the
Team ID. The real Team ID is the **OU (Organizational Unit)** in the cert subject.

**Fix:**
```
security find-certificate -c "Apple Development: <email>" -p \
  | openssl x509 -noout -subject
# subject= ... , OU=BG9TQ835ZT, O=Saif Khan, ...   ← OU is the Team ID
```
Used `OU=BG9TQ835ZT`.

**Takeaway:** Don't trust the parenthetical from `find-identity`. The certificate
subject's OU is authoritative.

---

## 10. xcodegen kept wiping the development team

**Symptom:** Every `xcodegen generate` reset signing; had to re-pick the team in
Xcode before each build.

**Root cause:** `project.yml` is the source of truth and had
`DEVELOPMENT_TEAM: ""`, which it faithfully wrote into each fresh `.xcodeproj`.

**Fix:** Set `DEVELOPMENT_TEAM` (and `CODE_SIGN_STYLE: Automatic`) in
`project.yml` so it survives regeneration.

**Takeaway:** With generated projects, anything you set in the IDE is ephemeral —
it must live in the generator spec.

---

## 11. Audio session conflict: camera vs. speech

**Risk:** `AVCaptureSession` by default manages the app's audio session; the
`SFSpeechRecognizer` voice recorder needs to own it while recording.

**Fix:** `session.automaticallyConfiguresApplicationAudioSession = false` (our
capture session has no audio input, so it has no reason to manage it), and the
recorder sets `.record`/`.measurement` and deactivates with
`.notifyOthersOnDeactivation` when done.

**Takeaway:** Two subsystems wanting the audio session will fight. Decide who owns
it explicitly.

---

## 12. Camera Control button (iPhone 16/17 Pro)

**Concept:** The physical Camera Control button is exposed via
`AVCaptureEventInteraction` (AVKit, iOS 17.2+) — a `UIInteraction` you attach to a
foreground view while a capture session runs. Fire on `event.phase == .ended`.

**Gotchas:** Hold the interaction strongly (a local var deallocates and stops
receiving events); the handler may fire off-main, so hop to main for UI/state.

**Takeaway:** It mirrors the native Camera app, so press-to-capture feels
identical — but only delivers events with an active session in the foreground.

---

## 13. Guidance directions were inverted (framing axes)

**Symptom:** "Lower the camera" pushed the face *out* of the frame.

**Root cause:** Sign errors mapping deltas to instructions. Face too high
(`faceY` smaller) needs the camera **raised** (subject then moves down in frame),
but the code said "lower." Same flip on the horizontal axis.

**Fix:** Corrected both: too high → "Raise"; too far right → "Move right".

**Takeaway:** Direction conventions can't be reasoned reliably from a desk —
they must be **verified on device** (see #15). Build the verification in.

---

## 14. One clear step at a time, in priority order

**Feedback:** Showing two corrections at once was confusing; it felt reactive,
not like being led to the shot.

**Fix:** Show one prominent action plus a faint "then …" hint. The comparator
emits problems in a fixed priority order
(**lighting → distance → aim → vertical → horizontal → level**) and shows the
top one or two. The match score still blends *all* axes so it climbs steadily.

**Takeaway:** Guidance UX is about sequencing and restraint, not dumping every
delta. Surface the single most impactful next action.

---

## 15. Gimbal lock: Euler angles blow up in the shooting pose

**Symptom:** "Tilt" was by far the most frequent (and wrong) message; aiming
up/down produced bogus roll; the match score kept dropping no matter what.

**Root cause:** Reading pitch/roll/yaw as **Euler angles** from `CMAttitude`.
Euler angles have a singularity at attitude-pitch ≈ 90° — which is **exactly the
upright pose you hold the phone in to shoot**. At the singularity, roll and yaw
become degenerate, so roll swings wildly and pitch leaks into roll.

**Fix:** Derive pitch and roll from the **gravity vector** instead:
```
roll  = atan2(gx, -gy)              // tilt right  => +
pitch = atan2(gz, hypot(gx, gy))    // aim up      => +
```
These are **decoupled** and stable in the upright pose; their only singularity is
phone-flat, which we never shoot in. Yaw isn't derivable from gravity and the
comparator doesn't use it.

**Takeaway:** Euler angles are the wrong representation for comparing orientations
near their singularity. For a leveling/aim app, gravity-derived pitch/roll (or
quaternion relative rotation) are the robust choice. **This was the single most
important fix in the project.**

---

## 16. The gravity migration silently re-inverted pitch

**Symptom:** After the gimbal fix, aiming up said "Angle camera up" (should be
"down") — even though pitch direction had been "fixed" earlier.

**Root cause:** The earlier pitch fix was verified against the *old* attitude-
based pitch. Switching to gravity-based pitch changed the signal's **sign**
(gravity's z required `+g.z`, not `-g.z`), re-inverting the direction without
anyone re-checking.

**Fix:** Flipped to `atan2(g.z, …)` so "aim up = pitch increases" holds again,
matching the comparator's assumption.

**Takeaway:** When you swap out the *source* of a signal, re-verify everything
downstream that depended on its sign/scale. A fix verified against the old signal
doesn't carry over for free.

---

## 17. Coupled axes: guide the cause, not the symptom

**Symptom:** Aiming down (no phone movement) said "Raise the camera" instead of
"Angle camera up."

**Root cause:** Aim (pitch) and vertical framing (`faceY`) are physically
coupled — tilting the camera moves the subject in the frame. Both errors trip at
once, and framing had higher priority, so it won the primary slot. But "raise the
camera" only treats the symptom; correcting the **aim** fixes both.

**Fix:** Prioritise pitch above faceY, and **suppress** the faceY message while
pitch is out of threshold. Only once aim is correct does a leftover vertical
error mean a genuine "raise/lower the phone."

**Takeaway:** With coupled measurements, detect which is the root cause and guide
that; silence the dependent symptom so you don't give contradictory advice.

---

## Cross-cutting lessons

- **Verify directions/signs on device, not at a desk.** A temporary on-screen
  readout of the raw values settled multiple sign bugs that hand-reasoning got
  wrong twice.
- **Diagnostic logging pays for itself.** Printing per-device depth-format counts
  and per-frame deltas located the LiDAR and gimbal issues fast.
- **Compile-check from the CLI** with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild … CODE_SIGNING_ALLOWED=NO`
  catches errors before deploying to the phone.
- **Representation choices dominate.** YCbCr planes, gravity vs Euler, histogram
  vs raw pixels, NSData vs boxed arrays — each was the difference between a hard
  problem and an easy one.
