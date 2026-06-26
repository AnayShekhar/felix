import SwiftUI

/// The popover shown when the menu bar icon is clicked: connection status,
/// the last 3 actions, and an "Open Dashboard" button.
struct MenuBarPopover: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider().overlay(.white.opacity(0.08))

            Text("RECENT")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            if env.recentActions.isEmpty {
                Text("Nothing yet. Open the iOS app to start.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(env.recentActions) { action in
                    HStack(spacing: 10) {
                        ToolIconBadge(tool: action.tool_name, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ToolSummary.line(title: action.title, message: action.message, tool: action.tool_name))
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(RelativeTime.string(fromUnix: action.timestamp))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            Button {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                HStack {
                    Image(systemName: "rectangle.3.group.fill")
                    Text("Open Dashboard")
                    Spacer()
                    Text("⌘⇧F").foregroundStyle(.secondary)
                }
                .font(.system(size: 13, weight: .bold))
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(FelixBrand.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .foregroundStyle(FelixBrand.accent)
            }
            .buttonStyle(.plain)

            HStack {
                Button("Quit Felix") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(Color.black.opacity(0.001))
        .preferredColorScheme(.dark)
        .task { await env.refreshRecent() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(FelixBrand.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Felix")
                    .font(.system(size: 15, weight: .heavy))
                HStack(spacing: 6) {
                    StatusDot(connected: env.feed.connected)
                    Text(env.feed.connected ? "Connected" : "Offline")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
