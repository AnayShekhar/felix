import SwiftUI
import PhotosUI

/// The liquid-glass chat bar that sits above the home page, under the Lumis
/// mark + transcript. A circular live-camera button to the left of a glass
/// capsule ("Talk to Lumis") whose leading "+" uploads a photo and whose
/// trailing arrow sends typed text.
struct ChatBarView: View {
    @EnvironmentObject private var vm: LumisViewModel

    /// Opens the full-screen live camera.
    var onCamera: () -> Void

    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                // Live camera — to the left of the chat bar.
                Button { Haptics.light(); onCamera() } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(LumisColors.textPrimary)
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular, in: Circle())
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open camera")

                // Chat capsule: + (photo) · field · send.
                HStack(spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(LumisColors.textPrimary)
                    }
                    .accessibilityLabel("Upload photo")

                    TextField("Talk to Lumis", text: $text)
                        .textFieldStyle(.plain)
                        .font(LumisTypography.bodyLarge)
                        .foregroundStyle(LumisColors.textPrimary)
                        .tint(LumisColors.tint)
                        .focused($focused)
                        .submitLabel(.send)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit(send)

                    if canSend {
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(LumisColors.onTint)
                                .frame(width: 32, height: 32)
                                .background(LumisColors.tint, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Send")
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, canSend ? 8 : 16)
                .frame(height: 56)
                .glassEffect(.regular, in: Capsule())
            }
        }
        .padding(.horizontal, 18)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: canSend)
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Haptics.medium()
        vm.send(image: nil, text: t)
        text = ""
        focused = false
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else { return }
            Haptics.medium()
            let caption = text.trimmingCharacters(in: .whitespacesAndNewlines)
            vm.send(image: image, text: caption)
            text = ""
            photoItem = nil
        }
    }
}
