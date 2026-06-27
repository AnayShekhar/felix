import SwiftUI
import RealityKit

/// Transparent RealityView hosting the Moonstone orb, sized to a fixed ~220pt
/// frame so it renders as a small 3D sphere (≈180pt) rather than filling the
/// screen. The #070B12 background and the Phase 5 glow live behind it in
/// ContentView and show through the clear RealityView background.
struct FelixOrbView: View {
    /// Drives which animation plays. Set by ContentView from speech + websocket.
    var state: OrbState
    /// Live mic amplitude for the LISTENING/SPEAKING pulses.
    @ObservedObject var amplitude: VoiceAmplitudeTracker
    /// Increments on each TTS word boundary to pulse the orb (Phase 4 SPEAKING).
    var pulseToken: Int = 0

    /// On-screen size of the orb's RealityView. Caps the orb so it can never fill
    /// the screen; the sphere fills ~80% of this frame.
    static let frameSize: CGFloat = 220

    @StateObject private var manager = FelixOrbManager()
    // Driven imperatively (not observed); @State keeps one instance across renders.
    @State private var animator = FelixOrbAnimator()

    var body: some View {
        RealityView { content in
            content.add(makeCamera())
            for light in makeLights() { content.add(light) }

            await manager.loadIfNeeded()
            if let orb = manager.root {
                content.add(orb)
                animator.entity = orb
                animator.material = manager.material
                animator.amplitudeProvider = { [weak amplitude] in amplitude?.amplitude ?? 0 }
                animator.state = state
                animator.start()
            }
        } update: { _ in
            // Update in place — never recreate entities on state change.
            if animator.state != state { animator.state = state }
        }
        .onChange(of: pulseToken) { _, _ in animator.pulse(0.03) }
        .frame(width: Self.frameSize, height: Self.frameSize)
        .background(Color.clear)
        .onDisappear { animator.stop() }
        .overlay(alignment: .bottom) {
            if case .fallback = manager.loadState {
                Text("Using fallback orb")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .offset(y: 18)
            }
        }
    }

    // MARK: - Scene rig

    /// Camera distance is tuned so the 0.20m orb projects to ~180pt inside the
    /// 220pt frame (≈80% fill). distance ≈ diameter / (2·tan(fov/2)·fill).
    private func makeCamera() -> Entity {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 30
        let position = SIMD3<Float>(0, 0, 0.48)
        camera.position = position
        camera.look(at: .zero, from: position, relativeTo: nil)
        return camera
    }

    /// A 3-light rig so the sphere reads as 3D, not flat:
    ///  • key: directional from the top-left at ~45°
    ///  • ambient fill: a dim directional from the camera to lift shadows
    ///    (RealityKit has no ambient-light entity, so this approximates one)
    ///  • rim: a point light behind the orb for an edge highlight
    private func makeLights() -> [Entity] {
        let key = DirectionalLight()
        key.light.intensity = 6500
        key.light.color = .init(white: 1, alpha: 1)
        key.look(at: .zero, from: SIMD3<Float>(-1, 1, 0.6), relativeTo: nil)

        let ambient = DirectionalLight()
        ambient.light.intensity = 1200
        ambient.light.color = .init(white: 1, alpha: 1)
        ambient.look(at: .zero, from: SIMD3<Float>(0, 0.2, 1), relativeTo: nil)

        let rim = PointLight()
        rim.light.intensity = 14000
        rim.light.attenuationRadius = 2
        rim.light.color = OrbPalette.primary
        rim.position = SIMD3<Float>(0.25, 0.25, -0.45)   // behind the sphere

        return [key, ambient, rim]
    }
}
