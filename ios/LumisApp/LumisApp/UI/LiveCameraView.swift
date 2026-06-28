import SwiftUI

/// Full-screen live camera. A single shutter captures the frame, sends it
/// straight to Lumis, and the view dismisses back to Home. No review step.
struct LiveCameraView: View {
    @EnvironmentObject private var vm: LumisViewModel

    /// Called with the captured image; the parent sends it and dismisses.
    var onCapture: (UIImage) -> Void
    var onClose: () -> Void

    @State private var capturing = false
    @State private var flash = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: vm.camera.session).ignoresSafeArea()

            if flash { Color.white.ignoresSafeArea().transition(.opacity) }

            VStack {
                HStack {
                    Button { Haptics.light(); onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular, in: Circle())
                    .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close camera")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                Button(action: shutter) {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                        Circle().fill(.white).frame(width: 62, height: 62)
                            .scaleEffect(capturing ? 0.85 : 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(capturing)
                .padding(.bottom, 54)
                .accessibilityLabel("Capture and send")
            }
        }
        .onAppear { vm.camera.start() }
        .onDisappear { vm.camera.stop() }
    }

    private func shutter() {
        guard !capturing else { return }
        capturing = true
        Haptics.medium()
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        Task {
            let image = await vm.camera.capturePhoto()
            withAnimation(.easeIn(duration: 0.15)) { flash = false }
            if let image {
                onCapture(image)   // parent sends + dismisses
            } else {
                capturing = false
            }
        }
    }
}
