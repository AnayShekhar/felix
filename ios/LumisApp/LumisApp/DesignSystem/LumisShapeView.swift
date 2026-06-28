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
/// ring. `.multiply` on the light Parchment background makes the overlaps read
/// as deeper blue, giving depth and contrast.
///
/// The mark expresses the current `state`:
///   • idle      — slow continuous rotation, petals calm and even.
///   • listening — rotation freezes; petals resize to the live mic level, like
///                 an equalizer reacting to the voice (`audioLevel`).
///   • thinking  — slow rotation resumes; petals pulse gently at staggered phases.
///   • speaking  — faster rotation; petals pulse energetically.
///
/// Honors Reduce Motion: when enabled the mark is static (no rotation/pulse).
struct LumisShapeView: View {
    var state: LumisState = .idle
    var containerSize: CGFloat = 260
    /// Live mic level (0…1). Only used in `.listening`.
    var audioLevel: CGFloat = 0
    /// When the linked Mac is offline the mark dims.
    var dimmed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let petalCount = 6
    // Staggered (duration, delay) per petal for the gentle thinking pulse.
    private let pulseParams: [(duration: Double, delay: Double)] = [
        (2.1, 0.00), (1.9, 0.30), (2.3, 0.60),
        (2.0, 0.90), (2.2, 0.45), (1.8, 0.75),
    ]

    @State private var scales: [CGFloat] = Array(repeating: 1.0, count: 6)
    @State private var rotation: Double = 0
    @State private var rotationTimer: Timer?
    @State private var pulseTimer: Timer?
    @State private var speakingPhase: Double = 0

    private var diameter: CGFloat { containerSize * 0.46 }
    private var ringRadius: CGFloat { containerSize * 0.22 }

    var body: some View {
        ZStack {
            ForEach(0..<petalCount, id: \.self) { i in
                petal(i)
            }
        }
        .frame(width: containerSize, height: containerSize)
        .rotationEffect(.degrees(rotation))
        .opacity(dimmed ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.5), value: dimmed)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .onAppear { apply(state) }
        .onDisappear(perform: stopAll)
        .onChange(of: state) { _, newState in apply(newState) }
        .onChange(of: audioLevel) { _, level in
            guard state == .listening, !reduceMotion else { return }
            updatePetalsForAudio(level)
        }
    }

    @ViewBuilder
    private func petal(_ i: Int) -> some View {
        let angle = Double(i) / Double(petalCount) * 2 * .pi
        let x = CGFloat(cos(angle)) * ringRadius
        let y = CGFloat(sin(angle)) * ringRadius
        Circle()
            .fill(LumisColors.powderBlue)
            .opacity(0.7)
            .frame(width: diameter, height: diameter)
            .scaleEffect(scales[i])
            .blendMode(.multiply)
            .offset(x: x, y: y)
    }

    // MARK: - State application

    private func apply(_ newState: LumisState) {
        stopAll()
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.3)) { scales = Array(repeating: 1.0, count: petalCount) }
            return
        }
        switch newState {
        case .idle:      startIdle()
        case .listening: startListening()
        case .thinking:  startThinking()
        case .speaking:  startSpeaking()
        }
    }

    // IDLE — slow rotation, petals calm and even.
    private func startIdle() {
        withAnimation(.easeInOut(duration: 0.4)) { scales = Array(repeating: 1.0, count: petalCount) }
        startRotation(secondsPerRevolution: 9)
    }

    // LISTENING — rotation frozen; petals driven by mic level via onChange.
    private func startListening() {
        withAnimation(.easeOut(duration: 0.25)) { scales = Array(repeating: 1.0, count: petalCount) }
        // No rotation timer — the wheel holds wherever it is.
    }

    private func updatePetalsForAudio(_ level: CGFloat) {
        for i in 0..<petalCount {
            let variance = CGFloat.random(in: 0.85...1.15)
            withAnimation(.easeOut(duration: 0.08)) {
                scales[i] = 1.0 + (level * 0.6 * variance)
            }
        }
    }

    // THINKING — slow rotation + gentle staggered pulse. The stagger is baked
    // into each petal's animation `.delay`, so there are no pending closures to
    // fire after we've left the state.
    private func startThinking() {
        startRotation(secondsPerRevolution: 14)
        for i in 0..<petalCount {
            let p = pulseParams[i]
            scales[i] = 1.0
            withAnimation(.easeInOut(duration: p.duration)
                .repeatForever(autoreverses: true).delay(p.delay)) {
                scales[i] = i % 2 == 0 ? 0.88 : 1.12
            }
        }
    }

    // SPEAKING — faster rotation + energetic sine-driven pulse.
    private func startSpeaking() {
        startRotation(secondsPerRevolution: 4)
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            speakingPhase += 0.3
            for i in 0..<petalCount {
                let offset = Double(i) * (.pi / 3.0)
                let scale = 1.0 + CGFloat(sin(speakingPhase + offset)) * 0.28
                withAnimation(.easeOut(duration: 0.05)) { scales[i] = scale }
            }
        }
    }

    // MARK: - Rotation driver

    private func startRotation(secondsPerRevolution: Double) {
        let step = 360.0 / (secondsPerRevolution * 60.0)
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            rotation += step
            if rotation >= 360 { rotation -= 360 }
        }
    }

    private func stopAll() {
        rotationTimer?.invalidate(); rotationTimer = nil
        pulseTimer?.invalidate(); pulseTimer = nil
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
