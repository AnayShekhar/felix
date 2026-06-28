# Lumis — Fixes & UI Refresh

This document covers three things:
1. Fix the wake word detection
2. Fix and redesign the Lumis animation with proper state behavior
3. Full UI refresh — iOS and Mac — inspired by Claude.ai's clean aesthetic, using the Lumis color palette

Everything here is surgical. Do not break existing functionality (auth, Mac linking,
WebSocket, agent pipeline, history, memory). Only touch what is listed.

---

## Part 1 — Wake Word Fix

### The problem
The wake word ("Hey Lumis") is either not triggering reliably or triggering in the
wrong state. The animation also does not respond to wake word detection — it just
keeps spinning regardless.

### Fix in `SpeechRecognizer.swift`

The wake word listener must:
1. Run continuously in the background using `SFSpeechAudioEngine` + `AVAudioEngine`
2. Only scan for the trigger phrases — do NOT transcribe full sentences here
3. When a trigger phrase is detected, immediately notify `LumisViewModel` to switch
   to `.listening` state and start Groq Whisper transcription

Trigger phrases to detect (fuzzy match — if the recognized string CONTAINS any of
these substrings, treat it as a wake word hit):
```
"hey lumis", "hey lewis", "hey lumos", "hey loomis",
"hey lumis", "hey luminous", "hey felics", "hey phoenix",
"a lumis", "okay lumis", "ok lumis"
```

Implementation:

```swift
// SpeechRecognizer.swift

import Speech
import AVFoundation

class SpeechRecognizer: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Generation counter — prevents old sessions clobbering new ones
    private var generationCounter = 0

    var onWakeWordDetected: (() -> Void)?
    var onTranscriptUpdate: ((String) -> Void)?
    var onTranscriptSettled: ((String) -> Void)?   // ~1.3s silence after speaking

    private let wakeWordPhrases = [
        "hey lumis", "hey lewis", "hey lumos", "hey loomis",
        "hey luminous", "hey felics", "hey phoenix",
        "a lumis", "okay lumis", "ok lumis", "hey louis"
    ]

    func startListeningForWakeWord() {
        // Keep mic open, low power, only check for wake phrases
        // On detection: call onWakeWordDetected()
        // Do NOT call onTranscriptUpdate during wake word phase
    }

    func startCommandTranscription() {
        // Called after wake word detected
        // Start fresh SFSpeechRecognitionTask
        // Stream partial results to onTranscriptUpdate
        // After ~1.3s of silence in partial results, call onTranscriptSettled
        // with the final transcript string
        let myGeneration = generationCounter
        // Only deliver results if myGeneration == generationCounter
        // (cancels results from old sessions)
    }

    func stopCommandTranscription() {
        generationCounter += 1
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    func stopAll() {
        generationCounter += 1
        audioEngine.stop()
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
    }

    private func transcriptContainsWakeWord(_ transcript: String) -> Bool {
        let lower = transcript.lowercased()
        return wakeWordPhrases.contains { lower.contains($0) }
    }
}
```

### Fix in `LumisViewModel.swift`

Wire the speech recognizer callbacks to state:

```swift
// In LumisViewModel.swift

func setupSpeechRecognizer() {
    speechRecognizer.onWakeWordDetected = { [weak self] in
        DispatchQueue.main.async {
            self?.lumisState = .listening
            self?.transcript = ""
            self?.speechRecognizer.startCommandTranscription()
            LumisHaptics.light()
        }
    }

    speechRecognizer.onTranscriptUpdate = { [weak self] partial in
        DispatchQueue.main.async {
            self?.transcript = partial
        }
    }

    speechRecognizer.onTranscriptSettled = { [weak self] final in
        DispatchQueue.main.async {
            self?.transcript = final
            // Do NOT auto-send — user must tap capture or the chat bar send button
            // Just update state to show transcript is ready
            self?.lumisState = .idle   // returns to idle, transcript stays visible
        }
    }

    speechRecognizer.startListeningForWakeWord()
}
```

### AVAudioSession configuration

In `SpeechRecognizer.swift`, configure the audio session correctly so the mic works
while the app is backgrounded:

```swift
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth])
try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
```

Add `UIBackgroundModes` → `audio` to `Info.plist` if not already present.

---

## Part 2 — Animation Redesign

### The problem
The current animation just spins and resizes everything constantly regardless of
state. There is no differentiation between idle, listening, thinking, and speaking.
It does not react to audio.

### What the animation should do

```
IDLE      → Slow continuous rotation. No resizing. Calm.
LISTENING → Rotation STOPS. Each capsule/circle resizes independently,
            dynamically, reacting to the microphone's audio level in real time.
            Feels like a waveform or equalizer — alive and responsive to voice.
THINKING  → Slow rotation resumes. Capsules gently pulse at different phases.
            Dreamy, slow. Clearly different from idle.
SPEAKING  → Faster rotation. Capsules resize dynamically (same as listening but
            driven by TTS amplitude, or use a simulated audio envelope if TTS
            amplitude is not available). Energetic.
```

### Implementation — `LumisShapeView.swift`

Replace the entire current implementation:

```swift
import SwiftUI
import AVFoundation

struct LumisShapeView: View {
    var state: LumisState
    var size: CGFloat = 260

    // Rotation
    @State private var rotation: Double = 0
    @State private var rotationTimer: Timer?

    // Per-petal independent scales (6 petals)
    @State private var petalScales: [CGFloat] = Array(repeating: 1.0, count: 6)

    // Audio level monitoring
    @State private var audioMonitor: AudioLevelMonitor? = nil

    // Idle/thinking gentle pulse phases
    private let gentlePulseParams: [(duration: Double, delay: Double)] = [
        (2.1, 0.00), (1.9, 0.30), (2.3, 0.60),
        (2.0, 0.90), (2.2, 0.45), (1.8, 0.75)
    ]

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(Color(hex: "#B0BFD1").opacity(0.6))
                    .frame(width: size * 0.45, height: size * 0.45)
                    .offset(petalOffset(index: i))
                    .scaleEffect(petalScales[i])
                    .blendMode(.multiply)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
        .animation(.easeInOut(duration: 0.6), value: state)
        .onAppear { startIdleRotation() }
        .onChange(of: state) { newState in handleStateChange(newState) }
    }

    // ── Petal layout ────────────────────────────────────────────────────────

    private func petalOffset(index: Int) -> CGSize {
        let angle = Double(index) * (360.0 / 6.0) * .pi / 180.0
        let radius = size * 0.26
        return CGSize(
            width: cos(angle) * radius,
            height: sin(angle) * radius
        )
    }

    // ── State handling ───────────────────────────────────────────────────────

    private func handleStateChange(_ newState: LumisState) {
        stopAllAnimations()
        switch newState {
        case .idle:
            startIdleRotation()
        case .listening:
            stopRotation()
            startAudioReactivePetals()
        case .thinking:
            startThinkingAnimation()
        case .speaking:
            startSpeakingAnimation()
        }
    }

    // ── IDLE — slow rotation, no petal resizing ──────────────────────────────

    private func startIdleRotation() {
        // Reset petal scales to 1.0
        withAnimation(.easeInOut(duration: 0.4)) {
            petalScales = Array(repeating: 1.0, count: 6)
        }
        // Continuous rotation: 1 full revolution every 9 seconds
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            DispatchQueue.main.async {
                rotation += 360.0 / (9.0 * 60.0)
                if rotation >= 360 { rotation -= 360 }
            }
        }
    }

    // ── LISTENING — rotation stops, petals react to mic audio level ──────────

    private func stopRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        // Snap current rotation — do not animate to 0, just freeze where it is
    }

    private func startAudioReactivePetals() {
        audioMonitor = AudioLevelMonitor()
        audioMonitor?.onLevelUpdate = { level in
            // level: 0.0 (silence) → 1.0 (loud)
            DispatchQueue.main.async {
                updatePetalsForAudioLevel(level)
            }
        }
        audioMonitor?.start()
    }

    private func updatePetalsForAudioLevel(_ level: CGFloat) {
        // Each petal gets a slightly different random scale based on audio level
        // This creates the organic equalizer feel
        for i in 0..<6 {
            let variance = CGFloat.random(in: 0.85...1.15)
            let targetScale = 1.0 + (level * 0.5 * variance)
            withAnimation(.easeOut(duration: 0.08)) {
                petalScales[i] = targetScale
            }
        }
    }

    // ── THINKING — slow rotation + gentle staggered petal pulse ─────────────

    private func startThinkingAnimation() {
        // Slower rotation: 1 revolution every 14 seconds
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            DispatchQueue.main.async {
                rotation += 360.0 / (14.0 * 60.0)
                if rotation >= 360 { rotation -= 360 }
            }
        }
        // Gentle staggered pulse on each petal
        for i in 0..<6 {
            let params = gentlePulseParams[i]
            DispatchQueue.main.asyncAfter(deadline: .now() + params.delay) {
                withAnimation(
                    .easeInOut(duration: params.duration)
                    .repeatForever(autoreverses: true)
                ) {
                    petalScales[i] = i % 2 == 0 ? 0.88 : 1.12
                }
            }
        }
    }

    // ── SPEAKING — faster rotation + dynamic petal sizing ────────────────────

    private func startSpeakingAnimation() {
        // Faster rotation: 1 revolution every 4 seconds
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            DispatchQueue.main.async {
                rotation += 360.0 / (4.0 * 60.0)
                if rotation >= 360 { rotation -= 360 }
            }
        }
        // Simulate audio envelope with staggered fast pulses
        // If real TTS amplitude is available, replace this with actual audio level
        var phase = 0.0
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            phase += 0.3
            DispatchQueue.main.async {
                for i in 0..<6 {
                    let offset = Double(i) * (Double.pi / 3.0)
                    let scale = 1.0 + CGFloat(sin(phase + offset) * 0.3)
                    withAnimation(.easeOut(duration: 0.05)) {
                        petalScales[i] = scale
                    }
                }
            }
        }
    }

    // ── Cleanup ──────────────────────────────────────────────────────────────

    private func stopAllAnimations() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        audioMonitor?.stop()
        audioMonitor = nil
    }
}
```

### `AudioLevelMonitor.swift` — new file

```swift
import AVFoundation

class AudioLevelMonitor {
    private var audioEngine: AVAudioEngine?
    var onLevelUpdate: ((CGFloat) -> Void)?

    func start() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let level = self.averagePower(from: buffer)
            self.onLevelUpdate?(level)
        }

        do {
            try engine.start()
            audioEngine = engine
        } catch {
            print("AudioLevelMonitor: failed to start — \(error)")
        }
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private func averagePower(from buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength { sum += abs(data[i]) }
        let avg = sum / Float(frameLength)
        // Normalize to 0.0–1.0 range
        return CGFloat(min(avg * 20.0, 1.0))
    }
}
```

Note: `AudioLevelMonitor` taps the same mic that `SpeechRecognizer` uses. Both can
run simultaneously on the same `AVAudioEngine` if you share the engine instance, or
use separate engines. If there is an `AVAudioEngine` conflict (only one input tap
per node), pass the audio level from `SpeechRecognizer`'s existing buffer tap to
`LumisViewModel`, and drive `updatePetalsForAudioLevel` from there instead.

---

## Part 3 — iOS UI Refresh

### Inspiration
Claude.ai's interface: clean, minimal, lots of breathing room, warm off-white
background, everything feels considered and calm. Apply that sensibility to Lumis
with the existing color palette.

### Color palette reminder
```
Parchment    #F8F3EE   background
Powder Blue  #B0BFD1   accents, active states
Carbon Black #212222   text, icons
```

### Home screen (`HomeView.swift` / `MainTabView.swift`)

**Current issues visible in screenshots:**
- Hamburger button is a plain white circle — too heavy
- Status dot (top right) is barely visible
- "Talk to Lumis" chat bar at the bottom looks like a standard iOS search bar
- No visual hierarchy — everything is the same visual weight

**Fixes:**

Hamburger button:
- Remove the white circle background
- Just the three-line SF Symbol `line.3.horizontal`, Carbon Black, 20pt
- 44pt tap target, no background shape
- Position: 20pt from left safe area edge, vertically centered in top bar

Status dot:
- Make it 10pt diameter (currently too small)
- Powder Blue when connected, with a subtle 1.5× scale pulse animation (opacity 0.4, 2s loop)
- Carbon Black 20% opacity when offline
- Position: 20pt from right safe area edge

"Talk to Lumis" chat bar:
- Increase height to 56pt
- Background: white at 80% opacity with `ultraThinMaterial` underneath
- Border: 1pt Carbon Black at 8% opacity, full pill radius (28pt)
- "+" button left side: Carbon Black, 18pt SF Symbol `plus`, 44pt tap target
- Camera button: separate pill to the left of the text bar, 56pt × 56pt, same material
- Text: "Talk to Lumis" placeholder in Carbon Black 35% opacity, 16pt regular
- Keyboard type: `.default`, autocorrect off, autocapitalization off
- Bottom padding: 12pt above home indicator

Overall home screen spacing:
- Top bar (hamburger + status dot): 16pt from safe area top
- Lumis shape: vertically centered between top bar and transcript text
- Transcript text: 32pt below the shape, centered, max 3 lines
- Chat bar: pinned to bottom, 12pt above home indicator

### Sidebar (`SidebarView.swift`)

**Current issues:**
- Shows raw tool names like `media.open_spotify` — these should be human-readable
- History items are plain list rows with no visual weight
- "Settings" text button at bottom is not styled

**Fixes:**

Header:
- "Lumis" wordmark: 28pt bold, Carbon Black, left aligned, 24pt from top safe area
- No subtitle

History items — format the tool name into a human-readable title:
```swift
func humanReadableTitle(for toolName: String) -> String {
    let map: [String: String] = [
        "media.open_spotify": "Opened Spotify",
        "media.open_apple_music": "Opened Apple Music",
        "media.play_pause": "Play / Pause",
        "gmail.draft_email": "Email Draft",
        "browser.open_url": "Opened URL",
        "browser.fill_form": "Filled Form",
        "web.research": "Web Research",
        "web.search": "Web Search",
        "notes.create_note": "Created Note",
        "notes.create_from_image": "Note from Image",
        "notes.append_to_note": "Updated Note",
        "numbers.add_expense": "Added Expense",
        "numbers.create_spreadsheet": "New Spreadsheet",
        "calendar.create_event": "Calendar Event",
        "reminders.add": "Added Reminder",
        "finder.find_file": "Found File",
        "finder.open_file": "Opened File",
        "system.set_volume": "Set Volume",
        "system.lock_screen": "Locked Screen",
        "clipboard.copy": "Copied to Clipboard",
    ]
    return map[toolName] ?? toolName
        .replacingOccurrences(of: ".", with: " ")
        .replacingOccurrences(of: "_", with: " ")
        .capitalized
}
```

Each history row:
- Icon circle: 36pt, Powder Blue 15% opacity background, colored SF Symbol inside
- Title: humanReadableTitle, 15pt medium, Carbon Black
- Timestamp: relative ("3 hours ago"), 12pt, Carbon Black 40% opacity
- No border, no card background — just clean rows with 16pt vertical padding
- Divider: 0.5pt Carbon Black 8% opacity between rows

Bottom of sidebar:
- User avatar circle: initials, 40pt, Powder Blue background, white initials
- Name + email in 13pt next to avatar
- Gear icon right side → opens Settings
- This row sits 16pt above home indicator, 16pt horizontal padding

Sidebar animation (already prompted before but ensure):
- Opens with `.spring(response: 0.45, dampingFraction: 0.82)`
- Closes with same spring
- Dimmed overlay behind sidebar: Carbon Black 30% opacity, tap to close

### Settings screen (`SettingsView.swift`)

**Current issues visible in screenshots:**
- Memory section shows raw JSON keys like `command_patterns` — needs human labels
- Memory values show raw array strings — needs formatting
- Section headers are uppercase gray text — fine but too small

**Fixes:**

Memory keys human-readable labels:
```swift
func humanReadableMemoryKey(_ key: String) -> String {
    let map: [String: String] = [
        "command_patterns": "Common Commands",
        "default_browser": "Default Browser",
        "frequent_contacts": "Frequent Contacts",
        "last_email_recipient": "Last Email Recipient",
        "expense_file_path": "Expense File",
        "preferred_calendar": "Default Calendar",
        "music_service": "Music Service",
    ]
    return map[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
}
```

Memory values — if the value is a JSON array string, parse and display as
comma-separated plain text instead of raw `["a", "b"]`.

Settings section headers: increase to 13pt, Carbon Black 50% opacity, uppercase,
letter-spacing 0.8pt.

---

## Part 4 — Mac App UI Refresh

### Current state (from screenshots)
The Mac app already has a good bones — three-column layout (sidebar, main content,
live feed), Activity/Memory/Settings sections, live feed panel. It looks functional
but feels like a developer tool. Needs to feel like a polished dashboard.

### What to keep
- Three-column layout (sidebar nav, main content, live feed)
- Activity, Memory, Settings navigation
- Live feed panel on the right
- "Connected" status at bottom left
- Menu bar popover

### Color system for Mac app

Apply the same palette:
```
Background:  #F8F3EE (Parchment) for main content area
Sidebar bg:  #EFEBE4 (slightly darker Parchment — just darken by 5%)
Live feed:   white with 0.5pt border
Cards:       white, 12pt radius, 0.5pt border #21222215
Text:        #212222
Secondary:   #21222280
Accent:      #B0BFD1
```

### Sidebar (`DashboardView.swift` left panel)

Current: plain list with icon + label. Keep the structure, refine the look.

- Sidebar width: 220pt
- Background: `#EFEBE4`
- "Lumis" header: 17pt semibold, Carbon Black, 20pt top padding, 16pt left padding
- Waveform icon next to "Lumis": SF Symbol `waveform`, Powder Blue, 18pt
- Nav items (Activity, Memory, Settings):
  - Height: 36pt
  - Active: Powder Blue 15% opacity background, Powder Blue icon + label, 8pt radius
  - Inactive: no background, Carbon Black 50% icon + label
  - Icon size: 16pt, label: 14pt medium
  - 8pt horizontal padding, 4pt vertical padding
  - 12pt left margin inside sidebar
- Bottom: connection status dot + "Connected" / "Disconnected" in 12pt, Carbon Black 50%
- No dividers between nav items — rely on spacing alone

### Activity view (`DashboardView.swift` main content)

**Current issues:**
- Cards show raw tool names (`media.open_spotify`)
- Status dots are red (error) for actions that actually succeeded — this appears to
  be a status mapping bug. Fix: if the history item has no `error` field and
  completed, it is SUCCESS (green dot), not error (red dot)
- "Undo" button appears on every card — only show it on reversible actions

**Fixes:**

Page header:
- "Activity" in 28pt semibold, Carbon Black
- Subtitle: "X actions today" in 15pt, Carbon Black 50%
- Refresh icon top right: SF Symbol `arrow.clockwise`, 16pt, Carbon Black 40%

Each activity card:
- Background: white, 12pt radius, 0.5pt border `#21222215`, 16pt padding
- Left: 40pt icon circle. Color by action family:
  - media.*      → green `#4CAF7D` bg, music note icon
  - gmail.*      → red `#E05252` bg, envelope icon  
  - browser.*    → blue `#5B8DEF` bg, globe icon
  - web.*        → purple `#9B7FE8` bg, sparkle icon
  - notes.*      → yellow `#E8A838` bg, note icon
  - numbers.*    → green `#4CAF7D` bg, tablecells icon
  - calendar.*   → red `#E05252` bg, calendar icon
  - reminders.*  → orange `#E87D3E` bg, bell icon
  - finder.*     → blue `#5B8DEF` bg, folder icon
  - system.*     → Carbon Black bg, gearshape icon
  - default      → Powder Blue bg, bolt icon
- Title: humanReadableTitle(for: toolName), 15pt semibold, Carbon Black
- Subtitle: family + action type + relative timestamp, 13pt, Carbon Black 50%
  Example: "Media · Open Spotify · 3 hours ago"
- Status: green dot (success) or red dot (error) — fix the mapping bug
- "Undo" button: only show if `TOOL_REGISTRY[toolName]?.irreversible == false`
  AND the action is less than 5 minutes old. Style: Powder Blue text, 13pt, 
  outlined pill button
- Expanded state (click to expand): shows full summary text in 13pt regular Carbon
  Black, 16pt padding, gray `#F5F5F5` background row below the card header

Fix status dot mapping:
```swift
// In the card view:
var isSuccess: Bool {
    item.status == "success" ||
    (item.status != "error" && item.errorMessage == nil)
}
```

### Memory view

**Current issues:**
- Raw JSON keys visible
- Raw array values like `["a", "b", "c"]` visible

Apply the same human-readable key + value formatting from the iOS Settings fix above.

Table design:
- Remove the plain table borders
- Each row: alternating white / `#F8F3EE` background, 48pt height
- Key column: monospaced 13pt, Carbon Black 50%, 200pt width
- Value column: 14pt regular, Carbon Black
- Delete button: SF Symbol `xmark`, 14pt, Carbon Black 30%, appears on hover only
- "Filter keys..." search field: full width, 36pt height, `#F8F3EE` bg, 8pt radius,
  no border, magnifying glass icon left side
- Header: "Memory" 28pt semibold + "X things Lumis knows about you" 15pt secondary

### Settings view (Mac)

**Current issues:**
- Toggle styling is default macOS — fine, keep it
- Section headers use Powder Blue color text — change to Carbon Black 50% uppercase

Section header style: 12pt semibold, Carbon Black 50%, uppercase, 1pt letter spacing.

Account card:
- White background, 12pt radius, 16pt padding
- Avatar: 44pt circle, Powder Blue bg, white initials, 17pt semibold
- Name: 17pt semibold, Carbon Black
- Email: 13pt, Carbon Black 50%
- "Sign Out" button: right aligned, 13pt medium, Carbon Black, outlined pill

Add "Sign in with Apple" and "Sign in with Google" buttons to the Mac login screen
if not already present (was covered in a previous prompt — verify they are actually
rendered in `LoginView.swift`).

### Live Feed panel

**Current issues:**
- "WORKFLOW COMPLETE" badge is a pink/red pill — use Powder Blue instead
- Feed items show raw tool names

**Fixes:**
- "WORKFLOW COMPLETE" pill: Powder Blue bg, white text, 11pt semibold, 6pt radius
- Feed item title: humanReadableTitle() for the tool name
- Feed item subtitle: the raw tool name in 11pt monospaced Carbon Black 40% — keep
  this for developers but smaller and secondary
- Live indicator dot next to "LIVE FEED": Powder Blue, with pulse animation
- "Clear" button: Carbon Black 40%, 13pt

### Menu bar popover

**Current issues:**
- Raw tool names in the Recent section

**Fix:**
Apply `humanReadableTitle()` to each recent item title. Keep the raw name as a
secondary subtitle in 11pt Carbon Black 40%.

---

## Part 5 — Verification

After all fixes:

- [ ] Say "Hey Lumis" — animation transitions from spinning to stopped, petals react
      to voice in real time
- [ ] Say a command — transcript appears below the shape word by word
- [ ] After silence, state returns to idle and rotation resumes
- [ ] During thinking state, rotation is slower and petals do a gentle staggered pulse
- [ ] During speaking, rotation is faster and petals pulse energetically
- [ ] iOS sidebar opens and closes with smooth spring animation on single tap
- [ ] Camera X button closes on single tap, no hold required
- [ ] All history items in sidebar show human-readable titles (not raw tool names)
- [ ] Mac Activity feed shows correct status colors (green for success, red for error)
- [ ] Mac Memory view shows human-readable keys and formatted values
- [ ] Mac "WORKFLOW COMPLETE" badge is Powder Blue
- [ ] Mac sidebar active state is Powder Blue, correct colors throughout
- [ ] Menu bar popover shows human-readable recent action titles
- [ ] No regression on auth, Mac linking, agent pipeline, or WebSocket connection