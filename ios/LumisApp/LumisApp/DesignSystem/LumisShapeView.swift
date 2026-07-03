import SwiftUI

/// The four states the Lumis mark can express (drives the surrounding UI text;
/// the mark itself breathes continuously in every state).
enum LumisState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

/// The animated Lumis mark — eight translucent, elongated petals radiating
/// from a soft glowing center. Each petal fades from more opaque at the hub to
/// transparent at the tip, and the overlaps blend (multiply on light, additive
/// on dark) so crossings visually deepen — the layered "frosted glass" look of
/// the reference frames, recolored in the tint.
///
/// The mark expresses the current `state`:
///   • idle      — slow continuous rotation, petals calm and even.
///   • listening — rotation freezes; each petal resizes independently to the
///                 live mic level (`audioLevel`), like the shape reacting to
///                 the voice.
///   • thinking  — rotation resumes slower than idle; gentle staggered pulse,
///                 each petal slightly out of phase.
///   • speaking  — rotation faster than idle; energetic simulated speech
///                 envelope, petals lively.
///
/// Rendering is a single `Canvas` inside `TimelineView(.animation)`, so every
/// frame is display-refresh-synced — no `Timer`, and no per-frame `@State`
/// writes churning SwiftUI. Honors Reduce Motion (static mark).
struct LumisShapeView: View {
    var state: LumisState = .idle
    var containerSize: CGFloat = 260
    /// Live mic level (0…1). Only used in `.listening`.
    var audioLevel: CGFloat = 0
    /// Dim the mark (e.g. while disconnected).
    var dimmed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Per-instance animation clock (reference type — mutated during draw,
    /// which is what keeps rotation continuous across state changes).
    @State private var clock = LumisShapeClock()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                clock.tick(now: timeline.date.timeIntervalSinceReferenceDate,
                           state: state,
                           audioLevel: audioLevel,
                           frozen: reduceMotion)
                LumisShapeRenderer.draw(
                    in: context, size: size,
                    angle: clock.angle, scales: clock.scales,
                    darkMode: colorScheme == .dark
                )
            }
        }
        .frame(width: containerSize, height: containerSize)
        .opacity(dimmed ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.5), value: dimmed)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch state {
        case .idle:      return "Lumis is idle"
        case .listening: return "Lumis is listening"
        case .thinking:  return "Lumis is thinking"
        case .speaking:  return "Lumis is speaking"
        }
    }
}

/// Frame-to-frame animation state. Advanced once per display frame from the
/// TimelineView; everything is smoothed toward per-state targets so state
/// changes glide instead of snapping.
final class LumisShapeClock {
    static let petalCount = 8

    private(set) var angle: Double = 0                 // radians
    private(set) var scales = [Double](repeating: 1, count: LumisShapeClock.petalCount)

    private var lastTime: TimeInterval?
    private var angularSpeed: Double = LumisShapeClock.idleSpeed
    private var smoothedAudio: Double = 0

    // Radians/second: idle 1 rev / 9s, thinking 1 rev / 14s, speaking 1 rev / 4s.
    private static let idleSpeed     = 2 * Double.pi / 9
    private static let thinkingSpeed = 2 * Double.pi / 14
    private static let speakingSpeed = 2 * Double.pi / 4

    // Stagger for the thinking pulse — deliberately irregular per petal.
    private static let pulseFrequency: [Double] = [0.48, 0.55, 0.42, 0.60, 0.45, 0.52, 0.58, 0.44]
    private static let pulsePhase: [Double] = [0, 1.3, 2.9, 4.1, 0.7, 2.2, 3.6, 5.0]

    func tick(now: TimeInterval, state: LumisState, audioLevel: CGFloat, frozen: Bool) {
        guard !frozen else {
            lastTime = now
            scales = .init(repeating: 1, count: Self.petalCount)
            return
        }
        let dt = min(max(now - (lastTime ?? now), 0), 1.0 / 20.0)  // clamp hiccups
        lastTime = now

        // Ease the angular speed toward the state's target so rotation speeds
        // shift organically (and hold position while listening).
        let targetSpeed: Double
        switch state {
        case .idle:      targetSpeed = Self.idleSpeed
        case .listening: targetSpeed = 0
        case .thinking:  targetSpeed = Self.thinkingSpeed
        case .speaking:  targetSpeed = Self.speakingSpeed
        }
        angularSpeed += (targetSpeed - angularSpeed) * min(1, dt * 4)
        angle = (angle + angularSpeed * dt).truncatingRemainder(dividingBy: 2 * .pi)

        // Smooth the mic level (attack faster than release, like a meter).
        let level = Double(min(max(audioLevel, 0), 1))
        let audioRate = level > smoothedAudio ? 18.0 : 6.0
        smoothedAudio += (level - smoothedAudio) * min(1, dt * audioRate)

        for i in 0..<Self.petalCount {
            let target: Double
            switch state {
            case .idle:
                target = 1
            case .listening:
                // Each petal reacts to the same voice with its own drifting
                // variance, so the response feels organic, not uniform.
                let variance = 0.85 + 0.3 * (0.5 + 0.5 * sin(now * (1.9 + Double(i) * 0.23) + Self.pulsePhase[i]))
                target = 1 + smoothedAudio * 0.6 * variance
            case .thinking:
                target = 1 + 0.11 * sin(now * 2 * .pi * Self.pulseFrequency[i] + Self.pulsePhase[i])
            case .speaking:
                // Simulated speech envelope: syllable-rate wobble modulated by
                // a slower phrase envelope (no per-frame randomness = smooth).
                let phrase = 0.55 + 0.45 * (0.5 + 0.5 * sin(now * 1.7 + Double(i)))
                target = 1 + 0.26 * phrase * sin(now * 7.5 + Self.pulsePhase[i])
            }
            let rate = state == .listening ? 14.0 : 6.0
            scales[i] += (target - scales[i]) * min(1, dt * rate)
        }
    }
}

/// Pure drawing of the petal cluster into a `GraphicsContext`.
enum LumisShapeRenderer {
    static func draw(in context: GraphicsContext, size: CGSize,
                     angle: Double, scales: [Double], darkMode: Bool) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let unit = min(size.width, size.height)

        // Soft blurred glow at the hub — tint at partial opacity, no hard dot.
        var glow = context
        glow.addFilter(.blur(radius: unit * 0.045))
        glow.fill(
            Path(ellipseIn: CGRect(x: center.x - unit * 0.13, y: center.y - unit * 0.13,
                                   width: unit * 0.26, height: unit * 0.26)),
            with: .radialGradient(
                Gradient(colors: [LumisColors.tint.opacity(darkMode ? 0.9 : 0.8),
                                  LumisColors.tint.opacity(0)]),
                center: center, startRadius: 0, endRadius: unit * 0.14
            )
        )

        // Petals: multiply deepens overlaps on a light background; additive
        // (plusLighter) brightens them on dark — both read as layered glass.
        var petals = context
        petals.blendMode = darkMode ? .plusLighter : .multiply

        let count = LumisShapeClock.petalCount
        let innerOffset = unit * 0.05        // petal root sits just off center
        let baseLength = unit * 0.40         // radial reach of a petal at scale 1
        let baseWidth = unit * 0.26          // petal thickness at scale 1

        for i in 0..<count {
            let petalAngle = angle + Double(i) / Double(count) * 2 * .pi
            let scale = scales.indices.contains(i) ? scales[i] : 1
            let length = baseLength * scale
            let width = baseWidth * (0.85 + 0.15 * scale)

            let dir = CGPoint(x: cos(petalAngle), y: sin(petalAngle))
            let mid = CGPoint(x: center.x + dir.x * (innerOffset + length / 2),
                              y: center.y + dir.y * (innerOffset + length / 2))
            let root = CGPoint(x: center.x + dir.x * innerOffset,
                               y: center.y + dir.y * innerOffset)
            let tip = CGPoint(x: center.x + dir.x * (innerOffset + length),
                              y: center.y + dir.y * (innerOffset + length))

            // Elongated rounded petal, drawn axis-aligned then rotated into place.
            let rect = CGRect(x: mid.x - length / 2, y: mid.y - width / 2,
                              width: length, height: width)
            let path = Path(roundedRect: rect, cornerRadius: width / 2)
                .applying(rotation(around: mid, by: petalAngle))

            // Frosted gradient: more opaque at the hub, dissolving at the tip.
            petals.fill(path, with: .linearGradient(
                Gradient(stops: [
                    .init(color: LumisColors.tint.opacity(0.62), location: 0),
                    .init(color: LumisColors.tint.opacity(0.34), location: 0.55),
                    .init(color: LumisColors.tint.opacity(0.10), location: 1),
                ]),
                startPoint: root, endPoint: tip
            ))
        }
    }

    private static func rotation(around pivot: CGPoint, by radians: Double) -> CGAffineTransform {
        CGAffineTransform(translationX: pivot.x, y: pivot.y)
            .rotated(by: radians)
            .translatedBy(x: -pivot.x, y: -pivot.y)
    }
}

#Preview {
    struct Demo: View {
        @State private var state: LumisState = .idle
        @State private var fakeLevel: CGFloat = 0.5
        var body: some View {
            ZStack {
                LumisColors.background.ignoresSafeArea()
                VStack(spacing: 40) {
                    LumisShapeView(state: state, containerSize: 260, audioLevel: fakeLevel)
                    Picker("State", selection: $state) {
                        Text("Idle").tag(LumisState.idle)
                        Text("Listening").tag(LumisState.listening)
                        Text("Thinking").tag(LumisState.thinking)
                        Text("Speaking").tag(LumisState.speaking)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 32)
                    if state == .listening {
                        Slider(value: $fakeLevel, in: 0...1)
                            .padding(.horizontal, 32)
                    }
                }
            }
        }
    }
    return Demo()
}
