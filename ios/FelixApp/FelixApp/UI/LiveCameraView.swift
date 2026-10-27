import SwiftUI

/// Full-screen live camera, reached from the text bar's "+". No scribble here
/// — just the live feed with a small liquid-glass "listening" pill near the
/// top. Speaking while this is open resolves into the exact same panel stack
/// as the voice-first path (the spoken command is sent with the current
/// frame); the shutter alone sends just the frame.
struct LiveCameraView: View {
    @EnvironmentObject private var vm: FelixViewModel

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
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.felixPress)
                    .felixGlass(in: Circle(), interactive: true)
                    .accessibilityLabel("Close camera")

                    Spacer()
                }
                .padding(.horizontal, FelixSpacing.screenMargin)
                .padding(.top, FelixSpacing.md)
                .overlay(ListeningPill())

                Spacer()

                // Shutter in the brand's language: the tint ring and fill of
                // the home mic button, not a stock white circle.
                Button(action: shutter) {
                    ZStack {
                        Circle().stroke(FelixColors.tint, lineWidth: 2)
                            .frame(width: 78, height: 78)
                        Circle().fill(FelixColors.tint).frame(width: 64, height: 64)
                            .scaleEffect(capturing ? 0.85 : 1)
                        Image(systemName: "camera")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(FelixColors.onTint)
                    }
                }
                .buttonStyle(.felixPress)
                .disabled(capturing)
                .padding(.bottom, 54)
                .accessibilityLabel("Capture and send")
            }
        }
        .onAppear {
            vm.camera.start()
            // A spoken command while the camera is open includes this frame,
            // so the camera path resolves into the same panel stack.
            vm.cameraFrameProvider = { [weak vm] in await vm?.camera.capturePhoto() }
        }
        .onDisappear {
            vm.cameraFrameProvider = nil
            vm.camera.stop()
        }
        // A request began (spoken or captured) — return home to its panels.
        .onChange(of: vm.currentChat?.id) { _, id in
            if id != nil { onClose() }
        }
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

/// The frosted "listening" pill near the top of the camera view — the
/// platform's translucent glass material, quietly pulsing while Felix hears
/// the user's voice.
private struct ListeningPill: View {
    @EnvironmentObject private var vm: FelixViewModel

    private var hearing: Bool { vm.felixState == .listening }

    var body: some View {
        HStack(spacing: FelixSpacing.sm) {
            Image(systemName: hearing ? "waveform" : "mic")
                .font(.footnote.weight(.medium))
                .foregroundStyle(FelixColors.tint)
                .symbolEffect(.variableColor.iterative, isActive: hearing)

            Text(hearing ? "Listening" : "Say \u{201C}Hey Felix\u{201D}")
                .font(FelixTypography.captionMedium)
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.opacity)
        }
        .padding(.horizontal, FelixSpacing.lg)
        .frame(height: 36)
        .felixGlass(in: Capsule())
        .animation(.easeInOut(duration: 0.3), value: hearing)
        .accessibilityLabel(hearing ? "Felix is listening" : "Felix is waiting for the wake word")
    }
}
