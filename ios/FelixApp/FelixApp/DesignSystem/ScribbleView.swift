import SwiftUI

/// The four states expressed by the Felix signal orb.
enum FelixState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

/// Felix's living status instrument.
///
/// The mark is intentionally contained and stateful rather than decorative:
/// three soft contours make one recognizable object, while a state-specific
/// signal appears around it. Listening uses live radial voice bars, thinking
/// uses directional orbits, and speaking sends resolved waves outward.
struct ScribbleView: View {
    var state: FelixState = .idle
    var containerSize: CGFloat = 260
    var audioLevel: CGFloat = 0
    var dimmed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = SignalOrbClock()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                clock.tick(now: timeline.date.timeIntervalSinceReferenceDate,
                           state: state,
                           audioLevel: audioLevel,
                           frozen: reduceMotion)
                SignalOrbRenderer.draw(in: context,
                                       size: size,
                                       state: state,
                                       time: clock.time,
                                       energy: clock.energy,
                                       breathe: clock.breathe,
                                       surge: clock.surge)
            }
        }
        .frame(width: containerSize, height: containerSize)
        .opacity(dimmed ? 0.42 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: dimmed)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityText: String {
        switch state {
        case .idle: return "Felix is ready"
        case .listening: return "Felix is listening"
        case .thinking: return "Felix is thinking"
        case .speaking: return "Felix is responding"
        }
    }

    private var accessibilityValue: String {
        state == .listening ? "Voice level \(Int(audioLevel * 100)) percent" : ""
    }
}

/// Display-linked animation state. Values ease toward state targets so an
/// interrupted command changes direction naturally instead of snapping.
final class SignalOrbClock {
    private(set) var time: Double = 0
    private(set) var energy: Double = 0.12
    private(set) var breathe: Double = 1
    private(set) var surge: Double = 0

    private var lastTime: TimeInterval?
    private var lastState: FelixState = .idle
    private var smoothedAudio: Double = 0
    private var phase: Double = 0

    func tick(now: TimeInterval, state: FelixState, audioLevel: CGFloat, frozen: Bool) {
        guard !frozen else {
            lastTime = now
            time = 0
            energy = state == .idle ? 0.12 : 0.38
            breathe = 1
            surge = 0
            lastState = state
            return
        }

        let dt = min(max(now - (lastTime ?? now), 0), 1.0 / 20.0)
        lastTime = now
        phase += dt

        if state != lastState { surge = 1 }
        lastState = state
        surge = max(0, surge - dt * 1.8)

        let level = Double(min(max(audioLevel, 0), 1))
        let audioRate = level > smoothedAudio ? 18.0 : 5.0
        smoothedAudio += (level - smoothedAudio) * min(1, dt * audioRate)

        let target: Double
        switch state {
        case .idle: target = 0.12
        case .listening: target = 0.38 + smoothedAudio * 0.78
        case .thinking: target = 0.48
        case .speaking: target = 0.50 + 0.16 * sin(phase * 5.4)
        }
        let response = target > energy ? 14.0 : 6.0
        energy += (target - energy) * min(1, dt * response)
        time += dt * (state == .thinking ? 1.45 : 0.48 + energy * 0.72)

        let depth = state == .listening ? 0.035 : 0.018
        let speed = state == .thinking ? 1.35 : 0.82
        breathe = 1 + depth * sin(phase * speed)
    }
}

enum SignalOrbRenderer {
    private static let contourSegments = 72

    static func draw(in context: GraphicsContext,
                     size: CGSize,
                     state: FelixState,
                     time: Double,
                     energy: Double,
                     breathe: Double,
                     surge: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.285 * breathe
        let line = max(1.2, radius * 0.021)

        // A quiet field gives the animated geometry a stable silhouette.
        let fieldRadius = radius * 1.42
        let field = Path(ellipseIn: circle(center: center, radius: fieldRadius))
        context.fill(field, with: .color(FelixColors.tintSoft.opacity(0.42)))
        context.stroke(field,
                       with: .color(FelixColors.glassStroke.opacity(0.72)),
                       lineWidth: 0.75)

        // On a state change, one restrained acknowledgement ring confirms that
        // Felix heard the transition before the continuous signal takes over.
        if surge > 0.02 {
            let progress = 1 - surge
            let acknowledgement = Path(ellipseIn: circle(
                center: center,
                radius: fieldRadius * (1.02 + progress * 0.22)
            ))
            context.stroke(acknowledgement,
                           with: .color(FelixColors.tintStrong.opacity(surge * 0.42)),
                           lineWidth: line * (1.8 - progress))
        }

        drawStateSignal(in: context,
                        center: center,
                        radius: radius,
                        line: line,
                        state: state,
                        time: time,
                        energy: energy)

        // Three related contours make the mark feel alive without becoming a
        // nest of unrelated lines. Their phases are fixed, so Felix remains a
        // recognizable object at every point in the animation.
        for layer in 0..<3 {
            let layerScale = 1 - Double(layer) * 0.17
            let contour = organicContour(center: center,
                                         radius: radius * layerScale,
                                         time: time,
                                         energy: energy,
                                         layer: layer,
                                         state: state)
            if layer == 2 {
                context.fill(contour, with: .color(FelixColors.tintSoft.opacity(0.34)))
            }
            context.stroke(contour,
                           with: .color(FelixColors.tintStrong.opacity(0.92 - Double(layer) * 0.20)),
                           style: StrokeStyle(lineWidth: line * (1.20 - Double(layer) * 0.12),
                                              lineCap: .round,
                                              lineJoin: .round))
        }

        let coreRadius = max(3.5, radius * (0.065 + energy * 0.018))
        context.fill(Path(ellipseIn: circle(center: center, radius: coreRadius)),
                     with: .color(FelixColors.tintStrong))
    }

    private static func drawStateSignal(in context: GraphicsContext,
                                        center: CGPoint,
                                        radius: Double,
                                        line: Double,
                                        state: FelixState,
                                        time: Double,
                                        energy: Double) {
        switch state {
        case .idle:
            // Four anchor points read as calm readiness, not inactivity.
            for index in 0..<4 {
                let angle = Double(index) * .pi / 2 + time * 0.08
                let point = polar(center: center, radius: radius * 1.18, angle: angle)
                let dot = Path(ellipseIn: circle(center: point, radius: line * 1.15))
                context.fill(dot, with: .color(FelixColors.tintStrong.opacity(0.42)))
            }

        case .listening:
            // A circular voice meter responds to the live smoothed mic level.
            for index in 0..<20 {
                let angle = Double(index) / 20 * .pi * 2 - .pi / 2
                let cadence = 0.5 + 0.5 * sin(Double(index) * 1.73 + time * 3.2)
                let length = radius * (0.10 + cadence * (0.08 + energy * 0.12))
                let inner = polar(center: center, radius: radius * 1.18, angle: angle)
                let outer = polar(center: center, radius: radius * 1.18 + length, angle: angle)
                var bar = Path()
                bar.move(to: inner)
                bar.addLine(to: outer)
                context.stroke(bar,
                               with: .color(FelixColors.tintStrong.opacity(0.52 + cadence * 0.38)),
                               style: StrokeStyle(lineWidth: line * 1.25, lineCap: .round))
            }

        case .thinking:
            // Deliberately directional orbital tracks convey active processing.
            for orbit in 0..<3 {
                let angle = time * (orbit == 1 ? -0.85 : 0.72) + Double(orbit) * .pi / 3
                let path = orbitPath(center: center,
                                     major: radius * (1.30 + Double(orbit) * 0.06),
                                     minor: radius * (0.52 + Double(orbit) * 0.08),
                                     rotation: angle)
                context.stroke(path,
                               with: .color(FelixColors.tintStrong.opacity(0.24 + Double(orbit) * 0.11)),
                               style: StrokeStyle(lineWidth: line,
                                                  lineCap: .round,
                                                  dash: [line * 2.2, line * 5.4],
                                                  dashPhase: time * 10))
            }

        case .speaking:
            // Resolved information moves outward in clean, readable waves.
            for wave in 0..<3 {
                let phase = (time * 0.75 + Double(wave) / 3).truncatingRemainder(dividingBy: 1)
                let waveRadius = radius * (1.14 + phase * 0.48)
                let wavePath = Path(ellipseIn: circle(center: center, radius: waveRadius))
                context.stroke(wavePath,
                               with: .color(FelixColors.tintStrong.opacity((1 - phase) * 0.38)),
                               lineWidth: line)
            }
        }
    }

    private static func organicContour(center: CGPoint,
                                       radius: Double,
                                       time: Double,
                                       energy: Double,
                                       layer: Int,
                                       state: FelixState) -> Path {
        var path = Path()
        let layerPhase = Double(layer) * 2.17
        let motion = state == .thinking ? time * 1.35 : time * 0.58
        for segment in 0...contourSegments {
            let angle = Double(segment) / Double(contourSegments) * .pi * 2
            let primary = sin(angle * 3 + layerPhase + motion)
            let secondary = cos(angle * 2 - layerPhase + motion * 0.72)
            let distortion = 0.035 + energy * 0.045
            let localRadius = radius * (1 + primary * distortion + secondary * distortion * 0.52)
            let point = polar(center: center, radius: localRadius, angle: angle)
            if segment == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func orbitPath(center: CGPoint,
                                  major: Double,
                                  minor: Double,
                                  rotation: Double) -> Path {
        var path = Path()
        for segment in 0...contourSegments {
            let angle = Double(segment) / Double(contourSegments) * .pi * 2
            let x = cos(angle) * major
            let y = sin(angle) * minor
            let point = CGPoint(x: center.x + x * cos(rotation) - y * sin(rotation),
                                y: center.y + x * sin(rotation) + y * cos(rotation))
            if segment == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private static func polar(center: CGPoint, radius: Double, angle: Double) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius)
    }

    private static func circle(center: CGPoint, radius: Double) -> CGRect {
        CGRect(x: center.x - radius,
               y: center.y - radius,
               width: radius * 2,
               height: radius * 2)
    }
}

#if DEBUG
#Preview {
    struct Demo: View {
        @State private var state = FelixState.idle
        var body: some View {
            ZStack {
                FelixColors.background.ignoresSafeArea()
                VStack(spacing: FelixSpacing.xl) {
                    ScribbleView(state: state, containerSize: 240, audioLevel: 0.72)
                    Picker("Felix state", selection: $state) {
                        Text("Ready").tag(FelixState.idle)
                        Text("Listen").tag(FelixState.listening)
                        Text("Think").tag(FelixState.thinking)
                        Text("Speak").tag(FelixState.speaking)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, FelixSpacing.xl)
                }
            }
        }
    }
    return Demo()
}
#endif
