import UIKit
import SwiftUI
import UniformTypeIdentifiers
import PDFKit

/// Phase 7 — Felix Share Extension.
///
/// Accepts text, URLs, images, and PDFs from the iOS share sheet, lets the user
/// edit the instruction, and POSTs to the backend `/ingest` endpoint.
///
/// IMPORTANT (App Group): app extensions do NOT share `UserDefaults.standard`
/// with the host app. To read the backend URL the user configured in the main
/// app, both targets must join the same App Group (see ShareViewController's
/// `backendBaseURL`). If the group isn't configured we fall back to standard
/// defaults (which will be empty in the extension) and finally the public URL.
final class ShareViewController: UIViewController {

    /// MUST match AppSettings.appGroupID in the main app.
    private static let appGroupID = "group.com.felix.shared"
    private static let backendURLKey = "felix.backendURL"
    private static let fallbackURL = "https://greyhound-self-division.ngrok-free.dev"

    private var model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let host = UIHostingController(rootView: ShareRootView(
            model: model,
            onSend: { [weak self] in self?.send() },
            onCancel: { [weak self] in self?.cancel() }
        ))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        extractSharedContent()
    }

    // MARK: - Extraction

    private func extractSharedContent() {
        guard let item = (extensionContext?.inputItems as? [NSExtensionItem])?.first,
              let providers = item.attachments else {
            model.defaultPrompt = "What should Felix do with this?"
            return
        }

        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                    if let data, let image = UIImage(data: data) {
                        DispatchQueue.main.async {
                            self?.model.imageBase64 = data.base64EncodedString()
                            self?.model.previewImage = image
                            self?.model.defaultPrompt = "What should Felix do with this image?"
                        }
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { [weak self] url, _ in
                    if let url, let text = Self.firstPDFText(url, limit: 500) {
                        DispatchQueue.main.async {
                            self?.model.contextText = text
                            self?.model.previewText = text
                            self?.model.defaultPrompt = "Summarize this PDF"
                        }
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] obj, _ in
                    if let url = obj as? URL {
                        DispatchQueue.main.async {
                            self?.model.voiceText = "Open and summarize \(url.absoluteString)"
                            self?.model.previewText = url.absoluteString
                            self?.model.defaultPrompt = "Open and summarize \(url.absoluteString)"
                        }
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] obj, _ in
                    if let text = obj as? String {
                        DispatchQueue.main.async {
                            self?.model.voiceText = text
                            self?.model.previewText = text
                            self?.model.defaultPrompt = text
                        }
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if self.model.defaultPrompt.isEmpty {
                self.model.defaultPrompt = "What should Felix do with this?"
            }
            if self.model.prompt.isEmpty {
                self.model.prompt = self.model.defaultPrompt
            }
        }
    }

    private static func firstPDFText(_ url: URL, limit: Int) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var collected = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let s = page.string {
                collected += s
                if collected.count >= limit { break }
            }
        }
        guard !collected.isEmpty else { return nil }
        return String(collected.prefix(limit))
    }

    // MARK: - Networking

    private var backendBaseURL: String {
        let shared = UserDefaults(suiteName: Self.appGroupID)?
            .string(forKey: Self.backendURLKey)
        let standard = UserDefaults.standard.string(forKey: Self.backendURLKey)
        let raw = [shared, standard].compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? Self.fallbackURL
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }

    private func send() {
        model.sending = true
        model.toast = nil

        let prompt = model.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        // The editable prompt is the instruction; PDF text is appended as context.
        var voice = prompt
        if !model.contextText.isEmpty {
            voice += "\n\nContext:\n\(model.contextText)"
        }

        let payload: [String: Any] = [
            "session_id": "ios-share-\(UUID().uuidString.prefix(6))",
            "image": model.imageBase64 ?? NSNull(),       // base64 or null
            "voice_text": voice,
            "timestamp": Date().timeIntervalSince1970,
        ]

        guard let url = URL(string: "\(backendBaseURL)/ingest"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            finishWithError("Couldn't build the request.")
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 20

        URLSession.shared.dataTask(with: req) { [weak self] _, resp, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.model.sending = false
                if let error {
                    self.finishWithError("Felix unreachable: \(error.localizedDescription)")
                    return
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(code) else {
                    self.finishWithError("Felix error (\(code)).")
                    return
                }
                self.model.toast = .success("Felix got it")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.extensionContext?.completeRequest(returningItems: nil)
                }
            }
        }.resume()
    }

    private func finishWithError(_ message: String) {
        // Surface in the UI (never console-only).
        model.sending = false
        model.toast = .error(message)
    }

    private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: "felix.share", code: 0))
    }
}

// MARK: - Shared model

final class ShareModel: ObservableObject {
    @Published var prompt = ""
    @Published var defaultPrompt = ""
    @Published var voiceText = ""
    @Published var contextText = ""        // PDF excerpt appended as context
    @Published var imageBase64: String?
    @Published var previewImage: UIImage?
    @Published var previewText: String?
    @Published var sending = false
    @Published var toast: Toast?

    enum Toast: Equatable {
        case success(String)
        case error(String)
    }
}

// MARK: - SwiftUI UI

private let felixAmber = Color(red: 0.961, green: 0.620, blue: 0.129)

struct ShareRootView: View {
    @ObservedObject var model: ShareModel
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.001).ignoresSafeArea() // catch taps, let blur show
            VStack(spacing: 0) {
                Spacer()
                card
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
        }
        .overlay(alignment: .top) { toastView }
        .preferredColorScheme(.dark)
    }

    private var card: some View {
        VStack(spacing: 16) {
            Capsule().fill(.white.opacity(0.25)).frame(width: 38, height: 5).padding(.top, 10)

            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(felixAmber)
                Text("Send to Felix")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer()
            }

            preview

            TextField("What should Felix do with this?", text: $model.prompt, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            Button(action: onSend) {
                HStack(spacing: 8) {
                    if model.sending { ProgressView().tint(.black).scaleEffect(0.8) }
                    Text(model.sending ? "Sending…" : "Send")
                }
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(felixAmber, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(model.sending || model.prompt.trimmingCharacters(in: .whitespaces).isEmpty)

            Button("Cancel", action: onCancel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    @ViewBuilder private var preview: some View {
        if let image = model.previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let text = model.previewText, !text.isEmpty {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder private var toastView: some View {
        if let toast = model.toast {
            let isError: Bool = { if case .error = toast { return true } else { return false } }()
            let text: String = { switch toast { case .success(let s), .error(let s): return s } }()
            Label(text, systemImage: isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(isError ? Color.red.opacity(0.9) : felixAmber,
                            in: Capsule())
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
