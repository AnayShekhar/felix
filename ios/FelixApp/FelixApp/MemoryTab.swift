import SwiftUI

/// Tab 3 — Memory. Key/value preferences Felix has learned (GET /memory).
/// Swipe to delete (DELETE /memory/{key}) with a confirmation alert.
struct MemoryTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var discovery: MacDiscovery

    @State private var entries: [(key: String, value: String)] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var pendingDelete: String?
    @State private var deleting: Set<String> = []

    private var baseURL: String { settings.resolvedBaseURL(discovery: discovery) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("Memory")
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
        .alert("Forget this?", isPresented: .constant(pendingDelete != nil)) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Forget", role: .destructive) {
                if let key = pendingDelete { Task { await forget(key) } }
                pendingDelete = nil
            }
        } message: {
            Text(pendingDelete.map { "Felix will forget “\($0)”." } ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && entries.isEmpty {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { _ in SkeletonRow().padding(.horizontal, 16) }
                }
                .padding(.vertical, 8)
            }
        } else if let loadError, entries.isEmpty {
            FelixEmptyState(symbol: "wifi.exclamationmark",
                            title: "Couldn’t load memory", subtitle: loadError)
        } else if entries.isEmpty {
            FelixEmptyState(symbol: "brain",
                            title: "Nothing learned yet",
                            subtitle: "Use Felix more and it will learn your preferences.")
        } else {
            List {
                Section {
                    ForEach(entries, id: \.key) { entry in
                        row(entry)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { pendingDelete = entry.key } label: {
                                    Label("Forget", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("\(entries.count) thing\(entries.count == 1 ? "" : "s") Felix knows about you")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await load() }
        }
    }

    private func row(_ entry: (key: String, value: String)) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.key)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.felix)
                Text(entry.value)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
            if deleting.contains(entry.key) { ProgressView().tint(.white).scaleEffect(0.7) }
        }
        .padding(14)
        .frostedCard(cornerRadius: 16)
    }

    // MARK: - Actions

    private func load() async {
        loading = entries.isEmpty
        defer { loading = false }
        do {
            let map = try await APIClient.memory(baseURL: baseURL)
            entries = map.map { (key: $0.key, value: $0.value) }.sorted { $0.key < $1.key }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func forget(_ key: String) async {
        deleting.insert(key)
        defer { deleting.remove(key) }
        do {
            try await APIClient.forget(key: key, baseURL: baseURL)
            entries.removeAll { $0.key == key }
        } catch {
            loadError = error.localizedDescription
        }
    }
}
