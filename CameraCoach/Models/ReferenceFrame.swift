// ReferenceFrame.swift
// What the teacher locks in: the target FrameState plus the human context
// around it — the spoken instructions, the chosen mode, and when it was taken.
//
// The shooter's whole job is to drive their live FrameState until it matches
// this reference's `state`.

import UIKit

struct ReferenceFrame: Identifiable {
    let id = UUID()

    // The measured target — orientation, face position, distance, lighting.
    var state: FrameState

    // A snapshot of the framing the teacher locked in — the picture the shooter
    // is trying to recreate. Drives the target thumbnail and the ghost overlay.
    // Optional: a reference can exist without an image (e.g. capture failed).
    var image: UIImage?

    // The teacher's selected capture mode (carried through to the shooter).
    var cameraMode: CameraMode

    // On-device transcription of the teacher's spoken framing instructions,
    // e.g. "keep her centred, angle slightly down, blur the background".
    var voiceTranscript: String

    // When this reference was captured — shown on the saved-reference card.
    var capturedAt: Date
}
