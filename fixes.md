# Felix Bug Fixes + Voice + Summary Card

Fix all issues below in order. After each section
summarize what changed and wait for confirmation.

---

## FIX 1: Inject current date into every LLM call

In backend/llm.py:
- Import datetime at the top if not already imported
- At the start of every prompt construction, compute:
  TODAY = datetime.now().strftime("%A, %B %d, %Y")
  TIME = datetime.now().strftime("%I:%M %p")
- Add this to the system prompt:
  "Today is {TODAY} and the current time is {TIME}.
  Always use these as the reference for all relative
  dates and times. 'Tomorrow' means the day after
  {TODAY}. 'Next Tuesday' means the next Tuesday
  after {TODAY}. Never guess or assume the date.
  Never use any date from your training data."
- This must be injected dynamically on every call,
  not hardcoded once at startup.

---

## FIX 2: Path expansion for all Finder tools

In backend/tools.py, apply these rules to every
finder tool before executing any shell command:

- Always run: path = os.path.expanduser(path)
- Always run: path = os.path.abspath(path)
- If the path has no directory separator (it is
  just a bare name like "Felix Test"), default it
  to os.path.expanduser("~/Desktop/{name}")
- Never pass raw /Users/[username] to any command
- Never let the LLM construct absolute paths —
  always expand and resolve in Python before use

Apply this to:
- finder.create_folder
- finder.open_file
- finder.find_file
- finder.move_file
- finder.rename_file
- finder.show_in_finder

Also update the LLM system prompt to say:
"For all finder tools, pass only relative paths
or folder names. Never construct absolute paths.
Examples: 'Felix Test', '~/Desktop/Felix Test',
'Documents/Projects'. The backend will resolve
the full path automatically."

---

## FIX 3: system.do_not_disturb

Replace the current AppleScript menu bar approach
entirely. Use this implementation in order of
preference:

Attempt 1 — shortcuts CLI:
subprocess.run([
  "shortcuts", "run",
  "Turn Do Not Disturb On" if enabled else
  "Turn Do Not Disturb Off"
], timeout=5)

Attempt 2 — osascript Focus toggle:
tell application "System Events"
  tell process "ControlCenter"
    click menu bar item "Control Center"
      of menu bar 1
    delay 0.5
    click button "Focus" of window "Control Center"
    delay 0.3
    click button "Do Not Disturb" of window 1
  end tell
end tell

Attempt 3 — if both fail, return a graceful error:
{
  status: "error",
  message: "Could not toggle Do Not Disturb
  automatically on this macOS version. Please
  go to Control Center and toggle Focus manually.",
  title: "Do Not Disturb",
  tool: "system.do_not_disturb"
}

Never crash or raise an exception — always return
a structured result even on failure.

---

## FIX 4: Contacts fuzzy matching

In backend/tools.py, contacts.find:

Replace the current AppleScript with this approach:
tell application "Contacts"
  set matches to (every person whose
    name contains "{query}" or
    first name contains "{query}" or
    last name contains "{query}" or
    nickname contains "{query}")
  set resultList to {}
  repeat with p in items 1 thru
    (minimum of {count of matches, 3})
    set contactInfo to {name of p}
    try
      set end of resultList to
        {name: name of p,
         email: value of first email of p,
         phone: value of first phone of p}
    end try
  end repeat
  return resultList
end tell

- Return top 3 matches not just 1
- If 0 results found, return:
  status: "error"
  message: "No contact found matching '{query}'.
  Try just the first name or check spelling."
- Never return an empty result silently

---

## FIX 5: Research intent detection

In backend/llm.py, update the system prompt to
add this block prominently at the top:

"CRITICAL ROUTING RULES:
- If the user says 'research X', 'look up X',
  'find out about X', 'what is X', 'tell me about X',
  'summarize X', 'learn about X' → ALWAYS use
  web.research. NEVER open a browser.
- If the user says 'open X', 'go to X', 'navigate
  to X', 'visit X' → use browser.open_url.
- NEVER use browser.open_url for research requests.
- NEVER use web.research for navigation requests.
- These two intents are mutually exclusive."

Also in backend/llm.py, add a post-processing
guard in _enforce_single_intent or equivalent:

research_keywords = [
  "research", "look up", "find out about",
  "what is", "tell me about", "summarize",
  "learn about", "explain"
]
navigation_keywords = [
  "open", "go to", "navigate", "visit", "browse to"
]

If any research_keyword is in voice_text.lower()
AND no navigation_keyword is present:
  Force the plan to use web.research
  Remove any browser.open_url steps

---

## FIX 6: Screen capture — Groq only, no Gemini

In backend/tools.py, rewrite screen.capture_and_describe
and screen.capture_and_act to use Groq exclusively:

Remove all Gemini API calls and GEMINI_API_KEY
checks from these tools entirely.

New implementation for screen.capture_and_describe:

1. Capture screenshot:
   subprocess.run([
     "screencapture", "-x", "-t", "png",
     "/tmp/felix_screen.png"
   ], check=True)

2. Read and encode:
   with open("/tmp/felix_screen.png", "rb") as f:
     b64 = base64.b64encode(f.read()).decode()

3. Call Groq with image:
   from groq import Groq
   client = Groq(api_key=os.environ["GROQ_API_KEY"])
   response = client.chat.completions.create(
     model=os.environ.get(
       "GROQ_MODEL",
       "meta-llama/llama-4-scout-17b-16e-instruct"
     ),
     messages=[{
       "role": "user",
       "content": [
         {
           "type": "image_url",
           "image_url": {
             "url": f"data:image/png;base64,{b64}"
           }
         },
         {
           "type": "text",
           "text": (
             "Describe what is on this Mac screen "
             "in detail. Include: the app in focus, "
             "any visible text, any errors or warnings,"
             " and what the user appears to be working"
             " on. Be specific and thorough."
           )
         }
       ]
     }],
     max_tokens=1000
   )
   description = response.choices[0].message.content

4. Clean up:
   os.remove("/tmp/felix_screen.png")

5. Return:
   {
     status: "success",
     message: description,
     title: "Screen Description",
     tool: "screen.capture_and_describe",
     data: { description: description },
     speak: first 2 sentences of description,
     summary: full description
   }

Apply the same Groq image pattern to
screen.capture_and_act, passing the instruction
as the text content alongside the screenshot.

Audit the entire tools.py file for any remaining
Gemini references and remove them all.
The only AI provider is Groq. The only required
API key is GROQ_API_KEY.

---

## FIX 7: Voice responses (text-to-speech)

### Backend changes

In backend/tools.py, add a "speak" field to every
tool's return dict. This is a short 1-2 sentence
spoken summary of the result:

- calendar.create_event success:
  "Done. I've added {title} to your calendar
  on {date} at {time}."

- calendar.read_today success:
  "You have {n} events today. First up is
  {first_event_title} at {first_event_time}."
  If no events: "Your calendar is clear today."

- calendar.read_week success:
  "You have {n} events this week. Next up is
  {first_event_title} on {day}."

- reminders.read_list success:
  "You have {n} reminders. First is {first_item}."
  If empty: "Your reminders list is empty."

- reminders.add_item success:
  "Added {title} to your reminders."

- contacts.find success:
  "Found {name}. Their email is {email}
  and phone is {phone}."

- system.get_battery success:
  "Your battery is at {level}% and is
  {charging/not charging}."

- web.research success:
  "Done. I've created a note summarizing
  {topic} for you."

- screen.capture_and_describe success:
  First 2 sentences of the description only.

- finder.open_file success:
  "Opened {filename} for you."

- clipboard.copy_text success:
  "Copied to your clipboard."

- notes.create_from_image success:
  "Created a new note called {title}."

- For any error: "I couldn't complete that.
  {one sentence reason from the error message}."

- For action-only tools with no content to speak
  (set_volume, set_brightness, create_folder,
  open_url, etc.): speak field can be empty string
  — do not generate a spoken response for these.

Pass the "speak" field through engine.py into
the WebSocket step_executed event broadcast.

### iOS changes

In WebSocketClient.swift:
- Add at the top: import AVFoundation
- Add property:
  private let synthesizer = AVSpeechSynthesizer()
- Add property:
  @Published var voiceEnabled: Bool =
    UserDefaults.standard.bool(
      forKey: "felix.voiceEnabled"
    )
- When handling step_executed WebSocket event,
  after updating published state, check:
  if voiceEnabled,
  let speak = data.speak,
  !speak.isEmpty {
    let utterance = AVSpeechUtterance(string: speak)
    utterance.voice =
      AVSpeechSynthesisVoice(language: "en-US")
    utterance.rate = 0.52
    utterance.pitchMultiplier = 1.0
    utterance.volume = 1.0
    synthesizer.speak(utterance)
  }

In SettingsTab.swift:
- Add a toggle under a new "Voice" section:
  Toggle("Felix speaks results",
    isOn: $voiceEnabled)
  .onChange(of: voiceEnabled) { _, val in
    UserDefaults.standard.set(val,
      forKey: "felix.voiceEnabled")
  }
- Default value: true
- Description text below toggle:
  "Felix will read results aloud when it finds
  information or completes a task."

---

## FIX 8: Summary card — iOS bottom sheet

### Backend changes

In backend/tools.py, add a "summary" field to
tools that return displayable content. This is
longer than "speak" and formatted for reading:

- calendar.read_today:
  Format as:
  "Today — {weekday}, {date}\n
  \n
  {start_time} — {title} ({location if exists})\n
  {start_time} — {title}\n
  ..."
  If no events: "No events scheduled for today."

- calendar.read_week:
  Group by day:
  "This Week\n
  \n
  Monday\n
  {time} — {title}\n
  \n
  Tuesday\n
  {time} — {title}\n
  ..."

- reminders.read_list:
  "Reminders — {list_name}\n
  \n
  • {title} (due {date if exists})\n
  • {title}\n
  ..."

- contacts.find:
  "Contact Found\n
  \n
  Name: {name}\n
  Email: {email}\n
  Phone: {phone}\n
  ..."

- system.get_battery:
  "Battery Status\n
  \n
  Level: {level}%\n
  Status: {Charging / Not Charging}\n
  Time remaining: {if available}"

- web.research:
  The full synthesized research text, up to
  500 characters, with a "See note for full
  summary" footer.

- screen.capture_and_describe:
  The full description text from Groq.

Pass "summary" through engine.py into the
WebSocket step_executed event.

### iOS changes (CameraTab.swift)

Replace the current ResultToast for content tools
with a full bottom sheet:

Define a list of content tools:
CONTENT_TOOLS = [
  "calendar.read_today",
  "calendar.read_week",
  "reminders.read_list",
  "contacts.find",
  "system.get_battery",
  "web.research",
  "screen.capture_and_describe"
]

When step_executed arrives:
- If tool is in CONTENT_TOOLS AND summary is
  non-empty → show SummarySheet
- Otherwise → show existing small ResultToast

SummarySheet view:
- Presented as .sheet with detents:
  [.medium, .large]
- Drag handle at top
- Tool icon (large, 52x52, amber background)
  centered at top
- Tool display name as subtitle (e.g. "Today's
  Calendar", "Battery Status", "Research")
- Divider
- Scrollable text area with the summary content
  formatted with proper line breaks
- Monospace font for structured data
  (calendar events, contacts)
- Regular SF Pro for prose (research, screen)
- Bottom bar with two buttons:
  Left: Copy (copies summary to clipboard,
    shows "Copied!" confirmation)
  Right: Dismiss
- Background: system background (dark)
- Amber accent on tool icon and copy button

Keep the small ResultToast for non-content tools.

### Mac dashboard changes (ActivityView.swift)

When an action row has a non-empty summary field:
- Show an expandable chevron on the right of
  the row
- Tapping the row expands a summary card below it
- Summary card styling:
  Rounded rectangle
  Slightly lighter background than the row
  SF Pro Regular for prose
  SF Mono for structured data
  Padding 12pt all sides
- Auto-expand the most recent content tool result
- Collapse when another row is tapped

---

## FIX 9: Update CLAUDE.md

After all fixes are complete, update CLAUDE.md:

Add under constraints:
"AI Provider: Groq (llama-4-scout) ONLY.
No Gemini, no OpenAI, no other providers.
GROQ_API_KEY is the only required API key.
Never add Gemini dependencies."

Add to tool list the new fields all tools return:
- speak: string (short spoken summary, empty for
  action-only tools)
- summary: string (longer formatted display text,
  only for content tools)

---

## Constraints throughout all fixes
- Never touch CameraManager.swift or
  SpeechRecognizer.swift
- No Gemini anywhere — Groq only
- No new Python dependencies except ones
  explicitly listed here
- All errors return structured results, never
  crash or raise unhandled exceptions
- Dark mode only, SF Pro, amber accent #F59E21
- All WebSocket event changes are additive only —
  never remove or rename existing fields
- Run test_tools.py after Fix 6 to verify all
  screen tools work with Groq
- After all fixes: do a full audit of tools.py
  to confirm zero Gemini references remain