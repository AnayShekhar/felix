import SwiftUI

/// The states the Lumis mark can express (drives the surrounding UI text;
/// the mark itself keeps a continuous idle drift in every state).
enum LumisState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

/// The Lumis mark: a hand-drawn tangle of continuous line work — overlapping
/// freeform loops forming a rough sphere, all stroked paths, no fill. The
/// feeling is a confident single pen stroke, not a chaotic mess.
///
/// State expression:
///   • idle      — gentle, slow drift; lines redraw and resettle, never frozen.
///   • listening — unmistakably awake. Entering the state fires a fast surge
///                 (an energy spike plus an expanding activation ring) so the
///                 wake word reads as a decisive pop, never a subtle drift.
///                 While listening the tangle holds a visibly higher baseline
///                 of motion — clearly "attentive" even in silence — and rides
///                 the live mic level (`audioLevel`) on top, so the shape
///                 keeps answering the user's voice for the whole utterance.
///   • thinking  — a touch more energy than idle, slow steady swirl.
///   • speaking  — lively simulated envelope (used on splash/auth only).
///
/// Rendering is a single `Canvas` inside `TimelineView(.animation)` — every
/// frame is display-refresh-synced (ProMotion-friendly), no `Timer`, and no
/// per-frame `@State` writes churning SwiftUI. The per-loop constants are
/// computed once; each frame only evaluates cheap sinusoids. Honors Reduce
/// Motion (static mark).
struct ScribbleView: View {
    var state: LumisState = .idle
    var containerSize: CGFloat = 260
    /// Live mic level (0…1). Only used in `.listening`.
    var audioLevel: CGFloat = 0
    /// Dim the mark (e.g. while disconnected).
    var dimmed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Per-instance animation clock (reference type — mutated during draw so
    /// motion stays continuous across state changes without invalidating SwiftUI).
    @State private var clock = ScribbleClock()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                clock.tick(now: timeline.date.timeIntervalSinceReferenceDate,
                           state: state,
                           audioLevel: audioLevel,
                           frozen: reduceMotion)
                ScribbleRenderer.draw(in: context, size: size,
                                      time: clock.time,
                                      energy: clock.energy,
                                      breathe: clock.breathe,
                                      surge: clock.surge)
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
        case .idle:      return "Lumis is ready"
        case .listening: return "Lumis is listening"
        case .thinking:  return "Lumis is thinking"
        case .speaking:  return "Lumis is speaking"
        }
    }
}

/// Frame-to-frame animation state. Advanced once per display frame from the
/// TimelineView; everything is smoothed toward per-state targets so state
/// changes glide instead of snapping.
final class ScribbleClock {
    /// Warped time driving the loop drift — runs faster when energetic.
    private(set) var time: Double = 0
    /// 0 (calm idle) … 1+ (loud speech) — scales wobble amplitude.
    private(set) var energy: Double = 0
    /// Slow whole-shape breathing scale, ~±2%.
    private(set) var breathe: Double = 1
    /// Wake-word activation burst: jumps to 1 the instant listening begins and
    /// decays over ~0.7s — drives the expanding ring and the energy spike that
    /// make the transition read as one decisive event.
    private(set) var surge: Double = 0

    private var lastTime: TimeInterval?
    private var lastState: LumisState = .idle
    private var smoothedAudio: Double = 0
    private var phase: Double = 0

    func tick(now: TimeInterval, state: LumisState, audioLevel: CGFloat, frozen: Bool) {
        guard !frozen else {
            lastTime = now
            time = 0; energy = 0; breathe = 1; surge = 0
            lastState = state
            return
        }
        let dt = min(max(now - (lastTime ?? now), 0), 1.0 / 20.0)  // clamp hiccups
        lastTime = now
        phase += dt

        // The moment the wake word lands, fire the activation burst.
        if state == .listening && lastState != .listening { surge = 1 }
        lastState = state
        surge = max(0, surge - dt * 1.5)   // ~0.7s decay

        // Smooth the mic level like a meter: fast attack, slower release.
        let level = Double(min(max(audioLevel, 0), 1))
        let audioRate = level > smoothedAudio ? 16.0 : 5.0
        smoothedAudio += (level - smoothedAudio) * min(1, dt * audioRate)

        // Per-state target energy. Listening holds a high, clearly-awake floor
        // with a slow attentive swell (visible even in total silence) and rides
        // the live voice on top; the surge stacks a further spike at activation.
        let targetEnergy: Double
        switch state {
        case .idle:      targetEnergy = 0.14
        case .listening: targetEnergy = 0.55 + 0.10 * sin(phase * 2.6)
                                      + smoothedAudio * 1.2 + surge * 0.8
        case .thinking:  targetEnergy = 0.34
        case .speaking:  targetEnergy = 0.55 + 0.25 * sin(phase * 5.1)
        }
        // Fast attack, slower release: waking up is abrupt and confident;
        // settling back down is calm.
        let rate = targetEnergy > energy ? 16.0 : 6.0
        energy += (targetEnergy - energy) * min(1, dt * rate)

        // Time warps with energy so louder speech visibly quickens the lines.
        time += dt * (0.35 + energy * 1.6)
        // Listening breathes deeper — the whole mark visibly swells with attention.
        let breatheDepth = state == .listening ? 0.035 : 0.02
        breathe = 1 + breatheDepth * sin(phase * (state == .listening ? 1.6 : 0.9))
    }
}

/// Pure drawing of the line tangle into a `GraphicsContext`.
enum ScribbleRenderer {
    /// One scribbled loop: a wobbly, squashed ellipse at a fixed orientation.
    /// All constants are seeded once so the tangle is stable frame to frame.
    private struct Loop {
        let orientation: Double     // rotation of the squashed loop
        let eccentricity: Double    // 0.35…0.9 — how flattened the loop is
        let radius: Double          // base radius as a fraction of the mark
        let wobbleSeed: Double      // phase offset for the hand wobble
        let wobbleFreq: Double      // how many wobbles around the loop
        let driftSpeed: Double      // how fast this loop's wobble drifts
        let width: Double           // stroke width multiplier
        let alpha: Double           // stroke opacity
    }

    /// 12 loops, hand-tuned (seeded pseudo-random) so density reads as one
    /// confident tangle at UI sizes without turning to noise when small.
    private static let loops: [Loop] = {
        var result: [Loop] = []
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rand() -> Double {   // deterministic xorshift — stable across runs
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 100_000) / 100_000
        }
        for i in 0..<12 {
            result.append(Loop(
                orientation: rand() * .pi * 2,
                eccentricity: 0.38 + rand() * 0.5,
                radius: 0.62 + rand() * 0.3,
                wobbleSeed: rand() * .pi * 2,
                wobbleFreq: 2 + Double(i % 3),
                driftSpeed: 0.5 + rand() * 0.9,
                width: 0.8 + rand() * 0.5,
                alpha: 0.6 + rand() * 0.4
            ))
        }
        return result
    }()

    private static let segments = 40   // points per loop — smooth, still cheap

    static func draw(in context: GraphicsContext, size: CGSize,
                     time: Double, energy: Double, breathe: Double,
                     surge: Double = 0) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let unit = min(size.width, size.height) / 2 * 0.86 * breathe
        // Base stroke scales with the render size so the tangle reads cleanly
        // both as the 220pt hero and the 80pt splash mark. Energy thickens the
        // line — an awake mark is visibly bolder, not just faster.
        let baseStroke = max(1.2, unit * 0.016) * (1 + energy * 0.35)

        // Wake-word activation ring: a single crisp circle bursting outward
        // from the tangle and fading — the "it heard you" moment, legible
        // even in peripheral vision.
        if surge > 0.02 {
            let progress = 1 - surge                       // 0 → 1 as it decays
            let ringRadius = unit * (1.02 + progress * 0.55)
            let ring = Path(ellipseIn: CGRect(x: center.x - ringRadius,
                                              y: center.y - ringRadius,
                                              width: ringRadius * 2,
                                              height: ringRadius * 2))
            context.stroke(
                ring,
                with: .color(LumisColors.tintStrong.opacity(surge * 0.65)),
                style: StrokeStyle(lineWidth: baseStroke * (1.6 - progress),
                                   lineCap: .round)
            )
        }

        for loop in loops {
            var path = Path()
            let cosO = cos(loop.orientation + time * 0.05 * loop.driftSpeed)
            let sinO = sin(loop.orientation + time * 0.05 * loop.driftSpeed)

            for s in 0...segments {
                let t = Double(s) / Double(segments) * 2 * .pi
                // Hand wobble: two drifting harmonics on the radius. Energy
                // raises the amplitude — voice visibly tightens/loosens lines.
                let wobble =
                    (0.05 + 0.10 * energy) * sin(t * loop.wobbleFreq + loop.wobbleSeed + time * loop.driftSpeed) +
                    (0.03 + 0.06 * energy) * sin(t * (loop.wobbleFreq + 3) - time * loop.driftSpeed * 1.7)
                let r = unit * loop.radius * (1 + wobble)

                // Squashed loop in local space, then rotated into place.
                let lx = cos(t) * r
                let ly = sin(t) * r * loop.eccentricity
                let point = CGPoint(x: center.x + lx * cosO - ly * sinO,
                                    y: center.y + lx * sinO + ly * cosO)
                if s == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()

            // tintStrong, not raw tint: Cool Steel on Alabaster is too faint
            // to read as deliberate — the deepened/lifted accent holds the
            // line confidently on both backgrounds.
            context.stroke(
                path,
                with: .color(LumisColors.tintStrong.opacity(loop.alpha)),
                style: StrokeStyle(lineWidth: baseStroke * loop.width,
                                   lineCap: .round, lineJoin: .round)
            )
        }
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
                    ScribbleView(state: state, containerSize: 240, audioLevel: fakeLevel)
                    Picker("State", selection: $state) {
                        Text("Idle").tag(LumisState.idle)
                        Text("Listening").tag(LumisState.listening)
                        Text("Thinking").tag(LumisState.thinking)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 32)
                    if state == .listening {
                        Slider(value: $fakeLevel, in: 0...1).padding(.horizontal, 32)
                    }
                }
            }
        }
    }
    return Demo()
}
