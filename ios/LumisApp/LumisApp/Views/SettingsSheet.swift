import SwiftUI

/// Phase 10 — Settings as a sheet (the tab bar is gone; this opens from a long
/// press on the orb). Keeps Backend, Voice, and Notifications, and folds the old
/// Memory tab into a "What Lumis knows" section with swipe-to-delete. Glass style
/// matches the result card.
struct SettingsSheet: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var discovery: MacDiscovery
    @ObservedObject var ws: WebSocketClient
    @Environment(\.dismiss) private var dismiss

    @State private var urlDraft = ""
    @State private var testing = false
    @State private var testResult: TestState?
    @State private var memory: [(key: String, value: String)] = []
    @State private var pendingForget: String?

    private enum TestState { case ok(Int), fail(String) }

    private var baseURL: String { settings.resolvedBaseURL(discovery: discovery) }

    var body: some View {
        NavigationStack {
            ZStack {
                LumisColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        backendSection
                        voiceSection
                        notificationsSection
                        memorySection
                        Text("Lumis v\(LumisBrand.appVersion)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(LumisColor.orbPrimary)
                }
            }
            .toolbarBackground(LumisColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(.lumis)
        .preferredColorScheme(.dark)
        .onAppear { urlDraft = settings.backendOverride }
        .task { await loadMemory() }
        .alert("Forget this?", isPresented: .constant(pendingForget != nil)) {
            Button("Cancel", role: .cancel) { pendingForget = nil }
            Button("Forget", role: .destructive) {
                if let key = pendingForget { Task { await forget(key) } }
                pendingForget = nil
            }
        } message: {
            Text(pendingForget.map { "Lumis will forget “\($0)”." } ?? "")
        }
    }

    // MARK: - Sections

    private var backendSection: some View {
        section("Backend") {
            TextField(text: $urlDraft) {
                Text(discovery.baseURL ?? "Auto (Mac on WiFi / fallback)")
                    .foregroundStyle(.white.opacity(0.4))
            }
            .textFieldStyle(.plain)
            .font(.system(size: 15, design: .monospaced))
            .foregroundStyle(.white)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onSubmit(saveURL)

            HStack(spacing: 10) {
                Button("Save", action: saveURL).buttonStyle(SheetPill(filled: true))
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack(spacing: 6) {
                        if testing { ProgressView().tint(.white).scaleEffect(0.7) }
                        Text("Test")
                    }
                }
                .buttonStyle(SheetPill(filled: false))
                .disabled(testing)
            }

            switch testResult {
            case .ok(let ms):
                Label("Connected · \(ms) ms", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(LumisColor.success)
            case .fail(let msg):
                Label(msg, systemImage: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(LumisColor.error)
            case nil:
                EmptyView()
            }
        }
    }

    private var voiceSection: some View {
        section("Voice") {
            Toggle(isOn: $ws.voiceEnabled) {
                label("Lumis speaks results",
                      "Read results aloud when Lumis finds info or finishes a task.")
            }.tint(.lumis)
        }
    }

    private var notificationsSection: some View {
        section("Notifications") {
            Toggle(isOn: $settings.notifyCompletion) {
                label("Task completion", "Notify when Lumis finishes.")
            }.tint(.lumis)
            Toggle(isOn: $settings.notifyErrors) {
                label("Errors", "Notify when something fails.")
            }.tint(.lumis)
        }
    }

    private var memorySection: some View {
        section("What Lumis knows") {
            if memory.isEmpty {
                Text("Nothing learned yet. Use Lumis more and it will pick up your preferences.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.45))
            } else {
                ForEach(memory, id: \.key) { entry in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.key)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(LumisColor.orbPrimary)
                            Text(entry.value)
                                .font(.system(size: 14)).foregroundStyle(.white)
                        }
                        Spacer(minLength: 0)
                        Button { pendingForget = entry.key } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(LumisColor.error)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    if entry.key != memory.last?.key {
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                }
            }
        }
    }

    // MARK: - Builders

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy)).tracking(1.1)
                .foregroundStyle(LumisColor.orbPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frostedCard()
    }

    private func label(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Actions

    private func saveURL() {
        settings.backendOverride = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        urlDraft = settings.backendOverride
        testResult = nil
        ws.connect(to: Config.wsURL(base: baseURL))
    }

    private func testConnection() async {
        saveURL()
        testing = true
        defer { testing = false }
        do { testResult = .ok(try await APIClient.health(baseURL: baseURL)) }
        catch { testResult = .fail("Can’t reach the backend") }
    }

    private func loadMemory() async {
        if let map = try? await APIClient.memory(baseURL: baseURL) {
            memory = map.map { (key: $0.key, value: $0.value) }.sorted { $0.key < $1.key }
        }
    }

    private func forget(_ key: String) async {
        try? await APIClient.forget(key: key, baseURL: baseURL)
        memory.removeAll { $0.key == key }
    }
}

/// Pill button used in the settings sheet — filled (Moonstone) or outlined.
private struct SheetPill: ButtonStyle {
    let filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(filled ? .black : .white)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(
                filled
                ? AnyShapeStyle(LumisColor.orbPrimary.opacity(configuration.isPressed ? 0.6 : 1))
                : AnyShapeStyle(.white.opacity(configuration.isPressed ? 0.04 : 0.1)),
                in: Capsule()
            )
    }
}
