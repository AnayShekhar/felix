import SwiftUI

/// Tab 2 — History. Full-screen list of everything Felix has done (GET /history)
/// with pull-to-refresh, swipe-to-undo, and a readable detail sheet. Undo posts
/// to /undo/{id}. Presentation only; networking is in APIClient.
struct HistoryTab: View {
    @ObservedObject var ws: WebSocketClient
    @ObservedObject var settings: AppSettings
    @ObservedObject var discovery: MacDiscovery

    @State private var items: [ActionHistoryItem] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var undoing: Set<Int> = []
    @State private var detail: ActionHistoryItem?
    @State private var toast: String?

    private var baseURL: String { settings.resolvedBaseURL(discovery: discovery) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
                if let toast { toastOverlay(toast) }
            }
            .navigationTitle("History")
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .tint(.felix)
        .preferredColorScheme(.dark)
        .task { await load() }
        .sheet(item: $detail) { item in
            HistoryDetailSheet(item: item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && items.isEmpty {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { _ in
                        SkeletonRow().padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 8)
            }
        } else if let loadError, items.isEmpty {
            FelixEmptyState(symbol: "wifi.exclamationmark",
                            title: "Couldn’t load history",
                            subtitle: loadError)
        } else if items.isEmpty {
            FelixEmptyState(symbol: "camera.metering.center.weighted",
                            title: "Nothing yet",
                            subtitle: "Point your camera at something.")
        } else {
            List {
                if let task = ws.activeTask, task.active {
                    activeTaskRow(task)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(items) { item in
                    Button { detail = item } label: { row(item) }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if item.undo_available {
                                Button(role: .destructive) {
                                    Task { await undo(item) }
                                } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await load() }
        }
    }

    private func row(_ item: ActionHistoryItem) -> some View {
        let failed = item.status == "error"
        return HStack(spacing: 12) {
            ToolBadge(tool: item.tool_name, failed: failed)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title?.isEmpty == false ? item.title! : toolMeta(item.tool_name).label)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item.message ?? toolMeta(item.tool_name).label)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                if undoing.contains(item.id) {
                    ProgressView().tint(.white).scaleEffect(0.7)
                }
                Text(RelativeTime.string(fromUnix: item.timestamp))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(12)
        .frostedCard(cornerRadius: 16)
    }

    private func activeTaskRow(_ task: TaskState) -> some View {
        HStack(spacing: 12) {
            ToolBadge(tool: nil)
                .overlay(Image(systemName: "bolt.fill").font(.system(size: 17, weight: .heavy)).foregroundStyle(.black))
            VStack(alignment: .leading, spacing: 5) {
                Text(task.instruction)
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white).lineLimit(1)
                ProgressView(value: Double(task.progressPct), total: 100)
                    .tint(.felix).scaleEffect(x: 1, y: 0.8, anchor: .center)
            }
            Text("\(task.progressPct)%")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.8)).monospacedDigit()
        }
        .padding(12)
        .background(Color.felix.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.felix.opacity(0.4), lineWidth: 1))
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }

    private func toastOverlay(_ text: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                Text(text).font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .frostedCard(cornerRadius: 30)
            .padding(.bottom, 28)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    private func load() async {
        loading = items.isEmpty
        defer { loading = false }
        do {
            items = try await APIClient.history(baseURL: baseURL)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func undo(_ item: ActionHistoryItem) async {
        undoing.insert(item.id)
        defer { undoing.remove(item.id) }
        do {
            let resp = try await APIClient.undo(actionID: item.id, baseURL: baseURL)
            showToast(resp.status == "success" ? "Undone" : (resp.message ?? "Couldn’t undo"))
            await load()
        } catch {
            showToast("Couldn’t undo")
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.3)) { toast = nil }
        }
    }
}

/// Tapping a history row opens this readable detail sheet (no raw JSON).
private struct HistoryDetailSheet: View {
    let item: ActionHistoryItem
    @Environment(\.dismiss) private var dismiss

    private var failed: Bool { item.status == "error" }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                ToolBadge(tool: item.tool_name, size: 70, failed: failed)
                Text(item.title?.isEmpty == false ? item.title! : toolMeta(item.tool_name).label)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28).padding(.horizontal, 24)

            VStack(spacing: 0) {
                detailRow("Tool", toolMeta(item.tool_name).label)
                detailRow("Status", (item.status ?? "—").capitalized,
                          tint: failed ? .red : .felix)
                if let message = item.message, !message.isEmpty {
                    detailRow("Result", message)
                }
                detailRow("When", RelativeTime.string(fromUnix: item.timestamp))
                if item.undo_available {
                    detailRow("Reversible", "Yes — swipe to undo")
                }
            }
            .padding(16)
            .frostedCard()
            .padding(20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    private func detailRow(_ label: String, _ value: String, tint: Color = .white) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(tint == .white ? .white : tint)
                    .multilineTextAlignment(.trailing)
            }
            Divider().overlay(.white.opacity(0.08))
        }
        .padding(.vertical, 6)
    }
}
