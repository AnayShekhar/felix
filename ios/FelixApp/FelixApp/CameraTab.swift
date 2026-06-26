import SwiftUI
import UIKit

/// Tab 1 — the redesigned camera screen. Keeps the existing capture/voice flow
/// (camera viewfinder, wake word, transcription, shutter, result) but restyles
/// it: pulsing vignette border, center-top status pill, frosted transcription
/// card, larger shutter with a listening ring, and a result bottom sheet.
struct CameraTab: View {
    @ObservedObject var camera: CameraManager
    @ObservedObject var speech: SpeechRecognizer
    @ObservedObject var ws: WebSocketClient
    @ObservedObject var discovery: MacDiscovery
    @ObservedObject var settings: AppSettings
    @ObservedObject private var router = DeepLinkRouter.shared
    let sessionID: String

    @State private var sending = false
    @State private var flash = 0.0
    @State private var wakeFlash = 0.0
    @State private var typedPrompt = ""
    @State private var longTask = false
    @State private var resultSheet: StepResult?
    @State private var summarySheet: StepResult?
    @FocusState private var promptFocused: Bool

    /// Tools whose results warrant a full summary sheet rather than a small toast (Fix 8).
    private static let contentTools: Set<String> = [
        "calendar.read_today", "calendar.read_week", "reminders.read_list",
        "contacts.find", "system.get_battery", "web.research",
        "screen.capture_and_describe",
    ]

    private var busy: Bool { sending || ws.working }
    private var listening: Bool { speech.phase == .hearing }
    private var baseURL: String { settings.resolvedBaseURL(discovery: discovery) }

    private var effectiveCommand: String {
        let typed = typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return speech.command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCapture: Bool { !busy && !effectiveCommand.isEmpty }

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            LinearGradient(colors: [.black.opacity(0.5), .clear, .clear, .black.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VignetteBorder(listening: listening)
                .allowsHitTesting(false)

            // Wake-word white flash + capture flash.
            Color.white.opacity(wakeFlash).ignoresSafeArea().allowsHitTesting(false)
            Color.white.opacity(flash).ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                statusPill
                    .padding(.top, 8)
                Spacer()
                if let task = ws.activeTask, task.active {
                    TaskProgressToast(task: task)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                }
                transcriptionCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                controls
                    .padding(.bottom, 10)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $resultSheet) { result in
            ResultSheet(result: result)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $summarySheet) { result in
            SummarySheet(result: result)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: speech.phase) { _, phase in
            if phase == .hearing { triggerWakeFlash() }
        }
        .onChange(of: ws.latest?.id) { _, _ in
            // Surface a completed result (ignore mid-workflow). Content tools with
            // a summary get the full sheet; everything else the small toast (Fix 8).
            guard !ws.working, let latest = ws.latest else { return }
            if let tool = latest.tool, Self.contentTools.contains(tool),
               let summary = latest.summary, !summary.isEmpty {
                summarySheet = latest
            } else {
                resultSheet = latest
            }
        }
        .onAppear(perform: consumeAutoCapture)
        .onChange(of: router.autoCapture) { _, on in if on { consumeAutoCapture() } }
    }

    /// Phase 8: when launched via felix://capture (lock-screen widget), arm the
    /// mic immediately so the user can just start talking.
    private func consumeAutoCapture() {
        guard router.autoCapture else { return }
        router.autoCapture = false
        speech.startListening()          // idempotent — no-op if already running
        triggerWakeFlash()               // visual + haptic "listening" confirmation
    }

    // MARK: - Status pill (center-top)

    private var statusPill: some View {
        HStack(spacing: 9) {
            if busy {
                ProgressView().tint(.white).scaleEffect(0.7)
            } else {
                Circle()
                    .fill(ws.connected ? Color.felix : .white.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .overlay(PulseRing(active: ws.connected, color: .felix))
            }
            Text(statusText)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frostedCard(cornerRadius: 30)
        .animation(.easeInOut(duration: 0.2), value: busy)
        .animation(.easeInOut(duration: 0.2), value: ws.connected)
    }

    private var statusText: String {
        if busy { return "Felix is working…" }
        if !ws.connected { return "Offline" }
        if listening { return "Listening…" }
        return "Online"
    }

    // MARK: - Transcription card (frosted glass)

    private var transcriptionCard: some View {
        HStack(spacing: 10) {
            Image(systemName: promptFocused ? "text.cursor" : (listening ? "waveform" : "mic.fill"))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(listening ? Color.felix : .white.opacity(0.7))
                .symbolEffect(.variableColor.iterative, isActive: listening)
                .frame(width: 22)

            TextField(text: $typedPrompt) {
                Text(speech.command.isEmpty ? "Say “Hey Felix” or type a command"
                                            : speech.command)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .focused($promptFocused)
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.white)
            .submitLabel(.done)
            .onSubmit { promptFocused = false }

            if typedPrompt.isEmpty, !speech.transcriptionEngine.isEmpty, !speech.command.isEmpty {
                Text(speech.transcriptionEngine)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(speech.transcriptionEngine == "Whisper" ? Color.felix : .white.opacity(0.6))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(
                        (speech.transcriptionEngine == "Whisper" ? Color.felix : Color.white).opacity(0.15),
                        in: Capsule()
                    )
            }

            if !typedPrompt.isEmpty {
                Button {
                    typedPrompt = ""
                    promptFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frostedCard(cornerRadius: 18)
    }

    // MARK: - Controls (long-task toggle + shutter)

    private var controls: some View {
        ZStack {
            Shutter(busy: busy, listening: listening, enabled: canCapture) {
                promptFocused = false
                capture(command: effectiveCommand)
            }

            HStack {
                Spacer()
                Button {
                    longTask.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: longTask ? "bolt.fill" : "bolt")
                            .font(.system(size: 16, weight: .heavy))
                        Text("Task")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(longTask ? Color.felix : .white.opacity(0.7))
                    .frame(width: 52, height: 52)
                    .frostedCard(cornerRadius: 16)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 28)
                .accessibilityLabel(longTask ? "Long task mode on" : "Long task mode off")
            }
        }
    }

    // MARK: - Actions

    private func triggerWakeFlash() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.easeOut(duration: 0.08)) { wakeFlash = 0.5 }
        withAnimation(.easeIn(duration: 0.45).delay(0.08)) { wakeFlash = 0 }
    }

    private func capture(command: String) {
        guard !busy else { return }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        Task { @MainActor in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeOut(duration: 0.06)) { flash = 0.85 }
            let image = await camera.capturePhoto()
            withAnimation(.easeIn(duration: 0.28)) { flash = 0 }

            sending = true
            defer { sending = false }
            if longTask {
                _ = try? await APIClient.createTask(instruction: trimmed,
                                                    sessionID: sessionID, baseURL: baseURL)
            } else {
                _ = try? await APIClient.ingest(image: image, voiceText: trimmed,
                                                sessionID: sessionID, baseURL: baseURL)
            }
            speech.reset()
            typedPrompt = ""
        }
    }
}

// MARK: - Vignette border (pulses while listening)

private struct VignetteBorder: View {
    let listening: Bool
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 0)
            .strokeBorder(
                listening ? Color.felix.opacity(pulse ? 0.9 : 0.3) : Color.white.opacity(0.06),
                lineWidth: listening ? 6 : 2
            )
            .blur(radius: listening ? 6 : 1)
            .ignoresSafeArea()
            .overlay(
                RadialGradient(
                    colors: [.clear, listening ? Color.felix.opacity(pulse ? 0.22 : 0.06) : .clear],
                    center: .center, startRadius: 180, endRadius: 520
                )
                .ignoresSafeArea()
            )
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onChange(of: listening) { _, now in pulse = now }
            .onAppear { pulse = listening }
    }
}

/// Expanding ring used by the status dot when connected.
private struct PulseRing: View {
    let active: Bool
    let color: Color
    @State private var on = false
    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .scaleEffect(on ? 2.4 : 1)
            .opacity(on ? 0 : 0.7)
            .onAppear {
                guard active else { return }
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

// MARK: - Shutter

private struct Shutter: View {
    let busy: Bool
    let listening: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var ring = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Listening ring animation (red, pulsing).
                if listening {
                    Circle()
                        .stroke(Color.red.opacity(0.9), lineWidth: 5)
                        .frame(width: 92, height: 92)
                        .scaleEffect(ring ? 1.08 : 0.92)
                        .opacity(ring ? 0.4 : 1)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: ring)
                        .onAppear { ring = true }
                }
                Circle().stroke(.white.opacity(0.9), lineWidth: 4).frame(width: 84, height: 84)
                Circle()
                    .fill(busy ? Color.white.opacity(0.45) : .white)
                    .frame(width: 70, height: 70)
                if busy { ProgressView().tint(.black) }
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel("Capture and send to Felix")
    }
}

// MARK: - Task progress toast (background autonomous task)

private struct TaskProgressToast: View {
    let task: TaskState
    var body: some View {
        HStack(spacing: 12) {
            ToolBadge(tool: nil, size: 42)
                .overlay(Image(systemName: "bolt.fill").font(.system(size: 17, weight: .heavy)).foregroundStyle(.black))
            VStack(alignment: .leading, spacing: 5) {
                Text("WORKING IN BACKGROUND")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.6))
                Text(task.instruction)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white).lineLimit(1)
                ProgressView(value: Double(task.progressPct), total: 100)
                    .tint(.felix)
                    .scaleEffect(x: 1, y: 0.8, anchor: .center)
            }
            Text("\(task.progressPct)%")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .monospacedDigit()
        }
        .padding(12)
        .frostedCard()
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: task.progressPct)
    }
}

// MARK: - Result bottom sheet

private struct ResultSheet: View {
    let result: StepResult
    @Environment(\.dismiss) private var dismiss

    private var failed: Bool { result.status == "error" }
    private var meta: (label: String, symbol: String) { toolMeta(result.tool) }

    var body: some View {
        VStack(spacing: 18) {
            ToolBadge(tool: result.tool, size: 76, failed: failed)
                .padding(.top, 26)

            VStack(spacing: 6) {
                Text(failed ? "Couldn’t complete" : meta.label.uppercased())
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.6))
                Text(result.title ?? meta.label)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if let message = result.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            if let urlString = result.url, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.forward.app.fill")
                        Text("Open")
                    }
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.felix, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 20)
            }

            Button("Dismiss") { dismiss() }
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Summary sheet (content tools: calendar, reminders, contacts, research…)

private struct SummarySheet: View {
    let result: StepResult
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var meta: (label: String, symbol: String) { toolMeta(result.tool) }

    /// Structured data reads better monospaced; prose reads better in SF Pro.
    private var monospaced: Bool {
        switch result.tool {
        case "web.research", "screen.capture_and_describe": return false
        default: return true
        }
    }

    private var displayName: String {
        switch result.tool {
        case "calendar.read_today": return "Today's Calendar"
        case "calendar.read_week": return "This Week"
        case "reminders.read_list": return "Reminders"
        case "contacts.find": return "Contact"
        case "system.get_battery": return "Battery Status"
        case "web.research": return "Research"
        case "screen.capture_and_describe": return "On Your Screen"
        default: return result.title ?? meta.label
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.felix)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: meta.symbol)
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(.black)
                    )
                Text(displayName)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider().overlay(Color.white.opacity(0.15))

            ScrollView {
                Text(result.summary ?? result.message ?? "")
                    .font(monospaced
                          ? .system(size: 14, weight: .regular, design: .monospaced)
                          : .system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(20)
            }

            Divider().overlay(Color.white.opacity(0.15))

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = result.summary ?? result.message ?? ""
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation { copied = true }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc.fill")
                        Text(copied ? "Copied!" : "Copy")
                    }
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.felix)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.felix.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button { dismiss() } label: {
                    Text("Dismiss")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }
}
