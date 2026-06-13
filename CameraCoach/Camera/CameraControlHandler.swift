// CameraControlHandler.swift
// Wraps the physical Camera Control button (iPhone 16 Pro / 17 Pro) so a
// press fires our capture action — exactly the way the native Camera app
// uses it.
//
// The API is AVCaptureEventInteraction (iOS 17.2+), from AVKit. It's a
// UIInteraction you attach to any UIView in the foreground while a capture
// session is running. The system then routes hardware button events to it.
//
// An "event" has a phase:
//   .began     — light press / half-press started
//   .ended     — full press completed  ← this is our trigger
//   .cancelled — gesture aborted
// We fire on .ended so the action matches the feel of releasing the shutter.

import AVKit
import UIKit

final class CameraControlHandler {

    // Held strongly so the interaction outlives this setup call. If it were
    // local it would deallocate immediately and stop receiving events.
    private var interaction: AVCaptureEventInteraction?

    // Attaches the interaction to a view. `onPress` runs on the main thread
    // each time the button is fully pressed.
    func attach(to view: UIView, onPress: @escaping () -> Void) {
        // The handler closure may be called on a non-main thread; hop to main
        // before touching UI / published state.
        let interaction = AVCaptureEventInteraction { event in
            guard event.phase == .ended else { return }
            DispatchQueue.main.async { onPress() }
        }
        interaction.isEnabled = true
        view.addInteraction(interaction)
        self.interaction = interaction
    }
}
