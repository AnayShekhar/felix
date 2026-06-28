import SwiftUI

/// Full-screen "enter the 6-digit code shown on your Mac" modal. Six individual
/// boxes that auto-advance; shake + message on failure; checkmark on success.
struct MacCodeEntryView: View {
    @EnvironmentObject private var macVM: MacConnectionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var shake = false
    @State private var failed = false
    @State private var helpExpanded = false
    @State private var succeeded = false
    @FocusState private var focused: Bool

    private let slots = 6

    var body: some View {
        ZStack {
            LumisColors.parchment.ignoresSafeArea()
            if succeeded {
                SuccessCheckmark(title: "Connected to \(macVM.macName ?? "your Mac")")
            } else {
                content
            }
        }
        .overlay(alignment: .topLeading) {
            if !succeeded {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LumisColors.carbonBlack)
                        .padding(16)
                }
                .accessibilityLabel("Close")
            }
        }
    }

    private var content: some View {
        VStack(spacing: 24) {
            Spacer()
            LumisShapeView(state: .idle, containerSize: 96)
            Text("Connect your Mac")
                .font(LumisTypography.titleLarge)
                .foregroundStyle(LumisColors.carbonBlack)
            Text("Enter the 6-digit code shown on your Mac.")
                .font(LumisTypography.bodyMedium)
                .foregroundStyle(LumisColors.textSecondary)
                .multilineTextAlignment(.center)

            boxes
                .modifier(ShakeEffect(animatableData: shake ? 1 : 0))

            if failed {
                Text("Invalid or expired code. Try again.")
                    .font(LumisTypography.caption)
                    .foregroundStyle(LumisColors.destructive)
            }

            helpSection

            Spacer()

            LumisPrimaryButton(title: "Connect",
                               loading: macVM.connectionState == .linking,
                               enabled: code.count == slots, action: submit)
                .padding(.horizontal, 32)
        }
        .padding(.bottom, 32)
    }

    private var boxes: some View {
        ZStack {
            // Hidden field that actually captures input.
            TextField("", text: $code)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focused)
                .opacity(0.01)
                .frame(width: 1, height: 1)
                .onChange(of: code) { _, newValue in
                    code = String(newValue.uppercased().prefix(slots))
                        .filter { $0.isLetter || $0.isNumber }
                    failed = false
                    if code.count == slots { submit() }
                }

            HStack(spacing: 10) {
                ForEach(0..<slots, id: \.self) { i in
                    box(at: i)
                }
            }
            .onTapGesture { focused = true }
        }
        .onAppear { focused = true }
    }

    private func box(at index: Int) -> some View {
        let chars = Array(code)
        let char = index < chars.count ? String(chars[index]) : ""
        let isCursor = index == code.count
        return Text(char)
            .font(.system(size: 24, weight: .semibold, design: .monospaced))
            .foregroundStyle(LumisColors.carbonBlack)
            .frame(width: 48, height: 56)
            .background(LumisColors.parchment)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCursor && focused ? LumisColors.powderBlue : LumisColors.divider,
                            lineWidth: isCursor && focused ? 1.5 : 1)
            )
    }

    private var helpSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation { helpExpanded.toggle() }
            } label: {
                Text("Where do I find the code?")
                    .font(LumisTypography.bodySmall)
                    .foregroundStyle(LumisColors.powderBlue)
            }
            if helpExpanded {
                Text("Open the Lumis app on your Mac and keep it running. It shows a 6-character code in a window — type that code here.")
                    .font(LumisTypography.caption)
                    .foregroundStyle(LumisColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
    }

    private func submit() {
        guard code.count == slots else { return }
        Task {
            let ok = await macVM.pair(code: code)
            if ok {
                withAnimation(.spring) { succeeded = true }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                dismiss()
            } else {
                failed = true
                withAnimation(.default) { shake.toggle() }
                code = ""
            }
        }
    }
}

/// Horizontal shake used for the invalid-code feedback.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 10 * sin(animatableData * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

/// Reused success state: animated checkmark + title.
struct SuccessCheckmark: View {
    let title: String
    @State private var pop = false
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(LumisColors.powderBlueLight).frame(width: 96, height: 96)
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(LumisColors.success)
                    .scaleEffect(pop ? 1 : 0.3)
                    .opacity(pop ? 1 : 0)
            }
            Text(title)
                .font(LumisTypography.titleMedium)
                .foregroundStyle(LumisColors.carbonBlack)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { pop = true } }
    }
}
