import SwiftUI

/// Pairing card for the menu-bar popover. While unlinked it shows a 6-digit
/// code (bound to this account) to enter on the iPhone; once a phone on the same
/// account confirms it, it flips to "Connected to iPhone".
struct LinkCodeView: View {
    @StateObject private var link = LinkController()

    var body: some View {
        Group {
            if link.linked {
                linkedCard
            } else if let code = link.code, !code.isEmpty {
                codeCard(code)
            } else if let error = link.error {
                errorCard(error)
            } else {
                waitingCard
            }
        }
        .onAppear { link.start() }
        .onDisappear { link.stop() }
    }

    private func codeCard(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONNECT YOUR IPHONE")
                .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                .foregroundStyle(LumisBrand.ink.opacity(0.55))
            HStack(spacing: 7) {
                ForEach(Array(code.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(LumisBrand.ink)
                        .frame(width: 30, height: 40)
                        .background(LumisBrand.surface, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(LumisBrand.hairline, lineWidth: 1))
                }
            }
            Text("On your iPhone (same account) → Settings → Connect Mac, enter this code.")
                .font(.system(size: 11))
                .foregroundStyle(LumisBrand.ink.opacity(0.55))
        }
    }

    private var linkedCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(LumisBrand.online)
            Text("Connected to your iPhone")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LumisBrand.ink)
            Spacer()
            Circle().fill(link.macOnline ? LumisBrand.online : LumisBrand.offline)
                .frame(width: 7, height: 7)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(LumisBrand.error)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(LumisBrand.ink.opacity(0.7))
        }
    }

    private var waitingCard: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Preparing your code…")
                .font(.system(size: 12))
                .foregroundStyle(LumisBrand.ink.opacity(0.55))
        }
    }
}
