import SwiftUI

/// Memory view: GET /memory rendered as a Key | Value table with per-row
/// delete (DELETE /memory/{key}) and a search filter.
struct MemoryView: View {
    @State private var entries: [(key: String, value: String)] = []
    @State private var loading = true
    @State private var error: String?
    @State private var query = ""
    @State private var deleting: Set<String> = []

    private var filtered: [(key: String, value: String)] {
        guard !query.isEmpty else { return entries }
        let q = query.lowercased()
        return entries.filter { $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "Memory", subtitle: subtitle) {
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Refresh")
            }

            if !entries.isEmpty {
                searchBar.padding(.horizontal, 20).padding(.bottom, 12)
            }

            if let error {
                ErrorBanner(message: error) { Task { await load() } }
                    .padding(.horizontal, 20).padding(.bottom, 10)
            }

            if loading {
                VStack(spacing: 4) { ForEach(0..<5, id: \.self) { _ in SkeletonRow() } }
                    .padding(20)
            } else if entries.isEmpty && error == nil {
                EmptyStateView(
                    symbol: "brain",
                    title: "Felix hasn't learned anything about you yet",
                    subtitle: "Use it more and it will."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        TableHeaderRow()
                        ForEach(filtered, id: \.key) { entry in
                            MemoryRow(
                                key: entry.key,
                                value: entry.value,
                                isDeleting: deleting.contains(entry.key),
                                onDelete: { Task { await forget(entry.key) } }
                            )
                            Divider().overlay(.white.opacity(0.05))
                        }
                    }
                    .felixCard(padding: 0)
                    .padding(20)
                }
            }
            Spacer(minLength: 0)
        }
        .task { await load() }
    }

    private var subtitle: String {
        entries.isEmpty ? "No memories" : "\(entries.count) thing\(entries.count == 1 ? "" : "s") Felix knows about you"
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter keys…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func load() async {
        loading = entries.isEmpty
        error = nil
        do {
            let map = try await APIService.memory()
            entries = map.map { (key: $0.key, value: $0.value) }.sorted { $0.key < $1.key }
        } catch let e as APIError {
            error = e.message
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func forget(_ key: String) async {
        deleting.insert(key)
        defer { deleting.remove(key) }
        do {
            try await APIService.forget(key: key)
            entries.removeAll { $0.key == key }
        } catch let e as APIError {
            error = e.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct TableHeaderRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("KEY").frame(width: 200, alignment: .leading)
            Text("VALUE").frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(width: 28)
        }
        .font(.system(size: 10, weight: .heavy))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.white.opacity(0.03))
    }
}

private struct MemoryRow: View {
    let key: String
    let value: String
    let isDeleting: Bool
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(FelixBrand.accent)
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button(action: onDelete) {
                if isDeleting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(hover ? FelixBrand.error : .secondary)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 28)
            .disabled(isDeleting)
            .help("Forget this")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(hover ? Color.white.opacity(0.03) : .clear)
        .onHover { hover = $0 }
    }
}
