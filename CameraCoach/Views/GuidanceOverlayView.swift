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
    let autoCapturing: Bool     // is auto-capture enabled (drives aligned ring)
    var onCapture: () -> Void   // tapping the ring captures

    var body: some View {
        VStack {
            Spacer()

            // Directional arrow while correcting. When aligned the center is
            // kept clear so the subject stays fully visible.
            if !guidance.isAligned {
                GuidanceArrow(direction: guidance.arrowDirection,
                              magnitude: guidance.arrowMagnitude)
                    .frame(height: 110)
            }

            Spacer()

            // Bottom: message + the ring, which doubles as the shutter button.
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

                Button(action: onCapture) {
                    ring.frame(width: 96, height: 96)
                }
                .buttonStyle(ShutterPressStyle())
                .padding(.top, 4)
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }

    // Ring states:
    //   aligned + auto-capture on  → green countdown ring ("hold")
    //   aligned + auto-capture off → full green ring ("shoot" — tap the shutter)
    //   not aligned                → red→green match ring (match %)
    private var ring: some View {
        if guidance.isAligned {
            return MatchIndicatorView(
                progress: autoCapturing ? Float(holdProgress) : 1.0,
                color: .green,
                centerText: autoCapturing ? "hold" : "shoot"
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

// MARK: - Shutter press style

// Gives the ring-as-shutter a tactile press: scales down and dims briefly.
struct ShutterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
