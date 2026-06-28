# Lumis — Full Production UI Rebuild

This document is a complete implementation spec. Execute every part in order. The output must be production-level, professional, and shippable. No placeholders, no TODOs in UI code, no half-implemented screens.

---

## Part 1 — Rebrand Felix → Lumis

Do a full find-and-replace across the entire codebase before touching any UI:

| From | To |
|------|----|
| `Felix` | `Lumis` |
| `felix` | `lumis` |
| `FELIX` | `LUMIS` |

Covers: all variable names, class names, struct names, function names, UI strings, comments, docstrings, bundle ID (`com.anay.felix` → `com.anay.lumis`), Info.plist display name, CFBundleName, CFBundleDisplayName, file names, folder names, app scheme URLs, route paths, notification identifiers, keychain service names.

After renaming, run:
```
grep -ri "felix" . --exclude-dir=.git
```
Fix every remaining hit before proceeding.

---

## Part 2 — Global Design System

### Colors

Create `LumisColors.swift` as the **single source of truth** for all colors. Delete every other color definition in the project.

```swift
import SwiftUI

struct LumisColors {
    // Core palette
    static let parchment     = Color(hex: "#F8F3EE")  // Primary background
    static let powderBlue    = Color(hex: "#B0BFD1")  // Accents, active states, glows
    static let carbonBlack   = Color(hex: "#212222")  // Text, icons

    // Derived
    static let powderBlueLight   = Color(hex: "#B0BFD1").opacity(0.15)
    static let powderBlueMid     = Color(hex: "#B0BFD1").opacity(0.55)
    static let textSecondary     = Color(hex: "#212222").opacity(0.5)
    static let textTertiary      = Color(hex: "#212222").opacity(0.3)
    static let divider           = Color(hex: "#212222").opacity(0.08)
    static let cardBackground    = Color(hex: "#FFFFFF").opacity(0.6)
    static let destructive       = Color(hex: "#E05252")
    static let success           = Color(hex: "#4CAF7D")
    static let offline           = Color(hex: "#212222").opacity(0.25)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}
```

### Typography

Create `LumisTypography.swift`:

```swift
import SwiftUI

struct LumisTypography {
    // Display
    static let displayLarge  = Font.system(size: 34, weight: .semibold, design: .default)
    static let displayMedium = Font.system(size: 28, weight: .semibold, design: .default)

    // Title
    static let titleLarge    = Font.system(size: 22, weight: .semibold, design: .default)
    static let titleMedium   = Font.system(size: 17, weight: .semibold, design: .default)
    static let titleSmall    = Font.system(size: 15, weight: .medium, design: .default)

    // Body
    static let bodyLarge     = Font.system(size: 17, weight: .regular, design: .default)
    static let bodyMedium    = Font.system(size: 15, weight: .regular, design: .default)
    static let bodySmall     = Font.system(size: 13, weight: .regular, design: .default)

    // Caption
    static let caption       = Font.system(size: 12, weight: .regular, design: .default)
    static let captionMedium = Font.system(size: 12, weight: .medium, design: .default)

    // Mono
    static let mono          = Font.system(size: 13, weight: .regular, design: .monospaced)
}
```

### Config

Create `LumisConfig.swift`:

```swift
struct LumisConfig {
    static let backendURL    = "https://lumis-production-b878.up.railway.app"
    static let websocketURL  = "wss://lumis-production-b878.up.railway.app/ws"
    static let appVersion    = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    static let buildNumber   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
}
```

Replace every hardcoded URL string throughout the entire codebase with `LumisConfig.backendURL` or `LumisConfig.websocketURL`.

---

## Part 3 — Authentication System

### Overview

Full email/password auth with Sign in with Apple and Sign in with Google. JWT tokens stored in Keychain. All auth state managed by `AuthViewModel`. No screen in the app is accessible without being authenticated.

### Backend endpoints required

```
POST /auth/register         { email, password, name }        → { token, user }
POST /auth/login            { email, password }              → { token, user }
POST /auth/apple            { identityToken, fullName }      → { token, user }
POST /auth/google           { idToken }                      → { token, user }
POST /auth/logout           (bearer token)                   → { success }
DELETE /auth/account        (bearer token)                   → { success }
GET  /auth/me               (bearer token)                   → { user }
```

### Keychain

Create `KeychainManager.swift` with `save`, `load`, and `delete` methods for `lumis.auth.token` and `lumis.auth.user`.

### AuthViewModel

`AuthViewModel.swift` manages:
- `isAuthenticated: Bool`
- `currentUser: LumisUser?`
- `isLoading: Bool`
- `error: String?`

Methods: `login`, `register`, `signInWithApple`, `signInWithGoogle`, `logout`, `deleteAccount`, `refreshUser`

On app launch, check Keychain for a stored token and call `GET /auth/me` to validate. If valid → authenticated. If 401 → clear token → show auth screens.

### Auth Screens

#### Splash / Launch Screen

Full Parchment background. The Lumis shape (see Part 5) centered, animated. Below it: "lumis" wordmark in Carbon Black, 28pt semibold. Fades into the login screen after 1.8 seconds if not authenticated, or into the main app if already authenticated.

#### Welcome Screen

- Parchment background
- Lumis shape, smaller (120pt diameter equivalent)
- "lumis" wordmark below it
- Tagline: "Your world, automated." in textSecondary, 15pt
- Spacer
- Two buttons stacked:
  - "Continue with email" — outlined style, Carbon Black border, Carbon Black text
  - "Sign in with Apple" — black filled, white text, Apple logo, uses `ASAuthorizationAppleIDButton`
  - "Continue with Google" — outlined, Google logo SVG inline, Carbon Black text
- "By continuing you agree to our Terms and Privacy Policy" — caption, textTertiary, tappable links

#### Sign Up Screen

- Back button top left
- Title: "Create your account" — titleLarge, Carbon Black
- Fields (in order):
  - Full name
  - Email address
  - Password (toggle visibility)
  - Confirm password (toggle visibility)
- Password strength indicator — 4-segment bar below password field, fills left to right: weak (red), fair (amber), good (blue), strong (green)
- "Create account" — full width filled button, Carbon Black bg, Parchment text
- "Already have an account? Sign in" — bottom, textSecondary

#### Sign In Screen

- Back button top left
- Title: "Welcome back" — titleLarge
- Fields: Email, Password (toggle visibility)
- "Forgot password?" — right aligned, Powder Blue, 13pt
- "Sign in" — full width filled button
- "Don't have an account? Sign up" — bottom

#### Forgot Password Screen

- Email field
- "Send reset link" button
- Success state: checkmark animation, "Check your email" message

#### All input fields:

Rounded rect, 14pt border radius, 1pt border in `divider` color, Parchment fill, Carbon Black text, Powder Blue focus border. Height 52pt. Label floats above on focus (animated placeholder).

---

## Part 4 — Mac Linking System

### Overview

One iPhone links to exactly one Mac at a time. The Mac app displays a 6-digit alphanumeric code. The user enters it in the iPhone app. The backend registers the pairing. The link persists until manually broken.

### Backend endpoints required

```
POST /link/generate                          → { code, expiresAt }   (Mac calls this)
POST /link/pair        { code }  (bearer)    → { macId, macName }    (iPhone calls this)
DELETE /link/unpair              (bearer)    → { success }
GET  /link/status                (bearer)    → { linked, macId, macName, macOnline, lastSeen }
POST /link/heartbeat             (Mac sends) → { success }
```

### Linking flow

**On Mac (agent side):**
1. Mac agent calls `POST /link/generate` → gets a 6-digit code valid for 10 minutes
2. Mac displays the code in a prominent window: large monospaced digits, "Open Lumis on your iPhone and enter this code in Settings → Connect Mac"
3. Mac polls `GET /link/status` every 5 seconds. When `linked: true` arrives, show "Linked to [your iPhone]" success state and close the code window

**On iPhone:**
1. User goes to Settings → "Connect your Mac"
2. Screen shows a text field with 6 large digit boxes (like an OTP input)
3. User types the 6-digit code
4. iPhone calls `POST /link/pair` with the code
5. On success: show checkmark animation, "Connected to [Mac Name]" and return to Settings
6. On failure: shake animation on the code boxes, "Invalid or expired code. Try again."

### Mac connection states (used throughout the app)

```swift
enum MacConnectionState {
    case linked_online      // Mac is linked and currently reachable
    case linked_offline     // Mac is linked but hasn't sent a heartbeat in >30s
    case unlinked           // No Mac paired
    case linking            // Pairing in progress
}
```

### Mac Offline State

When `MacConnectionState == .linked_offline`:
- A persistent non-dismissible banner appears below the top status bar on the Home screen
- Powder Blue background, Carbon Black text: "Your Mac is offline — actions won't run until it reconnects"
- A "Reconnect" button on the right that triggers a manual heartbeat ping
- The Lumis shape dims to 60% opacity and pauses its bloom animation

---

## Part 5 — The Lumis Shape

This is the centerpiece of the app. It must be implemented exactly as described.

### Construction

Build `LumisShapeView.swift` as a standalone SwiftUI view.

It consists of:
- 6 `Circle()` views arranged evenly in a ring (60° apart) around a shared center point
- Each circle: diameter = `containerSize * 0.45`, offset from center by `containerSize * 0.28`
- Each circle: Powder Blue `#B0BFD1`, opacity 0.55, `.blendMode(.screen)`
- A 7th white `Circle()` at the exact center: diameter 44pt, `.blur(radius: 14)`, opacity 0.85, `.blendMode(.screen)` — this is the inner glow

### Animation system

Two independent animations layered:

**Bloom (morphing):**
Each of the 6 circles has an individual `@State var bloomOffset: CGFloat` that animates between a compressed value (circles close to center, shape reads as one circle) and an expanded value (full petal bloom). Use `withAnimation(.easeInOut(duration: bloomDuration).repeatForever(autoreverses: true))`. Each circle's animation has a slight phase delay (`0.0, 0.08, 0.16, 0.24, 0.32, 0.40` second delays) so the bloom is organic and asymmetric rather than mechanical.

**Rotation:**
The entire shape group rotates continuously using a `@State var rotation: Double` driven by a `Timer` or `TimelineView`. One full 360° rotation per `rotationDuration` seconds. Apply with `.rotationEffect(.degrees(rotation))`.

### State-driven behavior

```swift
enum LumisState {
    case idle
    case listening
    case thinking
    case speaking
}
```

| State | Bloom duration | Bloom amplitude | Rotation duration | Opacity | Extra |
|-------|---------------|-----------------|-------------------|---------|-------|
| idle | 2.5s | 100% | 8s | 1.0 | Default |
| listening | 1.2s | 115% | 5s | 1.0 | Ripple rings emit outward |
| thinking | — (paused) | 50% (frozen mid) | 12s | 0.9 | Dreamy slow drift |
| speaking | 0.8s | 125% | 3.5s | 1.0 | High energy |

**Ripple rings (listening state only):**
When state == `.listening`, emit concentric `Circle()` stroke rings from the center outward. Each ring: starts at diameter 60pt, expands to 180pt, opacity 0.4 → 0. Use a `Timer` to emit a new ring every 0.9 seconds. Stagger up to 3 rings on screen at once.

**State transitions:**
All property changes (bloom duration, amplitude, rotation speed, opacity) animate with `.animation(.easeInOut(duration: 0.6), value: lumisState)`.

---

## Part 6 — Tab Bar & Navigation

### Structure

4 tabs in a liquid glass bottom tab bar:

```
[Home]  [History]  [Camera]  [Settings]
```

Tab bar implementation:
- Use a custom tab bar built with `HStack`, NOT the native `TabView` tab bar (which cannot be styled to liquid glass)
- Background: `.ultraThinMaterial` with a Parchment tint overlay at 40% opacity
- Active tab: Powder Blue icon + Powder Blue label, 12pt medium
- Inactive tab: Carbon Black icon at 30% opacity, no label
- Active indicator: small Powder Blue dot below the active icon, 4pt diameter, animated with `.matchedGeometryEffect`
- Height: 83pt total (49pt content + 34pt safe area)
- Top border: 0.5pt Carbon Black at 8% opacity

Icons (SF Symbols):
- Home: `waveform.circle.fill` (active) / `waveform.circle` (inactive)
- History: `clock.fill` / `clock`
- Camera: `camera.fill` / `camera`
- Settings: `gearshape.fill` / `gearshape`

---

## Part 7 — Home Screen

### Layout (top to bottom)

```
[Status bar area — safe]
[Connection status dot + "lumis" wordmark]      ← top, 44pt from safe area top
[Spacer — flexible]
[LumisShapeView — 260pt × 260pt]               ← centered
[16pt gap]
[Transcription / hint text — max 3 lines]       ← 17pt SF Pro Regular
[Spacer — flexible]
[Result card — slides up when action completes] ← conditional
[Custom tab bar]
```

### Connection status (top right)

A 8pt circle dot:
- Powder Blue + subtle pulse animation: Mac online
- Amber `#E8A838`: Mac linked but offline
- `textTertiary`: not linked

Tapping the dot opens a small popover: "Connected to [Mac Name]" or "Mac is offline — last seen X minutes ago" or "No Mac linked — go to Settings to connect".

### Transcription text

```swift
// Behavior by state:
// .idle      → "Say Hey Lumis"       — Powder Blue, 14pt, 60% opacity
// .listening → live transcript text  — Carbon Black, 17pt, words fade in as they arrive
// .thinking  → "Thinking…"           — Powder Blue, 14pt, slow opacity pulse 0.4→0.8
// .speaking  → Lumis response text   — Carbon Black, 17pt
```

Words in listening/speaking states animate in individually: each word appears with `.opacity` 0→1, `.offset(y: 4→0)`, duration 0.2s, staggered by 0.05s per word.

### Result card

Slides up from the bottom above the tab bar when Lumis completes an action. Implementation:

```swift
struct LumisResultCard: View {
    let result: ActionResult  // title, description, actionType, success, deeplink?
    var onDismiss: () -> Void
    var onOpen: (() -> Void)?   // only if deeplink exists
}
```

- Background: `.ultraThinMaterial` + Parchment tint, 16pt corner radius top-left/top-right
- Left side: icon (SF Symbol matching action type), Powder Blue background circle
- Title: 15pt medium, Carbon Black
- Description: 13pt regular, textSecondary, max 2 lines
- Right side: "Open" button (if deeplink exists) + "×" dismiss
- Entrance animation: `.transition(.move(edge: .bottom).combined(with: .opacity))`, spring animation
- Auto-dismisses after 8 seconds unless user interacts
- Swipe down to dismiss

---

## Part 8 — Camera Screen

### Overview

The Camera tab is not always a passive screen. It has two modes:

**Manual mode** (user tapped the Camera tab directly):
User sees a live viewfinder and can capture an image to send with a voice command.

**Auto-triggered mode** (Lumis detected an ambiguous reference):
The backend returns a special response type `{ action: "request_camera", reason: "..." }`. When this is received, the app automatically switches to the Camera tab with a contextual prompt showing why the camera is needed.

### Implementation

```swift
enum CameraMode {
    case manual
    case autoTriggered(reason: String)
    // reason example: "I need to see what you're referring to"
}
```

### Layout

Full screen camera viewfinder (AVFoundation `AVCaptureSession`). On top of the viewfinder:

**Top bar (floating):**
- Back/close button top left (if auto-triggered, closes and returns to Home)
- If auto-triggered: a pill at the top center showing the reason — `.ultraThinMaterial` background, Powder Blue text, e.g. "What should I turn into a spreadsheet?"

**Corner brackets:**
Draw 4 corner bracket marks (like a camera viewfinder) in Powder Blue. Each bracket is 24pt × 24pt, 2pt stroke, rounded caps. Position at 15% inset from each corner. These are pure SwiftUI overlay shapes.

**Bottom area (floating panel):**
- `.ultraThinMaterial` background, full width, 160pt height from bottom
- Large circular shutter button (64pt diameter, white fill, Carbon Black border 2pt) centered
- Left of shutter: mic button — if auto-triggered mode, mic is already active, shows animated waveform
- Right of shutter: photo library picker button
- Above shutter: "Frame what you want Lumis to see, then tap" — 13pt, white 80% opacity

**Flash toggle:** top right, SF Symbol `bolt.fill` / `bolt.slash.fill`, white

**After capture:**
- Shutter fires: brief white flash overlay (opacity 0→0.8→0, 0.15s)
- Image freezes in viewfinder with Powder Blue border
- Transcription field appears above the shutter: "Tell Lumis what to do with this…"
- If auto-triggered: the original voice command is pre-filled and sent automatically after 1.5s (with a cancel button to abort)
- Send button appears: filled Powder Blue circle with arrow icon
- Tapping send: packages image + text → sends to backend → navigates back to Home → Lumis processes

---

## Part 9 — History Screen

### Layout

```
[Navigation bar: "History"]
[Filter chips: All | Successful | Failed | Today]
[List of HistoryItem cards]
```

### HistoryItem card

```swift
struct ActionHistoryItem {
    let id: UUID
    let timestamp: Date
    let userSaid: String        // transcript of what user said
    let lumisAction: String     // what Lumis did, e.g. "Added expense to Numbers"
    let actionType: ActionType  // spreadsheet, email, calendar, file, web, other
    let status: ActionStatus    // success, failed, cancelled
    let imageThumbnail: UIImage? // if camera was used
    let deeplink: URL?
}
```

Card design:
- Parchment background, 12pt corner radius, 1pt `divider` border
- Left: colored icon circle (action type determines color) — 40pt diameter
- Top line: `lumisAction` — 15pt medium, Carbon Black
- Second line: `userSaid` — 13pt regular, textSecondary, truncated to 1 line
- Bottom line: relative timestamp — 12pt, textTertiary ("2 minutes ago", "Yesterday at 3:41 PM")
- Right: status indicator — Powder Blue checkmark (success), red × (failed), gray − (cancelled)
- If `imageThumbnail` exists: 48pt × 48pt rounded thumbnail on the right before the status

Tapping a card expands it inline (not a new screen) showing:
- Full transcript of what user said
- Full description of action taken
- If failed: error message and "Retry" button
- If deeplink: "Open result" button

### Empty state

Lumis shape (small, 80pt, idle animation) centered with:
"Nothing yet. Try saying Hey Lumis and giving it something to do."
14pt, textSecondary, centered.

### Filter chips

Horizontal scroll. Each chip: 13pt medium, 28pt height, 16pt horizontal padding, 8pt radius. Active: Powder Blue background, white text. Inactive: `divider` border, textSecondary text.

---

## Part 10 — Settings Screen

### Layout

Grouped list sections, Parchment background, section headers in 12pt uppercase Carbon Black 40% opacity.

```
[User profile card]

SECTION: MAC CONNECTION
[Connect your Mac / Mac status row]

SECTION: VOICE
[Wake word toggle]
[Microphone sensitivity slider]
[Response verbosity picker]

SECTION: CAMERA
[Auto-open camera for ambiguous commands toggle]
[Camera resolution picker: Standard / High]

SECTION: NOTIFICATIONS
[Action completed toggle]
[Mac went offline toggle]
[Weekly summary toggle]

SECTION: ACCOUNT
[Change email]
[Change password]
[Sign out]
[Delete account]

SECTION: ABOUT
[Version]
[Privacy Policy]
[Terms of Service]
[Send feedback]
```

### User profile card

At the top of Settings (not in a section). Background: white 60% opacity, 16pt radius, 1pt divider border, 16pt padding.

- Avatar: initials circle, 52pt, Powder Blue background, Carbon Black initials, 17pt semibold
- Name: 17pt semibold, Carbon Black
- Email: 13pt regular, textSecondary
- Chevron right → tapping opens Edit Profile screen (change name, avatar)

### Mac Connection row

**If unlinked:**
Row shows: Mac icon + "Connect your Mac" label + Powder Blue "Connect" button right-aligned.
Tapping "Connect" → full screen modal: "Enter the 6-digit code shown on your Mac". 6 large individual digit input boxes (48pt × 56pt each, 8pt radius, 1pt border, Powder Blue focus border), auto-advance on each digit. "Where do I find the code?" link below → expands inline explanation. Confirm button activates when all 6 digits filled.

**If linked and online:**
Row shows: green dot + Mac name + "Connected" in Powder Blue. Disclosure chevron → detail screen showing Mac name, linked since date, last active timestamp, "Unlink Mac" button (destructive).

**If linked and offline:**
Row shows: amber dot + Mac name + "Offline" in amber. Same disclosure.

### Voice settings

**Wake word toggle:**
Standard iOS toggle. Label: "Hey Lumis". Sublabel: "Listen for your wake word in the background" — 12pt textSecondary.

**Microphone sensitivity:**
Custom slider. Three detent labels below: "Low", "Medium", "High". Track: Carbon Black 15% opacity. Fill: Powder Blue. Thumb: white, 22pt, 1pt Powder Blue border.

**Response verbosity:**
Segmented picker: "Brief" | "Balanced" | "Detailed". Powder Blue selected segment.

### Notifications rows

Standard iOS toggle rows. No sublabels needed.

### Account rows

- "Change email" → modal with current email shown, new email field, password confirmation, "Update" button
- "Change password" → modal with current password, new password, confirm, strength indicator
- "Sign out" → confirmation action sheet: "Sign out of Lumis?" with destructive confirm
- "Delete account" → full screen confirmation requiring user to type "DELETE" before the button activates. Destructive red button. Calls `DELETE /auth/account`.

### About rows

- Version: "Version 1.0 (1)" — right-aligned, textSecondary, non-tappable
- Privacy Policy / Terms: open in in-app `SFSafariViewController`
- Send feedback: opens mail compose sheet pre-addressed to support

---

## Part 11 — Global UI Patterns

### Loading states

Never show a spinner alone. All loading states:
- Skeleton shimmer: use a `ShimmerView` modifier that animates a highlight sweep left→right over placeholder rectangles in the shape of the content
- Overlay: `.ultraThinMaterial` overlay + Lumis shape small (80pt) centered with `.thinking` state animation + "Working on it…" below

### Error states

A slide-up error toast (NOT an alert): bottom of screen above tab bar, red left border, Carbon Black text, auto-dismisses in 4 seconds. Example: "Couldn't connect to backend. Check your connection."

### Empty states

Every list/screen that can be empty has a dedicated empty state — Lumis shape (80pt, idle) + descriptive text + optional CTA. Never show a blank screen.

### Haptics

```swift
// Use UIImpactFeedbackGenerator and UINotificationFeedbackGenerator throughout:
// Tab bar tap → .light impact
// Shutter capture → .medium impact
// Successful action → .success notification
// Failed action → .error notification
// Mac connected → .success notification
// Wake word detected → .light impact
```

### Safe areas

All content respects safe areas. Tab bar sits above the home indicator. No content is ever clipped by notch or Dynamic Island.

### Accessibility

- All interactive elements have `.accessibilityLabel` set
- All icons have `.accessibilityHidden(true)` if decorative
- Dynamic Type supported on all text
- VoiceOver: Lumis shape announces its current state ("Lumis is listening", "Lumis is thinking")

---

## Part 12 — App Entry Point & State Management

### Root view

```swift
@main
struct LumisApp: App {
    @StateObject var authVM = AuthViewModel()
    @StateObject var macVM = MacConnectionViewModel()
    @StateObject var lumisVM = LumisViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if authVM.isLoading {
                    SplashView()
                } else if !authVM.isAuthenticated {
                    WelcomeView()
                } else {
                    MainTabView()
                }
            }
            .environmentObject(authVM)
            .environmentObject(macVM)
            .environmentObject(lumisVM)
        }
    }
}
```

### LumisViewModel

Owns:
- `lumisState: LumisState`
- `transcript: String`
- `responseText: String`
- `lastResult: ActionResult?`
- `cameraMode: CameraMode?`
- WebSocket connection to `LumisConfig.websocketURL`

On receiving `{ action: "request_camera", reason: "..." }` from the WebSocket:
1. Set `cameraMode = .autoTriggered(reason: reason)`
2. Switch active tab to Camera tab
3. Activate microphone in Camera screen (user's original command is retained)

### MacConnectionViewModel

Owns:
- `connectionState: MacConnectionState`
- `macName: String?`
- `lastSeen: Date?`

Polls `GET /link/status` every 15 seconds when app is foregrounded. Updates `connectionState` accordingly.

---

## Part 13 — Post-Implementation Checklist

Run these verifications after all code is written:

- [ ] `grep -ri "felix" . --exclude-dir=.git` returns zero results
- [ ] All colors reference `LumisColors.*` — no hardcoded hex values anywhere else
- [ ] All URLs reference `LumisConfig.*` — no hardcoded URL strings anywhere else
- [ ] Auth token stored in Keychain, never in UserDefaults
- [ ] App launches and reaches correct screen (splash → welcome if unauthenticated, splash → home if authenticated)
- [ ] Sign in with Apple entitlement added in Xcode capabilities
- [ ] Camera and microphone usage descriptions set in Info.plist
- [ ] All 4 tabs render without crashes
- [ ] Mac linking flow works end to end (generate code on Mac → enter on iPhone → linked state appears)
- [ ] Camera auto-trigger works: backend returns `request_camera` → Camera tab opens → image captured and sent
- [ ] History list populates from backend
- [ ] Offline state banner appears when Mac heartbeat stops
- [ ] Result card appears and auto-dismisses after successful action
- [ ] Delete account requires typing "DELETE" before confirming
- [ ] All empty states are implemented (History, no Mac linked, etc.)
- [ ] Haptics fire on all specified interactions
- [ ] App builds with zero warnings in release configuration

---

## External Services — Do Not Break

The Railway backend is live at `https://lumis-production-b878.up.railway.app`. Do not change Railway env var names in the dashboard. Do not touch the git remote URL or branch names.

Final manual checklist (post-deploy):
- [ ] Rename GitHub repo `felix` → `lumis`, then run `git remote set-url origin <new-url>`
- [ ] Rename Railway project display name to Lumis (cosmetic only)
- [ ] Re-check any OAuth redirect URIs registered under the old name (especially Google Sign-In)
- [ ] Add `lumis://` URL scheme to Google Cloud Console authorized redirect URIs
- [ ] Add bundle ID `com.anay.lumis` to Sign in with Apple configuration in Apple Developer portal