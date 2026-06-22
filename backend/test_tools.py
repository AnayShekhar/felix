"""Felix Mac-agent tool test harness (Phase 1).

Why this exists: the Mac agent's value is latency + reliability. This script
runs each tool in tools.py *in isolation* with safe sample inputs, executes the
real action on this Mac, and reports per-tool {status, elapsed_ms}. It is the
quickest way to spot a tool that is slow (>2s), failing, or silently broken
after a change.

Usage:
    ./venv/bin/python test_tools.py                 # run every tool
    ./venv/bin/python test_tools.py notes spotify   # run only matching tools
    ./venv/bin/python test_tools.py --list          # list available tools
    ./venv/bin/python test_tools.py --skip slides spotify

Notes:
  - These perform REAL actions (open Notes, Numbers, Chrome, Spotify). Run on a
    Mac where you don't mind windows opening.
  - slides.create_presentation needs Google auth (google_svc); it is included
    but will report an error if credentials are missing — that's expected.
  - SLOW_THRESHOLD_MS flags any tool over the Phase 1 latency budget.
"""
import argparse
import sys
import time

import tools

SLOW_THRESHOLD_MS = 2000.0

# Representative, side-effect-light sample inputs for each tool.
SAMPLES: dict[str, dict] = {
    "notes.create_from_image": {
        "title": "Felix Test Note",
        "content": "This note was created by test_tools.py.",
    },
    "spotify.play_song": {"query": "Bohemian Rhapsody"},
    "gmail.draft_email": {
        "to": "test@example.com",
        "subject": "Felix test draft",
        "body": "This is a harness-generated draft. Not sent.",
    },
    "browser.open_url": {"url": "https://example.com"},
    "slides.create_presentation": {
        "title": "Felix Test Deck",
        "slides": [{"title": "Hello", "bullets": ["one", "two"]}],
    },
    "numbers.create_spreadsheet": {
        "title": "Felix Test Sheet",
        "headers": ["A", "B"],
        "rows": [["1", "2"], ["3", "4"]],
    },
    "numbers.add_expense": {
        "expenses": [
            {"date": "2026-06-21", "merchant": "Test Cafe",
             "category": "Food", "amount": "12.50", "notes": "harness"}
        ]
    },
}


def run_one(tool: str) -> dict:
    """Execute a single tool through the real router and time it end-to-end."""
    args = SAMPLES.get(tool, {})
    start = time.monotonic()
    result = tools.execute(tool, args)
    wall_ms = round((time.monotonic() - start) * 1000, 1)
    # Prefer the tool's own measurement; fall back to wall-clock.
    result.setdefault("elapsed_ms", wall_ms)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Felix tool test harness.")
    parser.add_argument("filters", nargs="*",
                        help="Substring filters; run only matching tools.")
    parser.add_argument("--list", action="store_true", help="List tools and exit.")
    parser.add_argument("--skip", nargs="*", default=[],
                        help="Substring filters of tools to skip.")
    args = parser.parse_args()

    all_tools = list(tools.TOOL_REGISTRY)
    if args.list:
        print("\n".join(all_tools))
        return 0

    selected = [
        t for t in all_tools
        if (not args.filters or any(f in t for f in args.filters))
        and not any(s in t for s in args.skip)
    ]
    if not selected:
        print("No tools matched.", file=sys.stderr)
        return 1

    print(f"Running {len(selected)} tool(s)...\n")
    rows = []
    failures = 0
    slow = 0
    for tool in selected:
        result = run_one(tool)
        status = result.get("status", "?")
        elapsed = result.get("elapsed_ms", 0.0)
        message = result.get("message", "")
        if status != "success":
            failures += 1
        if elapsed > SLOW_THRESHOLD_MS:
            slow += 1
        rows.append((tool, status, elapsed, message))

    # Report table.
    name_w = max(len(r[0]) for r in rows)
    print(f"{'TOOL':<{name_w}}  {'STATUS':<8}  {'ms':>8}  FLAG")
    print("-" * (name_w + 30))
    for tool, status, elapsed, message in rows:
        flag = ""
        if status != "success":
            flag = "FAIL"
        elif elapsed > SLOW_THRESHOLD_MS:
            flag = "SLOW"
        print(f"{tool:<{name_w}}  {status:<8}  {elapsed:>8.1f}  {flag}")

    print()
    for tool, status, elapsed, message in rows:
        if status != "success" or elapsed > SLOW_THRESHOLD_MS:
            print(f"  {tool}: {message}")

    print(f"\n{len(rows)} run, {failures} failed, {slow} slow "
          f"(>{SLOW_THRESHOLD_MS:.0f}ms).")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
