"""Felix ReAct agent.

A deep reasoning loop on Groq (multimodal): THINK -> ACT -> OBSERVE -> ...
One tool call per iteration, reading the real result before deciding the next
step. Replaces the old single-shot llm.py planner + engine.py runner.

Where tools run (routed by TOOL_REGISTRY "runs_on"):
  - google_api    → google_tools (Docs/Sheets/Gmail/Calendar/Tasks/People/Drive)
  - cloud_browser → browser_tools (Browserbase) + web.* research
  - ios_native    → tools.execute_ios_tool (phone URL schemes)
Tools requiring a connected account emit a `service_required` event when the
user hasn't linked it yet.

Event model — the agent emits BOTH:
  - New agent_* events (agent_start/agent_step/agent_question/agent_done/
    agent_error) for a richer future UI, and
  - Backward-compatible step_started / step_executed / workflow_complete events
    so the current iOS and Mac apps keep working unchanged.

Clarifying questions pause the loop; the session is resumed (with full context
intact) when the user answers — see resume().
"""
import asyncio
import json
import logging
import os
import re
import threading
import time
from datetime import datetime
from typing import Awaitable, Callable, Optional

from dotenv import load_dotenv

import browser_tools
import connections
import db
import google_oauth
import google_tools
import memory
import tools
from agent_prompt import AGENT_SYSTEM_PROMPT

load_dotenv()

logger = logging.getLogger("felix.agent")


def _debug_dump(payload: dict) -> str:
    """Pretty-print a payload for debug logs, truncating any base64 image blob so
    a screenshot doesn't flood the log with tens of KB of data."""
    def _shorten(v):
        if isinstance(v, str) and len(v) > 200:
            return f"<{len(v)} chars: {v[:60]}…>"
        if isinstance(v, dict):
            return {k: _shorten(x) for k, x in v.items()}
        if isinstance(v, list):
            return [_shorten(x) for x in v]
        return v
    try:
        return json.dumps(_shorten(payload), indent=2, default=str)
    except Exception:  # noqa: BLE001 - logging must never raise
        return repr(payload)


GROQ_API_KEY = os.getenv("GROQ_API_KEY")
# llama-4-scout was shut down on Groq (2026-07-17). Default to the multimodal
# replacement; override with GROQ_MODEL. Qwen needs reasoning_effort=none for
# reliable JSON-mode agent turns.
DEFAULT_GROQ_MODEL = "qwen/qwen3.6-27b"
GROQ_MODEL = os.getenv("GROQ_MODEL", DEFAULT_GROQ_MODEL)

MAX_STEPS = int(os.getenv("AGENT_MAX_STEPS", "20"))      # hard cap on tool calls
# Fail fast if Groq is slow so the user gets feedback quickly rather than a long
# hang (Part 2). Overridable for vision-heavy steps via AGENT_THINK_TIMEOUT.
THINK_TIMEOUT_S = int(os.getenv("AGENT_THINK_TIMEOUT", "20"))


def _is_model_missing_error(exc: BaseException) -> bool:
    text = str(exc).lower()
    return "model_not_found" in text or "does not exist" in text or "do not have access" in text


def _groq_chat(client, *, model: str, messages: list, **kwargs):
    """Call Groq chat completions with model-specific kwargs.

    Qwen 3.6 defaults to reasoning tokens that break JSON mode unless
    reasoning_effort is set to \"none\".
    """
    create_kwargs = dict(kwargs)
    if model.startswith("qwen/"):
        create_kwargs.setdefault("reasoning_effort", "none")
    return client.chat.completions.create(
        model=model,
        messages=messages,
        **create_kwargs,
    )


# Tool args holding a datetime that must be ISO-8601 before execution.
_DATETIME_ARGS = {
    "calendar.create_event": ("start_datetime",),
    "reminders.add_item": ("due_date",),
}

Broadcast = Callable[[dict], Awaitable[None]]
SetLatest = Callable[[dict], None]


# --------------------------------------------------------------------------- #
# Conversation history (ported from the old llm.py)
#
# A fresh agent is created per /ingest, so cross-command follow-ups
# ("do that again", "change the time to 3pm") rely on this short per-session
# transcript, injected into the agent's first message.
# --------------------------------------------------------------------------- #
_session_history: dict = {}
_history_lock = threading.Lock()
_HISTORY_MAX_TURNS = 10
_HISTORY_INJECT_TURNS = 5
_HISTORY_TTL_S = 2 * 60 * 60


def _prune_expired_sessions() -> None:
    now = time.time()
    stale = [
        sid for sid, s in _session_history.items()
        if now - s.get("last_activity", 0) > _HISTORY_TTL_S
    ]
    for sid in stale:
        del _session_history[sid]


def _append_turn(session_id: str, role: str, content: str) -> None:
    content = str(content or "").strip()
    if not session_id or not content:
        return
    with _history_lock:
        _prune_expired_sessions()
        sess = _session_history.setdefault(
            session_id, {"turns": [], "last_activity": time.time()}
        )
        sess["turns"].append({"role": role, "content": content})
        sess["turns"] = sess["turns"][-_HISTORY_MAX_TURNS:]
        sess["last_activity"] = time.time()


def _conversation_block(session_id: str) -> str:
    if not session_id:
        return ""
    with _history_lock:
        _prune_expired_sessions()
        sess = _session_history.get(session_id)
        turns = list(sess["turns"]) if sess else []
    if not turns:
        return ""
    recent = turns[-_HISTORY_INJECT_TURNS:]
    lines = [
        f"{'User' if t.get('role') == 'user' else 'Felix'}: {t.get('content', '')}"
        for t in recent
    ]
    return "RECENT CONVERSATION:\n" + "\n".join(lines) + "\n\n"


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

def _date_block() -> str:
    now = datetime.now()
    today = now.strftime("%A, %B %d, %Y")
    return (
        f"Today is {today} and the current time is {now.strftime('%I:%M %p')}. "
        "Resolve every relative date/time against this clock. Never use a date "
        "from your training data.\n"
    )


# The model does not always follow the exact action schema — it very often
# puts the tool name directly in "action" (e.g. {"action": "gmail.read_inbox"})
# instead of {"action": "tool_call", "tool": "gmail.read_inbox"}, or omits
# "action" entirely and just gives a "tool". If we don't tolerate these, the loop
# treats every turn as "unexpected" and finishes having run nothing. Normalizing
# the decision is what makes the agent actually do work.
_FINISH_ALIASES = {"finish", "done", "complete", "completed", "stop", "end", "final"}
_ASK_ALIASES = {"ask_user", "ask", "question", "clarify", "ask_question", "need_input"}
_SCREEN_ALIASES = {"capture_screen", "screenshot", "screen", "look_at_screen",
                   "view_screen", "see_screen"}
_TOOLCALL_ALIASES = {"tool_call", "tool", "use_tool", "call_tool", "run_tool",
                     "call", "execute", "act"}


def _normalize_decision(d: dict) -> dict:
    """Coerce the model's loosely-formatted JSON into one of our four actions."""
    if not isinstance(d, dict):
        return {"action": "finish", "summary": "Done.", "speak": "Done."}

    action = str(d.get("action") or "").strip()
    low = action.lower()

    # Pull args out of whatever key the model used.
    if "args" not in d:
        for alt in ("arguments", "parameters", "params", "input"):
            if isinstance(d.get(alt), dict):
                d["args"] = d[alt]
                break
    # Tool name may live under several keys.
    tool_name = d.get("tool") or d.get("tool_name") or d.get("name")

    if low in _FINISH_ALIASES:
        d["action"] = "finish"
        return d
    if low in _ASK_ALIASES:
        d["action"] = "ask_user"
        return d
    if low in _SCREEN_ALIASES:
        # Full-Mac screen capture is gone; the only visual check is a browser shot.
        d["action"] = "tool_call"
        d["tool"] = "browser.screenshot"
        return d
    if low in _TOOLCALL_ALIASES:
        d["action"] = "tool_call"
        if not d.get("tool"):
            d["tool"] = tool_name
        return d
    # The model put the tool name directly in "action".
    if action in tools.TOOL_REGISTRY or ("." in action and " " not in action):
        d["action"] = "tool_call"
        d["tool"] = action
        return d
    # No usable action, but a tool was named anyway.
    if tool_name:
        d["action"] = "tool_call"
        d["tool"] = tool_name
        return d
    # Looks like a final answer (has a summary/answer/message) — finish on it.
    if d.get("summary") or d.get("answer") or d.get("speak") or d.get("message"):
        d["action"] = "finish"
        d.setdefault("summary", d.get("answer") or d.get("message") or "Done.")
        return d
    return {"action": "finish", "summary": "Done.", "speak": "Done."}


def _strip_fences(text: str) -> str:
    text = (text or "").strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1] if "\n" in text else text
        if text.endswith("```"):
            text = text[:-3]
        text = text.strip()
    return text


def _normalize_datetimes(tool: str, args: dict) -> dict:
    """Convert natural-language datetime args to ISO-8601 before execution.

    The model is told the current date and usually emits ISO directly, but if it
    passes "tomorrow at 3pm" we parse it (preferring future dates) so the
    calendar/reminder tools get a clean string. Already-ISO/unparseable values
    are left untouched.
    """
    keys = _DATETIME_ARGS.get(tool)
    if not keys or not isinstance(args, dict):
        return args
    try:
        import dateparser
    except ImportError:
        return args
    settings = {"PREFER_DATES_FROM": "future", "RETURN_AS_TIMEZONE_AWARE": False}
    for key in keys:
        raw = args.get(key)
        if not isinstance(raw, str) or not raw.strip():
            continue
        try:
            datetime.fromisoformat(raw.replace("Z", "+00:00"))
            continue  # already ISO
        except ValueError:
            pass
        parsed = None
        for cand in (raw, raw.replace("next ", ""), raw.replace(" at ", " ")):
            parsed = dateparser.parse(cand, settings=settings)
            if parsed:
                break
        if parsed:
            args[key] = parsed.isoformat()
            logger.info("Normalized %s %r -> %s", key, raw, args[key])
    return args


# --------------------------------------------------------------------------- #
# The agent
# --------------------------------------------------------------------------- #

class FelixAgent:
    def __init__(
        self,
        user_id: str,
        session_id: str,
        broadcast: Broadcast,
        set_latest: Optional[SetLatest] = None,
    ) -> None:
        self.user_id = user_id
        self.session_id = session_id
        self.broadcast = broadcast
        self.set_latest = set_latest or (lambda _e: None)
        self.steps_taken = 0
        self.context: list = []          # full message history for this run
        self.results: list = []          # tool results, for workflow_complete
        self.pending_question: Optional[str] = None
        self.created_at = time.time()
        self.last_active = time.time()
        self._loop = asyncio.get_event_loop()

    # ----- public entry points ----------------------------------------------

    async def run(self, voice_text: str, image_b64: Optional[str] = None) -> None:
        """Start a fresh ReAct run for a new command."""
        memory.set_user(self.user_id)

        # When a photo is attached the task is grounded in THAT image — do not
        # inject prior conversation, or the model conflates this with an earlier
        # task (e.g. turning previous research into the spreadsheet instead of
        # reading the new photo). Conversation context is only for image-less
        # follow-ups like "do that again" / "change the time".
        block = "" if image_b64 else _conversation_block(self.session_id)
        _append_turn(self.session_id, "user", voice_text)

        self.context.append({
            "role": "user",
            "content": self._build_initial_message(voice_text, image_b64, block),
        })

        await self._emit({
            "event": "agent_start",
            "session_id": self.session_id,
            "message": "Felix is thinking…",
        })
        # Compat: spin up the existing UI's working indicator.
        await self._emit({"event": "step_started",
                          "session_id": self.session_id, "data": {}})

        await self._loop_until_done()

    async def resume(self, user_reply: str, image_b64: Optional[str] = None) -> None:
        """Continue a paused run after the user answers a clarifying question."""
        memory.set_user(self.user_id)
        _append_turn(self.session_id, "user", user_reply)
        self.pending_question = None

        content: list = [{"type": "text", "text": f"User's answer: {user_reply}"}]
        if image_b64:
            content.append({
                "type": "image_url",
                "image_url": {"url": _data_url(image_b64)},
            })
        self.context.append({"role": "user", "content": content})

        await self._emit({"event": "step_started",
                          "session_id": self.session_id, "data": {}})
        await self._loop_until_done()

    # ----- the loop ----------------------------------------------------------

    async def _loop_until_done(self) -> None:
        while self.steps_taken < MAX_STEPS:
            self.last_active = time.time()
            decision = await self._think()
            action = decision.get("action")

            if action == "ask_user":
                await self._handle_ask_user(decision)
                return                      # pause — resumed by resume()
            if action == "finish":
                await self._handle_finish(decision)
                return
            if action == "tool_call":
                await self._handle_tool_call(decision)
                continue

            # Unexpected shape — treat as done so we never spin.
            await self._handle_finish(
                {"summary": "Task complete.", "speak": "Done.", "title": "Done"}
            )
            return

        await self._handle_step_limit()

    # ----- THINK -------------------------------------------------------------

    async def _think(self) -> dict:
        if not GROQ_API_KEY:
            return {"action": "finish",
                    "summary": "AI is not configured (no GROQ_API_KEY).",
                    "speak": "My AI isn't configured right now.",
                    "title": "Not configured"}
        try:
            raw = await self._loop.run_in_executor(None, self._groq_call)
            return _normalize_decision(json.loads(_strip_fences(raw)))
        except Exception as exc:  # noqa: BLE001 - never crash the loop
            logger.warning("THINK failed: %s", exc)
            return {"action": "finish",
                    "summary": f"I hit an error while thinking: {exc}",
                    "speak": "Something went wrong while I was thinking.",
                    "title": "Error"}

    def _groq_call(self) -> str:
        from groq import Groq

        client = Groq(api_key=GROQ_API_KEY)
        messages = [
            {"role": "system", "content": _date_block() + AGENT_SYSTEM_PROMPT},
            *self.context,
        ]
        model = GROQ_MODEL
        try:
            response = _groq_chat(
                client,
                model=model,
                messages=messages,
                temperature=0,
                response_format={"type": "json_object"},
                timeout=THINK_TIMEOUT_S,
            )
        except Exception as exc:  # noqa: BLE001 - migrate off shut-down model IDs
            if not _is_model_missing_error(exc) or model == DEFAULT_GROQ_MODEL:
                raise
            logger.warning(
                "GROQ_MODEL %s unavailable (%s); falling back to %s",
                model, exc, DEFAULT_GROQ_MODEL,
            )
            response = _groq_chat(
                client,
                model=DEFAULT_GROQ_MODEL,
                messages=messages,
                temperature=0,
                response_format={"type": "json_object"},
                timeout=THINK_TIMEOUT_S,
            )
        return response.choices[0].message.content or "{}"

    def _drop_stale_images(self) -> None:
        """Strip image data out of older context turns, keeping only the most
        recent screenshot as an actual image.

        Every THINK call re-sends the full context, so leaving past screenshots
        in as image_url payloads means each step re-uploads every screenshot ever
        taken — Groq vision payloads are large, so multi-step tasks get slower and
        slower. The model only needs to SEE the latest screen; earlier ones are
        replaced with a one-line text note so the reasoning trail stays intact.
        """
        for msg in self.context:
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            if not any(part.get("type") == "image_url" for part in content):
                continue
            note = next(
                (part.get("text") for part in content if part.get("type") == "text"),
                "a screenshot",
            )
            msg["content"] = f"[earlier screenshot omitted to save time: {note}]"

    # ----- ACT: tool call ----------------------------------------------------

    async def _handle_tool_call(self, decision: dict) -> None:
        tool = str(decision.get("tool") or "").strip()
        args = decision.get("args")
        if not isinstance(args, dict):
            args = {}
        reasoning = decision.get("reasoning", "")
        status_message = decision.get("status_message") or f"Running {tool}…"

        self.steps_taken += 1
        args = _normalize_datetimes(tool, args)

        # History row first, so even a crash leaves a trail. Its id doubles as
        # the unique action_id for the Mac round-trip.
        action_id = db.record_action(self.session_id, tool, args, user_id=self.user_id)

        await self._emit({
            "event": "agent_step",
            "session_id": self.session_id,
            "step": self.steps_taken,
            "tool": tool,
            "reasoning": reasoning,
            "message": status_message,
        })

        meta = tools.TOOL_REGISTRY.get(tool)
        if meta is None:
            result = {
                "tool": tool, "status": "error",
                "message": f"Unknown tool: {tool}", "title": tool,
                "data": {"error": "unknown_tool"},
            }
        elif not await self._service_ready(meta):
            # The tool needs a connected account that this user hasn't linked.
            service = meta.get("requires_service")
            if service == "google":
                # Cookie sync is NOT enough for Google REST tools — point the
                # user at the OAuth consent flow in Settings specifically.
                msg = ("Google isn't connected for API access yet. Open Felix "
                       "Settings and tap Connect next to Google to grant access.")
                speak = "Connect Google in Felix Settings first."
            else:
                msg = f"{service.capitalize()} isn't connected yet."
                speak = f"You'll need to connect {service} first."
            result = {
                "tool": tool, "status": "error", "title": "Connect an account",
                "message": msg, "speak": speak,
                "data": {"error": "service_required", "service": service},
            }
            await self._emit({
                "event": "service_required", "session_id": self.session_id,
                "service": service, "message": msg, "speak": speak,
            })
        elif meta["runs_on"] == "google_api":
            result = await self._loop.run_in_executor(
                None, google_tools.execute_google_tool, tool, args, self.user_id)
        elif meta["runs_on"] == "cloud_browser":
            result = await browser_tools.execute_browser_tool(tool, args, self.user_id)
            # DEBUG: full browser tool result (image_b64 truncated so logs stay readable).
            logger.info("DEBUG execute_browser_tool(%s) result: %s",
                        tool, _debug_dump(result))
        elif meta["runs_on"] == "ios_native":
            result = await self._loop.run_in_executor(
                None, tools.execute_ios_tool, tool, args, self.user_id)
        else:
            result = {
                "tool": tool, "status": "error",
                "message": f"No execution path for {tool}", "data": {},
            }

        # Persist result + undo info, and learn durable prefs from successes.
        undo_available, undo_script = tools.build_undo(tool, args, result)
        db.complete_action(action_id, result, undo_available, undo_script)
        try:
            memory.learn_from_action(tool, args, result)
        except Exception:  # noqa: BLE001 - learning is best-effort
            logger.warning("learn_from_action failed for %s", tool, exc_info=True)
        try:
            # Short-term working memory: remember what was just created/touched
            # so follow-ups ("send that draft") can act on the real artifact.
            import recent_activity
            recent_activity.record_from_result(self.user_id, tool, args, result)
        except Exception:  # noqa: BLE001 - recording is best-effort
            logger.warning("recent_activity record failed for %s", tool, exc_info=True)

        self.results.append(result)
        self._observe(tool, args, reasoning, result)

        # A tool that returns an image (e.g. browser.screenshot) is treated like
        # capture_screen: feed the image into context as a vision message so the
        # next THINK step can SEE the result and verify the action worked.
        image_b64 = result.pop("image_b64", None)
        if image_b64:
            self._drop_stale_images()  # keep only this newest screenshot as an image
            self.context.append({
                "role": "user",
                "content": [
                    {"type": "text",
                     "text": f"Screenshot returned by {tool}. Use it to verify "
                             "what happened and decide what to do next."},
                    {"type": "image_url",
                     "image_url": {"url": f"data:image/png;base64,{image_b64}"}},
                ],
            })

        # Compat event for the current iOS/Mac UI (drives result cards + TTS).
        # `image_b64` was popped above so we never push base64 over the socket.
        await self._emit_step_executed(tool, args, action_id, undo_available, result)

    def _observe(self, tool: str, args: dict, reasoning: str, result: dict) -> None:
        """Append the call + its real result to the model's context."""
        self.context.append({
            "role": "assistant",
            "content": json.dumps({
                "action": "tool_call", "tool": tool, "args": args,
                "reasoning": reasoning,
            }),
        })
        # Trim noisy/huge fields (e.g. base64) before feeding back to the model.
        observed = {k: v for k, v in result.items()
                    if k not in ("image_b64",) and k != "data"}
        data = result.get("data")
        if isinstance(data, dict):
            observed["data"] = {k: v for k, v in data.items() if k != "image_b64"}
        self.context.append({
            "role": "user",
            "content": json.dumps({"tool_result": {"tool": tool, "status": result.get("status"),
                                                    "result": observed}}),
        })

    # ----- service gating ----------------------------------------------------

    async def _service_ready(self, meta: dict) -> bool:
        """True if the connected account this tool needs is available for the user."""
        service = meta.get("requires_service")
        if not service:
            return True
        if service == "google":
            return await self._loop.run_in_executor(
                None, google_oauth.has_google, self.user_id)
        connected = await self._loop.run_in_executor(
            None, connections.get_connected_services, self.user_id)
        return service in connected

    # ----- terminal states ---------------------------------------------------

    async def _handle_ask_user(self, decision: dict) -> None:
        question = decision.get("question") or "I need a little more information to continue."
        self.pending_question = question
        self.context.append({
            "role": "assistant",
            "content": json.dumps({"action": "ask_user", "question": question}),
        })

        await self._emit({
            "event": "agent_question",
            "session_id": self.session_id,
            "question": question,
            "speak": question,
        })
        # Compat: show the question as a result card + speak it, then stop the
        # spinner. The user answers by capturing again; routes resumes us.
        q_result = {"tool": "felix.ask", "status": "success", "title": "One quick question",
                    "message": question, "speak": question}
        await self._emit_step_executed("felix.ask", {}, None, False, q_result)
        await self._complete([q_result])

    async def _handle_finish(self, decision: dict) -> None:
        summary = decision.get("summary") or "Done."
        speak = decision.get("speak") or summary
        title = decision.get("title") or "Complete"
        url = decision.get("url")
        _append_turn(self.session_id, "felix", summary)

        agent_done_payload = {
            "event": "agent_done",
            "session_id": self.session_id,
            "title": title, "summary": summary, "speak": speak, "url": url,
        }
        # DEBUG: full agent_done payload right before it's broadcast.
        logger.info("DEBUG agent_done payload: %s", _debug_dump(agent_done_payload))
        await self._emit(agent_done_payload)
        final = {"tool": "felix.finish", "status": "success", "title": title,
                 "message": summary, "summary": summary, "speak": speak}
        if url:
            final["url"] = url
        await self._emit_step_executed("felix.finish", {}, None, False, final)
        await self._complete(self.results + [final])

    async def _handle_step_limit(self) -> None:
        msg = "I ran out of steps trying to finish that. Try breaking it into smaller commands."
        await self._emit({
            "event": "agent_error",
            "session_id": self.session_id,
            "message": msg, "speak": msg,
        })
        err = {"tool": "felix.finish", "status": "error", "title": "Didn't finish",
               "message": msg, "speak": msg}
        await self._emit_step_executed("felix.finish", {}, None, False, err)
        await self._complete(self.results + [err])

    # ----- emit helpers ------------------------------------------------------

    async def _emit(self, event: dict) -> None:
        # Route events to this user's clients only (websocket.manager filters
        # on user_id, so one phone never hears another account's results).
        event.setdefault("user_id", self.user_id)
        await self.broadcast(event)

    async def _emit_step_executed(
        self, tool: str, args: dict, action_id, undo_available: bool, result: dict
    ) -> None:
        event = {
            "session_id": self.session_id,
            "user_id": self.user_id,
            "event": "step_executed",
            "data": {
                "index": self.steps_taken, "total": self.steps_taken,
                "tool": tool, "args": args, "action_id": action_id,
                "undo_available": undo_available, **result,
            },
        }
        self.set_latest(event)
        await self.broadcast(event)

    async def _complete(self, steps: list) -> None:
        event = {
            "session_id": self.session_id,
            "user_id": self.user_id,
            "event": "workflow_complete",
            "data": {"total": len(steps), "steps": steps},
        }
        self.set_latest(event)
        await self.broadcast(event)
        # The run is over — flush + close the live cloud-browser session so the
        # persisted context (logins picked up during the run) is saved. A paused
        # ask_user run also lands here; the resumed run just reopens a session.
        asyncio.create_task(browser_tools.release_session(self.user_id))

    # ----- initial message ---------------------------------------------------

    def _build_initial_message(
        self, voice_text: str, image_b64: Optional[str], conversation_block: str
    ) -> list:
        content: list = []
        if image_b64:
            content.append({
                "type": "image_url",
                "image_url": {"url": _data_url(image_b64)},
            })

        ctx = memory.get_context_block()
        memory_block = (
            "\n\nWHAT FELIX KNOWS ABOUT THIS USER (use as defaults; never override "
            f"what the user explicitly says):\n{ctx}" if ctx else ""
        )
        # Working memory of just-created artifacts, so "send that draft" /
        # "add to it" resolves to the real thing instead of a new duplicate.
        try:
            import recent_activity
            recent_block = recent_activity.context_block(self.user_id)
        except Exception:  # noqa: BLE001 - context is best-effort
            recent_block = ""
        content.append({
            "type": "text",
            "text": f"{conversation_block}User command: {voice_text}"
                    f"{memory_block}{recent_block}",
        })
        return content


def _data_url(image_b64: str) -> str:
    if image_b64.startswith("data:"):
        return image_b64
    return f"data:image/jpeg;base64,{image_b64}"
