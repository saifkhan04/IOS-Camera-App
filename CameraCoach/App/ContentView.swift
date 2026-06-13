// ContentView.swift
// Root view. As of Day 4 it hosts Teacher Mode. Once Shooter Mode lands
// (Days 5–6) this becomes the Teacher ↔ Shooter switcher.

import SwiftUI

struct ContentView: View {
    var body: some View {
        TeacherModeView()
    }
}

// MARK: - HistogramView

// Draws the 256-bin luminance histogram as a filled curve. Each bin value
// is already normalised to [0, 1] by the C++ side (1.0 = tallest bin), so we
// just map bin index → x and value → bar height. Shared by any view that
// wants to show the live histogram.
struct HistogramView: View {
    let bins: [Float]

    var body: some View {
        Canvas { ctx, size in
            guard !bins.isEmpty else { return }
            let barWidth = size.width / CGFloat(bins.count)

            // One filled path spanning all bins: across the bottom, up and
            // over each bin's height, then close. A single path is far cheaper
            // than stroking 256 separate rectangles every frame.
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for (i, value) in bins.enumerated() {
                let x = CGFloat(i) * barWidth
                let y = size.height - CGFloat(value) * size.height
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()

            ctx.fill(path, with: .color(.white.opacity(0.8)))
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(4)
    }
}
