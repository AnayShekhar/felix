import SwiftUI

/// Three-column dashboard: nav sidebar (200) · main panel · live feed (260).
struct DashboardView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)

            Divider().overlay(LumisBrand.hairline)

            mainPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !env.feedCollapsed {
                Divider().overlay(LumisBrand.hairline)
                EventFeedView()
                    .frame(width: 260)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DashboardBackground())
        .preferredColorScheme(.light)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(LumisBrand.accent)
                Text("Lumis")
                    .font(.system(size: 17, weight: .heavy))
            }
            .padding(.horizontal, 14)
            .padding(.top, 22)
            .padding(.bottom, 18)

            ForEach(DashboardSection.allCases) { section in
                NavItem(section: section, selected: env.section == section) {
                    env.section = section
                }
            }

            Spacer()

            // One-time browser-automation setup (Playwright Chromium download).
            if env.macAgent.settingUpBrowser {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Setting up browser automation…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            HStack(spacing: 7) {
                StatusDot(connected: env.feed.connected)
                Text(env.feed.connected ? "Connected" : "Offline")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if env.feedCollapsed {
                    Button {
                        withAnimation(.spring(response: 0.3)) { env.feedCollapsed = false }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show live feed")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity)
        // Slightly darker Parchment (#EFEBE4) so the nav column reads as its own
        // surface against the main content area.
        .background(Color(red: 0.937, green: 0.922, blue: 0.894))
    }

    // MARK: Main panel

    @ViewBuilder
    private var mainPanel: some View {
        switch env.section {
        case .activity: ActivityView()
        case .memory:   MemoryView()
        case .settings: SettingsView()
        }
    }
}

private struct NavItem: View {
    let section: DashboardSection
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                    .foregroundStyle(selected ? LumisBrand.accent : .secondary)
                Text(section.title)
                    .font(.system(size: 13, weight: selected ? .heavy : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? LumisBrand.accent.opacity(0.14)
                          : (hover ? LumisBrand.surfaceHover : .clear))
            )
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Parchment backdrop with a faint powder-blue glow at the top-left.
struct DashboardBackground: View {
    var body: some View {
        ZStack {
            LumisBrand.parchment
            RadialGradient(
                colors: [LumisBrand.accent.opacity(0.18), .clear],
                center: .topLeading, startRadius: 0, endRadius: 560
            )
        }
        .ignoresSafeArea()
    }
}
