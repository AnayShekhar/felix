import SwiftUI

struct ContentView: View {
    @StateObject private var ws = WebSocketClient()
    @StateObject private var speech = SpeechRecognizer()

    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var sending = false

    private let sessionID = "ios-\(UUID().uuidString.prefix(6))"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .cornerRadius(12)
                    }

                    Button { showCamera = true } label: {
                        Label("Capture Image", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Text(speech.transcript.isEmpty ? "Tap “Record Voice” and speak a command…" : speech.transcript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.gray.opacity(0.1))
                        .cornerRadius(12)

                    Button {
                        if speech.isRecording { speech.stop() } else { try? speech.start() }
                    } label: {
                        Label(speech.isRecording ? "Stop" : "Record Voice",
                              systemImage: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(speech.isRecording ? .red : .accentColor)

                    Button {
                        Task { await send() }
                    } label: {
                        if sending {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Send to Lumis").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sending || speech.transcript.isEmpty)

                    Divider()

                    HStack {
                        Circle().fill(ws.connected ? .green : .red).frame(width: 10, height: 10)
                        Text(ws.connected ? "Live connected" : "Disconnected")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let r = ws.latest {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(r.title).font(.headline)
                            Text("action: \(r.action)  •  target: \(r.target)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(r.content).font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.blue.opacity(0.08))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Lumis")
            .sheet(isPresented: $showCamera) { CameraPicker(image: $image) }
            .onAppear {
                speech.requestPermission()
                ws.connect()
            }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        // Result will stream back over the WebSocket and update ws.latest.
        try? await APIClient.ingest(image: image, voiceText: speech.transcript, sessionID: sessionID)
    }
}

#Preview {
    ContentView()
}
