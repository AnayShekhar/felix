# Lumis — Recent Activity Memory & Placeholder Fix

## The problem

Right now Lumis has durable, long-term preference memory (expense sheet
location, preferred browser, frequent contacts) but no short-term memory of
what it just did. Starting a new chat gives the agent a completely blank
slate, so a follow-up like "send that draft" or "send it to John" can't
reference anything real — it creates a brand new draft from scratch and
inserts a literal placeholder like "insert contact" instead of a real
recipient, because it has no idea who "it" refers to and no fallback besides
guessing.

This needs two separate fixes: a short-term memory of recent actions so
follow-up requests can reference real things Lumis just created, and a hard
rule that the agent must never fabricate or placeholder information it
doesn't actually have — it must look the information up or ask.

This should generalize across every tool, not just email — the same pattern
applies to documents, spreadsheets, calendar events, Notion pages, and
anything else Lumis creates that a user might reasonably refer back to
shortly after ("edit that spreadsheet," "add another row to it," "open the
doc I just made").

---

## Part 1 — Short-term recent activity memory

### Concept

Distinct from `memory.py`'s durable preferences, add a lightweight, recency-
based store of things Lumis has recently created or touched for a given user
— recent enough to still be "that thing" in conversation, but expiring after
a reasonable window (a few hours is a sensible default) so it doesn't grow
unbounded or resurface stale, irrelevant context weeks later.

Each entry should capture enough to be useful in a future request: what kind
of thing it is, a real identifier or URL, a short human-readable description,
and when it was created. For example, after drafting an email: the draft's
real ID/URL, the subject, and the intended recipient if one was specified (or
an explicit note that no recipient was given yet, so a later "send it to
John" can fill that gap on the existing draft rather than creating a new one).

### Where this lives

Add this alongside the existing memory system in the backend — a natural
approach is a small table or store keyed by user, holding a short list of
recent artifacts, each with a type, a reference (ID/URL), a description, and
a timestamp. Expire or cap the list so it only ever holds a small, recent
window — this is working memory, not a permanent record (permanent records of
what happened already exist in the action history / Past Chats).

### How the agent uses it

When building the initial context for a new request, include this recent
activity list alongside the durable preferences already being injected — so
the agent's very first reasoning step has visibility into "you drafted an
email to nobody in particular 10 minutes ago, subject X" without the user
needing to re-explain anything.

When a request references something ambiguously ("send that," "the draft I
just made," "add to it") the agent should check this recent activity list
first before assuming a brand new action is needed. If a match is found, the
agent should act on the existing real artifact (attach a recipient to the
existing draft, append to the existing document, etc.) rather than creating a
duplicate. If nothing plausible matches, proceed as a new request rather than
guessing at a stale or unrelated match.

Update this recent activity list every time a tool successfully creates or
meaningfully modifies something — this should be a natural side effect of a
successful tool result, not a separate manual step someone has to remember to
wire up per tool.

---

## Part 2 — Never fabricate or placeholder missing information

### The rule

If the agent needs a piece of information to complete an action — a
recipient's email address, a specific date, a file location — and it does not
actually have that information from the user's request, the recent activity
memory, or the durable preference memory, it must not invent a placeholder
value and proceed as if the action succeeded. This applies universally: email
recipients, contact details, dates, file paths, or any other required field.

### What it should do instead

First, attempt to resolve the missing information for real — for a contact,
this means actually looking them up (via whatever contact lookup capability
exists) rather than guessing at an address or writing filler text. If a real
lookup succeeds, use that real information and proceed.

If it cannot be resolved automatically — the contact isn't found, there are
multiple plausible matches, or the information simply isn't available
anywhere — the agent should ask the user directly, using the same
ask-a-clarifying-question capability it already has for other ambiguous
situations, rather than proceeding with a guess or a placeholder. A specific,
targeted question ("Which email address should I send this to?") is always
correct here; silently inserting filler text is never acceptable.

### Update the agent's guiding instructions accordingly

Add this as an explicit, non-negotiable rule alongside its existing
instructions: it should treat "I don't have this piece of information" as a
signal to look it up or ask, never as a reason to fabricate something
plausible-looking and report success anyway. A completed action that contains
made-up or placeholder content is a failure, not a success, even if the
underlying tool call didn't technically error.

---

## Part 3 — Apply this pattern generally, not just to email

Audit every tool capable of creating or modifying something a user might
reasonably reference again shortly after — documents, spreadsheets, calendar
events, Notion pages, reminders, and anything else in the current tool set —
and ensure each one:

- Records a recent activity entry on success, with enough detail to be useful
  in a follow-up request
- Is checked against recent activity when a new request contains an ambiguous
  reference, rather than always treating every request as entirely fresh
- Never proceeds with fabricated or placeholder values for required fields it
  doesn't actually have — always resolves for real or asks

---

## Verification

- Drafting an email, then in a separate, later request saying "send that to
  John" (with John being a real, resolvable contact) correctly updates the
  same draft with a real recipient rather than creating a second draft
- Drafting an email with no recipient specified, then asking to send it
  without giving a name, results in the agent asking who to send it to —
  never a placeholder like "insert contact" in the actual sent or drafted
  content
- The same recent-reference behavior works for at least one non-email case —
  for example, creating a document and then saying "add another paragraph to
  it" in a following request correctly edits the same real document
- Recent activity naturally stops being referenced after enough time or
  intervening unrelated requests have passed — it does not incorrectly
  resurface something from days earlier as if it were just created
- No tool in the current set ever reports success while having inserted
  fabricated or placeholder content for information it didn't actually have