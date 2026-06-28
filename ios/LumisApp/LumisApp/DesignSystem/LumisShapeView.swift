import SwiftUI

/// The four states the Lumis mark can express (drives the surrounding UI text;
/// the mark itself breathes continuously in every state).
enum LumisState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

/// The animated Lumis mark — six overlapping Powder-Blue circles in a petal
/// ring. Each petal pulses at its own rhythm (independent scale) while the whole
/// wheel rotates slowly. `.multiply` on the light Parchment background makes the
/// overlaps read as deeper blue, giving depth and contrast.
///
/// All animations are started exactly once (in `onAppear`) and never restarted,
/// so the wheel can't drift, stack, or speed up.
struct LumisShapeView: View {
    var state: LumisState = .idle
    var containerSize: CGFloat = 260
    /// When the linked Mac is offline the mark dims.
    var dimmed: Bool = false

    private let petalCount = 6
    // Per-circle (duration, delay) — each petal breathes at its own rhythm.
    private let params: [(duration: Double, delay: Double)] = [
        (2.1, 0.00), (1.9, 0.30), (2.3, 0.60),
        (2.0, 0.90), (2.2, 0.45), (1.8, 0.75),
    ]

    @State private var scales: [CGFloat] = Array(repeating: 1.0, count: 6)
    @State private var rotation: Double = 0
    @State private var started = false

    private var diameter: CGFloat { containerSize * 0.46 }
    private var ringRadius: CGFloat { containerSize * 0.22 }

    var body: some View {
        ZStack {
            ForEach(0..<petalCount, id: \.self) { i in
                let angle = Double(i) / Double(petalCount) * 2 * .pi
                Circle()
                    .fill(LumisColors.powderBlue)
                    .opacity(0.7)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(scales[i])
                    .blendMode(.multiply)
                    .offset(x: CGFloat(cos(angle)) * ringRadius,
                            y: CGFloat(sin(angle)) * ringRadius)
            }
        }
        .frame(width: containerSize, height: containerSize)
        .rotationEffect(.degrees(rotation))
        .opacity(dimmed ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.5), value: dimmed)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .onAppear(perform: startIfNeeded)
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true

        // Whole wheel: one slow continuous rotation.
        withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
            rotation = 360
        }

        // Each petal: independent pulse between 0.85 and 1.15.
        for i in 0..<petalCount {
            scales[i] = 0.85
            withAnimation(
                .easeInOut(duration: params[i].duration)
                    .repeatForever(autoreverses: true)
                    .delay(params[i].delay)
            ) {
                scales[i] = 1.15
            }
        }
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

#Preview {
    struct Demo: View {
        @State private var state: LumisState = .idle
        var body: some View {
            ZStack {
                LumisColors.parchment.ignoresSafeArea()
                VStack(spacing: 40) {
                    LumisShapeView(state: state, containerSize: 260)
                    Picker("State", selection: $state) {
                        Text("Idle").tag(LumisState.idle)
                        Text("Listening").tag(LumisState.listening)
                        Text("Thinking").tag(LumisState.thinking)
                        Text("Speaking").tag(LumisState.speaking)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 32)
                }
            }
        }
    }
    return Demo()
}
