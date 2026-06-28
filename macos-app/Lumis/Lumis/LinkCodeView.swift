import SwiftUI

/// Reads the pairing state that the local Mac agent writes to
/// ~/.lumis/link_state.json and publishes it for the UI.
@MainActor
final class LinkStateReader: ObservableObject {
    struct State: Codable {
        var code: String?
        var linked: Bool
        var mac_name: String?
        var updated_at: Double?
    }

    @Published var state = State(code: nil, linked: false, mac_name: nil, updated_at: nil)

    private var timer: Timer?
    private let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".lumis/link_state.json")

    func start() {
        read()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.read() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func read() {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(State.self, from: data)
        else { return }
        state = decoded
    }
}

/// Prominent pairing-code card for the menu-bar popover. Shows the 6-char code
/// while unlinked and a "Linked" confirmation once an iPhone pairs.
struct LinkCodeView: View {
    @StateObject private var reader = LinkStateReader()

    var body: some View {
        Group {
            if reader.state.linked {
                linkedCard
            } else if let code = reader.state.code, !code.isEmpty {
                codeCard(code)
            } else {
                waitingCard
            }
        }
        .onAppear { reader.start() }
        .onDisappear { reader.stop() }
    }

    private func codeCard(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONNECT YOUR IPHONE")
                .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(code.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .frame(width: 30, height: 40)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Text("Open Lumis on your iPhone → Settings → Connect Mac")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var linkedCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Linked to your iPhone")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    private var waitingCard: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Starting agent…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
