// HistoryView.swift
// The action-history feed (Phase 2). Shows everything Felix has done across
// devices via GET /history, and lets the user undo any reversible action via
// POST /undo/{id}. Presented as a sheet over the camera so the live capture
// flow is never disturbed. Dark mode, SF Pro, single accent — matches the app.
import SwiftUI

struct HistoryView: View {
    let baseURL: String?
    @ObservedObject var ws: WebSocketClient

    @Environment(\.dismiss) private var dismiss
    @State private var items: [ActionHistoryItem] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var undoing: Set<Int> = []
    @State private var toast: String?

    // Single brand accent (warm amber — not blue, not purple).
    private let accent = Color(red: 1.0, green: 0.72, blue: 0.30)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
                if let toast {
                    VStack {
                        Spacer()
                        ToastView(text: toast)
                            .padding(.bottom, 28)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.tint(accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.tint(accent)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading && items.isEmpty {
            ProgressView().tint(.white)
        } else if let loadError {
            emptyState(symbol: "wifi.exclamationmark",
                       title: "Couldn’t load history",
                       subtitle: loadError)
        } else if items.isEmpty {
            emptyState(symbol: "clock.arrow.circlepath",
                       title: "Nothing yet",
                       subtitle: "Actions Felix takes will show up here.")
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if let task = ws.activeTask, task.active {
                        activeTaskRow(task)
                    }
                    ForEach(items) { item in
                        row(item)
                    }
                }
                .padding(16)
            }
            .refreshable { await load() }
        }
    }

    private func activeTaskRow(_ task: TaskState) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accent)
                    .frame(width: 40, height: 40)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(task.instruction)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                ProgressView(value: Double(task.progressPct), total: 100)
                    .tint(accent)
                    .scaleEffect(x: 1, y: 0.8, anchor: .center)
            }
            Text("\(task.progressPct)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .monospacedDigit()
        }
        .padding(12)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.4), lineWidth: 1)
        )
    }

    private func row(_ item: ActionHistoryItem) -> some View {
        let meta = toolMeta(item.tool_name)
        let failed = item.status == "error"
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(failed ? Color.red.opacity(0.9) : accent)
                    .frame(width: 40, height: 40)
                Image(systemName: failed ? "exclamationmark.triangle.fill" : meta.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title?.isEmpty == false ? item.title! : meta.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item.message ?? meta.label)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Text(relativeTime(item.timestamp))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 0)

            if item.undo_available {
                Button {
                    Task { await undo(item) }
                } label: {
                    if undoing.contains(item.id) {
                        ProgressView().tint(.white).scaleEffect(0.7)
                            .frame(width: 64, height: 30)
                    } else {
                        Text("Undo")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 30)
                            .background(Color.white.opacity(0.12), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
                .disabled(undoing.contains(item.id))
            }
        }
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func emptyState(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Actions

    private func load() async {
        guard let baseURL else {
            loadError = "Not connected to a Felix backend."
            return
        }
        loading = true
        defer { loading = false }
        do {
            items = try await APIClient.history(baseURL: baseURL)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func undo(_ item: ActionHistoryItem) async {
        guard let baseURL else { return }
        undoing.insert(item.id)
        defer { undoing.remove(item.id) }
        do {
            let resp = try await APIClient.undo(actionID: item.id, baseURL: baseURL)
            let ok = resp.status == "success"
            showToast(ok ? "Undone" : (resp.message ?? "Couldn’t undo"))
            await load()
        } catch {
            showToast("Couldn’t undo: \(error.localizedDescription)")
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.3)) { toast = nil }
        }
    }

    private func relativeTime(_ ts: Double?) -> String {
        guard let ts else { return "" }
        let date = Date(timeIntervalSince1970: ts)
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

private struct ToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }
}
