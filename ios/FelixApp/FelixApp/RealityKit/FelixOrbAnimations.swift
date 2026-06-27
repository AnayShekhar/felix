import Foundation
import RealityKit
import UIKit
import QuartzCore

/// The state that drives which animation the orb is playing. Set by the app
/// (SpeechRecognizer.phase + WebSocket activity) and consumed by the animator.
enum OrbState: Equatable {
    case idle          // alive but waiting
    case wake          // wake word detected — perks up
    case listening     // user is speaking — pulses with amplitude
    case thinking      // request sent, waiting for response
    case speaking      // Felix TTS playing back
    case camera        // capturing visual context
    case error         // something went wrong
}

/// Design tokens reused by the orb materials/animations. Mirrors Phase 3.
enum OrbPalette {
    static let primary = UIColor(red: 0.722, green: 0.851, blue: 1.0, alpha: 1.0)   // #B8D9FF
    static let error = UIColor(red: 1.0, green: 0.267, blue: 0.267, alpha: 1.0)     // #FF4444
}

/// Drives all orb animations frame-by-frame on a display link. Transforms the
/// orb container (scale, float, spin) and nudges material emissive/tint — never
/// the mesh. State transitions are smoothed so they never feel jarring: target
/// values are eased toward each frame rather than snapped.
@MainActor
final class FelixOrbAnimator {
    /// Current state. Setting it kicks off transient impulses (wake/error).
    var state: OrbState = .idle {
        didSet { if state != oldValue { onStateChange(to: state) } }
    }

    /// 0…1 voice amplitude, supplied by VoiceAmplitudeTracker during listening.
    var amplitudeProvider: () -> Float = { 0 }

    weak var entity: Entity?
    weak var material: FelixOrbMaterialController?

    private var link: CADisplayLink?
    private var elapsed: TimeInterval = 0
    private var lastTimestamp: CFTimeInterval = 0

    // Smoothed live values.
    private var scale: Float = 1.0
    private var emissive: Float = 0.75
    private var spin: Float = 0
    private var tilt: Float = 0           // transient horizontal shake (error)
    private var impulse: Float = 0        // transient scale bump (wake / speaking word)

    // Eased base-color tint (RGB) so ERROR returns to idle color over ~1s rather
    // than snapping. Starts at the moonstone primary.
    private var tint = FelixOrbAnimator.rgb(OrbPalette.primary)
    private var targetTint = FelixOrbAnimator.rgb(OrbPalette.primary)

    // Last values pushed to the material, to avoid rebuilding it when nothing
    // meaningfully changed (keeps the 60fps target comfortable).
    private var lastEmissive: Float = -1
    private var lastTint = SIMD3<Float>(repeating: -1)

    // MARK: - Lifecycle

    func start() {
        guard link == nil else { return }
        lastTimestamp = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// Manually pulse the orb on a TTS word boundary (Phase 4 SPEAKING).
    func pulse(_ amount: Float = 0.03) {
        impulse = max(impulse, amount)
    }

    // MARK: - State transitions

    private func onStateChange(to state: OrbState) {
        switch state {
        case .wake:
            // Spring up to ~1.12 (target 1.05 + impulse 0.07) then settle to 1.05.
            impulse = 0.07
            targetTint = Self.rgb(OrbPalette.primary)
        case .error:
            tilt = 1.0                              // single horizontal shake, decays
            tint = Self.rgb(OrbPalette.error)       // snap red now…
            targetTint = Self.rgb(OrbPalette.primary) // …then ease back to primary over ~1s
        case .idle, .listening, .thinking, .speaking, .camera:
            targetTint = Self.rgb(OrbPalette.primary)
        }
    }

    /// Extract linear RGB from a UIColor for frame-by-frame easing.
    private static func rgb(_ color: UIColor) -> SIMD3<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3<Float>(Float(r), Float(g), Float(b))
    }

    // MARK: - Frame loop

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = Float(min(now - lastTimestamp, 1.0 / 20.0))  // clamp big gaps
        lastTimestamp = now
        elapsed += TimeInterval(dt)

        let amp = max(0, min(amplitudeProvider(), 1))
        updateTargets(dt: dt, amplitude: amp)
        applyToEntity(dt: dt)
    }

    /// Per-state target scale/emissive + continuous spin.
    private func updateTargets(dt: Float, amplitude amp: Float) {
        let t = Float(elapsed)

        // Decay transients.
        impulse *= powf(0.001, dt)        // fast settle
        tilt *= powf(0.0005, dt)

        var targetScale: Float = 1.0
        var targetEmissive: Float = 0.75
        var spinSpeed: Float = 0.25       // rad/s, gentle idle spin

        switch state {
        case .idle:
            // Breathing emissive 0.6–0.9 over 3s; float handled in applyToEntity.
            targetEmissive = 0.75 + 0.15 * sinf(t * (2 * .pi / 3))
            targetScale = 1.0
            spinSpeed = 0.25
        case .wake:
            targetScale = 1.05
            targetEmissive = 1.1
            spinSpeed = 0.25
        case .listening:
            targetScale = 1.0 + 0.08 * amp
            targetEmissive = 0.85 + 0.6 * amp
            spinSpeed = 0.2
        case .thinking:
            targetScale = 1.0
            targetEmissive = 0.95
            spinSpeed = 1.4                // faster continuous rotation
        case .speaking:
            targetScale = 1.0
            targetEmissive = 0.9 + 0.2 * sinf(t * 6)
            spinSpeed = 0.3
        case .camera:
            targetScale = 0.92
            targetEmissive = 0.9
            spinSpeed = 0.4
        case .error:
            targetScale = 1.0
            targetEmissive = 0.9
            spinSpeed = 0.0
        }

        // Ease live values toward targets so transitions are smooth.
        let k: Float = 1 - powf(0.02, dt)
        scale += (targetScale - scale) * k
        emissive += (targetEmissive - emissive) * k
        spin += spinSpeed * dt

        // Tint eases with a ~1s time constant (ERROR red → primary).
        let tintK: Float = 1 - powf(0.018, dt)
        tint += (targetTint - tint) * tintK
    }

    private func applyToEntity(dt: Float) {
        guard let entity else { return }
        let t = Float(elapsed)

        // Slow float: ±0.012m over ~4s (idle/speaking/listening feel alive).
        let floats: Set<OrbState> = [.idle, .speaking, .listening]
        let floatY = floats.contains(state) ? 0.012 * sinf(t * (2 * .pi / 4)) : 0

        // Transient horizontal shake for ERROR.
        let shakeX = tilt * 0.02 * sinf(t * 40)

        entity.position = SIMD3<Float>(shakeX, floatY, 0)
        entity.orientation = simd_quatf(angle: spin, axis: SIMD3<Float>(0, 1, 0))

        // Scale = eased base + transient impulse (wake spring / per-word pulse).
        entity.scale = SIMD3<Float>(repeating: scale + impulse)

        applyMaterial(emissive: emissive + impulse * 2)
    }

    /// Push emissive + tint to the material, but only when they changed enough to
    /// matter — avoids rebuilding the PhysicallyBasedMaterial every single frame.
    private func applyMaterial(emissive value: Float) {
        let emissiveChanged = abs(value - lastEmissive) > 0.01
        let tintChanged = simd_length(tint - lastTint) > 0.004
        guard emissiveChanged || tintChanged else { return }
        lastEmissive = value
        lastTint = tint
        let color = UIColor(red: CGFloat(tint.x), green: CGFloat(tint.y),
                            blue: CGFloat(tint.z), alpha: 1)
        material?.update(emissiveIntensity: value, tint: color)
    }
}
