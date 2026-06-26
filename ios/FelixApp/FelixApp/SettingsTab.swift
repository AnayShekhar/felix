import SwiftUI

/// Tab 4 — Settings. Backend URL (UserDefaults), test connection w/ latency,
/// notification toggles, clear-all-memory destructive action, app version.
struct SettingsTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var discovery: MacDiscovery
    @ObservedObject var ws: WebSocketClient

    @State private var urlDraft = ""
    @State private var testing = false
    @State private var testResult: Result<Int, String>?
    @State private var clearing = false
    @State private var showClearConfirm = false
    @State private var clearMessage: String?
    @State private var groqKeyDraft = ""

    enum Result<S, F> { case success(S); case failure(F) }

    private var baseURL: String { settings.resolvedBaseURL(discovery: discovery) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        backendSection
                        voiceSection
                        transcriptionSection
                        notificationsSection
                        dangerSection
                        Text("Felix v\(FelixBrand.appVersion)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 8)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(.felix)
        .preferredColorScheme(.dark)
        .onAppear {
            urlDraft = settings.backendOverride
            groqKeyDraft = UserDefaults.standard.string(forKey: WhisperTranscriber.apiKeyDefaultsKey) ?? ""
        }
        .alert("Clear all memory?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { Task { await clearAllMemory() } }
        } message: {
            Text("Felix will forget everything it has learned about you. This can’t be undone.")
        }
    }

    // MARK: - Sections

    private var backendSection: some View {
        section("Backend") {
            Text("URL")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white.opacity(0.5))
            TextField(text: $urlDraft) {
                Text(discovery.baseURL ?? "Auto (Mac on WiFi / fallback)")
                    .foregroundStyle(.white.opacity(0.4))
            }
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .regular, design: .monospaced))
            .foregroundStyle(.white)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onSubmit(saveURL)

            Text("Leave blank to auto-discover your Mac, then fall back to the public demo server.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))

            HStack(spacing: 10) {
                Button("Save", action: saveURL)
                    .buttonStyle(FelixPillButton(filled: true))
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack(spacing: 6) {
                        if testing { ProgressView().tint(.white).scaleEffect(0.7) }
                        Text("Test Connection")
                    }
                }
                .buttonStyle(FelixPillButton(filled: false))
                .disabled(testing)
            }

            switch testResult {
            case .success(let ms):
                Label("Connected · \(ms) ms", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(.green)
            case .failure(let msg):
                Label(msg, systemImage: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(.red)
            case nil:
                EmptyView()
            }
        }
    }

    private var voiceSection: some View {
        section("Voice") {
            Toggle(isOn: $ws.voiceEnabled) {
                settingLabel("Felix speaks results",
                             "Felix will read results aloud when it finds information or completes a task.")
            }.tint(.felix)
        }
    }

    private var transcriptionSection: some View {
        section("Transcription") {
            Text("GROQ API KEY")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white.opacity(0.5))
            SecureField(text: $groqKeyDraft) {
                Text("gsk_…").foregroundStyle(.white.opacity(0.4))
            }
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .regular, design: .monospaced))
            .foregroundStyle(.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onSubmit(saveGroqKey)

            Text("Commands are transcribed with Groq Whisper for far better accuracy on names. Without a key, Felix falls back to on-device Apple speech.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))

            Button("Save Key", action: saveGroqKey)
                .buttonStyle(FelixPillButton(filled: true))
        }
    }

    private var notificationsSection: some View {
        section("Notifications") {
            Toggle(isOn: $settings.notifyCompletion) {
                settingLabel("Task completion", "Notify when Felix finishes.")
            }.tint(.felix)
            Toggle(isOn: $settings.notifyErrors) {
                settingLabel("Errors", "Notify when something fails.")
            }.tint(.felix)
        }
    }

    private var dangerSection: some View {
        section("Data") {
            Button(role: .destructive) { showClearConfirm = true } label: {
                HStack(spacing: 8) {
                    if clearing { ProgressView().tint(.red).scaleEffect(0.7) }
                    Image(systemName: "trash.fill")
                    Text("Clear all memory")
                }
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(clearing)
            if let clearMessage {
                Text(clearMessage).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Builders

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy)).tracking(1.1)
                .foregroundStyle(Color.felix)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frostedCard()
    }

    private func settingLabel(_ title: String, _ subtitle: String) -> some View {
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

    private func saveGroqKey() {
        let trimmed = groqKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        groqKeyDraft = trimmed
        UserDefaults.standard.set(trimmed, forKey: WhisperTranscriber.apiKeyDefaultsKey)
    }

    private func testConnection() async {
        saveURL()
        testing = true
        defer { testing = false }
        do {
            let ms = try await APIClient.health(baseURL: baseURL)
            testResult = .success(ms)
        } catch {
            testResult = .failure("Can’t reach the backend")
        }
    }

    private func clearAllMemory() async {
        clearing = true
        defer { clearing = false }
        do {
            let map = try await APIClient.memory(baseURL: baseURL)
            for key in map.keys {
                try? await APIClient.forget(key: key, baseURL: baseURL)
            }
            clearMessage = map.isEmpty ? "Nothing to clear." : "Cleared \(map.count) item\(map.count == 1 ? "" : "s")."
        } catch {
            clearMessage = "Couldn’t clear memory."
        }
    }
}

/// Pill button used in Settings — filled (accent) or outlined.
private struct FelixPillButton: ButtonStyle {
    let filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(filled ? .black : .white)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(
                filled
                ? AnyShapeStyle(Color.felix.opacity(configuration.isPressed ? 0.6 : 1))
                : AnyShapeStyle(.white.opacity(configuration.isPressed ? 0.04 : 0.1)),
                in: Capsule()
            )
    }
}
