// CameraMode.swift
// The capture mode the teacher selects and the shooter must match.
//
// This is a label/reminder carried on the ReferenceFrame, not a capture-pipeline
// switch: portrait depth blur is post-capture only, not a live preview
// behaviour, so the modes don't change how frames are captured.

import Foundation

enum CameraMode: String, CaseIterable, Identifiable {
    case photo    = "Photo"
    case portrait = "Portrait"
    case live     = "Live"

    // Identifiable conformance lets SwiftUI use these directly in a Picker /
    // ForEach without a separate id key.
    var id: String { rawValue }
}
