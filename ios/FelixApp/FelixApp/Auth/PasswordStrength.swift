import SwiftUI

/// Heuristic password strength on a 0–4 scale.
enum PasswordStrength: Int {
    case empty = 0, weak, fair, good, strong

    static func evaluate(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else { return .empty }
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.range(of: "[A-Z]", options: .regularExpression) != nil &&
           password.range(of: "[a-z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[0-9]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil { score += 1 }
        return PasswordStrength(rawValue: min(max(score, 1), 4)) ?? .weak
    }

    var label: String {
        switch self {
        case .empty:  return ""
        case .weak:   return "Weak"
        case .fair:   return "Fair"
        case .good:   return "Good"
        case .strong: return "Strong"
        }
    }

    // Single-accent discipline: red only for "weak" (an error state), neutral
    // for "fair", and the brand tint — deepening with confidence — for good
    // and strong. No third hue.
    var color: Color {
        switch self {
        case .empty:  return FelixColors.divider
        case .weak:   return FelixColors.destructive
        case .fair:   return FelixColors.textTertiary
        case .good:   return FelixColors.tint
        case .strong: return FelixColors.tintStrong
        }
    }
}

/// 4-segment bar that fills left→right with the strength color.
struct PasswordStrengthBar: View {
    let strength: PasswordStrength

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index < strength.rawValue ? strength.color : FelixColors.divider)
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: strength)
        .overlay(alignment: .trailing) {
            if strength != .empty {
                Text(strength.label)
                    .font(FelixTypography.caption)
                    .foregroundStyle(strength.color)
                    .offset(y: 14)
            }
        }
    }
}
