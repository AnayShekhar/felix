import SwiftUI

/// A small pulsing connection dot (green when connected, grey when not).
struct StatusDot: View {
    let connected: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(connected ? LumisBrand.online : LumisBrand.offline)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(connected ? LumisBrand.online : LumisBrand.offline, lineWidth: 2)
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 0.6)
            )
            .onAppear {
                guard connected else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

/// A rounded square badge holding a tool's tinted SF Symbol.
struct ToolIconBadge: View {
    let tool: String?
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(ToolStyle.tint(for: tool).opacity(0.18))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: ToolStyle.icon(for: tool))
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(ToolStyle.tint(for: tool))
            )
    }
}

/// Status indicator for success/error result dots.
struct ResultStatusDot: View {
    let status: String?
    var body: some View {
        Circle()
            .fill((status ?? "").lowercased() == "error" ? LumisBrand.error : LumisBrand.online)
            .frame(width: 7, height: 7)
    }
}

/// Standard empty-state block: large symbol, heading, supporting text.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(LumisBrand.accent.opacity(0.7))
            Text(title)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Inline error banner shown above content when an API call fails.
struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(LumisBrand.error)
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LumisBrand.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(LumisBrand.error.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(LumisBrand.error.opacity(0.35), lineWidth: 1)
        )
    }
}

/// A shimmering skeleton row used while lists load.
struct SkeletonRow: View {
    @State private var shimmer = false
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).frame(width: 180, height: 11)
                RoundedRectangle(cornerRadius: 4).frame(width: 90, height: 9)
            }
            Spacer()
        }
        .foregroundStyle(LumisBrand.ink.opacity(shimmer ? 0.12 : 0.05))
        .padding(.vertical, 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }
}

extension View {
    /// Standard card surface used across the dashboard — native Liquid Glass on
    /// macOS 26+, `.ultraThinMaterial` below.
    func lumisCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .lumisGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LumisBrand.hairline, lineWidth: 1)
            )
    }
}
