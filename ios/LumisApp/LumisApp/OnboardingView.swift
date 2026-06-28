import SwiftUI
import UIKit

/// First-launch onboarding (Phase 9). Three swipeable screens that explain the
/// product and capture the backend URL. Presented full-screen from ContentView
/// while UserDefaults "lumis.onboardingComplete" is false/missing.
///
/// Design: dark background, amber accent (LumisBrand.accent #F59E21), SF Pro
/// Heavy headlines, SF Pro Regular body. Calls `onFinish` when the user is ready.
struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    let onFinish: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Subtle amber glow behind the slides.
            RadialGradient(colors: [Color.lumis.opacity(0.16), .clear],
                           center: .top, startRadius: 20, endRadius: 480)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    OnboardScreenOne(advance: { withAnimation { page = 1 } }).tag(0)
                    OnboardScreenTwo(advance: { withAnimation { page = 2 } }).tag(1)
                    OnboardScreenThree(settings: settings, onFinish: onFinish).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                PageDots(count: 3, index: page)
                    .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Shared building blocks

private struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.lumis : Color.white.opacity(0.25))
                    .frame(width: i == index ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
            }
        }
    }
}

/// Full-width amber primary button used across slides.
private struct AmberButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Color.lumis, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SlideText: View {
    let eyebrow: String
    let headline: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Text(eyebrow.uppercased())
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.lumis)
                .tracking(1.5)
            Text(headline)
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }
}

// MARK: - Screen 1

private struct OnboardScreenOne: View {
    let advance: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.lumis.opacity(0.12))
                    .frame(width: 200, height: 200)
                    .scaleEffect(pulse ? 1.08 : 0.92)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 96, weight: .light))
                    .foregroundStyle(Color.lumis)
                    .symbolEffect(.pulse, isActive: true)
            }
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }

            Spacer().frame(height: 44)

            SlideText(eyebrow: "Your camera is now a command",
                      headline: "Point. Speak. Done.",
                      message: "Show Lumis anything in the real world. It figures out what to do on your Mac.")

            // Example visual: receipt → Numbers.
            ExampleFlow(fromSymbol: "doc.text.viewfinder", fromLabel: "Receipt",
                        toSymbol: "tablecells.fill", toLabel: "Numbers")
                .padding(.top, 28)

            Spacer()
            AmberButton(title: "Next", systemImage: "arrow.right") { advance() }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - Screen 2

private struct OnboardScreenTwo: View {
    let advance: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            // iPhone <-> Cloud <-> Mac diagram.
            HStack(spacing: 14) {
                DeviceNode(symbol: "iphone", label: "iPhone")
                ConnArrow()
                DeviceNode(symbol: "cloud.fill", label: "Cloud")
                ConnArrow()
                DeviceNode(symbol: "desktopcomputer", label: "Mac")
            }
            .padding(.horizontal, 16)

            Spacer().frame(height: 44)

            SlideText(eyebrow: "Lumis lives on both your devices",
                      headline: "One brain. Two devices.",
                      message: "Speak on your phone. Execute on your Mac. Results come back to you instantly.")

            // Example command text.
            Text("“Hey Lumis, add this receipt to my expenses.”")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frostedCard(cornerRadius: 16)
                .padding(.horizontal, 28)
                .padding(.top, 28)

            Spacer()
            AmberButton(title: "Next", systemImage: "arrow.right") { advance() }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
        }
    }
}

private struct DeviceNode: View {
    let symbol: String
    let label: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Color.lumis)
                .frame(width: 64, height: 64)
                .frostedCard(cornerRadius: 18)
            Text(label)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

private struct ConnArrow: View {
    @State private var slide = false
    var body: some View {
        Image(systemName: "arrow.left.arrow.right")
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(Color.lumis.opacity(slide ? 1 : 0.4))
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: slide)
            .onAppear { slide = true }
    }
}

private struct ExampleFlow: View {
    let fromSymbol: String
    let fromLabel: String
    let toSymbol: String
    let toLabel: String
    var body: some View {
        HStack(spacing: 16) {
            DeviceNode(symbol: fromSymbol, label: fromLabel)
            Image(systemName: "arrow.right")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.lumis)
            DeviceNode(symbol: toSymbol, label: toLabel)
        }
    }
}

// MARK: - Screen 3 — connect

private struct OnboardScreenThree: View {
    @ObservedObject var settings: AppSettings
    let onFinish: () -> Void

    @State private var urlText = ""
    @State private var testing = false
    @State private var testResult: TestResult?
    @State private var showSetupInfo = false

    private enum TestResult { case ok(Int), fail(String) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 24)
            Image(systemName: "link.circle.fill")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Color.lumis)
                .padding(.bottom, 18)

            SlideText(eyebrow: "Let's connect",
                      headline: "Connect your Mac",
                      message: "Point Lumis at your backend so your phone and Mac can talk.")

            VStack(spacing: 14) {
                TextField(text: $urlText) {
                    Text("https://your-backend-url").foregroundStyle(.white.opacity(0.4))
                }
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.done)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frostedCard(cornerRadius: 14)

                Button(action: runTest) {
                    HStack(spacing: 8) {
                        if testing { ProgressView().tint(.white).scaleEffect(0.8) }
                        else { Image(systemName: "bolt.horizontal.circle.fill") }
                        Text(testing ? "Testing…" : "Test Connection")
                    }
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .frostedCard(cornerRadius: 14)
                }
                .buttonStyle(.plain)
                .disabled(testing || trimmedURL.isEmpty)
                .opacity(trimmedURL.isEmpty ? 0.5 : 1)

                resultBanner

                Button(action: { showSetupInfo = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "desktopcomputer")
                        Text("Grant Mac Permissions")
                    }
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color.lumis)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.lumis.opacity(0.6), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            Spacer()

            AmberButton(title: "I'm ready", systemImage: "checkmark") {
                persistURL()
                onFinish()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
        .onAppear { if urlText.isEmpty { urlText = settings.backendOverride } }
        .alert("Grant Mac Permissions", isPresented: $showSetupInfo) {
            Button("Open Lumis on Mac") {
                if let url = URL(string: "lumis://setup") { openExternal(url) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("On your Mac, open the Lumis menu-bar app and allow Accessibility & Automation permissions in System Settings › Privacy & Security so Lumis can control your apps.")
        }
    }

    private var trimmedURL: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }

    @ViewBuilder private var resultBanner: some View {
        switch testResult {
        case .ok(let ms):
            Label("Connected · \(ms) ms", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(LumisBrand.online)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .fail(let msg):
            Label(msg, systemImage: "xmark.octagon.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(LumisBrand.error)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .none:
            EmptyView()
        }
    }

    private func persistURL() {
        let clean = trimmedURL.hasSuffix("/") ? String(trimmedURL.dropLast()) : trimmedURL
        settings.backendOverride = clean
    }

    private func runTest() {
        persistURL()
        testResult = nil
        testing = true
        let base = trimmedURL.hasSuffix("/") ? String(trimmedURL.dropLast()) : trimmedURL
        Task {
            let start = Date()
            do {
                guard let url = URL(string: "\(base)/health") else {
                    throw URLError(.badURL)
                }
                var req = URLRequest(url: url)
                req.timeoutInterval = 8
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(code) else {
                    throw NSError(domain: "lumis", code: code,
                                  userInfo: [NSLocalizedDescriptionKey: "Server returned \(code)"])
                }
                let serverMs = (try? JSONDecoder().decode(HealthResponse.self, from: data))?.latency_ms
                let ms = serverMs ?? Int(Date().timeIntervalSince(start) * 1000)
                await MainActor.run { testResult = .ok(ms); testing = false }
            } catch {
                await MainActor.run {
                    testResult = .fail(error.localizedDescription)
                    testing = false
                }
            }
        }
    }

    private func openExternal(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

/// GET /health → { status: "ok", latency_ms }
private struct HealthResponse: Decodable {
    let status: String?
    let latency_ms: Int?
}

#Preview {
    OnboardingView(settings: AppSettings()) {}
}
