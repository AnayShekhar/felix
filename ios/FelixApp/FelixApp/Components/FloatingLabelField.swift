import SwiftUI

/// Rounded input with a floating label and native glass depth. The field keeps
/// the same quiet surface in both appearances; only focus earns the slate-blue
/// ring so the form never becomes a collection of outlined boxes.
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
                .font(floated ? FelixTypography.caption : FelixTypography.bodyMedium)
                .foregroundStyle(focused ? FelixColors.tintStrong : FelixColors.textSecondary)
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
                .font(FelixTypography.bodyLarge)
                .foregroundStyle(FelixColors.textPrimary)
                .tint(FelixColors.tint)
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
                            .foregroundStyle(FelixColors.textSecondary)
                    }
                    .accessibilityLabel(reveal ? "Hide password" : "Show password")
                }
            }
            .padding(.top, floated ? 10 : 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(FelixColors.surface, in: FelixRadius.rect(FelixRadius.lg))
        .felixGlass(in: FelixRadius.rect(FelixRadius.lg), interactive: true)
        .overlay(
            FelixRadius.rect(FelixRadius.lg)
                .stroke(focused ? FelixColors.tint : FelixColors.divider,
                        lineWidth: focused ? 1 : 0.5)
        )
        .animation(.easeInOut(duration: 0.18), value: focused)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}
