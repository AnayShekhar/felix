# Lumis — Connect iOS App to Chrome Extension Services

The Chrome extension and backend (`/connect/status`, `/connect/cookies/sync`) are
built and working. The iOS app currently has no UI reflecting any of this. This
prompt wires the iPhone app to read and display connected services, and guides
users who haven't connected anything yet toward the Chrome extension.

Do not touch the Chrome extension or backend — they are done. iOS only.

---

## Part 1 — Audit first, and remove the Mac app entirely

The `macos-app/` folder still exists in the repo from before the cloud browser
pivot. Delete it completely:

```bash
rm -rf macos-app
```

Then grep the entire repo for any remaining references to the deleted Mac system
and remove/fix each one:

```bash
grep -ril "macos-app\|mac_agent\|MacConnectionViewModel\|MacLinkingView\|MacDetailView\|mac_bridge" . --exclude-dir=.git --exclude-dir=node_modules
```

This should catch things like:
- Any `import` or reference to Mac-related Swift files that no longer exist
- Any mention of `macos-app` in `README.md`, `DEPLOY.md`, or other docs
- Any leftover route registrations in `backend/main.py` referencing `linking.py`
  or `mac_agent.py` if those weren't already fully removed in the cloud browser
  migration
- Any Xcode workspace/project references to the old Mac target

Fix every result before moving on — do not leave dangling references to deleted
files, as these will cause build failures or confusing dead code paths.

Before writing new code, also check `ios/LumisApp/SettingsView.swift` for any
remaining "Mac Connection" section from before the cloud browser pivot. If found,
remove it entirely — it's dead code referencing a system that no longer exists
(no Mac app, no Mac agent, no pairing).

Also check for any lingering `MacConnectionViewModel`, `MacLinkingView`,
`MacDetailView`, or Mac status dot references in `HomeView.swift` — remove if present.

---

## Part 2 — ConnectedServicesViewModel

Create `ios/LumisApp/ConnectedServicesViewModel.swift`:

```swift
import Foundation

struct ServiceDefinition: Identifiable {
    let id: String              // "gmail", "sheets", "notion", etc. — matches backend service names
    let displayName: String
    let icon: String            // SF Symbol name or asset name
    let description: String
}

let SUPPORTED_SERVICES: [ServiceDefinition] = [
    ServiceDefinition(id: "gmail",    displayName: "Gmail",         icon: "envelope.fill",      description: "Read and draft emails"),
    ServiceDefinition(id: "sheets",   displayName: "Google Sheets", icon: "tablecells.fill",    description: "Track expenses and data"),
    ServiceDefinition(id: "notion",   displayName: "Notion",        icon: "doc.text.fill",      description: "Create and edit pages"),
    ServiceDefinition(id: "linkedin", displayName: "LinkedIn",      icon: "person.crop.circle", description: "Search and post updates"),
    ServiceDefinition(id: "slack",    displayName: "Slack",         icon: "message.fill",       description: "Send messages"),
    ServiceDefinition(id: "airtable", displayName: "Airtable",      icon: "square.grid.3x3.fill", description: "Manage records"),
]

@MainActor
class ConnectedServicesViewModel: ObservableObject {
    @Published var connectedServiceIds: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchStatus() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: ConnectStatusResponse = try await apiClient.get("/connect/status")
            connectedServiceIds = Set(response.connected)
        } catch {
            errorMessage = "Couldn't load connected services"
        }
        isLoading = false
    }

    func isConnected(_ serviceId: String) -> Bool {
        connectedServiceIds.contains(serviceId)
    }

    var hasAnyConnection: Bool {
        !connectedServiceIds.isEmpty
    }
}

struct ConnectStatusResponse: Codable {
    let connected: [String]
}
```

Wire this into the app's environment objects alongside `AuthViewModel` and
`LumisViewModel` in `LumisApp.swift`:

```swift
@StateObject var connectedServicesVM: ConnectedServicesViewModel
// initialize with the same APIClient instance used elsewhere
```

---

## Part 3 — Settings → Connected Services section

In `SettingsView.swift`, add (or replace the old Mac Connection section with):

```swift
SECTION: CONNECTED SERVICES

if connectedServicesVM.hasAnyConnection {
    ForEach(SUPPORTED_SERVICES) { service in
        HStack {
            Image(systemName: service.icon)
                .foregroundColor(LumisColors.carbonBlack.opacity(0.6))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName)
                    .font(LumisTypography.bodyMedium)
                    .foregroundColor(LumisColors.carbonBlack)
                Text(service.description)
                    .font(LumisTypography.caption)
                    .foregroundColor(LumisColors.carbonBlack.opacity(0.5))
            }
            Spacer()
            if connectedServicesVM.isConnected(service.id) {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(LumisTypography.caption)
                    .foregroundColor(LumisColors.success)
            } else {
                Text("Not connected")
                    .font(LumisTypography.caption)
                    .foregroundColor(LumisColors.carbonBlack.opacity(0.3))
            }
        }
        .padding(.vertical, 8)
    }

    Divider()

    Button(action: { showExtensionInstructions = true }) {
        Label("Connect more accounts", systemImage: "plus.circle")
            .font(LumisTypography.bodyMedium)
            .foregroundColor(LumisColors.powderBlue)
    }
} else {
    ConnectServicesEmptyState(onGetStarted: { showExtensionInstructions = true })
}
```

Add `.task { await connectedServicesVM.fetchStatus() }` to `SettingsView`'s body
so it refreshes every time the user opens Settings — this is the moment they're
most likely checking after connecting something in the extension.

Also refresh on pull-to-refresh if the Settings screen uses a `List` or `ScrollView`
with `.refreshable`.

---

## Part 4 — Empty state / onboarding nudge

Create `ConnectServicesEmptyState.swift`:

```swift
import SwiftUI

struct ConnectServicesEmptyState: View {
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 32))
                .foregroundColor(LumisColors.powderBlue)

            Text("No accounts connected yet")
                .font(LumisTypography.titleSmall)
                .foregroundColor(LumisColors.carbonBlack)

            Text("Install the Lumis Chrome extension on your computer to connect Gmail, Sheets, Notion, and more.")
                .font(LumisTypography.bodySmall)
                .foregroundColor(LumisColors.carbonBlack.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onGetStarted) {
                Text("How to connect")
                    .font(LumisTypography.bodyMedium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(LumisColors.carbonBlack)
                    .cornerRadius(20)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
```

---

## Part 5 — "How to connect" instructions sheet

Create `ExtensionInstructionsView.swift` — a simple sheet explaining the setup
since there's no in-app way to install a Chrome extension on the user's computer
from their phone:

```swift
import SwiftUI

struct ExtensionInstructionsView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Connect your accounts")
                        .font(LumisTypography.displayMedium)
                        .foregroundColor(LumisColors.carbonBlack)

                    Text("Lumis uses a small Chrome extension on your computer to securely connect your accounts. Your phone tells Lumis what to do — the extension is just how it gets access.")
                        .font(LumisTypography.bodyMedium)
                        .foregroundColor(LumisColors.carbonBlack.opacity(0.7))

                    stepRow(number: 1, text: "On your computer, open Chrome and go to the Lumis extension link")
                    stepRow(number: 2, text: "Sign in with the same account you used on your phone")
                    stepRow(number: 3, text: "Tap Connect next to each account you want Lumis to use")
                    stepRow(number: 4, text: "Come back here — it'll show up automatically")

                    Button(action: {
                        if let url = URL(string: "https://lumis-production-b878.up.railway.app/extension") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Text("Copy extension link")
                            .font(LumisTypography.bodyMedium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LumisColors.carbonBlack)
                            .cornerRadius(14)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
            .background(LumisColors.parchment)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(LumisTypography.bodyMedium.bold())
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(LumisColors.powderBlue)
                .clipShape(Circle())
            Text(text)
                .font(LumisTypography.bodyMedium)
                .foregroundColor(LumisColors.carbonBlack)
        }
    }
}
```

Note: since there's no Chrome Web Store listing yet (extension is unpacked/dev
mode), "Copy extension link" should instead show a simple instruction to reach
out to you directly for the extension folder for now. Replace the button with:

```swift
Text("This extension isn't on the Chrome Web Store yet — ask for the install file directly.")
    .font(LumisTypography.caption)
    .foregroundColor(LumisColors.carbonBlack.opacity(0.5))
```

Swap back to the real link once it's published.

---

## Part 6 — Agent awareness of connected services

Confirm (from earlier work) that `LumisViewModel` or wherever `/ingest` requests
are built includes the current connected services in context, OR that the backend
already fetches this itself per-request via `get_connected_services(user_id)` in
`agent.py`. If the backend already does this server-side, no iOS change is needed
here — just verify by testing:

- [ ] With zero services connected, ask Lumis to "email someone" — it should
      respond telling you to connect Gmail first (via the `service_required` event
      from the backend), not attempt and fail silently
- [ ] Handle the `service_required` WebSocket event in `WebSocketClient.swift` if
      not already handled:

```swift
case "service_required":
    lumisVM.lumisState = .idle
    lumisVM.responseText = ""
    let service = event.service ?? ""
    showServiceRequiredToast(service: service, message: event.message ?? "")
    if let speak = event.speak { TextToSpeech.speak(speak) }
```

The toast/result card in this case should include a button "Connect \(service)"
that opens `ExtensionInstructionsView` directly, pre-scrolled or highlighted to
that specific service if possible — at minimum just opens the same instructions
sheet.

---

## Part 7 — Verification

- [ ] Settings screen shows no leftover Mac Connection UI
- [ ] Settings → Connected Services section loads real data from `/connect/status`
- [ ] Connecting a service via the Chrome extension, then pulling to refresh (or
      reopening) Settings on the phone shows it as "Connected" — same account,
      cross-device sync working correctly
- [ ] Empty state appears correctly for a brand new user with zero connections
- [ ] "How to connect" sheet opens and displays clearly
- [ ] Asking Lumis to do something requiring an unconnected service shows a clear
      in-app message telling the user what to connect, not a silent failure or
      generic error
- [ ] No crashes, no dead references to deleted Mac-related files