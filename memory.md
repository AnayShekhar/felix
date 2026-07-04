# Lumis — Fix Recent Activity Memory Regressions

Testing surfaced three specific problems with the recent activity memory work.
Fix each of these precisely — don't do a broad rewrite, these are targeted bugs.

---

## Bug 1 — Email body still contains literal placeholder text

Recipient resolution now works correctly, but the generated email body itself
still contains literal unfilled template text — phrases like "insert recipient
name" and "best regards, your name" are appearing verbatim in the sent email.

This is the same underlying problem as the recipient placeholder issue, just
inside the content itself rather than a structured field. The agent is
generating a template with fill-in-the-blank markers rather than either
writing complete, real content upfront or filling in every blank with real
information before the email is finalized.

Fix: when generating email (or any) body content, the agent must write the
actual, complete content directly — the recipient's real name (if known, from
the resolved contact) in the greeting, the user's own real name or a neutral
sign-off if their name isn't confidently known, and no bracketed or
instructional placeholder text anywhere in what gets sent. If the agent
genuinely doesn't know something needed to complete the content properly (for
example, it doesn't know the user's name for a signature), it should either
omit that element gracefully (no sign-off name at all, rather than a
placeholder) or ask the user — the same rule as before, just applied to
generated prose as much as structured fields. Audit the prompt or generation
step responsible for email body content specifically, since this is a
different code path than the recipient-lookup fix and needs its own check for
lingering placeholder-style output.

---

## Bug 2 — "Add to it" creates a new item instead of editing the existing one

The recent-activity memory and ambiguous-reference matching that now works
for email was not wired up for other tools — asking to add a row to "it" or a
paragraph to "it" right after creating a spreadsheet or document creates a
brand new item instead of editing the one just created.

Fix: confirm the recent activity recording (Part 1 of the earlier memory doc)
and the ambiguous-reference matching (Part 1's "check recent activity before
assuming a new action" behavior) are actually implemented for every tool that
creates a persistent artifact — not just email. Trace through the actual
tool implementations for documents and spreadsheets specifically and confirm
each one records a recent activity entry on success, and confirm the agent's
reasoning step actually consults that list when a request like "add to it" or
"edit it" comes in for these tool types. If the original implementation only
touched the email path, generalize it properly now rather than patching this
one case in isolation — the same mechanism should serve every tool type.

---

## Bug 3 — Unrelated new requests are incorrectly linking to recent memory

This is the most important fix. A completely unrelated new request (for
example, asking to create a calendar event right after drafting an email)
is incorrectly being connected to that unrelated recent activity, when it
should be treated as entirely fresh.

Root cause to look for: recent activity is likely being surfaced to the agent
unconditionally on every request, and the agent is treating its mere presence
as a signal to connect it to the current request, rather than only using it
when the current request actually contains an ambiguous reference that needs
resolving (words like "it," "that," "the one I just made," or an action verb
that implies continuing something rather than starting something new, like
"add to" or "send" with no other context).

Fix: tighten the condition under which recent activity is actually used to
influence a decision. Recent activity should be available as context, but the
agent should only draw a connection to it when the current request is
genuinely ambiguous on its own and specifically seems to be referring back to
something rather than describing a new, independent action. A request that
is fully self-contained and unambiguous — like "create a calendar event for
Friday at 3pm" — has no missing information that needs resolving from recent
context, and should never be linked to unrelated prior activity just because
that activity happens to be recent. Make this distinction explicit in
whatever instructions or logic govern when recent activity gets consulted, so
it functions as a fallback for genuine ambiguity, not a default influence on
every request regardless of whether the request needed it.

---

## Verification — re-run all of these after fixing

- Draft an email with no recipient, then in a new chat say "send that to
  [real contact]" — the sent email contains no placeholder text anywhere in
  the body, and uses real names throughout or gracefully omits a sign-off
  name rather than inserting a placeholder
- Create a document or spreadsheet, then in a new chat say "add [something]
  to it" — the existing item is edited, not a new one created
- Right after creating something (email, doc, event — anything), issue a
  completely unrelated, fully self-contained new request — it is treated as
  entirely fresh with zero connection to the prior unrelated activity
- Repeat the "add to it" test for at least two different tool types (for
  example, both a document and a spreadsheet) to confirm the fix is general
  and not just patched for whichever one was tested first