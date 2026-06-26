# Felix Pre-Launch Feature Build

Complete each phase fully before moving to the next.
After each phase: summarize every file changed, how to
test it, and wait for confirmation before proceeding.

---

## PHASE 1: Fix broken tools + add core missing tools

### 1a. Replace Spotify tool
In backend/tools.py, delete the entire spotify.play_song
implementation and replace with:

- spotify.play_song: args { query: string }
  - Open Spotify via URI: open "spotify:"
  - Delay 1.5 seconds
  - Send play/pause media key via AppleScript:
    tell application "System Events" to key code 100
  - If query is specific (not just "play something"),
    open "spotify:search:{encoded_query}" first, then
    delay 1.5, then send key code 100
  - Never use UI scripting, never poll for buttons

### 1b. Add system control tools
- system.set_volume: args { level: 0-100 }
  osascript: set volume output volume {level}

- system.set_brightness: args { level: 0-100 }
  Use the brightness CLI tool if installed, fallback to
  osascript via System Events slider

- system.do_not_disturb: args { enabled: bool }
  Toggle macOS Focus via osascript

- system.lock_screen: no args
  osascript: tell application "System Events" to
  keystroke "q" using {control down, command down}

- system.empty_trash: no args
  osascript: tell application "Finder" to empty trash
  Requires confirmation (mark as irreversible)

- system.get_battery: no args
  Shell: pmset -g batt, parse and return percentage
  and charging status

### 1c. Add Finder tools
- finder.open_file: args { query: string }
  Use mdfind "{query}" to search via Spotlight
  Open the top result with the open command
  Return the file path that was opened

- finder.find_file: args { query: string }
  Same as above but return the top 5 results as a
  list without opening, so Felix can confirm with
  the user which one they meant

- finder.move_file: args { source: string,
  destination: string }
  Shell: mv with full path expansion
  Mark as irreversible — requires confirmation

- finder.create_folder: args { path: string }
  Shell: mkdir -p "{path}"

- finder.rename_file: args { path: string,
  new_name: string }
  Shell: mv to rename in place
  Mark as irreversible

- finder.show_in_finder: args { path: string }
  osascript: tell application "Finder" to
  reveal POSIX file "{path}"

### 1d. Add clipboard tool
- clipboard.copy_text: args { text: string }
  Shell: echo "{text}" | pbcopy
  Returns confirmation of what was copied

### 1e. Add Calendar tools
- calendar.create_event: args { title: string,
  start_datetime: ISO8601 string,
  duration_minutes: int, notes?: string,
  calendar_name?: string }
  Parse natural language dates in llm.py BEFORE
  calling this tool — convert "tomorrow at 3pm"
  to a real ISO8601 datetime using Python's
  dateparser library
  AppleScript to Calendar.app to create the event
  Mark as irreversible — requires confirmation

- calendar.read_today: no args
  AppleScript reads all events from today
  Returns list of { title, start_time, end_time,
  location, calendar_name }

- calendar.read_week: no args
  Same as above but for the next 7 days

- calendar.find_free_time: args { duration_minutes:
  int, within_days: int }
  Read calendar for the next {within_days} days
  Find gaps of at least {duration_minutes} minutes
  during work hours (9am-6pm)
  Return the top 3 free slots

### 1f. Add Reminders tools
- reminders.add_item: args { title: string,
  list_name?: string, due_date?: ISO8601 string,
  notes?: string }
  AppleScript to Reminders.app
  Default list_name to "Reminders" if not specified
  Mark as irreversible

- reminders.read_list: args { list_name?: string }
  AppleScript reads incomplete items from the list
  Returns { title, due_date, notes } per item

- reminders.complete_item: args { title: string,
  list_name?: string }
  AppleScript marks matching item as complete

### 1g. Add Contacts tool
- contacts.find: args { query: string }
  AppleScript searches Contacts.app by name
  Returns { name, email, phone } for top 3 matches
  Use this to resolve "email my boss" by looking
  up the contact first

### 1h. Add Screenshot tool
- screen.capture_and_describe: no args
  Take a screenshot using screencapture CLI
  Send the screenshot to Gemini Vision
  Return a description of what is on screen
  Felix can then act on what it sees

- screen.capture_and_act: args { instruction: string }
  Take screenshot, send to Gemini with the instruction
  Gemini returns a plan based on what it sees
  Execute the plan
  This lets Felix "see" the Mac screen and act on it

### 1i. Update LLM routing
In backend/llm.py:
- Add dateparser to requirements.txt
- Before passing args to calendar tools, parse any
  natural language date/time strings to ISO8601
- Update the system prompt to include all new tools
  with descriptions so the LLM knows they exist
- Add intent recognition for the new tool categories:
  "volume", "brightness", "calendar", "reminder",
  "find file", "screenshot", "contacts"

All tools must return:
{ status, message, title, tool, data, elapsed_ms }
following the existing contract.

---

## PHASE 2: Confirmation system for irreversible actions

Irreversible tools that require confirmation before
executing:
- finder.move_file
- finder.rename_file
- system.empty_trash
- calendar.create_event
- reminders.add_item
- gmail.draft_email

### Backend (backend/engine.py)
- Before executing any tool in the irreversible list,
  broadcast a WebSocket event "confirm_required":
  {
    session_id: string,
    action_id: int,
    tool: string,
    args: object,
    summary: string  // plain English: "Create a calendar
                     // event called 'Lunch with Ishaan'
                     // on Tuesday June 24 at 12:00 PM"
  }
- Pause execution using asyncio.Event, wait up to
  30 seconds for confirmation
- Listen for incoming WebSocket message type
  "confirm_action": { action_id, confirmed: bool }
- If confirmed true: execute and continue
- If confirmed false or timeout: broadcast
  "action_cancelled" and skip the step

### iOS (WebSocketClient.swift + CameraTab.swift)
- Handle "confirm_required" event in WebSocketClient
- Show a modal confirmation sheet from CameraTab:
  - Large tool icon at top
  - Summary text in bold
  - Green "Do it" button
  - Red "Cancel" button
- Tapping either sends "confirm_action" back over
  the WebSocket immediately
- Sheet dismisses automatically after action

### Web client (web-client/index.html)
- Same confirmation as a centered modal overlay
- Same two buttons, same WebSocket response

---

## PHASE 3: Conversation history within a session

### Backend (backend/llm.py)
- Add in-memory dict: session_history = {}
  keyed by session_id
- Each entry stores last 10 turns:
  [{ role: "user"|"felix", content: string }]
- On each /ingest:
  1. Append voice_text as a user turn
  2. Inject last 5 turns into the LLM prompt as
     a "RECENT CONVERSATION" block before the
     current command
  3. After plan executes successfully, append a
     one-sentence summary as a felix turn
- Clear a session's history after 2 hours of
  inactivity using a timestamp per session
- Format for prompt injection:
  RECENT CONVERSATION:
  User: {turn}
  Felix: {turn}
  ...
  Current command: {voice_text}

This allows commands like:
"Do that again" / "Add another one" /
"Change the time to 3pm instead" to work correctly

---

## PHASE 4: Expanded persistent memory

### Backend (backend/memory.py)
Expand learn_from_action to extract and store:

- expense_file (already exists)
- music_service (already exists)
- last_email_recipient (already exists)
- default_browser: learn from browser.open_url,
  store which browser is used (Chrome/Safari/Firefox)
- preferred_calendar: learn from calendar.create_event,
  store which calendar_name is used most
- preferred_reminder_list: learn from reminders.add_item,
  store which list_name is used most
- frequent_contacts: from gmail.draft_email and
  contacts.find, maintain a list of top 5 names/emails
- home_folder: infer from finder operations,
  store the most common directory path prefix
- command_patterns: store the 5 most frequent
  command types (e.g. "calendar", "notes", "music")
  so Felix can anticipate intent faster

Add a memory.get_context_block() method that formats
all current memory as a natural language paragraph
injected into every LLM call:

"The user's expense file is at ~/Documents/Expenses.
Their preferred calendar is 'Personal'. They frequently
email john@example.com. Their most used tools are
calendar and notes."

---

## PHASE 5: Screen awareness

### Backend (backend/tools.py)
- screen.capture_and_describe: no args
  1. Run: screencapture -x /tmp/felix_screen.png
     (-x = no sound)
  2. Read the file as base64
  3. Send to Gemini Vision with prompt:
     "Describe what is on this screen in detail.
      List the app in focus, any visible text,
      any errors, and what the user appears to
      be working on."
  4. Return the description as the tool result
  5. Delete the temp file

- screen.capture_and_act: args { instruction: string }
  1. Same screenshot capture
  2. Send to Gemini Vision with the instruction:
     "Here is a screenshot of the user's Mac.
      The user wants to: {instruction}
      Based on what you see, create a step-by-step
      plan using Felix's available tools."
  3. Execute the returned plan through engine.py
  4. This enables: "fix this error", "what am I
     looking at", "summarize this page", "fill in
     this form"

This is Felix's biggest differentiator vs Claude
Dispatch — Felix can see the physical world via
phone camera AND the digital world via screen capture.

---

## PHASE 6: Research agent

### Backend (backend/tools.py)
- web.search: args { query: string }
  Use the Gemini API's built-in grounding/search
  capability, or fallback to SerpAPI if available
  Returns top 5 results as { title, url, snippet }

- web.fetch_page: args { url: string }
  Use requests + BeautifulSoup to fetch and parse
  a web page, strip HTML, return clean text
  Truncate to 3000 chars to fit in context

- web.research: args { topic: string,
  output_format: "note"|"document"|"summary" }
  This is a compound tool that:
  1. Searches for the topic (3-5 queries)
  2. Fetches the top 3 results
  3. Sends all content to Gemini with:
     "Synthesize this into a {output_format}
      about {topic}. Be specific and cite sources."
  4. Creates a Note or document with the result
  5. Returns what was created

Add BeautifulSoup4 and requests to requirements.txt

### LLM routing
Update system prompt to recognize research intent:
"research", "find out about", "look up", "what is",
"summarize", "learn about" → route to web.research

---

## PHASE 7: iOS share sheet extension

### New Xcode target: FelixShare
- Type: Share Extension
- Deployment target: iOS 17
- Accepted content types: text, URLs, images,
  PDFs (kUTTypeText, kUTTypeURL, kUTTypeImage,
  kUTTypePDF)

### ShareViewController.swift (new)
- On appear: extract the shared content
  - Text: use as voice_text directly
  - URL: use as voice_text "Open and summarize {url}"
  - Image: encode as base64 for the image field
  - PDF: extract first 500 chars of text as context
- Show a minimal UI:
  - Preview of what's being shared (text preview
    or image thumbnail)
  - Single text field: "What should Felix do with
    this?" pre-filled with a sensible default
  - Send button (amber, full width)
  - Cancel button
- On send: POST to /ingest using the stored
  backend URL from UserDefaults "felix.backendURL"
- Show success toast: "Felix got it" then dismiss
- Show error toast if backend unreachable

---

## PHASE 8: iOS lock screen widget + URL scheme

### URL scheme
In Info.plist add URL scheme: felix
Handle felix://capture in the main app:
- Set a flag that auto-triggers microphone on launch
- In CameraTab.swift onAppear: check for this flag
  and immediately activate listening mode if set

### New Xcode target: FelixWidget
- Type: Widget Extension
- Name: FelixWidget
- Widget kind: accessoryCircular (lock screen only)

### FelixWidget.swift (new)
- Timeline: refreshes every 15 minutes
- Display: waveform.circle SF Symbol in amber
  on dark background
- Tap action: deep link to felix://capture
- Subtitle: "Felix" in small text below icon

---

## PHASE 9: Onboarding flow

### OnboardingView.swift (new)
Show on first launch when UserDefaults
"felix.onboardingComplete" is false or missing.

Three swipeable screens:

Screen 1 — "Your camera is now a command"
- Large camera icon animation
- Headline: "Point. Speak. Done."
- Body: "Show Felix anything in the real world.
  It figures out what to do on your Mac."
- Example: image of a receipt → Numbers spreadsheet
- Next button

Screen 2 — "Felix lives on both your devices"
- Simple diagram: iPhone ↔ Cloud ↔ Mac
- Headline: "One brain. Two devices."
- Body: "Speak on your phone. Execute on your Mac.
  Results come back to you instantly."
- Example command: "Hey Felix, find my pitch deck
  and email it to Sarah"
- Next button

Screen 3 — "Let's connect"
- Backend URL text field
  placeholder: "https://your-backend-url"
  saved to UserDefaults "felix.backendURL"
- Test Connection button → shows green checkmark
  and latency, or red error message
- "Grant Mac Permissions" button →
  opens felix://setup or shows instructions
  for granting Accessibility permission on Mac
- "I'm ready" button → sets
  felix.onboardingComplete = true,
  dismisses onboarding, enters main app

Design: dark background, amber accent,
SF Pro Heavy headlines, SF Pro Regular body.
No more than 3 words per bullet point on slides.

---

## PHASE 10: Update CLAUDE.md and tool registry

After all phases complete:

Update CLAUDE.md to reflect the new tool list:

New tools added pre-launch:
- system: set_volume, set_brightness,
  do_not_disturb, lock_screen, empty_trash,
  get_battery
- finder: open_file, find_file, move_file,
  create_folder, rename_file, show_in_finder
- clipboard: copy_text
- calendar: create_event, read_today,
  read_week, find_free_time
- reminders: add_item, read_list, complete_item
- contacts: find
- screen: capture_and_describe, capture_and_act
- web: search, fetch_page, research

Update the system prompt in llm.py to include
all new tools with one-line descriptions so the
LLM can route to them correctly.

Run test_tools.py on all new tools and fix any
that exceed 2000ms or return errors.

---

## Constraints (do not violate)
- Never touch CameraManager.swift or
  SpeechRecognizer.swift
- No new Python dependencies without listing them
  explicitly and adding to requirements.txt
- All errors surface in UI, never console-only
- Dark mode only, SF Pro, amber accent #F59E21
- All new tools follow the existing return contract
- Existing WebSocket event types unchanged,
  only add new ones
- All new AppleScript requires Accessibility
  permission — document this in each tool's
  docstring