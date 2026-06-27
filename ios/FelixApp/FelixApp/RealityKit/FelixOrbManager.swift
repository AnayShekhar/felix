import Foundation
import RealityKit
import Combine
import UIKit

/// Loads and owns the Moonstone orb entity hierarchy.
///
/// The model ships at `Models/moonstone.usdc` (bundled with the app). We load it
/// once, wrap it in a container we fully control (so animations transform the
/// container while the model keeps its authored transform), normalize its size to
/// a fixed world diameter, and expose the result. If the USD can't load we fall
/// back to a frosted-glass sphere so the orb is never missing. All entity
/// lifecycle lives here; nothing else creates or destroys the orb.
@MainActor
final class FelixOrbManager: ObservableObject {
    enum LoadState: Equatable { case idle, loading, ready, fallback(String) }

    /// The container entity added to the RealityView scene. Animations transform
    /// this; the model (or fallback sphere) is its child.
    @Published private(set) var root: Entity?
    @Published private(set) var loadState: LoadState = .idle

    /// Controls material properties (emissive, opacity, tint) so the orb feels
    /// alive through material changes, not geometry deformation.
    private(set) var material: FelixOrbMaterialController?

    /// Fixed world diameter of the orb in meters. The camera (FelixOrbView) is
    /// framed around this so it renders at ~180pt on screen.
    static let diameter: Float = 0.20

    private var loaded = false

    /// Load the moonstone model once. Safe to call repeatedly (no-op when ready).
    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        loadState = .loading

        let container = Entity()
        container.name = "felix.orb.container"

        do {
            let model = try await loadModelEntity()
            normalize(model)
            container.addChild(model)
            print("🟢 Felix orb: moonstone.usdc loaded successfully.")
            loadState = .ready
        } catch {
            // Fall back to a frosted-glass sphere so the orb is never missing.
            print("🔴 Felix orb: moonstone.usdc FAILED to load — \(error.localizedDescription). Using fallback sphere.")
            container.addChild(makeFallbackSphere())
            loadState = .fallback(error.localizedDescription)
        }

        root = container
        material = FelixOrbMaterialController(root: container)
    }

    /// Load moonstone.usdc from the app bundle as a RealityKit entity.
    private func loadModelEntity() async throws -> Entity {
        guard let url = Bundle.main.url(forResource: "moonstone", withExtension: "usdc")
                ?? Bundle.main.url(forResource: "moonstone", withExtension: "usdz") else {
            print("🔴 Felix orb: moonstone.usdc not found in bundle.")
            throw OrbError.modelMissing
        }
        print("🔵 Felix orb: loading model from \(url.lastPathComponent)…")
        return try await Entity(contentsOf: url)
    }

    /// Scale the model to `diameter` and recenter it on its bounding box so it
    /// pivots about its own middle and frames consistently.
    private func normalize(_ model: Entity) {
        let extents = model.visualBounds(relativeTo: nil).extents
        let maxDim = max(extents.x, max(extents.y, extents.z))
        if maxDim > 0 {
            model.scale = SIMD3<Float>(repeating: Self.diameter / maxDim)
        }
        let center = model.visualBounds(relativeTo: nil).center
        model.position -= center
    }

    /// Fallback: a frosted-glass sphere (baseColor #B8D9FF, roughness 0.1,
    /// metallic 0.3, transparent 0.85) — looks like moonstone, not a flat disc.
    private func makeFallbackSphere() -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: Self.diameter / 2)
        var pbr = PhysicallyBasedMaterial()
        pbr.baseColor = .init(tint: UIColor(red: 0.722, green: 0.851, blue: 1.0, alpha: 1.0))
        pbr.roughness = .init(floatLiteral: 0.1)
        pbr.metallic = .init(floatLiteral: 0.3)
        pbr.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        return ModelEntity(mesh: mesh, materials: [pbr])
    }

    enum OrbError: LocalizedError {
        case modelMissing
        var errorDescription: String? {
            switch self {
            case .modelMissing: return "Moonstone model not found in the app bundle."
            }
        }
    }
}
