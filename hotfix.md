# Felix Hotfixes v2

Fix all issues below. Report after each and
wait for confirmation before proceeding.

---

## HOTFIX 1: Replace Apple Speech with
Groq Whisper for transcription

The core problem is Apple's Speech framework
mishears names badly. "Anay Shekhar" becomes
"a shaker", "Chauhan" becomes "chauhans".
This breaks contacts, calendar, and any
command with a proper noun.

Replace the transcription engine in
SpeechRecognizer.swift:

- Keep the "Hey Felix" wake word detection
  using Apple Speech — it only needs to
  detect two words so accuracy is fine
- Once wake word is detected and the user
  starts speaking their command, record
  the audio to a buffer instead of using
  Apple Speech for transcription
- When the user stops speaking (1.3 second
  silence threshold, same as current), send
  the recorded audio buffer to Groq's
  Whisper API endpoint:
  POST https://api.groq.com/openai/v1/audio/transcriptions
  model: whisper-large-v3-turbo
  file: the recorded audio as m4a or wav
  language: en
- Use the Groq transcription result as the
  command text instead of Apple Speech output
- The GROQ_API_KEY is already stored —
  add a way to pass it from the backend
  settings or hardcode it in Config.swift
  from UserDefaults key "felix.groqAPIKey"
- Add "felix.groqAPIKey" input field to
  SettingsTab.swift so the user can enter
  their Groq API key once
- Show a small "Whisper" badge near the
  transcription text so the user knows
  which engine transcribed their command
- If Groq Whisper fails for any reason,
  fall back to the existing Apple Speech
  transcription silently

This fix alone will dramatically improve
accuracy for names, technical terms, and
any non-common-word commands.

---

## HOTFIX 2: Do Not Disturb

Stop trying to automate Focus mode.
Apple has locked this down on modern macOS
and no AppleScript approach works reliably.

Remove system.do_not_disturb entirely.

Replace with system.open_focus_settings:
args: none
Opens System Settings to the Focus pane:
subprocess.run(["open",
  "x-apple.systempreferences:
  com.apple.preference.notifications"])

speak: "Opening Focus settings for you."
summary: ""

Update LLM routing so any command containing
"do not disturb", "focus mode", "focus on",
"quiet mode", "silence notifications" routes
to system.open_focus_settings.

---

## HOTFIX 3: Web research returning
no sources

Fix web.research so it actually returns
results for any valid topic. Try multiple
search strategies in order until one works.
Never return empty results for a real topic.
If all search methods fail, have Groq
generate a summary from its own knowledge
and clearly label it as "from AI knowledge,
not live sources".

Also fix LLM routing to ensure "research X",
"look up X", "tell me about X" always goes
to web.research and never to browser.open_url.

---

## Constraints
- wake word detection stays on Apple Speech
- Whisper transcription via Groq API only
- No new dependencies beyond what Groq SDK
  already provides
- All fixes follow existing return contract
- Dark mode, amber accent, SF Pro throughout