import SwiftUI

/// Right panel: live WebSocket event feed. Each event is a small card with an
/// event-type badge, tool name, status dot, and message. Auto-scrolls to newest.
struct EventFeedView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            header

            if env.feed.events.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Waiting for events…")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(env.feed.events) { event in
                                EventCard(event: event).id(event.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(12)
                    }
                    .onChange(of: env.feed.events.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(.white.opacity(0.02))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("LIVE FEED")
                .font(.system(size: 11, weight: .heavy)).tracking(1.1)
            StatusDot(connected: env.feed.connected)
            Spacer()
            Button("Clear") { env.feed.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .disabled(env.feed.events.isEmpty)
            Button {
                withAnimation(.spring(response: 0.3)) { env.feedCollapsed = true }
            } label: {
                Image(systemName: "sidebar.right").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hide feed")
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(.white.opacity(0.03))
    }
}

private struct EventCard: View {
    let event: FeedEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(badgeText)
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(badgeColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(badgeColor)
                Spacer()
                Text(event.receivedAt, style: .time)
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ResultStatusDot(status: event.status)
                if let tool = event.tool, !tool.isEmpty {
                    Image(systemName: ToolStyle.icon(for: tool))
                        .font(.system(size: 11))
                        .foregroundStyle(ToolStyle.tint(for: tool))
                    Text(ToolSummary.prettyToolName(tool))
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                }
            }
            Text(event.message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .felixCard(padding: 10)
    }

    private var badgeText: String {
        event.event.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private var badgeColor: Color {
        if event.isError { return FelixBrand.error }
        switch event.event {
        case "workflow_complete", "task_complete": return FelixBrand.online
        case "action_undone": return FelixBrand.accentSoft
        default: return FelixBrand.accent
        }
    }
}
