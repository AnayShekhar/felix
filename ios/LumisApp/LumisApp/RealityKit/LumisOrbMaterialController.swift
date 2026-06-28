import Foundation
import RealityKit
import UIKit

/// Controls the orb's material so animation states can make it feel alive through
/// material changes — emissive glow, opacity, roughness, and a base-color tint —
/// rather than deforming geometry.
///
/// It collects every `ModelEntity` under the orb root and re-applies a controlled
/// `PhysicallyBasedMaterial` built from the current tunable values. Values are
/// cached so changing one (e.g. emissive intensity each frame) preserves the
/// others.
@MainActor
final class LumisOrbMaterialController {
    private weak var root: Entity?
    private var targets: [ModelEntity] = []

    // Tunable state. The orb is frosted-glass moonstone — low roughness, light
    // metallic, slightly transparent — so it reads as a lit 3D sphere, NOT a flat
    // self-lit disc. Emissive is a faint inner glow only (see `apply`).
    private var emissiveIntensity: Float = 0.75
    private var opacity: Float = 0.85
    private var roughness: Float = 0.1
    private var metallic: Float = 0.3
    private var tint: UIColor = UIColor(red: 0.722, green: 0.851, blue: 1.0, alpha: 1.0) // #B8D9FF

    /// Emissive is scaled way down so lighting — not self-illumination — defines
    /// the form. Without this the sphere looks like a flat glowing circle.
    private let emissiveScale: Float = 0.18

    init(root: Entity) {
        self.root = root
        collect(root)
        apply()
    }

    private func collect(_ entity: Entity) {
        if let model = entity as? ModelEntity, model.model != nil {
            targets.append(model)
        }
        for child in entity.children { collect(child) }
    }

    // MARK: - Public knobs (used by LumisOrbAnimations)

    func setEmissiveIntensity(_ value: Float) {
        emissiveIntensity = max(0, value)
        apply()
    }

    func setOpacity(_ value: Float) {
        opacity = min(max(value, 0), 1)
        apply()
    }

    func setRoughness(_ value: Float) {
        roughness = min(max(value, 0), 1)
        apply()
    }

    func setBaseColorTint(_ color: UIColor) {
        tint = color
        apply()
    }

    /// Set several properties at once (one material rebuild instead of several).
    func update(emissiveIntensity: Float? = nil,
                opacity: Float? = nil,
                roughness: Float? = nil,
                tint: UIColor? = nil) {
        if let v = emissiveIntensity { self.emissiveIntensity = max(0, v) }
        if let v = opacity { self.opacity = min(max(v, 0), 1) }
        if let v = roughness { self.roughness = min(max(v, 0), 1) }
        if let v = tint { self.tint = v }
        apply()
    }

    // MARK: - Material application

    private func apply() {
        var pbr = PhysicallyBasedMaterial()
        pbr.baseColor = .init(tint: tint)
        pbr.roughness = .init(floatLiteral: roughness)
        pbr.metallic = .init(floatLiteral: metallic)
        pbr.emissiveColor = .init(color: tint)
        pbr.emissiveIntensity = emissiveIntensity * emissiveScale  // faint inner glow
        pbr.blending = opacity < 1.0
            ? .transparent(opacity: .init(floatLiteral: opacity))
            : .opaque

        for model in targets {
            guard var component = model.model else { continue }
            component.materials = component.materials.map { _ in pbr }
            model.model = component
        }
    }
}
