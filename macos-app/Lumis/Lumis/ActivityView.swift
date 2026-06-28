import SwiftUI

/// Activity (default view): the full action history from GET /history. Rows
/// expand to show args/result; undo button shown when available.
struct ActivityView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var actions: [ActionHistoryItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var expanded: Set<Int> = []
    @State private var undoing: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "Activity", subtitle: subtitle) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh")
            }

            if let error {
                ErrorBanner(message: error) { Task { await load() } }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            if loading {
                VStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
                }
                .padding(20)
            } else if actions.isEmpty && error == nil {
                EmptyStateView(
                    symbol: "bolt.slash",
                    title: "Lumis hasn't done anything yet",
                    subtitle: "Start by opening the iOS app and pointing the camera at something."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(actions) { action in
                            ActivityRow(
                                action: action,
                                isExpanded: expanded.contains(action.id),
                                isUndoing: undoing.contains(action.id),
                                onTap: { toggle(action.id) },
                                onUndo: { Task { await undo(action) } }
                            )
                        }
                    }
                    .padding(20)
                }
            }
            Spacer(minLength: 0)
        }
        .task { await load() }
    }

    private var subtitle: String {
        actions.isEmpty ? "No actions" : "\(actions.count) action\(actions.count == 1 ? "" : "s")"
    }

    private func toggle(_ id: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            // Single-expand: tapping another row collapses the previous one (Fix 8).
            expanded = expanded.contains(id) ? [] : [id]
        }
    }

    private func load() async {
        loading = actions.isEmpty
        error = nil
        do {
            actions = try await APIService.history()
            // Auto-expand the most recent result that carries a summary (Fix 8).
            if expanded.isEmpty,
               let recent = actions.first(where: { ($0.summary ?? "").isEmpty == false }) {
                expanded = [recent.id]
            }
        } catch let e as APIError {
            error = e.message
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func undo(_ action: ActionHistoryItem) async {
        undoing.insert(action.id)
        defer { undoing.remove(action.id) }
        do {
            try await APIService.undo(actionID: action.id)
            await load()
            await env.refreshRecent()
        } catch let e as APIError {
            error = e.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ActivityRow: View {
    let action: ActionHistoryItem
    let isExpanded: Bool
    let isUndoing: Bool
    let onTap: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ToolIconBadge(tool: action.tool_name)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ToolSummary.line(title: action.title, message: action.message, tool: action.tool_name))
                        .font(.system(size: 13, weight: .heavy))
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        ResultStatusDot(status: action.status)
                        Text(ToolSummary.prettyToolName(action.tool_name ?? "—"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.secondary)
                        Text(RelativeTime.string(fromUnix: action.timestamp))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if action.undo_available {
                    Button(action: onUndo) {
                        if isUndoing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Undo")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LumisBrand.error)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(LumisBrand.error.opacity(0.12), in: Capsule())
                    .disabled(isUndoing)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().overlay(LumisBrand.hairline).padding(.vertical, 10)
                    if let summary = action.summary, !summary.isEmpty {
                        SummaryCard(summary: summary, tool: action.tool_name)
                    }
                    DetailField(label: "Tool", value: action.tool_name ?? "—")
                    DetailField(label: "Status", value: action.status ?? "—")
                    if let message = action.message, !message.isEmpty {
                        DetailField(label: "Result", value: message)
                    }
                    DetailField(label: "Session", value: action.session_id ?? "—")
                    DetailField(label: "When",
                                value: RelativeTime.string(fromUnix: action.timestamp))
                }
            }
        }
        .lumisCard()
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// Expandable summary card for content-tool results (Fix 8). Prose tools render
/// in SF Pro; structured data (calendar, contacts, battery…) in SF Mono.
private struct SummaryCard: View {
    let summary: String
    let tool: String?

    private var monospaced: Bool {
        switch tool {
        case "web.research", "screen.capture_and_describe": return false
        default: return true
        }
    }

    var body: some View {
        Text(summary)
            .font(monospaced
                  ? .system(size: 12, weight: .regular, design: .monospaced)
                  : .system(size: 13, weight: .regular))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(LumisBrand.surface,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DetailField: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

/// Shared header for each main-panel section: heavy title + subtitle + actions.
struct PanelHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 24, weight: .heavy))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }
}
