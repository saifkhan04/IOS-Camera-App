// SettingsView.swift
// App settings, presented as a sheet. Backed by @AppStorage (UserDefaults) so
// values persist and any view can read the same key reactively. Designed to grow
// — add new Sections/toggles here as features land.

import SwiftUI

// Central place for the persisted keys so they don't drift between views.
enum SettingsKeys {
    static let autoCapture = "autoCapture"
    static let ghostOverlay = "ghostOverlay"
}

struct SettingsView: View {
    @AppStorage(SettingsKeys.autoCapture) private var autoCapture = false
    @AppStorage(SettingsKeys.ghostOverlay) private var ghostOverlay = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Capture") {
                    Toggle("Auto-capture when aligned", isOn: $autoCapture)
                    Text("When on, the shot fires automatically after you hold the "
                         + "match for 1.5s. When off, tap the shutter or press the "
                         + "Camera Control button to capture.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Guidance") {
                    Toggle("Ghost overlay", isOn: $ghostOverlay)
                    Text("When on, the teacher's reference shot is faintly overlaid on "
                         + "your live preview so you can line the framing up visually. "
                         + "Turn off for an unobstructed view.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
