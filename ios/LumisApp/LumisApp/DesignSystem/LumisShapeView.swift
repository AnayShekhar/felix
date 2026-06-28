import SwiftUI

/// The four states the Lumis shape can express. Drives bloom speed/amplitude,
/// rotation speed, opacity, and the listening ripple emitter.
enum LumisState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

/// The animated Lumis mark: six Powder-Blue petal circles blooming around a
/// white inner glow, the whole group rotating continuously. Standalone and
/// reusable at any size (Home = 260, Splash/empty states = 80–120).
struct LumisShapeView: View {
    var state: LumisState = .idle
    var containerSize: CGFloat = 260
    /// When the linked Mac is offline the shape dims and the bloom pauses.
    var dimmed: Bool = false

    // One bloom phase per petal (0 = compressed at center, 1 = full bloom).
    @State private var bloom: [CGFloat] = Array(repeating: 0.5, count: 6)
    @State private var rotation: Double = 0
    @State private var ripples: [UUID] = []
    @State private var rippleTimer: Timer?

    private let petalCount = 6
    private let phaseDelays: [Double] = [0.0, 0.08, 0.16, 0.24, 0.32, 0.40]

    // Per-state tuning: bloom duration (0 = paused), bloom amplitude,
    // rotation duration, base opacity.
    private var tuning: (bloomDuration: Double, amplitude: CGFloat, rotationDuration: Double, opacity: Double) {
        switch state {
        case .idle:      return (2.5, 1.00, 8.0, 1.0)
        case .listening: return (1.2, 1.15, 5.0, 1.0)
        case .thinking:  return (0.0, 0.50, 12.0, 0.9)
        case .speaking:  return (0.8, 1.25, 3.5, 1.0)
        }
    }

    private var petalDiameter: CGFloat { containerSize * 0.45 }
    private var baseOffset: CGFloat { containerSize * 0.28 }

    var body: some View {
        ZStack {
            // Listening ripple rings (under the petals).
            ForEach(ripples, id: \.self) { id in
                RippleRing(startDiameter: 60, endDiameter: 180)
                    .id(id)
            }

            // Rotating petal group.
            ZStack {
                ForEach(0..<petalCount, id: \.self) { i in
                    petal(index: i)
                }
                // Inner glow — soft luminous core at the exact center.
                Circle()
                    .fill(Color.white)
                    .frame(width: 44, height: 44)
                    .blur(radius: 14)
                    .opacity(0.9)
            }
            .rotationEffect(.degrees(rotation))
        }
        .frame(width: containerSize, height: containerSize)
        .opacity(dimmed ? 0.6 : tuning.opacity)
        .animation(.easeInOut(duration: 0.6), value: state)
        .animation(.easeInOut(duration: 0.6), value: dimmed)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .onAppear {
            startRotation()
            startBloom()
            updateRipples()
        }
        .onChange(of: state) { _, _ in
            startRotation()
            startBloom()
            updateRipples()
        }
        .onChange(of: dimmed) { _, _ in
            startBloom()
        }
        .onDisappear {
            rippleTimer?.invalidate()
            rippleTimer = nil
        }
    }

    // MARK: - Petals

    private func petal(index i: Int) -> some View {
        let angle = Double(i) / Double(petalCount) * 2 * .pi
        let distance = baseOffset * bloom[i]
        // Translucent powder-blue petals layer with normal alpha so overlaps
        // deepen into the bloom on the light Parchment background. (`.screen`,
        // from the original dark-theme spec, washes out on Parchment.)
        return Circle()
            .fill(LumisColors.powderBlue)
            .frame(width: petalDiameter, height: petalDiameter)
            .opacity(0.55)
            .blendMode(.multiply)
            .offset(x: CGFloat(cos(angle)) * distance,
                    y: CGFloat(sin(angle)) * distance)
    }

    // MARK: - Animation drivers

    private func startRotation() {
        // Reset then drive a continuous linear spin. Because a 360° rotation is
        // visually identical to 0°, restarting on state change is seamless.
        rotation = 0
        withAnimation(.linear(duration: tuning.rotationDuration).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }

    private func startBloom() {
        let t = tuning
        if dimmed || t.bloomDuration == 0 {
            // Thinking / offline: freeze the petals mid-bloom (no repeat).
            withAnimation(.easeInOut(duration: 0.6)) {
                for i in 0..<petalCount { bloom[i] = t.amplitude }
            }
            return
        }
        let compressed = t.amplitude * 0.18
        let expanded = t.amplitude
        for i in 0..<petalCount {
            bloom[i] = compressed
            withAnimation(
                .easeInOut(duration: t.bloomDuration)
                    .repeatForever(autoreverses: true)
                    .delay(phaseDelays[i])
            ) {
                bloom[i] = expanded
            }
        }
    }

    private func updateRipples() {
        rippleTimer?.invalidate()
        rippleTimer = nil
        guard state == .listening, !dimmed else {
            ripples.removeAll()
            return
        }
        emitRipple()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { _ in
            Task { @MainActor in emitRipple() }
        }
        rippleTimer = timer
    }

    private func emitRipple() {
        let id = UUID()
        ripples.append(id)
        // Each ring lives ~1.8s; drop it after it has fully expanded/faded.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            ripples.removeAll { $0 == id }
        }
        // Keep at most 3 rings on screen.
        if ripples.count > 3 { ripples.removeFirst(ripples.count - 3) }
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

/// A single expanding/fading ring used by the listening state.
private struct RippleRing: View {
    let startDiameter: CGFloat
    let endDiameter: CGFloat
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(LumisColors.powderBlue, lineWidth: 1.5)
            .frame(width: animate ? endDiameter : startDiameter,
                   height: animate ? endDiameter : startDiameter)
            .opacity(animate ? 0 : 0.4)
            .onAppear {
                withAnimation(.easeOut(duration: 1.8)) { animate = true }
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
