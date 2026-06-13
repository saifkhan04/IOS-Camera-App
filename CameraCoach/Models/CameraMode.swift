// CameraMode.swift
// The capture mode the teacher selects and the shooter must match.
//
// In the MVP these are mostly a label/reminder carried on the ReferenceFrame
// (see CLAUDE.md — portrait depth blur is post-capture only, not a live
// preview behaviour). They become functional capture settings in Day 7.

import Foundation

enum CameraMode: String, CaseIterable, Identifiable {
    case photo    = "Photo"
    case portrait = "Portrait"
    case live     = "Live"

    // Identifiable conformance lets SwiftUI use these directly in a Picker /
    // ForEach without a separate id key.
    var id: String { rawValue }
}
