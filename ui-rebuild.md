# Felix UI Rebuild — Moonstone Orb Interface

Complete redesign of the iOS app presentation layer.

Never touch:
- CameraManager.swift
- SpeechRecognizer.swift

Only rebuild the presentation layer.
All existing logic stays intact.

---

## PRE-PHASE FIX: Remove Groq API key from Settings

In ios/FelixApp/FelixApp/SettingsTab.swift:
- Remove the entire TRANSCRIPTION section
- Remove the Groq API key SecureField
- Remove the Save Key button
- Remove all description text about Groq Whisper
- Remove any reference to felix.groqAPIKey
  in this file

In ios/FelixApp/FelixApp/WhisperTranscriber.swift:
- Remove UserDefaults lookup for felix.groqAPIKey
- Hardcode the key as a private constant at
  the top of the file:
  private let groqAPIKey = "GROQ_KEY_HERE"
- Add a comment: // Set this before building.
  Never commit your real key.
- Add WhisperTranscriber.swift to .gitignore
  so the key is never pushed to GitHub

The user never sees or manages this key.
They just speak and it works.

---

## PHASE 1: Remove shutter button,
auto-send on voice completion

In CameraTab.swift and ContentView.swift:
- Remove the shutter button entirely
- Remove the canCapture gate
- Remove any manual send requirement

When SpeechRecognizer settles after 1.3 seconds
of silence following a command, automatically
trigger the capture and send flow with no user
input required.

Visual context trigger words — if any of these
appear in the settled command string, activate
the camera automatically before sending:
"this", "here", "that", "what is", "read this",
"scan", "look at", "show me", "add this",
"turn this", "what does this", "how much",
"who is", "translate this", "summarize this"

If none of these words are present, send
immediately with no image.

Add a cancel gesture: shake the phone cancels
a pending auto-send before it fires. Show a
brief "Cancelled" caption below the orb.

---

## PHASE 2: Moonstone Orb — RealityKit setup

The 3D model already exists at:
ios/FelixApp/Models/moonstone.usdc
with textures at:
ios/FelixApp/Models/textures/

Do not create a new model.
Do not import any other asset.
Use only what is already there.

Create these new files inside
ios/FelixApp/FelixApp/RealityKit/:

### FelixOrbManager.swift
- Loads moonstone.usdc using RealityKit
  Entity(named:) or ModelEntity loading
- Holds a reference to the root entity
  and all named child entities
- Exposes the orb to the rest of the app
- Handles all entity lifecycle

### FelixOrbMaterialController.swift
- Controls material properties on the orb
- Exposes functions to change:
  emissive intensity
  opacity
  roughness
  base color tint
- Used by animation states to make the orb
  feel alive through material changes
  not geometry deformation

### FelixOrbAnimations.swift
- Contains all animation functions for each
  orb state (see Phase 4)
- Uses RealityKit animations and SwiftUI
  spring animations
- No third party libraries

### FelixOrbView.swift (in Views/)
- ARView or RealityView wrapping the orb
- Full screen, transparent background
- Orb centered at roughly 40% from top
- Passes audio level from SpeechRecognizer
  into the animation system in real time
- Exposes an OrbState enum to drive
  which animation is playing

### VoiceAmplitudeTracker.swift (in Audio/)
- Reads audio level from AVAudioRecorder
  or from SpeechRecognizer's existing
  audio session
- Publishes normalized amplitude 0.0 to 1.0
- Used to drive orb animation during
  listening and speaking states
- Runs on a timer at 30hz — enough for
  smooth animation without battery drain

---

## PHASE 3: Design system

Replace the old amber palette entirely.

### Color tokens
Background: #070B12
Orb primary: #B8D9FF
Orb glow: #DDF6FF at 20% opacity
Core metallic: #9FB3C6
Text primary: #FFFFFF
Text secondary: #FFFFFF at 60% opacity
Card background: UIBlurEffect .dark
Card border: #FFFFFF at 8% opacity
Error: #FF4444
Success: #B8D9FF

### Typography
SF Pro Heavy for any headlines
SF Pro Regular for body and captions
SF Pro Mono for any data display
No custom fonts

### Atmosphere
The background is #070B12 — deep blue black
not pure black. It should feel like deep space
or the inside of a high-end device, not a
generic dark mode app.

The orb casts a soft radial glow on the
background that reacts to its current state.
This is a SwiftUI radial gradient layered
behind the RealityView, not a RealityKit
effect. It animates with the orb state.

---

## PHASE 4: Orb animation states

All states are driven by OrbState enum.
FelixOrbAnimations.swift handles transitions.
Transitions between states should feel smooth,
never jarring.

### IDLE
The orb is alive but waiting.
- Slow floating: subtle Y-axis translation
  oscillating ±4pt over 4 seconds
- Slow rotation: gentle Y-axis spin
- Breathing: emissive intensity pulses
  softly between 0.6 and 0.9 over 3 seconds
- Background glow: soft blue at low opacity

### WAKE WORD DETECTED
The orb recognizes it's being addressed.
- Immediate brightness increase
- Scale spring from 1.0 to 1.12 then settle
  to 1.05 — feels like it perked up
- Background glow brightens and spreads
- Transition should feel instant but smooth

### LISTENING
The user is speaking.
- Orb scale pulses with voice amplitude
  from VoiceAmplitudeTracker
  Quiet: 1.0, Loud: 1.08 max
- Emissive intensity increases with amplitude
- Inner glow becomes more active
- Background glow widens with amplitude
- Do not deform the mesh
  Use scale and material changes only

### THINKING
Request has been sent, waiting for response.
- Slow continuous Y-axis rotation
- Emissive intensity slightly higher than idle
- Background glow shifts to a slow rotating
  conic gradient — implies processing
- Caption below orb: "Thinking..."
  SF Pro Regular 14pt white 60% opacity
  fades in after 0.5 seconds

### SPEAKING
Felix TTS is playing back.
- Orb pulses with AVSpeechSynthesizer output
- Use AVSpeechSynthesizerDelegate to get
  word boundaries for timing
- Each word boundary: small scale pulse
  1.0 → 1.03 → 1.0 with spring
- Emissive intensity pulses with speech rhythm
- Background glow pulses with speech
- Result card visible below orb

### CAMERA ACTIVE
Felix needs visual context.
- Orb animates from center (180pt) to
  top center (56pt pill) over 0.4 seconds
  with spring animation
- Camera feed fades in behind the orb
  over 0.3 seconds
- Wait 1.5 seconds for autofocus
- Capture silently — no sound, no flash,
  no UI indicators
- Camera feed fades out over 0.3 seconds
- Orb animates back to center over 0.4 seconds
- Enter THINKING state

### ERROR
Something went wrong.
- Orb shifts to #FF4444 tint briefly
- Single horizontal shake animation
- Returns to idle color over 1 second
- Error message appears below orb
  then fades after 3 seconds

---

## PHASE 5: Ambient background glow

Behind the orb, render a SwiftUI radial
gradient that reacts to orb state.

Implementation:
- ZStack with #070B12 background
- Radial gradient centered at orb position
- Gradient: orb glow color at varying opacity
  fading to transparent
- Animate opacity and radius with orb state

State-specific behavior:
- IDLE: radius 180pt, opacity 15%
- WAKE: radius 220pt, opacity 25%
- LISTENING: radius scales with amplitude
  200-280pt, opacity 20-35%
- THINKING: slow animated rotation using
  Angular gradient, opacity 20%
- SPEAKING: pulses with speech timing
- ERROR: shifts to #FF4444 glow briefly

---

## PHASE 6: Navigation

Remove the tab bar entirely.

Replace with two floating icon buttons
at the bottom of the screen.

Left: camera.fill SF Symbol
- Tap: manually trigger camera mode
- Same flow as automatic camera activation

Right: clock.fill SF Symbol  
- Tap: history sheet slides up from bottom

Settings: long press orb for 0.8 seconds
- Gear icon fades in above the orb
- Tap gear to open settings sheet

All icons:
- White at 60% opacity when inactive
- #B8D9FF at 100% opacity when active
- No text labels
- 44x44pt tap targets
- Positioned 48pt from bottom safe area

---

## PHASE 7: Transcription display

While the user is speaking show the live
transcription text below the orb.

Style:
- SF Pro Regular 16pt
- White at 80% opacity
- Maximum 2 lines
- Truncate from left to show most recent words
- Centered below orb
- Fade in as words appear
- Fade out 1 second after command is sent

Position:
- 24pt below orb bottom edge
- Horizontal padding 32pt each side

---

## PHASE 8: Result card

When Felix completes an action show a result
card sliding up from the bottom.

Style:
- UIBlurEffect .dark background
- Corner radius 28pt
- White border 8% opacity 1pt
- Horizontal margin 20pt

Content:
- Tool icon in #B8D9FF tinted circle 44x44pt
- Tool name in SF Pro Regular 12pt
  white 60% caps above title
- Result title SF Pro Heavy 17pt white
- Result description SF Pro Regular 15pt
  white 80% opacity max 3 lines
- Open button in #B8D9FF if URL exists
  SF Pro Semibold 15pt

For content tools (calendar, email, research,
contacts, notes, spreadsheet):
- Show full bottom sheet instead of small card
- Sheet detents: medium and large
- Scrollable summary in SF Pro Regular 15pt
- Copy button and Dismiss button at bottom
- Monospace for structured data

Behavior:
- Slides up from bottom with spring animation
- Auto dismisses after 5 seconds
- Tap anywhere on card dismisses early
- During TTS: stays visible until speech ends
- Orb moves to top area while card is visible
  and pulses with speech

---

## PHASE 9: Update ContentView

ContentView.swift becomes the root compositor:

Structure:
ZStack (fills screen):
  1. Color(#070B12) — background
  2. Ambient glow layer (Phase 5)
  3. FelixOrbView — the orb (Phase 2)
  4. Transcription text (Phase 7)
  5. Result card or bottom sheet (Phase 8)
  6. Floating nav buttons (Phase 6)
  7. Confirmation sheet if needed

State management:
- OrbState drives all orb animations
- SpeechRecognizer.phase drives OrbState
- WebSocketClient.latest drives result card
- All existing @StateObject instances kept

Remove:
- CameraPreview as default background
- Viewfinder brackets
- Shutter button
- Long task toggle (fold into settings)
- Status chip (orb IS the status indicator)
- Tab bar

Keep:
- All @StateObject instances
- All existing logic connections
- History sheet
- Settings sheet
- Confirmation modal

---

## PHASE 10: Update Settings sheet

Since the tab bar is gone settings lives
in a sheet triggered by long pressing the orb.

In SettingsTab.swift or a new SettingsSheet.swift:
- Remove TRANSCRIPTION section entirely
  (done in pre-phase fix)
- Keep BACKEND section
- Keep VOICE section (Felix speaks results toggle)
- Keep NOTIFICATIONS section
- Add a "What Felix knows" section that shows
  memory key/value pairs from GET /memory
  with swipe to delete per row
  This replaces the old Memory tab
- App version at bottom
- Sheet style: matches result card glass style

---

## Constraints
- Never touch CameraManager.swift or
  SpeechRecognizer.swift
- No third party libraries of any kind
- RealityKit and SwiftUI only
- 60fps performance target
- Do not recreate RealityKit entities
  on state changes — update in place
- Do not deform orb geometry
  Use transforms and materials only
- All color literals use the new design
  tokens from Phase 3
- No amber anywhere in the new UI
- Dark mode only
- The moonstone.usdc model at
  ios/FelixApp/Models/moonstone.usdc
  is the only 3D asset — use it as-is

---

## File structure after rebuild

ios/FelixApp/FelixApp/
├── RealityKit/
│   ├── FelixOrbManager.swift
│   ├── FelixOrbMaterialController.swift
│   ├── FelixOrbAnimations.swift
│   └── FelixOrbView.swift
├── Audio/
│   └── VoiceAmplitudeTracker.swift
├── Views/
│   ├── ContentView.swift (rebuilt)
│   ├── SettingsSheet.swift
│   ├── HistoryView.swift (keep, restyle)
│   └── ResultCard.swift (new)
└── Models/
    ├── moonstone.usdc
    └── textures/