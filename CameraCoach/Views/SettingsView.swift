// SettingsView.swift
// App settings, presented as a sheet. Backed by @AppStorage (UserDefaults) so
// values persist and any view can read the same key reactively. Designed to grow
// — add new Sections/toggles here as features land.

import SwiftUI

// Central place for the persisted keys so they don't drift between views.
enum SettingsKeys {
    static let autoCapture = "autoCapture"
}

struct SettingsView: View {
    @AppStorage(SettingsKeys.autoCapture) private var autoCapture = false
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
