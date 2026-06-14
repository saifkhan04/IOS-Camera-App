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
    var showCamera: Bool = false   // when aligned: show a camera glyph instead of %

    var body: some View {
        ZStack {
            // White shutter disc.
            Circle().fill(Color.white)

            // Track (subtle, visible on white).
            Circle()
                .stroke(Color.black.opacity(0.1), lineWidth: 6)

            // Progress arc — a soft charcoal loader filling as the match improves.
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(Color.black.opacity(0.6), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: progress)

            // Center: a camera glyph once aligned (ready to shoot), otherwise
            // the live match %.
            if showCamera {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundColor(.black.opacity(0.8))
            } else {
                Text(centerText)
                    .font(.system(.title3, design: .rounded)).bold()
                    .foregroundColor(.black.opacity(0.8))
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 6)
    }
}
