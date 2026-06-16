import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var speech = SpeechRecognizer()
    @StateObject private var ws = WebSocketClient()
    @StateObject private var discovery = MacDiscovery()

    @State private var sending = false
    @State private var flash = 0.0
    @State private var typedPrompt = ""
    @FocusState private var promptFocused: Bool

    private let sessionID = "ios-\(UUID().uuidString.prefix(6))"

    private var busy: Bool { sending || ws.working }

    /// Typed prompt wins over voice when both are present.
    private var effectiveCommand: String {
        let typed = typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return speech.command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCapture: Bool {
        !busy && discovery.baseURL != nil && !effectiveCommand.isEmpty
    }

    var body: some View {
        ZStack {
            // Live camera feed.
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            // Legibility gradients.
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.65)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            Viewfinder()
                .padding(40)
                .allowsHitTesting(false)

            // Capture flash.
            Color.white.opacity(flash).ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let result = ws.latest {
                    ResultToast(result: result).padding(.horizontal, 20).padding(.bottom, 14)
                }
                statusChip
                    .padding(.bottom, 12)
                promptBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                shutter
                    .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear(perform: setup)
        .onChange(of: discovery.baseURL) { _, base in
            guard let base else {
                ws.disconnect()
                return
            }
            ws.connect(to: Config.wsURL(base: base))
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 15, weight: .bold))
                Text("Felix")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(ws.connected ? Color.green : Color.white.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(ws.connected ? "Live" : "Offline")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var statusChip: some View {
        HStack(spacing: 9) {
            Group {
                if busy {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else if speech.phase == .hearing {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative)
                } else {
                    Image(systemName: "mic.fill")
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)

            Text(statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                speech.phase == .hearing ? Color.white.opacity(0.5) : Color.white.opacity(0.12),
                lineWidth: 1
            )
        )
        .animation(.easeInOut(duration: 0.2), value: speech.phase)
        .animation(.easeInOut(duration: 0.2), value: busy)
    }

    private var statusText: String {
        if busy { return "Felix is working…" }
        if !ws.connected { return discovery.statusText }
        if promptFocused { return "Type your command…" }
        if !effectiveCommand.isEmpty { return effectiveCommand }
        switch speech.phase {
        case .hearing:
            return "Listening…"
        case .waiting:
            return "Say “Hey Felix” or type below"
        case .idle:
            return "Starting…"
        }
    }

    private var promptBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.cursor")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            TextField("turn this into notes", text: $typedPrompt)
                .focused($promptFocused)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .submitLabel(.done)
                .onSubmit { promptFocused = false }

            if !typedPrompt.isEmpty {
                Button {
                    typedPrompt = ""
                    promptFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    promptFocused ? Color.white.opacity(0.45) : Color.white.opacity(0.12),
                    lineWidth: 1
                )
        )
    }

    private var shutter: some View {
        Button {
            promptFocused = false
            capture(command: effectiveCommand)
        } label: {
            ZStack {
                Circle().stroke(.white.opacity(0.9), lineWidth: 4).frame(width: 74, height: 74)
                Circle()
                    .fill(busy ? Color.white.opacity(0.5) : Color.white)
                    .frame(width: 60, height: 60)
                if busy {
                    ProgressView().tint(.black)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canCapture)
        .opacity(canCapture ? 1 : 0.5)
        .accessibilityLabel("Capture and send to Felix")
    }

    // MARK: - Actions

    private func setup() {
        speech.requestPermission()
        camera.start()
        discovery.start()
        speech.startListening()
    }

    private func capture(command: String) {
        guard !busy else { return }
        guard let baseURL = discovery.baseURL else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        // Require a spoken command — sending an empty one makes Felix guess from
        // the image alone and produce a random note/expense.
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
            try? await APIClient.ingest(
                image: image,
                voiceText: trimmed,
                sessionID: sessionID,
                baseURL: baseURL
            )
            // Sent — clear voice + typed prompt for the next capture.
            speech.reset()
            typedPrompt = ""
        }
    }
}

// MARK: - Result toast

private struct ResultToast: View {
    let result: StepResult

    private var failed: Bool { result.status == "error" }
    private var meta: (label: String, symbol: String) { toolMeta(result.tool) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(failed ? Color.red : Color.white)
                    .frame(width: 42, height: 42)
                Image(systemName: failed ? "exclamationmark.triangle.fill" : meta.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(failed ? .white : .black)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(failed ? "Couldn’t complete" : meta.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
                Text(result.title ?? meta.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let message = result.message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if let urlString = result.url, let url = URL(string: urlString) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .background(.white, in: Circle())
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: result.id)
    }
}

private func toolMeta(_ tool: String?) -> (label: String, symbol: String) {
    switch tool {
    case "notes.create_from_image": return ("Apple Notes", "note.text")
    case "numbers.create_spreadsheet", "numbers.add_expense": return ("Apple Numbers", "tablecells")
    case "slides.create_presentation": return ("Google Slides", "rectangle.on.rectangle")
    case "gmail.draft_email": return ("Gmail", "envelope.fill")
    case "browser.open_url": return ("Chrome", "globe")
    case "spotify.play_song": return ("Spotify", "music.note")
    default: return (tool ?? "Done", "checkmark.seal.fill")
    }
}

// MARK: - Viewfinder brackets

private struct Viewfinder: View {
    var body: some View {
        GeometryReader { geo in
            let len: CGFloat = 26
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                // top-left
                p.move(to: CGPoint(x: 0, y: len)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: len, y: 0))
                // top-right
                p.move(to: CGPoint(x: w - len, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: len))
                // bottom-left
                p.move(to: CGPoint(x: 0, y: h - len)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: len, y: h))
                // bottom-right
                p.move(to: CGPoint(x: w - len, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - len))
            }
            .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}

#Preview {
    ContentView()
}
