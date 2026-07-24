# Lumis iOS App

SwiftUI client in `ios/LumisApp/` — capture an image + speak a command → POST to
the Lumis backend → structured results stream live over WebSocket.

## Build

1. Open `ios/LumisApp/LumisApp.xcodeproj` in Xcode (iOS 17+).
2. Select a Signing Team under Signing & Capabilities.
3. Run on a simulator or device. Simulator falls back to the photo library for
   camera; physical device gets the real camera + mic.

Backend URL defaults to Railway production via `LumisConfig.backendURL`
(`https://lumis-production-b878.up.railway.app`). Auth token lives in the Keychain.

## Notes

- Privacy usage strings (camera / mic / speech) are set via Xcode build settings
  (`INFOPLIST_KEY_NS*UsageDescription`).
- Do not edit `CameraManager.swift` or `SpeechRecognizer.swift` unless explicitly
  asked — they are constrained files.
- `ios/Lumis/` is a legacy sample folder and is not part of the current Xcode
  project.
