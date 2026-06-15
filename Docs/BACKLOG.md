# CameraCoach — Backlog

Lightweight scrum-lite backlog. **Features** group related work; every **story**
has a single global number — just say the number (e.g. "do 3") and we implement it.

Legend — Effort: `S` ≈ <½ day · `M` ≈ ~1 day · `L` ≈ multi-day.
Status: ⬜ todo · 🔵 in progress · ✅ done.

Format: **#. (Effort) Status** — _As a [role], I want [X], so that [Y]._
Then a one-line "Done when…" acceptance note.

---

## Feature A — Visual Reference Target
Let the shooter SEE the target shot, not just numbers. Biggest amplifier of the
core loop; also makes guidance work when there's no face.

**1. (M) ✅** — _As a teacher, when I lock a frame I want a still snapshot stored on
the reference, so the shooter can see the exact composition I framed._
Done when: capturing a reference grabs the current frame as an image held on
`ReferenceFrame` (e.g. downscaled UIImage/Data).
DONE + device-verified 2026-06-15: CameraManager.latestVideoImage (throttled ~5fps, upright via
.right orientation); TeacherModeView stores it on ReferenceFrame.image.

**2. (S) ✅** — _As a shooter, I want a corner "target" thumbnail of the teacher's
shot, so I always know what I'm composing toward._
Done when: Shooter Mode shows the reference image thumbnail; tap = enlarge.
DONE + device-verified 2026-06-15: bottom-trailing yellow-bordered "Target" thumbnail in
ShooterModeView; tap → full-screen target viewer.

**3. (M) ✅** — _As a shooter, I want to toggle a semi-transparent ghost of the
reference image over my live preview, so I can line the shot up visually._
Done when: a toggle overlays the reference image (~30% opacity) on the preview.
DONE + device-verified 2026-06-15: Settings → Guidance → "Ghost overlay" toggle (default off);
ghostLayer renders reference.image at 0.3 opacity below the HUD.

**4. (S) ⬜** — _As a shooter, I want to adjust the ghost overlay opacity, so I can
balance it against the live scene._
Done when: a slider drives the overlay opacity (persisted in Settings).

**5. (L) ⬜** — _As a shooter, I want a visual-similarity score alongside the numeric
guidance, so alignment works even without a detected face._
Done when: C++ compares live vs reference image (e.g. downscaled luma diff /
histogram correlation) and feeds a 0–1 score into the match ring.

---

## Feature B — Reference Persistence & Library
Turn a one-shot live demo into a reusable tool: save references and pick from them.

**6. (M) ⬜** — _As a teacher, I want my locked references saved to disk, so they
survive relaunching the app._
Done when: `ReferenceFrame` (+ its image) is Codable and persisted; reloaded on launch.

**7. (M) ⬜** — _As a user, I want a library grid of saved references with thumbnails,
so I can see everything I've set up._
Done when: a browsable grid lists saved references with their target thumbnails.

**8. (S) ⬜** — _As a shooter, I want to pick a saved reference and start shooting it,
so I can replicate any past framing._
Done when: tapping a library item enters Shooter Mode targeting that reference.

**9. (S) ⬜** — _As a user, I want to delete references I no longer need._
Done when: swipe/long-press delete removes it from disk + library.

**10. (S) ⬜** — _As a teacher, I want to give a reference a short name, so I can
recognise it later._
Done when: an editable label is stored and shown in the library + shooter banner.

---

## Feature C — AI Voice Intelligence
Make the teacher's spoken instructions actually drive coaching (post-MVP phase —
geometry stays source of truth; AI never overrides a measured delta).

**11. (L) ⬜** — _As a shooter, I want the teacher's spoken intent turned into natural
coaching messages, so guidance feels human, not robotic._
Done when: transcript → short coaching lines surfaced in the HUD.

**12. (L) ⬜** — _As a shooter, I want spoken intent (e.g. "a bit lower") to nudge the
comparator's numeric targets, so the AI adjusts what "aligned" means._
Done when: parsed intent shifts target faceY/faceX/etc. within safe bounds.

**13. (L) ⬜** — _As a shooter, I want the shot gated on expression/timing (smile, eyes
open), so the captured moment is right._
Done when: Vision checks gate auto-capture on the chosen expression.

**14. (L) ⬜** — _As a developer, I want on-device parsing with a Claude API fallback,
so it's fast for simple cases and smart for nuanced ones, and degrades to MVP when
offline/off._
Done when: hybrid path implemented behind a Settings toggle; MVP behaviour intact when off.

---

## Feature D — Composition & Camera Niceties
Low-risk, familiar camera affordances.

**15. (S) ⬜** — _As a user, I want a rule-of-thirds grid toggle, so I can compose
deliberately._
Done when: grid overlay toggle (Settings), drawn over the preview.

**16. (S) ⬜** — _As a user, I want a level indicator from roll, so I can keep the
horizon straight._
Done when: a level line/dot shows level state using `motionManager.roll`.

**17. (M) ⬜** — _As a user, I want tap-to-focus and tap-to-set-exposure, so I control
what's sharp and bright._
Done when: tapping the preview sets focus/exposure POI on the device.

**18. (S) ⬜** — _As a user, I want a self-timer (3s/10s), so I can get into the shot._
Done when: a timer option counts down before firing capture.

**19. (S) ⬜** — _As a user, I want AE/AF lock, so the exposure/focus doesn't drift
while I line up the shot._
Done when: a lock control freezes focus/exposure until released.

---

## Feature E — Capture & Output
Quality/output options beyond the MVP single HEIF.

**20. (L) ⬜** — _As a user, I want an optional 48MP / ProRAW capture mode, so I can get
maximum quality when I want it._
Done when: a Settings toggle swaps to the wide-camera 48MP/ProRAW path at capture
(accepting a brief guidance pause — see LEARNINGS #20).

**21. (S) ⬜** — _As a user, I want guided shots collected in their own Photos album, so
they're easy to find._
Done when: saved captures are added to a "CameraCoach" album.

**22. (S) ⬜** — _As a user, I want the shutter to feel right (sound + refined haptic),
so capture is satisfying and obvious._
Done when: capture plays a shutter sound + tuned haptic.

---

## Feature F — Manual Camera Controls & Framing
Hands-on capture controls. NOTE: the session is pinned to `.builtInLiDARDepthCamera`
for live depth — controls that don't touch the active format are easy; ones that
need a different device/format carry a caveat (see LEARNINGS #20).

**23. (M) ⬜** — _As a user, I want to choose an aspect ratio (4:3 / 16:9 / 1:1), so I
can frame for the output I want._
Done when: a selector crops the preview (mask/letterbox) AND the saved image to the
chosen ratio. Pure crop on top of the sensor frame — no session-format change, so it
plays nicely with depth. Reference target overlay (Feature A) respects the ratio too.

**24. (M) ⬜** — _As a user, I want pinch-to-zoom (and quick 1×/2× steps), so I can
reach my framing without moving._
Done when: pinch ramps `device.videoZoomFactor` (clamped to the active device's max);
optional preset buttons. Works on the LiDAR virtual device; depth scales with it.

**25. (S) ⬜** — _As a user, I want an exposure-compensation (EV) slider, so I can
brighten or darken the shot deliberately._
Done when: a slider drives `setExposureTargetBias` within the device's min/max.

**26. (S) ⬜** — _As a user, I want a torch/flash toggle, so I can shoot in low light._
Done when: a control sets `device.torchMode`. CAVEAT: verify the LiDAR depth device
exposes torch; photo `flashMode` may be unavailable on it (we already use a screen
flash). If unsupported on device, hide the control.

**27. (S) ⬜** — _As a user, I want to pick the capture format (HEIF vs JPEG), so I can
trade size for compatibility._
Done when: a Settings toggle chooses the codec in `makePhotoSettings()`.

**28. (S) ⬜** — _As a user, I want a white-balance lock, so colour doesn't shift while
I line up the shot._
Done when: a lock control freezes white balance (`whiteBalanceMode = .locked`).

**29. (L) ⬜** — _As a user, I want a front-camera selfie mode, so I can guide my own
shots._
Done when: front capture works. CAVEAT: front is TrueDepth, a different device — this
needs a separate session config and loses the back-LiDAR guidance path. Significant;
likely its own arc, not a quick nicety.

---

## Feature G — Pro Assistant Mode (solo AI photo coach)
Instead of a teacher, pick a TEMPLATE of the shot you want; the app coaches you to
a good photo. Two loops: a fast on-device loop (geometry + composition + shot-
quality score, real-time, free, private) and a slow cloud loop (periodic Claude
vision frames → template-aware natural-language coaching, opt-in). Geometry stays
source of truth; AI never overrides a measured delta; degrades to on-device when
offline/off. Architecture note: you SAMPLE frames (~1 every 1.5–2s), you don't
stream video to the AI — the deterministic loop carries the real-time feel.

DECIDED 2026-06-15 (not yet started): build ON-DEVICE FIRST. Sequence
30 → 31 → 32 → 33 (mode + template picker → synthesized target reusing the
existing FrameComparator/HUD → on-device aesthetics/quality meter → good-shot
gating). Cloud Claude coaching (34 → 35 → 36) layered on later as a proven add-on.
Key design: a template synthesises a ReferenceFrame, so picking one drops straight
into the existing Shooter HUD — no teacher needed. TO VERIFY before story 32: that
`VNCalculateImageAestheticsScoresRequest` (iOS 18 Vision) exists/behaves as assumed.
Cloud side (story 34) would use Claude vision `claude-opus-4-8` (~$5/1M input
tokens, ~4.8K tokens per full-res frame) — confirm before building the cloud loop.

**30. (M) ⬜** — _As a solo shooter, I want to enter Pro Assistant mode and pick a
shot template (grid of thumbnails), so I can shoot a kind of photo without a teacher._
Done when: a third mode + template picker (portrait / full-body / rule-of-thirds
landscape / tight headshot / etc.), each with an example thumbnail.

**31. (M) ⬜** — _As a developer, I want each template to synthesise a target
ReferenceFrame, so the existing FrameComparator + HUD guide toward it for free._
Done when: selecting a template builds a target FrameState (subject size/distance,
faceY headroom, level) and enters the guidance HUD against it.

**32. (L) ⬜** — _As a solo shooter, I want an on-device "shot quality" meter, so I
get real-time feedback even without a face or any cloud._
Done when: iOS 18 Vision (`VNCalculateImageAestheticsScoresRequest` + saliency +
horizon) drives a live 0–1 quality score in the HUD. Real-time, free, private.

**33. (M) ⬜** — _As a solo shooter, I want the app to tell me when the shot is good
and prompt/auto-capture, so I catch the moment._
Done when: capture is gated/prompted when geometry aligned AND quality score high.

**34. (L) ⬜** — _As a solo shooter, I want template-aware natural-language coaching
from AI, so guidance feels like a pro photographer, not just numbers._
Done when: periodic (~2s) downscaled frame → Claude vision (`claude-opus-4-8`) with
the template context → short coaching line in the HUD. Throttled + session budget.

**35. (M) ⬜** — _As a user, I want cloud AI coaching to be explicit opt-in with a
clear privacy note, so frames only leave my device when I allow it._
Done when: Settings toggle (default OFF) + first-use explanation; off = on-device only.

**36. (M) ⬜** — _As a user, I want Pro Assistant to keep working offline / when AI is
off, so it always degrades to the deterministic + on-device experience._
Done when: no network / toggle off → stories 31–33 still fully functional; no crash,
no hang waiting on the cloud.

---

_Add new stories at the next free number; don't renumber existing ones._
