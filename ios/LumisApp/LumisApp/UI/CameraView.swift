import SwiftUI
import PhotosUI

/// Full-screen manual camera. Frame something, capture, add a spoken/typed
/// command, and send the image + text to Lumis. Nothing is sent automatically.
struct CameraView: View {
    @EnvironmentObject private var vm: LumisViewModel

    @State private var captured: UIImage?
    @State private var flash = false
    @State private var flashOn = false
    @State private var commandText = ""
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let captured {
                Image(uiImage: captured)
                    .resizable().scaledToFill()
                    .ignoresSafeArea()
                    .overlay(Rectangle().stroke(LumisColors.powderBlue, lineWidth: 3).ignoresSafeArea())
            } else {
                CameraPreview(session: vm.camera.session).ignoresSafeArea()
                GeometryReader { geo in
                    CornerBrackets()
                        .padding(.horizontal, geo.size.width * 0.15)
                        .padding(.vertical, geo.size.height * 0.15)
                }
                .ignoresSafeArea()
            }

            if flash { Color.white.opacity(0.8).ignoresSafeArea() }

            VStack {
                topBar
                Spacer()
                bottomPanel
            }
        }
        .onAppear { vm.camera.start() }
        .onDisappear { vm.camera.stop() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .top) {
            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close camera")

            Spacer()

            Button { flashOn.toggle() } label: {
                Image(systemName: flashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(flashOn ? "Flash on" : "Flash off")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            if captured == nil {
                Text("Frame what you want Lumis to see, then tap")
                    .font(LumisTypography.bodySmall)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                capturedControls
            }

            HStack {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 22)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Choose from library")
                .opacity(captured == nil ? 1 : 0)

                Spacer()

                if captured == nil {
                    Button { capture() } label: {
                        Circle().fill(.white)
                            .frame(width: 64, height: 64)
                            .overlay(Circle().stroke(LumisColors.carbonBlack, lineWidth: 2).padding(3))
                    }
                    .accessibilityLabel("Capture")
                } else {
                    Button { send() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(LumisColors.carbonBlack)
                            .frame(width: 64, height: 64)
                            .background(LumisColors.powderBlue, in: Circle())
                    }
                    .accessibilityLabel("Send to Lumis")
                }

                Spacer()

                // Balance the library button on the left.
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 28)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(.ultraThinMaterial)
        .onChange(of: photoItem) { _, item in loadPickedPhoto(item) }
    }

    private var capturedControls: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Tell Lumis what to do with this…", text: $commandText)
                    .font(LumisTypography.bodyMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Actions

    private func capture() {
        Haptics.medium()
        Task {
            let image = await vm.camera.capturePhoto()
            withAnimation(.easeOut(duration: 0.08)) { flash = true }
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation { flash = false }
            captured = image
        }
    }

    private func send() {
        vm.send(image: captured, text: commandText)
        close()
    }

    private func close() {
        vm.closeCamera()
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                captured = image
            }
        }
    }
}

/// Four Powder-Blue viewfinder corner brackets.
private struct CornerBrackets: View {
    var body: some View {
        GeometryReader { geo in
            ForEach(0..<4, id: \.self) { i in
                Bracket()
                    .stroke(LumisColors.powderBlue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(Double(i) * 90))
                    .position(position(for: i, in: geo.size))
            }
        }
    }

    private func position(for corner: Int, in size: CGSize) -> CGPoint {
        switch corner {
        case 0: return CGPoint(x: 12, y: 12)
        case 1: return CGPoint(x: size.width - 12, y: 12)
        case 2: return CGPoint(x: size.width - 12, y: size.height - 12)
        default: return CGPoint(x: 12, y: size.height - 12)
        }
    }

    private struct Bracket: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return p
        }
    }
}
