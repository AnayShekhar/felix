import SwiftUI

/// Rounded input with an animated floating label, a Powder-Blue focus border,
/// and an optional show/hide toggle for secure entry. 52pt tall, 14pt radius.
struct FloatingLabelField: View {
    let title: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool
    @State private var reveal = false

    private var floated: Bool { focused || !text.isEmpty }

    var body: some View {
        ZStack(alignment: .leading) {
            // Floating label.
            Text(title)
                .font(floated ? LumisTypography.caption : LumisTypography.bodyMedium)
                .foregroundStyle(focused ? LumisColors.powderBlue : LumisColors.textSecondary)
                .offset(y: floated ? -20 : 0)
                .animation(.easeInOut(duration: 0.18), value: floated)
                .allowsHitTesting(false)

            HStack(spacing: 8) {
                Group {
                    if isSecure && !reveal {
                        SecureField("", text: $text)
                    } else {
                        TextField("", text: $text)
                    }
                }
                .font(LumisTypography.bodyLarge)
                .foregroundStyle(LumisColors.carbonBlack)
                .tint(LumisColors.powderBlue)
                .focused($focused)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(isSecure || keyboard == .emailAddress ? .never : .sentences)
                .autocorrectionDisabled(isSecure || keyboard == .emailAddress)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)

                if isSecure {
                    Button {
                        reveal.toggle()
                    } label: {
                        Image(systemName: reveal ? "eye.slash" : "eye")
                            .foregroundStyle(LumisColors.textSecondary)
                    }
                    .accessibilityLabel(reveal ? "Hide password" : "Show password")
                }
            }
            .padding(.top, floated ? 10 : 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(LumisColors.parchment)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(focused ? LumisColors.powderBlue : LumisColors.divider,
                        lineWidth: focused ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.18), value: focused)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}
