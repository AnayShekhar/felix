import SwiftUI

/// Settings section listing what Lumis has learned about you (GET /memory),
/// with the ability to forget any single entry (DELETE /memory/{key}).
struct MemorySection: View {
    @State private var memory: [String: String] = [:]
    @State private var loading = true

    var body: some View {
        SettingsSection("Memory") {
            if loading {
                HStack { ProgressView().tint(LumisColors.powderBlue); Spacer() }
                    .settingsRowPadding()
            } else if memory.isEmpty {
                Text("Lumis hasn’t learned anything yet. As you use it, your preferences show up here.")
                    .font(LumisTypography.bodySmall)
                    .foregroundStyle(LumisColors.textSecondary)
                    .settingsRowPadding()
            } else {
                ForEach(memory.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(prettyKey(key))
                                .font(LumisTypography.bodyMedium)
                                .foregroundStyle(LumisColors.carbonBlack)
                            Text(value)
                                .font(LumisTypography.bodySmall)
                                .foregroundStyle(LumisColors.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        Button { forget(key) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(LumisColors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Forget \(prettyKey(key))")
                    }
                    .settingsRowPadding()
                }
            }
        }
        .task { await load() }
    }

    private func prettyKey(_ key: String) -> String {
        key.split(whereSeparator: { $0 == "_" || $0 == "." })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func load() async {
        loading = memory.isEmpty
        defer { loading = false }
        if let fetched = try? await APIClient.memory(baseURL: LumisConfig.backendURL) {
            memory = fetched
        }
    }

    private func forget(_ key: String) {
        Haptics.light()
        let previous = memory
        withAnimation { memory.removeValue(forKey: key) }
        Task {
            do {
                try await APIClient.forget(key: key, baseURL: LumisConfig.backendURL)
            } catch {
                withAnimation { memory = previous }   // restore on failure
            }
        }
    }
}
