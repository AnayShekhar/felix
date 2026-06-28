import SwiftUI

/// Phase 5 — the soft radial glow the orb casts on the background. Pure SwiftUI
/// (layered behind the RealityView, never a RealityKit effect) so it can react
/// to `OrbState` and live amplitude. Sits over the #070B12 background.
struct LumisGlowView: View {
    var state: OrbState
    @ObservedObject var amplitude: VoiceAmplitudeTracker
    /// Vertical position of the orb (matches LumisOrbView framing, ~40% from top).
    var centerYFraction: CGFloat = 0.4

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2,
                                     y: geo.size.height * centerYFraction)
                let p = params(t: t)
                Circle()
                    .fill(fillStyle(for: p, t: t))
                    .frame(width: p.radius * 2, height: p.radius * 2)
                    .position(center)
                    .blur(radius: 70)
                    .opacity(p.opacity)
                    .animation(.easeInOut(duration: 0.5), value: state)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Per-state parameters

    private struct GlowParams {
        var radius: CGFloat
        var opacity: Double
        var color: Color
        var angular: Bool   // THINKING uses a rotating angular gradient
    }

    private func params(t: TimeInterval) -> GlowParams {
        let glow = LumisColor.orbGlow
        switch state {
        case .idle:
            return .init(radius: 180, opacity: 0.15, color: glow, angular: false)
        case .wake:
            return .init(radius: 220, opacity: 0.25, color: glow, angular: false)
        case .listening:
            let amp = CGFloat(min(max(amplitude.amplitude, 0), 1))
            return .init(radius: 200 + amp * 80,            // 200–280pt
                         opacity: 0.20 + Double(amp) * 0.15, // 20–35%
                         color: glow, angular: false)
        case .thinking:
            return .init(radius: 220, opacity: 0.20, color: glow, angular: true)
        case .speaking:
            let pulse = (sin(t * 6) + 1) / 2                 // 0…1 with speech rhythm
            return .init(radius: 200 + pulse * 40,
                         opacity: 0.18 + pulse * 0.12,
                         color: glow, angular: false)
        case .camera:
            return .init(radius: 200, opacity: 0.18, color: glow, angular: false)
        case .error:
            return .init(radius: 220, opacity: 0.30, color: LumisColor.error, angular: false)
        }
    }

    // MARK: - Fills

    private func fillStyle(for p: GlowParams, t: TimeInterval) -> AnyShapeStyle {
        if p.angular {
            // Slowly rotating conic glow — implies processing.
            return AnyShapeStyle(AngularGradient(
                gradient: Gradient(colors: [
                    p.color.opacity(0), p.color.opacity(0.9),
                    p.color.opacity(0), p.color.opacity(0.5),
                    p.color.opacity(0),
                ]),
                center: .center,
                angle: .degrees(t.truncatingRemainder(dividingBy: 12) / 12 * 360)
            ))
        } else {
            return AnyShapeStyle(RadialGradient(
                gradient: Gradient(colors: [p.color, p.color.opacity(0)]),
                center: .center, startRadius: 0, endRadius: p.radius
            ))
        }
    }
}
