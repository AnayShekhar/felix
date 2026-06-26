# Felix UI Rebuild — Moonstone Orb Interface

Complete redesign of the iOS app interface.

Core logic files untouched as always.

DO NOT modify:

```
CameraManager.swift
SpeechRecognizer.swift
```

Only rebuild the presentation layer.

---

# PHASE 1: Remove the shutter button

and auto-send on voice completion

In:

```
CameraTab.swift
ContentView.swift
```

Remove the shutter button entirely.

Remove any:

* `canCapture` gate
* manual send requirement
* button-dependent camera flow

When SpeechRecognizer settles:

```
1.3 seconds silence after command
```

automatically trigger the send flow.

If the command contains visual context:

Examples:

```
"this"
"here"
"what is"
"read this"
"scan"
"look at"
"show"
"add this"
"turn this"
```

activate camera automatically before sending.

If the command does not need vision:

* send immediately
* no camera activation
* no image capture

The user should never press a button to send.

---

# PHASE 2: Moonstone Orb as primary UI element

Replace the entire camera viewfinder as the default home screen.

The Felix assistant is represented by a 3D Moonstone Orb.

The model already exists in the codebase.

DO NOT create a new model.

DO NOT import another asset.

Use:

```
models/
└── FelixMoonstoneOrb.usdc
```

---

# RealityKit Integration

Create:

```
FelixOrbView.swift
FelixOrbManager.swift
FelixOrbMaterialController.swift
```

The orb should load using RealityKit.

Expected hierarchy:

```
FelixMoonstoneOrb

├── Moonstone_OuterShell
│
├── Moonstone_Core
│
├── Moonstone_ReflectionLayer
│
└── Moonstone_InternalLight
```

Keep the hierarchy intact.

Each part should remain independently controllable.

Swift should control:

* scale
* rotation
* opacity
* glow
* material intensity
* listening effects
* speaking effects

The USD model is only the physical object.

The intelligence comes from animation states.

---

# PHASE 3: Felix Visual Design System

The old amber blob palette is replaced.

Felix should feel like:

* Apple hardware
* moonstone glass
* intelligent system component

Not a cartoon assistant.

## Design Tokens

Background:

```
#070B12
```

Deep blue-black.

Orb primary:

```
#B8D9FF
```

Moonstone icy blue.

Orb secondary glow:

```
#DDF6FF
```

Soft internal light.

Core metallic:

```
#9FB3C6
```

Text:

Primary:

```
#FFFFFF
```

Secondary:

```
#FFFFFF 60%
```

Glass card:

```
UIBlurEffect .dark
```

Border:

```
FFFFFF 8%
```

Error:

```
#FF4444
```

Success:

```
#B8D9FF
```

---

# PHASE 4: Orb States and Animations

## IDLE

Default state.

Behavior:

* slow floating movement
* subtle rotation
* internal light breathing

Animation:

Scale:

```
0.97 → 1.03
```

over:

```
3 seconds
```

Control:

```
Moonstone_Controller
```

Glow:

soft blue-white pulse.

---

# WAKE WORD DETECTED

Trigger:

"Hey Felix"

Effects:

Orb brightens immediately.

Increase:

```
Moonstone_InternalLight intensity
```

Increase:

```
Moonstone_ReflectionLayer opacity
```

Scale:

```
1.0 → 1.12 → 1.0
```

with spring animation.

The orb should feel like it wakes up.

---

# LISTENING

User speaking.

Use:

SpeechRecognizer audio level.

Drive:

```
Moonstone_OuterShell
```

and:

```
Moonstone_Core
```

animation.

Effects:

* glass vibration
* subtle breathing
* internal energy movement

Do not deform geometry.

Use:

* material changes
* transforms
* shader parameters

The orb should remain clean.

---

# THINKING

Request sent.

Waiting for response.

Effects:

Rotate:

```
Moonstone_Core
```

independently.

Increase:

```
Moonstone_InternalLight
```

slightly.

Add:

slow internal movement.

Caption:

```
Thinking...
```

small text below orb.

---

# SPEAKING

Felix TTS active.

Drive animation from speech.

Effects:

Internal light pulses.

Reflection layer reacts.

Small scale pulses:

```
1.0 → 1.02
```

Each spoken phrase creates a subtle ripple.

The orb should feel alive, not animated like a character.

---

# CAMERA ACTIVE

When Felix needs vision:

The orb becomes the camera indicator.

Flow:

1. Orb shrinks

```
180pt → 56pt
```

2. Moves top center

3. Camera feed fades behind it

4. Autofocus waits

```
1.5 seconds
```

5. Capture silently

6. Camera fades away

7. Orb returns center

8. Enter thinking state

No:

* shutter button
* brackets
* camera UI overlays

The orb IS the interface.

---

# PHASE 5: Ambient Moonstone Glow

The background should react to Felix.

Implementation:

Radial gradient behind orb.

Gradient:

Center:

```
#DDF6FF
20% opacity
```

Fade:

transparent edges.

States:

Idle:

soft blue glow.

Listening:

wider brighter glow.

Thinking:

slow rotating gradient.

Speaking:

pulse with voice.

---

# PHASE 6: Navigation

Remove tab bar completely.

Replace with floating icons.

Bottom:

Left:

SF Symbol:

```
camera.fill
```

Action:

manual camera mode.

Right:

SF Symbol:

```
clock.fill
```

Action:

history sheet.

Settings:

Long press orb.

Optional small gear appears.

Icons:

White:

60%

Active:

Moonstone blue.

No labels.

---

# PHASE 7: Transcription Display

While speaking:

Show live transcription.

Position:

Below orb.

Style:

SF Pro Regular

16pt

Color:

white 80%

Behavior:

* fade in
* max 2 lines
* recent words visible
* fade out 1 second after send

---

# PHASE 8: Result Display

When Felix responds:

Show result card.

Style:

* frosted glass
* rounded 28pt
* dark blur background

Contains:

* tool icon
* title
* description
* open button if URL exists

Card:

Slides upward.

Auto dismiss:

5 seconds.

Tap dismisses early.

During TTS:

Card stays.

Orb moves above card.

Orb pulses with speech.

---

# PHASE 9: File Structure

Expected:

```
Felix/

├── models/
│
│   └── FelixMoonstoneOrb.usdc
│
├── RealityKit/
│
│   ├── FelixOrbManager.swift
│   ├── FelixOrbMaterialController.swift
│   └── FelixOrbAnimations.swift
│
├── Views/
│
│   ├── FelixOrbView.swift
│   └── ContentView.swift
│
└── Audio/
    └── VoiceAmplitudeTracker.swift
```

---

# Constraints

Never touch:

```
CameraManager.swift
SpeechRecognizer.swift
```

No third-party animation libraries.

Use:

* SwiftUI animations
* RealityKit
* Metal only if required

Performance target:

```
60 FPS
```

Avoid:

* heavy particles
* expensive shaders
* recreating entities
* high-frequency geometry changes

Use:

* materials
* transforms
* RealityKit animations

---

# Final Design Goal

Felix should not feel like a mascot.

Felix should feel like an Apple system intelligence.

The Moonstone Orb is:

* the assistant
* the listening indicator
* the thinking animation
* the camera indicator
* the personality

The model already exists.

The job is making the orb feel intelligent.
