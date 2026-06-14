// GuidanceOverlayView.swift
// The shooter's heads-up display: a big animated directional arrow, the current
// instruction (primary + faint "then …" hint), and the match/countdown ring.
//
// Pure presentation — it's handed a GuidanceResult and a hold progress and just
// draws them. All the timing/haptics/capture logic lives in ShooterModeView.

import SwiftUI

struct GuidanceOverlayView: View {
    let guidance: GuidanceResult
    let holdProgress: CGFloat   // 0…1, auto-capture countdown while aligned

    var body: some View {
        VStack {
            Spacer()

            // Center: arrow while correcting, big check when aligned.
            if guidance.isAligned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 96, weight: .bold))
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                GuidanceArrow(direction: guidance.arrowDirection,
                              magnitude: guidance.arrowMagnitude)
                    .frame(height: 110)
            }

            Spacer()

            // Bottom: message + ring.
            VStack(spacing: 10) {
                Text(guidance.primaryMessage)
                    .font(.title).bold()
                    .foregroundColor(guidance.isAligned ? .green : .white)
                    .multilineTextAlignment(.center)
                    .shadow(radius: 4)

                if !guidance.isAligned, let secondary = guidance.secondaryMessage {
                    Text("then \(secondary.lowercasedFirstLetter)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }

                ring
                    .frame(width: 92, height: 92)
                    .padding(.top, 4)
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }

    // Aligned → green countdown ring; otherwise → red→green match ring.
    private var ring: some View {
        if guidance.isAligned {
            return MatchIndicatorView(
                progress: Float(holdProgress),
                color: .green,
                centerText: "hold"
            )
        } else {
            let pct = Int((guidance.matchScore * 100).rounded())
            return MatchIndicatorView(
                progress: guidance.matchScore,
                color: MatchIndicatorView.matchColor(guidance.matchScore),
                centerText: "\(pct)%"
            )
        }
    }
}

// MARK: - GuidanceArrow

// A large SF Symbol arrow that bounces in its direction. The bounce amplitude
// scales with the correction magnitude, so a big error animates more urgently.
// Directionless corrections (distance, roll, lighting) show no arrow — the text
// carries those.
private struct GuidanceArrow: View {
    let direction: ArrowDirection
    let magnitude: Float
    @State private var animate = false

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 84, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 6)
                    .offset(offset)
                    .animation(
                        .easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }

    private var symbol: String? {
        switch direction {
        case .up:    return "arrow.up"
        case .down:  return "arrow.down"
        case .left:  return "arrow.left"
        case .right: return "arrow.right"
        case .none:  return nil
        }
    }

    private var offset: CGSize {
        guard animate else { return .zero }
        // Clamp so even small errors give a visible nudge.
        let amp = CGFloat(max(0.25, min(1, magnitude))) * 26
        switch direction {
        case .up:    return CGSize(width: 0, height: -amp)
        case .down:  return CGSize(width: 0, height:  amp)
        case .left:  return CGSize(width: -amp, height: 0)
        case .right: return CGSize(width:  amp, height: 0)
        case .none:  return .zero
        }
    }
}

// MARK: - Helpers

extension String {
    // "Raise the camera" -> "raise the camera", for the "then …" hint.
    var lowercasedFirstLetter: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
