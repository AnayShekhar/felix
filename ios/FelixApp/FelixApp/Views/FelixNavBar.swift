import SwiftUI
import UIKit

/// Phase 6 — the two floating icon buttons that replace the tab bar. Camera on
/// the left (manual camera trigger), history on the right (slide-up sheet).
/// 44×44 tap targets, no labels, 48pt from the bottom safe area. Settings lives
/// on a long-press of the orb (handled in ContentView), not here.
struct FelixNavBar: View {
    var cameraActive: Bool
    var historyActive: Bool
    let onCamera: () -> Void
    let onHistory: () -> Void

    var body: some View {
        HStack {
            FloatingIconButton(symbol: "camera.fill", active: cameraActive, action: onCamera)
            Spacer()
            FloatingIconButton(symbol: "clock.fill", active: historyActive, action: onHistory)
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, alignment: .bottom)
    }
}

/// A single 44×44 icon button — white at 60% when inactive, Moonstone at 100%
/// when active.
struct FloatingIconButton: View {
    let symbol: String
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(active ? FelixColor.orbPrimary : Color.white.opacity(0.6))
                .frame(width: 44, height: 44)
                .frostedCard(cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: active)
    }
}
