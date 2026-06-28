import SwiftUI

/// Liquid Glass surfaces for the macOS app.
///
/// Per the project decision, we keep the macOS 14 deployment floor: on
/// macOS 26+ we use the genuine native `.glassEffect`; below that we fall back
/// to `.ultraThinMaterial`, which reads as a close approximation.
extension View {
    /// A static glass surface clipped to `shape` (cards, panels, the popover).
    @ViewBuilder
    func lumisGlass(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// An interactive glass surface for buttons (adds the press response on 26+).
    @ViewBuilder
    func lumisGlassButton(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
