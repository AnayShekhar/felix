# Lumis iOS App

SwiftUI client: capture an image + speak a command → POST to the Lumis backend →
structured result streams back live over WebSocket.

## Build it in Xcode (on any Mac)

1. **Xcode → Create New Project → iOS → App.**
   - Product Name: `Lumis`
   - Interface: **SwiftUI**, Language: **Swift**
   - Save it anywhere (e.g. inside this repo).
2. **Delete** the auto-generated `ContentView.swift` and `LumisApp.swift` from the project.
3. **Drag all the `.swift` files from `ios/Lumis/` into the Xcode project navigator.**
   Check "Copy items if needed" and add to the `Lumis` target.
4. **Set the backend URL:** open `Config.swift` and replace
   `https://YOUR-CLOUD-RUN-URL.run.app` with your deployed Cloud Run URL.
5. **Add privacy permissions.** Target → **Info** tab → add three keys:
   - `Privacy - Camera Usage Description` → "Lumis uses the camera to capture context."
   - `Privacy - Microphone Usage Description` → "Lumis uses the mic for voice commands."
   - `Privacy - Speech Recognition Usage Description` → "Lumis transcribes your voice command."
6. **Run.** Simulator works for everything except the real camera (it falls back to the
   photo library). For real camera + best results, run on a physical iPhone
   (select your device, set a Signing Team under Signing & Capabilities).

## Files
| File | Role |
|---|---|
| `LumisApp.swift` | App entry point |
| `Config.swift` | **Backend URL — edit this** |
| `Models.swift` | Input/output data contracts |
| `APIClient.swift` | POST `/ingest` |
| `WebSocketClient.swift` | Live `/ws` updates |
| `SpeechRecognizer.swift` | Voice → text (Speech framework) |
| `CameraPicker.swift` | Camera/photo capture |
| `ContentView.swift` | UI |
