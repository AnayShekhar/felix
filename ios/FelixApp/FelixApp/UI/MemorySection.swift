import SwiftUI

/// Settings section listing what Felix has learned about you (GET /memory),
/// with the ability to forget any single entry (DELETE /memory/{key}).
struct MemorySection: View {
    @State private var memory: [String: String] = [:]
    @State private var loading = true

    var body: some View {
        SettingsSection("Memory") {
            if loading {
                HStack { ProgressView().tint(FelixColors.tint); Spacer() }
                    .settingsRowPadding()
            } else if memory.isEmpty {
                Text("Felix hasn’t learned anything yet. As you use it, your preferences show up here.")
                    .font(FelixTypography.bodySmall)
                    .foregroundStyle(FelixColors.textSecondary)
                    .settingsRowPadding()
            } else {
                ForEach(memory.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(prettyKey(key))
                                .font(FelixTypography.bodyMedium)
                                .foregroundStyle(FelixColors.textPrimary)
                            Text(prettyValue(value))
                                .font(FelixTypography.bodySmall)
                                .foregroundStyle(FelixColors.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        Button { forget(key) } label: {
                            Image(systemName: "xmark.circle")
                                .font(.body.weight(.medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(FelixColors.textTertiary)
                        }
                        .buttonStyle(.felixPress)
                        .accessibilityLabel("Forget \(prettyKey(key))")
                    }
                    .settingsRowPadding()
                }
            }
        }
        .task { await load() }
    }

    // Shared with the Mac app via MemoryFormat (shared/Constants.swift).
    private func prettyKey(_ key: String) -> String { MemoryFormat.prettyKey(key) }
    private func prettyValue(_ value: String) -> String { MemoryFormat.prettyValue(value) }

    private func load() async {
        loading = memory.isEmpty
        defer { loading = false }
        if let fetched = try? await APIClient.memory(baseURL: FelixConfig.backendURL) {
            memory = fetched
        }
    }

    private func forget(_ key: String) {
        Haptics.light()
        let previous = memory
        withAnimation { memory.removeValue(forKey: key) }
        Task {
            do {
                try await APIClient.forget(key: key, baseURL: FelixConfig.backendURL)
            } catch {
                withAnimation { memory = previous }   // restore on failure
            }
        }
    }
}
