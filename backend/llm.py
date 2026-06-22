"""Groq/Gemini workflow planner with a deterministic keyword fallback.

The LLM converts user intent (voice + image) into an ordered workflow:
{"steps": [{"tool": string, "args": {}}, ...]}. No prose, no abstract labels.
Steps run in order; an arg string may reference a prior step's output via
{{N.field}} (e.g. {{0.url}}) so results chain forward.
"""
import base64
import json
import logging
import os
import re

from dotenv import load_dotenv

import memory

load_dotenv()

logger = logging.getLogger("felix.llm")

# Prioritize Gemini if available (per README), otherwise use Groq.
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GROQ_API_KEY = os.getenv("GROQ_API_KEY")

# Vision-capable models.
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-1.5-flash")
GROQ_MODEL = os.getenv("GROQ_MODEL", "meta-llama/llama-4-scout-17b-16e-instruct")

VALID_TOOLS = (
    "notes.create_from_image",
    "spotify.play_song",
    "gmail.draft_email",
    "browser.open_url",
    "slides.create_presentation",
    "numbers.create_spreadsheet",
    "numbers.add_expense",
)

SYSTEM_INSTRUCTION = (
    "You are a macOS automation agent, like a hands-on coworker. You do not "
    "respond with text. You only output a JSON workflow of executable tool "
    "calls. You convert user intent (voice + an optional image) into real "
    "actions on the operating system. If an action cannot be executed, choose "
    "the closest valid tool.\n\n"
    'Output ONLY a single JSON object: {"steps": [{"tool": string, "args": {}}, ...]}\n'
    "Steps execute in order. To use a previous step's result in a later step, "
    'reference it as {{INDEX.FIELD}} inside a string arg, e.g. {{0.url}} is the '
    "URL produced by step 0. Most results expose: url, title.\n\n"
    "When an image is provided, READ IT CAREFULLY and EXTRACT its content "
    "VERBATIM to fill the document (slides bullets, sheet rows, note content). "
    "Transcribe text exactly as written — preserve every number, name, date, "
    "currency amount, email address, and unit precisely. Do NOT summarize, "
    "paraphrase, round, correct spelling, or omit anything. For receipts and "
    "tables, read every row and column and keep their order; align numbers to the "
    "right columns.\n"
    "ANTI-FABRICATION (critical for receipts): Use ONLY the merchant name, items, "
    "quantities, and prices that are ACTUALLY PRINTED in the image. NEVER guess a "
    "store from branding, NEVER substitute the e-commerce platform (e.g. do not "
    "write 'Shopify', 'Square', 'Stripe') for the real store name, and NEVER make "
    "up prices. Read each price digit-for-digit. If a field is unreadable, leave it "
    "blank ('') instead of inventing a value. Better to leave a cell empty than wrong.\n"
    "CRITICAL: Output only literal values you actually extracted. NEVER invent "
    "placeholder tokens such as {{date}}, {{merchant}}, or {{image.text}} — the "
    "ONLY allowed templating is {{N.field}} referencing a PRIOR step's url/title.\n"
    "CRITICAL: NEVER add a notes.create_from_image step just to extract text for "
    "another tool. Put the extracted image content DIRECTLY into the target "
    "tool's args — the email body, the slide bullets, the sheet rows, etc. Use "
    "notes.create_from_image ONLY when the user explicitly wants a NOTE.\n"
    "For 'draft an email from this', output exactly ONE step: gmail.draft_email "
    "with the extracted body. Keep the workflow minimal — usually one step.\n\n"
    "Available tools and their args:\n"
    "1. slides.create_presentation — Create a real Google Slides deck from the "
    'content. args: {"title": str, "slides": [{"title": str, "bullets": [str, ...]}, ...]}\n'
    "2. numbers.create_spreadsheet — Create a NEW Apple Numbers spreadsheet from "
    'the content. args: {"title": str, "headers": [str, ...], "rows": [[cell, ...], ...]}\n'
    "2b. numbers.add_expense — APPEND a receipt/expense to the user's ONE persistent "
    "Apple Numbers expense file (use this for 'add to my expense spreadsheet'). "
    "Extract date, merchant, category, amount, notes from the receipt image. "
    'args: {"rows": [[date, merchant, category, amount, notes], ...]}\n'
    "3. notes.create_from_image — Apple Notes note from extracted image text. "
    'args: {"title": str, "content": str}\n'
    "4. spotify.play_song — Open Spotify, search and play. "
    'args: {"query": str}\n'
    "5. gmail.draft_email — Open a Gmail compose window in Chrome (do NOT send). "
    'args: {"to": str, "subject": str, "body": str}\n'
    "6. browser.open_url — Open Chrome at a URL. "
    'args: {"url": str}\n\n'
    "Examples:\n"
    'User (whiteboard image): "turn this into notes" -> '
    '{"steps": [{"tool": "notes.create_from_image", "args": {"title": "...", "content": "<all text from the whiteboard>"}}]}\n'
    'User (receipt image): "add to my expense spreadsheet" -> '
    '{"steps": [{"tool": "numbers.add_expense", "args": {"rows": [["2026-06-13", "Whole Foods", "Groceries", "$42.10", "milk, eggs"]]}}]}\n'
    'User (handwritten note image): "draft an email from this" -> '
    '{"steps": [{"tool": "gmail.draft_email", "args": {"to": "", "subject": "<subject from note>", "body": "<email body from the handwriting>"}}]}\n'
    'User: "play bohemian rhapsody" -> {"steps": [{"tool": "spotify.play_song", "args": {"query": "bohemian rhapsody"}}]}\n'
    'User (image of notes): "turn this into a 3 slide presentation" -> '
    '{"steps": [{"tool": "slides.create_presentation", "args": {"title": "...", "slides": [{"title": "...", "bullets": ["...", "..."]}]}}]}\n'
    'User (image of notes): "make a deck from this and email the link to sam" -> '
    '{"steps": ['
    '{"tool": "slides.create_presentation", "args": {"title": "...", "slides": [{"title": "...", "bullets": ["..."]}]}}, '
    '{"tool": "gmail.draft_email", "args": {"to": "sam", "subject": "Deck", "body": "Here is the deck: {{0.url}}"}}'
    "]}\n"
    'User (image of a table): "make a spreadsheet from this" -> '
    '{"steps": [{"tool": "numbers.create_spreadsheet", "args": {"title": "...", "headers": ["..."], "rows": [["..."]]}}]}\n'
    "Note: Apple Numbers files are local and have NO url, so never reference "
    "{{N.url}} for a numbers step."
)


def _system_instruction() -> str:
    """Base instruction plus any learned user memory (Phase 3)."""
    block = memory.as_prompt_block()
    return SYSTEM_INSTRUCTION + block if block else SYSTEM_INSTRUCTION


def _mock_plan(voice_text: str, image: str) -> dict:
    """Keyword fallback so the agent still routes to real tools without the LLM.

    Cannot read the image, so document content is minimal in this mode.
    """
    logger.warning("Falling back to keyword routing (no LLM).")
    text = voice_text.strip()
    lower = text.lower()

    def one(tool, args):
        return {"steps": [{"tool": tool, "args": args}]}

    # Google Slides.
    if any(k in lower for k in ("slide", "presentation", "deck", "powerpoint", "pitch")):
        return one("slides.create_presentation", {
            "title": text or "Presentation",
            "slides": [{"title": text or "Presentation", "bullets": []}],
        })

    # Expense file (append) — must come before the generic spreadsheet branch.
    if any(k in lower for k in ("expense", "receipt")):
        return one("numbers.add_expense", {"rows": [[text]] if text else []})

    # Apple Numbers (new spreadsheet).
    if any(k in lower for k in ("spreadsheet", "sheet", "numbers", "excel", "table")):
        return one("numbers.create_spreadsheet", {
            "title": text or "Spreadsheet",
            "headers": [],
            "rows": [],
        })

    # Spotify.
    if any(k in lower for k in ("play ", "spotify", "song", "music", "track")):
        query = lower
        for verb in ("play the song", "play song", "play me", "play "):
            if verb in query:
                query = query.split(verb, 1)[1]
                break
        query = query.replace("on spotify", "").strip(" .'\"") or text
        return one("spotify.play_song", {"query": query})

    # Gmail.
    if any(k in lower for k in ("email", "gmail", "draft", "compose", "send a mail")):
        return one("gmail.draft_email", {"to": "", "subject": "", "body": text})

    # Apple Notes.
    if image or any(k in lower for k in ("note", "notes", "write down", "save this", "transcribe")):
        return one("notes.create_from_image", {
            "title": "Felix Note",
            "content": "" if image else text,
        })

    # Default — browser.
    url = text
    for verb in ("open website", "go to", "open the", "open ", "navigate to", "search for"):
        if verb in lower:
            url = lower.split(verb, 1)[1].strip()
            break
    return one("browser.open_url", {"url": url or "https://google.com"})


def _strip_fences(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1] if "\n" in text else text
        if text.endswith("```"):
            text = text[:-3]
        text = text.strip()
    return text


_REF = re.compile(r"\{\{\s*(\d+)\.(\w+)\s*\}\}")


def _drop_extraction_note(steps: list, voice_text: str) -> list:
    """Remove a spurious leading notes.create_from_image used only to extract
    text for a later step, folding its content into the steps that referenced it.

    The vision model sometimes inserts a notes step "to extract the image" before
    the real action (email/slides/sheets). Unless the user actually asked for a
    note, drop it and inline its extracted content where it was referenced.
    """
    lower = voice_text.lower()
    if any(k in lower for k in ("note", "notes", "write down", "save this", "jot", "transcribe")):
        return steps
    if len(steps) < 2 or steps[0].get("tool") != "notes.create_from_image":
        return steps
    if all(s.get("tool") == "notes.create_from_image" for s in steps):
        return steps  # genuinely a notes-only workflow

    nargs = steps[0].get("args", {}) or {}
    extracted = str(nargs.get("content") or nargs.get("title") or "")

    def fix(val):
        if isinstance(val, str):
            def repl(m):
                idx, field = int(m.group(1)), m.group(2)
                if idx == 0:
                    return extracted          # inline the dropped note's content
                return "{{%d.%s}}" % (idx - 1, field)  # shift later references
            return _REF.sub(repl, val)
        if isinstance(val, dict):
            return {k: fix(v) for k, v in val.items()}
        if isinstance(val, list):
            return [fix(v) for v in val]
        return val

    logger.info("Pruning spurious extraction notes step from plan.")
    return [{"tool": s["tool"], "args": fix(s.get("args", {}))} for s in steps[1:]]


_CONJUNCTIONS = (" and ", " then ", " also ", " after ", " plus ", "&", ", then")

# Ordered (specific -> general) keyword groups mapping intent to a tool.
_INTENT_KEYWORDS = [
    ("gmail.draft_email", ("email", "gmail", "draft", "compose", "send a mail")),
    ("numbers.add_expense", ("expense", "receipt")),
    ("numbers.create_spreadsheet", ("spreadsheet", "sheet", "numbers", "excel", "table")),
    ("slides.create_presentation", ("slide", "presentation", "deck", "powerpoint", "pitch")),
    ("spotify.play_song", ("play ", "spotify", "song", "music", "track")),
    ("notes.create_from_image", ("note", "notes", "write down", "save this", "jot", "transcribe")),
    ("browser.open_url", ("open website", "go to", ".com", ".org", ".io", "website", "url", "browser")),
]


def _intent_for(lower: str):
    for tool, keys in _INTENT_KEYWORDS:
        if any(k in lower for k in keys):
            return tool
    return None


def _args_for_intent(intent: str, steps: list, voice_text: str) -> dict:
    """Build args for the intended tool, reusing LLM-extracted content."""
    def reuse(tool):
        for s in steps:
            if s.get("tool") == tool and s.get("args"):
                return s["args"]
        return None

    def field(tool, key):
        for s in steps:
            if s.get("tool") == tool:
                v = s.get("args", {}).get(key)
                if v:
                    return v
        return None

    if intent == "gmail.draft_email":
        return reuse(intent) or {
            "to": "",
            "subject": "",
            "body": field("notes.create_from_image", "content") or "",
        }
    if intent == "notes.create_from_image":
        return reuse(intent) or {
            "title": "Felix Note",
            "content": field("gmail.draft_email", "body") or "",
        }
    # For the remaining tools, reuse the LLM args or fall back to keyword routing.
    return reuse(intent) or _mock_plan(voice_text, "")["steps"][0]["args"]


def _enforce_single_intent(steps: list, voice_text: str) -> list:
    """For single-intent commands, force the tool the keywords clearly indicate.

    The vision model is unreliable at routing when an image is present (it often
    defaults to notes). When the command has no conjunction, trust the keyword
    intent and reuse any content the model extracted.
    """
    lower = f" {voice_text.lower()} "
    if any(c in lower for c in _CONJUNCTIONS):
        return steps  # genuine multi-step — trust the LLM plan
    intent = _intent_for(lower)
    if intent is None:
        return steps[:1] if steps else steps
    if steps and steps[0].get("tool") == intent:
        return steps[:1]
    return [{"tool": intent, "args": _args_for_intent(intent, steps, voice_text)}]


def _coerce_plan(data: dict, voice_text: str, image: str) -> dict:
    """Validate LLM output into a list of known tool steps, or fall back."""
    # Accept {"steps":[...]}, a bare [...], or a single {"tool",...}.
    if isinstance(data, list):
        raw_steps = data
    elif isinstance(data, dict) and "steps" in data:
        raw_steps = data.get("steps") or []
    elif isinstance(data, dict) and "tool" in data:
        raw_steps = [data]
    else:
        raw_steps = []

    steps = []
    for s in raw_steps:
        if not isinstance(s, dict):
            continue
        tool = str(s.get("tool", "")).strip()
        args = s.get("args") or {}
        if not isinstance(args, dict):
            args = {}
        if tool in VALID_TOOLS:
            steps.append({"tool": tool, "args": args})
        else:
            logger.warning("Skipping unknown tool '%s' from LLM plan.", tool)

    if not steps:
        logger.warning("LLM produced no valid steps; using fallback.")
        return _mock_plan(voice_text, image)
    steps = _drop_extraction_note(steps, voice_text)
    steps = _enforce_single_intent(steps, voice_text)
    return {"steps": steps}


def _call_gemini(voice_text: str, image: str) -> dict:
    import google.generativeai as genai

    genai.configure(api_key=GEMINI_API_KEY)
    model = genai.GenerativeModel(
        model_name=GEMINI_MODEL,
        system_instruction=_system_instruction(),
    )

    contents = [f"User voice command: {voice_text}"]
    if image:
        try:
            img_data = base64.b64decode(image.split(",", 1)[1] if "," in image else image)
            contents.append({"mime_type": "image/jpeg", "data": img_data})
        except Exception as e:
            logger.warning("Failed to decode base64 image for Gemini (%s)", e)

    response = model.generate_content(
        contents,
        generation_config=genai.GenerationConfig(
            response_mime_type="application/json",
            temperature=0,
        ),
    )
    raw = _strip_fences(response.text or "")
    data = json.loads(raw)
    return _coerce_plan(data, voice_text, image)


def _call_groq(voice_text: str, image: str) -> dict:
    from groq import Groq

    client = Groq(api_key=GROQ_API_KEY)

    user_content = [
        {
            "type": "text",
            "text": (
                f"User voice command: {voice_text}\n\n"
                "Output ONLY the JSON workflow. No explanations, no markdown."
            ),
        }
    ]

    if image:
        data_url = image if image.startswith("data:") else f"data:image/jpeg;base64,{image}"
        try:
            base64.b64decode(image.split(",", 1)[1] if "," in image else image)
            user_content.append(
                {"type": "image_url", "image_url": {"url": data_url}}
            )
        except Exception as e:
            logger.warning("Failed to decode base64 image for Groq (%s)", e)

    response = client.chat.completions.create(
        model=GROQ_MODEL,
        messages=[
            {"role": "system", "content": _system_instruction()},
            {"role": "user", "content": user_content},
        ],
        temperature=0,
        response_format={"type": "json_object"},
    )

    raw = _strip_fences(response.choices[0].message.content or "")
    data = json.loads(raw)
    return _coerce_plan(data, voice_text, image)


def parse_plan(voice_text: str, image: str) -> dict:
    """Turn voice + image into an ordered workflow {"steps": [...]}.

    Prioritizes Gemini, then Groq, then keyword fallback.
    """
    if GEMINI_API_KEY:
        try:
            return _call_gemini(voice_text, image)
        except Exception as exc:
            logger.warning("Gemini call failed (%s); trying Groq.", exc)

    if GROQ_API_KEY:
        try:
            return _call_groq(voice_text, image)
        except Exception as exc:
            logger.warning("Groq call failed (%s); using keyword fallback.", exc)

    return _mock_plan(voice_text, image)
