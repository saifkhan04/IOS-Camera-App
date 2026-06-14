// MatchIndicatorView.swift
// A circular progress ring used two ways in Shooter Mode:
//   1. Match score — fills 0→1, colour shifts red → amber → green.
//   2. Auto-capture countdown — a green ring filling over the 1.5s hold.
//
// Keeping it a single configurable ring (progress + colour + centre text) means
// both uses share the same visual language.

import SwiftUI

struct MatchIndicatorView: View {
    let progress: Float      // 0…1, the trim fraction
    let color: Color
    let centerText: String

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 8)

            // Progress arc — starts at 12 o'clock (rotated −90°).
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: progress)

            Text(centerText)
                .font(.system(.headline, design: .rounded)).bold()
                .foregroundColor(.white)
        }
    }

    // Smooth red→green hue ramp for a match score. hue 0 = red, 0.33 = green.
    static func matchColor(_ score: Float) -> Color {
        let s = Double(max(0, min(1, score)))
        return Color(hue: s * 0.33, saturation: 0.9, brightness: 0.95)
    }
}
