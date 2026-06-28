# Lumis — Full Agentic Rebuild

This document replaces the current single-shot `llm.py → engine.py` pipeline with a
proper deep ReAct agentic loop. Every section must be implemented completely and to
production quality. No placeholders.

---

## What is changing and why

The current system works like this:
1. User sends image + voice text
2. `llm.py` asks Groq to generate a full JSON plan upfront
3. `engine.py` blindly executes every step in that plan
4. Done — no ability to observe results, recover from errors, or adapt

This is not agentic. It is a script runner with an LLM attached.

The new system works like this:
1. User sends image + voice text
2. The agent reasons about what to do first
3. It calls one tool
4. It reads the real result of that tool
5. It reasons again — did it work? what next? does it need to ask the user something?
6. It calls the next tool based on what actually happened
7. It keeps going until the task is genuinely complete or it determines it cannot proceed
8. At any point it can look at the Mac screen to verify reality, ask the user a
   clarifying question, or recover from an error by trying a different approach

This loop runs entirely in `backend/` on Railway. The iOS app, Mac agent, and
WebSocket layer are largely unchanged — the agent just uses them as tools.

---

## Part 1 — Remove Google Slides integration

Delete or disable all Google Slides / Google Cloud API dependencies. These require
per-user OAuth consent flows that are not deployment-ready.

Files to clean up:
- `backend/google_svc.py` — delete entirely
- `backend/authorize.py` — delete entirely
- `backend/token.json` — delete if present, add to `.gitignore`
- `backend/tools.py` — remove all functions in the `slides.*` family:
  - `slides.create_presentation`
  - Any other tool that calls `google_svc.py` or requires `token.json`
- `backend/llm.py` — remove `slides.*` tools from the tool list / system prompt
- `backend/.env.example` — remove `GOOGLE_*` variables
- `backend/requirements.txt` — remove `google-api-python-client`,
  `google-auth-httplib2`, `google-auth-oauthlib` if present

After removal, verify the backend starts cleanly with no import errors related to
Google APIs.

---

## Part 2 — The ReAct Agent Loop

### Overview

Replace `backend/llm.py` and `backend/engine.py` with a new agent module:
`backend/agent.py`.

The agent implements a **Reasoning + Acting (ReAct)** loop:

```
THINK → ACT → OBSERVE → THINK → ACT → OBSERVE → ... → DONE
```

Each iteration:
1. **THINK** — send the full context (original request, image, memory, conversation
   history, and ALL previous tool results so far) to Groq and ask: what should I do
   next?
2. **ACT** — execute exactly one tool call
3. **OBSERVE** — read the real result, append it to context
4. **REPEAT** — until the agent emits a `finish` action or hits the step limit

### `backend/agent.py` — new file

```python
"""
Lumis ReAct Agent
Implements a deep reasoning loop using Groq (llama-4-scout).
One tool call per iteration. Observes real results before deciding next step.
"""

import json
import asyncio
import base64
from typing import Optional
from groq import Groq

from tools import TOOL_REGISTRY, execute_tool
from memory import get_memory, update_memory
from mac_bridge import send_to_mac, wait_for_mac_result
from vision import capture_mac_screen

MAX_STEPS = 20          # Hard cap — prevents infinite loops
THINK_TIMEOUT = 30      # Seconds to wait for Groq response
MAC_TOOL_TIMEOUT = 30   # Seconds to wait for Mac agent result

class LumisAgent:
    def __init__(self, user_id: str, session_id: str, websocket_broadcast):
        self.user_id = user_id
        self.session_id = session_id
        self.broadcast = websocket_broadcast   # async fn to push updates to phone
        self.client = Groq()
        self.steps_taken = 0
        self.context = []   # Full message history for this run
        self.pending_question = None  # Set when agent asks user something

    async def run(self, voice_text: str, image_b64: Optional[str] = None):
        """
        Entry point. Called by routes.py when /ingest receives a request.
        Runs the full ReAct loop until done or step limit hit.
        """
        user_memory = get_memory(self.user_id)

        # Build the initial user message
        user_content = self._build_initial_message(voice_text, image_b64, user_memory)
        self.context.append({"role": "user", "content": user_content})

        await self.broadcast({
            "event": "agent_start",
            "session_id": self.session_id,
            "message": "Lumis is thinking…"
        })

        while self.steps_taken < MAX_STEPS:
            # THINK
            decision = await self._think()

            action = decision.get("action")

            # Agent wants to ask the user something
            if action == "ask_user":
                await self._handle_ask_user(decision)
                return   # Pause loop — will resume when user replies

            # Agent is done
            if action == "finish":
                await self._handle_finish(decision)
                return

            # Agent wants to look at the Mac screen
            if action == "capture_screen":
                await self._handle_screen_capture()
                continue

            # Agent wants to call a tool
            if action == "tool_call":
                await self._handle_tool_call(decision)
                continue

            # Unexpected response — treat as done
            await self._handle_finish({"summary": "Task complete.", "speak": "Done."})
            return

        # Hit step limit
        await self.broadcast({
            "event": "agent_error",
            "session_id": self.session_id,
            "message": "I ran out of steps trying to complete that. Try a simpler command.",
            "speak": "I wasn't able to finish that. Try breaking it into smaller steps."
        })

    async def resume(self, user_reply: str):
        """
        Called when the user answers a clarifying question.
        Appends their answer and continues the loop.
        """
        self.context.append({
            "role": "user",
            "content": user_reply
        })
        self.pending_question = None
        await self.run_from_context()

    async def run_from_context(self):
        """Continue the ReAct loop from existing context (used after user replies)."""
        while self.steps_taken < MAX_STEPS:
            decision = await self._think()
            action = decision.get("action")

            if action == "ask_user":
                await self._handle_ask_user(decision)
                return
            if action == "finish":
                await self._handle_finish(decision)
                return
            if action == "capture_screen":
                await self._handle_screen_capture()
                continue
            if action == "tool_call":
                await self._handle_tool_call(decision)
                continue

            await self._handle_finish({"summary": "Done.", "speak": "Done."})
            return

    # ── Private methods ──────────────────────────────────────────────────────

    async def _think(self) -> dict:
        """Send full context to Groq. Returns the agent's next decision as a dict."""
        try:
            response = self.client.chat.completions.create(
                model="meta-llama/llama-4-scout-17b-16e-instruct",
                messages=[
                    {"role": "system", "content": AGENT_SYSTEM_PROMPT},
                    *self.context
                ],
                response_format={"type": "json_object"},
                timeout=THINK_TIMEOUT
            )
            raw = response.choices[0].message.content
            return json.loads(raw)
        except Exception as e:
            return {"action": "finish", "summary": f"I hit an error while thinking: {e}", "speak": "Something went wrong."}

    async def _handle_tool_call(self, decision: dict):
        tool_name = decision.get("tool")
        tool_args = decision.get("args", {})
        reasoning = decision.get("reasoning", "")

        self.steps_taken += 1

        await self.broadcast({
            "event": "agent_step",
            "session_id": self.session_id,
            "step": self.steps_taken,
            "tool": tool_name,
            "reasoning": reasoning,
            "message": decision.get("status_message", f"Running {tool_name}…")
        })

        # Determine if this tool runs on the Mac or on Railway
        tool_meta = TOOL_REGISTRY.get(tool_name)
        if tool_meta is None:
            result = {"status": "error", "message": f"Unknown tool: {tool_name}"}
        elif tool_meta.get("runs_on") == "mac":
            result = await self._run_mac_tool(tool_name, tool_args)
        else:
            result = await execute_tool(tool_name, tool_args, self.user_id)

        # Update persistent memory if the result teaches us something
        if result.get("status") == "success" and result.get("learn"):
            update_memory(self.user_id, result["learn"])

        # Append tool result to context so next THINK sees it
        self.context.append({
            "role": "assistant",
            "content": json.dumps({
                "action": "tool_call",
                "tool": tool_name,
                "args": tool_args,
                "reasoning": reasoning
            })
        })
        self.context.append({
            "role": "user",
            "content": json.dumps({
                "tool_result": {
                    "tool": tool_name,
                    "status": result.get("status"),
                    "data": result
                }
            })
        })

        # Broadcast the result to the phone live
        await self.broadcast({
            "event": "step_executed",
            "session_id": self.session_id,
            "tool": tool_name,
            "status": result.get("status"),
            "title": result.get("title", tool_name),
            "message": result.get("message", ""),
            "url": result.get("url"),
            "summary": result.get("summary"),
            "speak": result.get("speak")
        })

    async def _run_mac_tool(self, tool_name: str, tool_args: dict) -> dict:
        """Send a tool call to the Mac agent and wait for the result."""
        action_id = f"{self.session_id}-{self.steps_taken}"
        sent = await send_to_mac(self.user_id, {
            "event": "execute_on_mac",
            "action_id": action_id,
            "tool": tool_name,
            "args": tool_args
        })
        if not sent:
            return {
                "status": "error",
                "message": "Mac agent is not connected. Make sure the Lumis Mac app is running."
            }
        result = await wait_for_mac_result(action_id, timeout=MAC_TOOL_TIMEOUT)
        if result is None:
            return {
                "status": "error",
                "message": "Mac agent did not respond in time. It may be busy or offline."
            }
        return result

    async def _handle_screen_capture(self):
        """Capture the Mac screen, encode it, add to context as vision input."""
        self.steps_taken += 1
        await self.broadcast({
            "event": "agent_step",
            "session_id": self.session_id,
            "step": self.steps_taken,
            "tool": "capture_screen",
            "message": "Looking at your Mac screen…"
        })

        screenshot_b64 = await capture_mac_screen(self.user_id)

        if screenshot_b64 is None:
            self.context.append({
                "role": "user",
                "content": json.dumps({
                    "tool_result": {
                        "tool": "capture_screen",
                        "status": "error",
                        "message": "Could not capture Mac screen. Mac agent may be offline."
                    }
                })
            })
            return

        # Add screenshot as a vision message so llama-4-scout can see it
        self.context.append({
            "role": "assistant",
            "content": json.dumps({"action": "capture_screen", "reasoning": "Checking what is on the Mac screen"})
        })
        self.context.append({
            "role": "user",
            "content": [
                {
                    "type": "text",
                    "text": "Here is the current Mac screen. Use this to verify what happened and decide what to do next."
                },
                {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/png;base64,{screenshot_b64}"
                    }
                }
            ]
        })

    async def _handle_ask_user(self, decision: dict):
        """Pause the loop and ask the user a clarifying question."""
        question = decision.get("question", "I need more information to continue.")
        self.pending_question = question

        await self.broadcast({
            "event": "agent_question",
            "session_id": self.session_id,
            "question": question,
            "speak": question
        })

        # Append to context so the agent remembers it asked
        self.context.append({
            "role": "assistant",
            "content": json.dumps({"action": "ask_user", "question": question})
        })

    async def _handle_finish(self, decision: dict):
        """Agent is done. Broadcast final result."""
        await self.broadcast({
            "event": "agent_done",
            "session_id": self.session_id,
            "summary": decision.get("summary", "Done."),
            "speak": decision.get("speak", "Done."),
            "title": decision.get("title", "Complete"),
            "url": decision.get("url")
        })

    def _build_initial_message(self, voice_text: str, image_b64: Optional[str], memory: dict) -> list:
        """Build the initial multimodal user message."""
        content = []

        if image_b64:
            content.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}
            })

        context_block = ""
        if memory:
            context_block = f"\n\nUser memory (preferences learned from past sessions):\n{json.dumps(memory, indent=2)}"

        content.append({
            "type": "text",
            "text": f"User command: {voice_text}{context_block}"
        })

        return content
```

---

## Part 3 — Agent System Prompt

Create `backend/agent_prompt.py`. This is the single most important file for agent
quality. Do not truncate or simplify it.

```python
AGENT_SYSTEM_PROMPT = """
You are Lumis, a deep reasoning AI agent that controls a user's Mac computer and iPhone.

You think step by step, call one tool at a time, observe the real result, and then decide what to do next.
You never generate a full plan upfront. You act, observe, and adapt.

## Your output format

Every response must be a single JSON object. Never output prose. Always one of:

### 1. Call a tool
{
  "action": "tool_call",
  "tool": "<tool_name>",
  "args": { ... },
  "reasoning": "Why I am calling this tool right now, given what I know",
  "status_message": "Short message to show the user while this runs (e.g. 'Opening Numbers…')"
}

### 2. Look at the Mac screen
{
  "action": "capture_screen",
  "reasoning": "Why I need to see the screen right now"
}
Use this AFTER any Mac action to verify it actually worked. Use it when you are unsure what state the Mac is in.

### 3. Ask the user a clarifying question
{
  "action": "ask_user",
  "question": "The exact question to ask. Be specific. Only ask one question at a time."
}
Use this ONLY when you genuinely cannot proceed without more information.
Do NOT ask if you can reasonably infer the answer from context or memory.

### 4. Finish
{
  "action": "finish",
  "title": "Short title of what was accomplished",
  "summary": "One or two sentences describing what was done",
  "speak": "What to say aloud to the user. Conversational, not robotic.",
  "url": "<optional — a URL to show as a result button>"
}

## Rules

OBSERVE BEFORE ACTING AGAIN
After every tool call you will receive a tool_result. Read it carefully.
If status is "error", do not repeat the same call. Try a different approach, a
simpler tool, or ask the user.

VERIFY WITH SCREEN CAPTURE
After any action that changes something visible on the Mac (opening an app,
creating a file, filling a form), call capture_screen to confirm it worked.
Do not just assume success.

NEVER HALLUCINATE CONTENT
If you are given an image, read it word for word. Never invent data, prices,
names, dates, or any content. If you cannot read something clearly, leave it
blank and say so.

CHAINING
You can and should chain multiple tools to complete complex tasks.
Example: user says "make a note of this receipt and remind me to submit expenses Friday"
→ notes.create_from_image → reminders.add → finish
Read each result before calling the next tool.

MEMORY
You will receive the user's learned preferences (expense file path, preferred
calendar, most emailed contacts, etc.) in the initial message. Use these as
defaults. If a tool result tells you to learn something new (a file path, a
preference), note it — it will be stored automatically.

ERROR RECOVERY
If a tool fails:
1. Read the error message carefully
2. Try to understand why it failed
3. Try a different approach (different tool, simpler args, different app)
4. If you have tried twice and still cannot do it, explain clearly to the user
   what went wrong and what they could do manually

IRREVERSIBLE ACTIONS
These tools are marked irreversible: gmail.send_email, finder.move_file,
finder.rename_file, reminders.complete. Before calling an irreversible tool,
make sure you are confident the args are exactly right. If unsure, call ask_user first.

AMBIGUOUS REFERENCES
If the user says "this", "that", "it", "here", "these" and there is no image
attached, your first action must be:
{
  "action": "ask_user",
  "question": "I want to make sure I'm looking at the right thing — could you point your camera at it and tap capture?"
}

SHORT STATUS MESSAGES
The status_message field is shown live to the user while the tool runs.
Keep it short and human: "Opening Numbers…", "Reading the receipt…",
"Sending the draft…". Not "Executing tool gmail.draft_email with args {...}".

DO NOT OVER-EXPLAIN
Your reasoning field is for your own chain-of-thought — it is logged but not
shown to the user. Be thorough there. Keep user-facing messages brief.

## Available tools

NOTES
- notes.create_note        args: { title, body }
- notes.create_from_image  args: { title, text_from_image }
- notes.append_to_note     args: { note_name, text }
- notes.list_notes         args: {}

NUMBERS (SPREADSHEETS)
- numbers.create_spreadsheet  args: { title, headers: [], rows: [[]] }
- numbers.add_expense         args: { file_path, date, store, amount, category }
- numbers.read_sheet          args: { file_path, sheet_name? }
- numbers.edit_cell           args: { file_path, sheet_name, cell, value }

GMAIL
- gmail.draft_email    args: { to, subject, body }          ← opens draft in Chrome
- gmail.read_inbox     args: { max_results? }
- gmail.read_email     args: { email_id }
- gmail.open_reply     args: { email_id, body_prefill? }

BROWSER (CHROME)
- browser.open_url     args: { url }
- browser.read_page    args: {}                             ← reads currently open tab
- browser.fill_form    args: { fields: { selector: value } }

MEDIA
- media.play_pause     args: {}
- media.next_track     args: {}
- media.previous_track args: {}
- media.open_spotify   args: { search_query? }
- media.open_apple_music args: { search_query? }

CALENDAR
- calendar.create_event  args: { title, date, time, duration_minutes?, location?, notes? }
- calendar.read_today    args: {}
- calendar.read_week     args: {}
- calendar.find_free_time args: { date, duration_minutes }

REMINDERS
- reminders.add          args: { title, due_date?, due_time?, notes? }
- reminders.read         args: { list_name? }
- reminders.complete     args: { reminder_id }              ← IRREVERSIBLE

CONTACTS
- contacts.lookup        args: { name }
- contacts.get_email     args: { name }
- contacts.get_phone     args: { name }

SYSTEM
- system.set_volume       args: { level: 0-100 }
- system.set_brightness   args: { level: 0-100 }
- system.lock_screen      args: {}
- system.empty_trash      args: {}
- system.get_battery      args: {}
- system.open_focus       args: {}

FINDER
- finder.find_file        args: { name_contains?, extension? }
- finder.open_file        args: { path }
- finder.move_file        args: { path, destination }       ← IRREVERSIBLE
- finder.rename_file      args: { path, new_name }          ← IRREVERSIBLE
- finder.create_folder    args: { path, name }
- finder.reveal_in_finder args: { path }

CLIPBOARD
- clipboard.copy          args: { text }

SCREEN
- capture_screen          (special action — not a tool_call, use action: "capture_screen")

WEB
- web.search              args: { query }
- web.fetch_page          args: { url }
- web.research            args: { topic, save_as_note?: bool }

IPHONE NATIVE (opens on the user's phone)
- ios.create_reminder     args: { title, due_date? }
- ios.create_note         args: { title, body }
- ios.open_maps           args: { destination }
- ios.draft_message       args: { to, body }

## What you cannot do
- Make real Google Slides presentations (removed — requires per-user OAuth)
- Access files outside the user's home directory without finder.find_file first
- Send emails directly — gmail.draft_email opens a draft; the user sends it
- Control apps that are not in the tool list above

When asked to do something outside your capabilities, explain briefly what you
cannot do and suggest the closest alternative you can do.
"""
```

---

## Part 4 — Tool Registry

Update `backend/tools.py` to add a `TOOL_REGISTRY` dict that the agent uses to look
up each tool and know where it runs:

```python
# Add this dict to tools.py
# runs_on: "mac" = execute via Mac agent, "cloud" = run on Railway directly

TOOL_REGISTRY = {
    # Notes (Mac)
    "notes.create_note":        {"runs_on": "mac", "irreversible": False},
    "notes.create_from_image":  {"runs_on": "mac", "irreversible": False},
    "notes.append_to_note":     {"runs_on": "mac", "irreversible": False},
    "notes.list_notes":         {"runs_on": "mac", "irreversible": False},

    # Numbers (Mac)
    "numbers.create_spreadsheet": {"runs_on": "mac", "irreversible": False},
    "numbers.add_expense":        {"runs_on": "mac", "irreversible": False},
    "numbers.read_sheet":         {"runs_on": "mac", "irreversible": False},
    "numbers.edit_cell":          {"runs_on": "mac", "irreversible": False},

    # Gmail (Mac — opens in Chrome)
    "gmail.draft_email":  {"runs_on": "mac", "irreversible": False},
    "gmail.read_inbox":   {"runs_on": "mac", "irreversible": False},
    "gmail.read_email":   {"runs_on": "mac", "irreversible": False},
    "gmail.open_reply":   {"runs_on": "mac", "irreversible": False},

    # Browser (Mac)
    "browser.open_url":  {"runs_on": "mac", "irreversible": False},
    "browser.read_page": {"runs_on": "mac", "irreversible": False},
    "browser.fill_form": {"runs_on": "mac", "irreversible": False},

    # Media (Mac)
    "media.play_pause":        {"runs_on": "mac", "irreversible": False},
    "media.next_track":        {"runs_on": "mac", "irreversible": False},
    "media.previous_track":    {"runs_on": "mac", "irreversible": False},
    "media.open_spotify":      {"runs_on": "mac", "irreversible": False},
    "media.open_apple_music":  {"runs_on": "mac", "irreversible": False},

    # Calendar (Mac)
    "calendar.create_event":   {"runs_on": "mac", "irreversible": False},
    "calendar.read_today":     {"runs_on": "mac", "irreversible": False},
    "calendar.read_week":      {"runs_on": "mac", "irreversible": False},
    "calendar.find_free_time": {"runs_on": "mac", "irreversible": False},

    # Reminders (Mac)
    "reminders.add":      {"runs_on": "mac", "irreversible": False},
    "reminders.read":     {"runs_on": "mac", "irreversible": False},
    "reminders.complete": {"runs_on": "mac", "irreversible": True},

    # Contacts (Mac)
    "contacts.lookup":    {"runs_on": "mac", "irreversible": False},
    "contacts.get_email": {"runs_on": "mac", "irreversible": False},
    "contacts.get_phone": {"runs_on": "mac", "irreversible": False},

    # System (Mac)
    "system.set_volume":    {"runs_on": "mac", "irreversible": False},
    "system.set_brightness":{"runs_on": "mac", "irreversible": False},
    "system.lock_screen":   {"runs_on": "mac", "irreversible": False},
    "system.empty_trash":   {"runs_on": "mac", "irreversible": False},
    "system.get_battery":   {"runs_on": "mac", "irreversible": False},
    "system.open_focus":    {"runs_on": "mac", "irreversible": False},

    # Finder (Mac)
    "finder.find_file":       {"runs_on": "mac", "irreversible": False},
    "finder.open_file":       {"runs_on": "mac", "irreversible": False},
    "finder.move_file":       {"runs_on": "mac", "irreversible": True},
    "finder.rename_file":     {"runs_on": "mac", "irreversible": True},
    "finder.create_folder":   {"runs_on": "mac", "irreversible": False},
    "finder.reveal_in_finder":{"runs_on": "mac", "irreversible": False},

    # Clipboard (Mac)
    "clipboard.copy": {"runs_on": "mac", "irreversible": False},

    # Web (cloud — runs on Railway)
    "web.search":    {"runs_on": "cloud", "irreversible": False},
    "web.fetch_page":{"runs_on": "cloud", "irreversible": False},
    "web.research":  {"runs_on": "cloud", "irreversible": False},

    # iOS native (cloud — backend sends URL scheme to phone)
    "ios.create_reminder": {"runs_on": "cloud", "irreversible": False},
    "ios.create_note":     {"runs_on": "cloud", "irreversible": False},
    "ios.open_maps":       {"runs_on": "cloud", "irreversible": False},
    "ios.draft_message":   {"runs_on": "cloud", "irreversible": False},
}
```

Also add an `execute_tool(tool_name, args, user_id)` async function to `tools.py`
that routes cloud tools and returns a result dict:

```python
async def execute_tool(tool_name: str, args: dict, user_id: str) -> dict:
    """Execute a cloud-side tool and return a result dict."""
    try:
        fn = CLOUD_TOOL_FUNCTIONS.get(tool_name)
        if fn is None:
            return {"status": "error", "message": f"No cloud implementation for {tool_name}"}
        return await fn(args, user_id)
    except Exception as e:
        return {"status": "error", "message": str(e)}
```

---

## Part 5 — Screen Capture Bridge

Create `backend/vision.py`:

```python
"""
Captures the Mac screen via the Mac agent and returns it as base64 PNG.
The Mac agent already has a screenshot tool — this just calls it through
the existing mac_bridge and returns the image data.
"""

import asyncio
from mac_bridge import send_to_mac, wait_for_mac_result

async def capture_mac_screen(user_id: str) -> str | None:
    """
    Returns base64-encoded PNG of the current Mac screen,
    or None if the Mac agent is unavailable.
    """
    action_id = f"screen-{user_id}-{asyncio.get_event_loop().time()}"
    sent = await send_to_mac(user_id, {
        "event": "execute_on_mac",
        "action_id": action_id,
        "tool": "screen.capture",
        "args": {}
    })
    if not sent:
        return None

    result = await wait_for_mac_result(action_id, timeout=15)
    if result is None or result.get("status") != "success":
        return None

    return result.get("image_b64")
```

Add `screen.capture` to the Mac agent (`mac_agent.py`):

```python
# In mac_agent.py, add to the tool handler:
elif tool == "screen.capture":
    import subprocess, base64, tempfile, os
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        tmp_path = f.name
    subprocess.run(["screencapture", "-x", tmp_path], check=True)
    with open(tmp_path, "rb") as f:
        image_b64 = base64.b64encode(f.read()).decode()
    os.unlink(tmp_path)
    result = {"status": "success", "image_b64": image_b64}
```

---

## Part 6 — Mac Bridge

Create `backend/mac_bridge.py` to cleanly separate Mac agent communication from
agent logic. Extract the existing WebSocket send/wait logic from `engine.py` and
`websocket.py` into this module:

```python
"""
mac_bridge.py
Sends tool execution requests to the Mac agent over WebSocket
and waits for the result.
"""

import asyncio
from typing import Optional
from websocket import get_mac_socket_for_user, pending_mac_results

async def send_to_mac(user_id: str, payload: dict) -> bool:
    """
    Send a payload to the Mac agent connected for this user.
    Returns True if sent, False if no Mac agent is connected.
    """
    ws = get_mac_socket_for_user(user_id)
    if ws is None:
        return False
    try:
        await ws.send_json(payload)
        return True
    except Exception:
        return False

async def wait_for_mac_result(action_id: str, timeout: int = 30) -> Optional[dict]:
    """
    Wait for the Mac agent to reply with mac_result for action_id.
    Returns the result dict or None on timeout.
    """
    future = asyncio.get_event_loop().create_future()
    pending_mac_results[action_id] = future
    try:
        return await asyncio.wait_for(future, timeout=timeout)
    except asyncio.TimeoutError:
        return None
    finally:
        pending_mac_results.pop(action_id, None)
```

Update `backend/websocket.py` to:
- Export `get_mac_socket_for_user(user_id)` — returns the active Mac WebSocket for a user
- Export `pending_mac_results` dict — maps `action_id` → `asyncio.Future`
- When a `mac_result` message arrives, resolve the matching future from `pending_mac_results`

---

## Part 7 — Update `/ingest` route

Update `backend/routes.py` to use the new agent instead of the old `llm.py` +
`engine.py`:

```python
# backend/routes.py

from agent import LumisAgent
from websocket import broadcast_to_user

# Active agent sessions — keyed by session_id
# Stored in memory (Railway restarts clear them, which is fine)
active_agents: dict[str, LumisAgent] = {}

@app.post("/ingest")
async def ingest(request: IngestRequest, user=Depends(get_current_user)):
    """
    Main entry point. Receives image + voice from the iPhone.
    Starts or continues a ReAct agent session.
    """
    session_id = request.session_id

    async def broadcast(payload):
        await broadcast_to_user(user.id, payload)

    # New session
    agent = LumisAgent(
        user_id=user.id,
        session_id=session_id,
        websocket_broadcast=broadcast
    )
    active_agents[session_id] = agent

    # Run agent in background so /ingest returns immediately
    # Results stream to the phone over WebSocket
    asyncio.create_task(agent.run(
        voice_text=request.voice_text,
        image_b64=request.image
    ))

    return {"status": "accepted", "session_id": session_id}


@app.post("/agent/reply")
async def agent_reply(request: AgentReplyRequest, user=Depends(get_current_user)):
    """
    Called when the user answers a clarifying question from the agent.
    """
    agent = active_agents.get(request.session_id)
    if agent is None:
        raise HTTPException(404, "Session not found or expired")

    asyncio.create_task(agent.resume(request.reply))
    return {"status": "accepted"}
```

Add `POST /agent/reply` handling to the iOS app (`APIClient.swift` and
`WebSocketClient.swift`):
- When the phone receives `event: "agent_question"`, show the question text in the
  chat bar, activate the text input, and when the user submits their reply call
  `POST /agent/reply` with `{ session_id, reply }`.
- The Lumis shape should enter `.listening` state while waiting for user reply.

---

## Part 8 — Delete old files

Once the new agent is working end-to-end, delete or archive:

- `backend/llm.py` — replaced by `agent.py` + `agent_prompt.py`
- `backend/engine.py` — replaced by `agent.py`
- `backend/google_svc.py` — removed (Google Slides)
- `backend/authorize.py` — removed (Google Slides)

Keep:
- `backend/tools.py` — updated with TOOL_REGISTRY and execute_tool
- `backend/websocket.py` — updated with mac_bridge exports
- `backend/memory.py` — unchanged
- `backend/db.py` — unchanged
- `backend/routes.py` — updated
- `backend/mac_agent.py` — updated with screen.capture tool
- `backend/tasks.py` — unchanged

---

## Part 9 — iOS updates for agentic flow

### `WebSocketClient.swift` — handle new event types

Add handlers for:

```swift
case "agent_start":
    lumisVM.lumisState = .thinking
    lumisVM.transcript = ""

case "agent_step":
    // Show the status_message live below the Lumis shape
    lumisVM.responseText = event.message ?? ""
    lumisVM.currentTool = event.tool ?? ""

case "step_executed":
    // Same as before — show result card if success
    if let result = event.toActionResult() {
        lumisVM.lastResult = result
    }
    if let speakText = event.speak {
        TextToSpeech.speak(speakText)
    }

case "agent_question":
    // Agent needs user input — activate reply mode
    lumisVM.lumisState = .listening
    lumisVM.pendingQuestion = event.question
    lumisVM.responseText = event.question ?? ""
    TextToSpeech.speak(event.question ?? "")
    // Show the chat bar text input pre-focused

case "agent_done":
    lumisVM.lumisState = .idle
    lumisVM.responseText = ""
    if let result = event.toFinalResult() {
        lumisVM.lastResult = result
    }
    if let speakText = event.speak {
        TextToSpeech.speak(speakText)
    }

case "agent_error":
    lumisVM.lumisState = .idle
    lumisVM.responseText = ""
    showErrorToast(event.message ?? "Something went wrong.")
    if let speakText = event.speak {
        TextToSpeech.speak(speakText)
    }
```

### `LumisViewModel.swift` — add reply flow

```swift
@Published var pendingQuestion: String? = nil

func submitReply(_ reply: String) async {
    guard let sessionId = currentSessionId else { return }
    pendingQuestion = nil
    lumisState = .thinking
    await apiClient.post("/agent/reply", body: [
        "session_id": sessionId,
        "reply": reply
    ])
}
```

### Home screen — question reply UI

When `lumisVM.pendingQuestion != nil`:
- The chat bar text field activates automatically (`.focused`)
- Placeholder text shows the question
- Lumis shape is in `.listening` state
- On submit: call `lumisVM.submitReply(text)`, clear the field

---

## Part 10 — Environment variables

Update `backend/.env.example` — remove Google vars, ensure these are present:

```
# Required
GROQ_API_KEY=your_groq_key_here
GROQ_MODEL=meta-llama/llama-4-scout-17b-16e-instruct
LUMIS_JWT_SECRET=generate-a-long-random-string-here

# Optional — social login
LUMIS_APPLE_BUNDLE_ID=com.anay.lumis
LUMIS_GOOGLE_CLIENT_ID=your_google_client_id

# Optional — tuning
AGENT_MAX_STEPS=20
MAC_TOOL_TIMEOUT=30
```

In Railway dashboard, ensure `GROQ_API_KEY`, `GROQ_MODEL`, and `LUMIS_JWT_SECRET`
are set. No other external API keys required for core functionality.

---

## Part 11 — Verification checklist

Run these after implementation:

```bash
# Backend starts clean
cd backend && ./venv/bin/uvicorn main:app --reload --port 8000

# No Google API imports remain
grep -r "google" backend/ --include="*.py" | grep -v ".env" | grep -v "google_svc\|authorize"
# Expected: only google auth lines in auth.py (Sign in with Google)

# No llm.py or engine.py imports remain
grep -r "from llm\|import llm\|from engine\|import engine" backend/ --include="*.py"
# Expected: no output

# Health check
curl https://lumis-production-b878.up.railway.app/health
# Expected: {"status": "ok"}
```

Manual end-to-end tests:

- [ ] Simple one-step command: "set volume to 50" → agent calls system.set_volume → captures screen → finishes
- [ ] Two-step chain: "find my resume and open it" → finder.find_file → finder.open_file → captures screen → finishes
- [ ] Image command: point at receipt, "add to expenses" → numbers.add_expense with real values from image → finishes
- [ ] Ambiguous command: "add this to my notes" with no image → agent asks for camera → user sends image → agent completes
- [ ] Error recovery: disconnect Mac agent, run a Mac command → agent reports Mac offline, does not crash
- [ ] Clarifying question: "email Sarah" (no last name in contacts, multiple Sarahs) → agent asks which Sarah → user replies → agent calls gmail.draft_email
- [ ] Web research: "research the latest news on AI and save a note" → web.search → web.fetch_page → notes.create_note → finishes
- [ ] Screen verification: "open Spotify" → media.open_spotify → capture_screen → agent confirms Spotify opened → finishes
- [ ] Step limit: deliberately trigger a loop → agent stops at MAX_STEPS and explains
- [ ] `/agent/reply` endpoint responds correctly to a mid-session user reply
- [ ] All 4 iOS tabs still work after WebSocket event type additions
- [ ] No regression on auth, Mac linking, or history screen