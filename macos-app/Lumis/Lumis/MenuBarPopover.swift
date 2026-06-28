import SwiftUI

/// The popover shown when the menu bar icon is clicked: connection status,
/// the last 3 actions, and an "Open Dashboard" button.
struct MenuBarPopover: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var auth: AuthStore
    /// Opens (and focuses) the dashboard window — owned by `LumisApp` so the
    /// activation-policy handoff happens in one place.
    var onOpenDashboard: () -> Void

    var body: some View {
        if auth.isAuthenticated {
            signedInBody
        } else {
            signedOutBody
        }
    }

    private var signedOutBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider().overlay(LumisBrand.hairline)
            Text("Sign in to sync history and memory with your iPhone.")
                .font(.system(size: 12))
                .foregroundStyle(LumisBrand.ink.opacity(0.55))
            primaryButton("Sign In", systemImage: "person.crop.circle") { onOpenDashboard() }
            quitRow
        }
        .padding(16)
        .frame(width: 300)
        .foregroundStyle(LumisBrand.ink)
        .background(LumisBrand.parchment)
        .preferredColorScheme(.light)
    }

    private var signedInBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider().overlay(LumisBrand.hairline)

            LinkCodeView()

            Divider().overlay(LumisBrand.hairline)

            Text("RECENT")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(LumisBrand.ink.opacity(0.55))
                .tracking(1.2)

            if env.recentActions.isEmpty {
                Text("Nothing yet. Open the iOS app to start.")
                    .font(.system(size: 12))
                    .foregroundStyle(LumisBrand.ink.opacity(0.55))
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
                                .foregroundStyle(LumisBrand.ink.opacity(0.55))
                        }
                        Spacer()
                    }
                }
            }

            primaryButton("Open Dashboard", systemImage: "rectangle.3.group.fill",
                          trailing: "⌘⇧F") { onOpenDashboard() }

            quitRow
        }
        .padding(16)
        .frame(width: 300)
        .foregroundStyle(LumisBrand.ink)
        .background(LumisBrand.parchment)
        .preferredColorScheme(.light)
        .task { await env.refreshRecent() }
    }

    private func primaryButton(_ title: String, systemImage: String,
                               trailing: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
                Spacer()
                if let trailing { Text(trailing).foregroundStyle(LumisBrand.ink.opacity(0.55)) }
            }
            .font(.system(size: 13, weight: .bold))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(LumisBrand.accent.opacity(0.9), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .foregroundStyle(LumisBrand.ink)
        }
        .buttonStyle(.plain)
    }

    private var quitRow: some View {
        HStack {
            Button("Quit Lumis") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(LumisBrand.ink.opacity(0.55))
            Spacer()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(LumisBrand.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lumis")
                    .font(.system(size: 15, weight: .heavy))
                HStack(spacing: 6) {
                    StatusDot(connected: env.feed.connected)
                    Text(env.feed.connected ? "Connected" : "Offline")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LumisBrand.ink.opacity(0.55))
                }
                HStack(spacing: 6) {
                    StatusDot(connected: env.macAgentConnected)
                    Text(env.macAgentConnected ? "Mac Agent: Connected" : "Mac Agent: Offline")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LumisBrand.ink.opacity(0.55))
                }
            }
            Spacer()
        }
    }
}
