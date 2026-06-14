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
    let centerText: String

    var body: some View {
        ZStack {
            // White shutter disc.
            Circle().fill(Color.white)

            // Track (subtle, visible on white).
            Circle()
                .stroke(Color.black.opacity(0.12), lineWidth: 8)

            // Progress arc — a black loader filling as the match improves.
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(Color.black, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: progress)

            // Center: value + a camera glyph, in black on the white disc.
            VStack(spacing: 1) {
                Text(centerText)
                    .font(.system(.headline, design: .rounded)).bold()
                Image(systemName: "camera.fill")
                    .font(.caption2)
                    .opacity(0.7)
            }
            .foregroundColor(.black)
        }
        .shadow(color: .black.opacity(0.4), radius: 6)
    }
}
