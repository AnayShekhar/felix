# Felix — UI Quality (Real Design System Rules) + Correctness + Deploy Readiness

This covers two categories: concrete UI rules translated from Anthropic's actual
production design system (not vague guidance this time — specific, numeric,
enforceable rules), and a set of correctness/deployment issues that must be
fixed before this can be tested by anyone besides you or actually deployed.

Investigate the current implementation before changing anything.

---

## Part 1 — UI Quality: Concrete, Enforceable Rules

These are real rules from a production AI product's design system, translated
to this app's SwiftUI context. Apply them literally, not as vague inspiration —
specificity is exactly what's been missing from previous passes.

### Borders and hairlines
Every border in the app should be a genuine hairline — visually equivalent to
0.5pt, not a thick 1-2pt stroke. Thick borders around every card is a strong
"assembled, not designed" signal. Use the thinnest stroke the platform will
render cleanly, and reserve thicker (2pt) borders for exactly one purpose: a
deliberate accent highlighting a single featured/recommended item, never as a
default treatment applied everywhere.

### One accent color rule
At most one strongly accented, filled element should be visible on any given
screen at once. Every other interactive element should be a quieter, outlined
or plain style. Right now things like the "Connected" checkmarks, action
buttons, and other tinted elements are likely all competing for attention
simultaneously — pick the single most important action per screen to carry the
strong accent treatment, and let everything else recede to plain text, thin
outline, or muted color.

### Restraint rule
When in doubt, choose the quieter visual option. If a previous pass added a
card, a border, a background tint, or a bold weight and it's not clearly
earning its place, remove it rather than adding more. The most common note on
any interface like this is "too cluttered" — default to removing weight, not
adding it.

### Elevation discipline
Establish a small number of clearly distinct surface levels — page background,
in-flow card, panel/sheet, popover — and use them consistently rather than
inventing new grey values per screen. At most two floating/elevated surfaces
should ever be visible at once (for example: a sheet with a popover on top of
it is fine; a popover on top of a sheet on top of another floating panel is
not) — if you find a need for a third floating layer, that's a sign it should
be a distinct full sheet, not another popover stacked on popovers.

### Muted text — never opacity
Secondary/muted text should use an actual distinct color value, not the
primary text color at reduced opacity. Opacity-based dimming multiplies
against whatever is behind it and drifts inconsistently across different
surface colors (a card vs. the background vs. a colored banner all end up
looking like different shades of "grey" rather than one consistent secondary
text color). Define one real "secondary" and one real "muted" color and use
those directly everywhere, never `.opacity()` for text dimming.

### Copy and microcopy rules
- Sentence case everywhere — buttons, headings, section labels. Never Title
  Case, never ALL CAPS (this includes the current uppercase section headers
  in Settings — switch these to sentence case)
- No exclamation points in system copy
- No "please" in instructions or errors
- Buttons are verb-first, one to three words, no trailing punctuation:
  "Connect account," not "Click here to connect your account!"
- Errors state what happened, then what to do, in one sentence, without a
  first-person voice ("Couldn't connect to Gmail. Try again." not "I was
  unable to connect.")
- Empty states are an invitation, not an apology: a short headline naming
  the space, one line explaining it, and a clear verb-first action — avoid
  "Nothing here yet"-style phrasing where a more specific, inviting
  alternative is possible
- Confirmations use past tense with no first person: "Draft saved," not "I
  saved your draft"

### Typography weight discipline
Use exactly two weights in the entire interface for the SF Pro side of the
type system: one regular weight for nearly everything, and one medium/semibold
weight reserved for the single most important heading or label per screen.
Avoid a heavier bold weight scattered across many elements — if several things
on one screen are all bold, none of them reads as more important than the
others, which is the core problem in the current Settings and sidebar screens.

### Section headers
Settings section headers ("CONNECTED SERVICES," "APPEARANCE," "VOICE," etc.)
should be small, quiet, and clearly secondary to the content beneath them —
sentence case, muted color, no heavy weight. They're organizational labels,
not their own competing headline.

---

## Part 2 — Fix the Logo Placeholder

An SVG asset already exists in the codebase (`image.svg`). Replace the empty
bordered placeholder box currently shown next to the "Felix" wordmark with
this real asset.

Note: SwiftUI does not natively render arbitrary SVG content well without
additional handling. Before wiring this in, confirm how the asset is meant to
be consumed — the cleanest options are converting it to a PDF vector asset in
the asset catalog (which SwiftUI renders natively and scales cleanly), or, if
the SVG needs to stay an SVG specifically, using a small SVG-rendering
dependency. Pick whichever approach fits the project's existing conventions
and actually renders correctly at small sizes in both light and dark mode,
rather than assuming a raw `Image("image.svg")` reference will work as-is.

---

## Part 3 — Connection Status Must Be Genuinely Accurate

The connection status between iOS and the Chrome extension currently reports
incorrect states in both directions — showing "not connected" when it is, and
"connected" when it isn't. This needs a real fix, not a cosmetic one.

Investigate the actual source of truth being used to determine this status.
Common causes of exactly this symptom: relying on a cached or stale flag
rather than checking live state, checking only whether cookies were ever
synced once rather than whether the sync is still recent/valid, or a race
condition where the iOS app checks status before the backend has finished
processing a just-completed sync.

The fix should query real, current state every time the status is displayed
or refreshed — not a value that was fetched once and never re-validated. If
there's a reasonable definition of "connected" (for example: synced within
the last some-number-of-hours, or a successful recent verification), make
sure that definition is applied consistently and is actually checked against
real timestamps at the moment of display, not assumed from a boolean that was
set once and potentially never updated correctly.

---

## Part 4 — Remove All Hardcoded Test-Specific Values

Before this can be tested by anyone else, or on another account, audit the
entire codebase — backend and iOS — for anything hardcoded to a specific test
user, test email, test account ID, or specific Browserbase context that would
break or behave incorrectly for a different account.

Specifically check:
- Any hardcoded email addresses, user IDs, or account identifiers used as
  fallbacks or defaults anywhere in the backend or app
- Any assumption that only one user/context exists (a global variable holding
  "the" Browserbase context instead of one correctly looked up per
  authenticated user)
- Any test or debug flag that bypasses real authentication or real service
  checks, left enabled
- Any UI string or logic that only makes sense for one specific account's
  data (e.g., assuming a particular contact list, a particular connected
  service, or a particular email address will exist)

Test concretely: create a second, completely separate account (different
email), sign into the iOS app with it, sign into the Chrome extension with
that same second account, and confirm the entire flow works correctly and
independently — no data, connection status, or behavior bleeds over from any
other account.

---

## Part 5 — Confirm Task Execution Does Not Depend on the Extension's Computer Being On

This is an important architectural point to verify explicitly, since it's easy
to get subtly wrong given how the system evolved. Once the Chrome extension
has synced a user's cookies into their persistent cloud browser context, task
execution happens entirely in the cloud (Browserbase) — the local computer
running the extension should not need to be on, awake, or connected for Felix
to actually complete tasks using those synced credentials afterward. The
extension's only job is the initial (and periodic re-) sync; it is not a
runtime dependency for executing tasks.

Verify this concretely: sync a service via the extension, then fully quit
Chrome and turn off or disconnect the computer running it, and confirm a
voice command from the iPhone that depends on that connected service still
completes successfully. If it does not — if any part of the current
implementation is still waiting on a live extension connection, a live
WebSocket from that computer, or anything resembling the old local Mac-agent
execution model — find and remove that dependency. Execution should be
entirely decoupled from whether the syncing computer is currently reachable.

If this reveals that connection status (Part 3) is being computed based on
whether the extension's computer is currently online, rather than whether a
valid synced session exists in the cloud, that's likely a contributing cause
of the status inaccuracy — the two problems may share a root cause.

---

## Part 6 — Deployment Readiness Pass

Confirm the app is genuinely ready to be deployed and used by someone who
isn't you, not just working in your local development/testing setup.

- No `localhost` URLs, local IP addresses, or development-only backend
  endpoints hardcoded anywhere — everything should point to the real
  deployed backend, configurable via environment/build configuration rather
  than hardcoded literals
- All required environment variables (API keys, secrets, service credentials)
  are documented and confirmed present in the actual deployment environment,
  not just a local `.env` file
- The backend fails clearly and safely if a required configuration value is
  missing, rather than crashing unpredictably or silently behaving
  incorrectly
- Basic health-check verification: a fresh deploy, hit from a clean install
  of the iOS app on a different device with a brand new account, should be
  able to sign up, connect a service via the extension, and complete a real
  task successfully end to end

---

## Part 7 — Future-Proof for Stripe and Rate Limiting (Do Not Implement Yet)

Do not add Stripe or rate limiting now. Do confirm the current architecture
won't need to be awkwardly reworked to add them later:

- The user model should have reasonable room to add a subscription/plan-tier
  field and related billing metadata without requiring a disruptive schema
  migration later — a nullable or default-valued field added now costs
  nothing and avoids that friction
- Request/action handling should go through a small number of clear,
  centralized entry points (the `/ingest` endpoint, the agent's tool-execution
  path) rather than being scattered across many independent code paths — this
  is what will make it straightforward to insert rate-limiting or usage-metering
  logic at a single choke point later, rather than needing to instrument every
  tool individually
- Confirm there's nothing structurally preventing a future middleware or
  decorator-style check from being added in front of the main request path
  without a significant rewrite

This is a review and light preparatory step only — flag anything that looks
like it would make adding billing or rate limiting later genuinely painful,
but do not build the features themselves yet.

---

## Part 8 — Navigation Redesign: Liquid Glass Controls & Sidebar Scope

Do not change the existing "+" button or its expansion into the chat bar —
that interaction is correct as-is and should be left untouched.

### Top bar controls

Replace the current sidebar toggle with a native **Liquid Glass** button
(Apple's real translucent glass material and control style, not a plain blurred
rectangle standing in for it) positioned top-left, sitting comfortably beneath
the logo/wordmark rather than crowding it. Use the platform's actual glass
effect/material API so it behaves like genuine system glass — refracting and
responding to what's behind it — rather than a manually approximated blur.

Add a second Liquid Glass button, same treatment, positioned top-right,
showing the signed-in user's profile (initials). Tapping it opens Settings
directly — this button is the sole entry point to Settings now.

### Sidebar scope

The sidebar, opened via the top-left button, contains **only** Past Chats.
Remove any profile summary or Settings entry that currently lives inside the
sidebar — Settings is reached exclusively through the new top-right profile
button, not through the sidebar at all. This is a real scope narrowing, not
just a visual change — the sidebar's job is now singular.

Add a Liquid Glass button at the bottom of the sidebar for starting a new
chat. This button should only be present/visible while the sidebar is open —
it's not a persistent element elsewhere.

### Reply within a past chat's context

Currently reopening a past chat shows its completed panel stack as a frozen
record. Add the ability to genuinely continue that conversation — when a
user replies (by voice or text) while viewing a reopened past chat, the new
request should be handled with that specific chat's context available (what
was asked, what was done, what was created), the same way a follow-up in an
active, not-yet-archived chat would work, rather than being treated as an
entirely fresh, disconnected request. The new exchange should append to that
same chat's stack as a continuation, not spawn a separate, unrelated stack.

### Design bar

Apply the same Apple design philosophy and concrete rules from Part 1
throughout this navigation work — genuine hairline treatment where any
non-glass borders remain, sentence case on the new chat button and any
labels, restrained use of the accent color, and glass materials that behave
like real system-provided glass rather than an approximation.

---

## Part 9 — Light Mode Background: Pure White

In light mode, the base background color should be pure white, not the
Alabaster tone previously used as the background. Update the color token
definitions accordingly: the background token in light mode becomes true
white, and Alabaster is repurposed as an elevated-surface tone instead (the
chat bar, cards, sheets) so that elevation contrast (Part 1) is still
achieved — white page background with a very slightly warmer/cooler elevated
surface on top of it, rather than losing that distinction entirely. Dark mode
is unaffected by this change. Re-verify contrast and elevation throughout the
app once this change is made, since several surfaces were likely designed
assuming Alabaster as the base rather than as an elevated tone.

---

## Verification

- The sidebar toggle and profile buttons are both genuine Liquid Glass
  controls, correctly positioned top-left (beneath the logo) and top-right
- Tapping the profile button opens Settings directly; Settings is not
  reachable from inside the sidebar
- The sidebar contains only Past Chats — no profile or settings content
  remains there
- A Liquid Glass "new chat" button appears at the bottom of the sidebar only
  while it's open
- Reopening a past chat and replying continues that same chat's stack with
  real access to its prior context, rather than starting an unrelated fresh
  request
- The "+" button and chat bar expansion behavior are unchanged from before
  this pass
- Light mode's base background is pure white; elevated surfaces (chat bar,
  cards) are visibly distinct from that white background using the
  repurposed Alabaster tone; dark mode is unaffected

- Every border in the app reads as a true hairline; only one deliberate 2pt
  accent border exists anywhere, and only for a genuinely featured element
- Only one strongly accented/filled element is visible per screen at a time
- Settings section headers and all button/label text use sentence case, no
  Title Case or all-caps remain
- Secondary/muted text uses a distinct defined color, not the primary text
  color at reduced opacity — verify this by checking the actual color values
  used, not just the visual appearance
- The Felix logo asset renders correctly (not a placeholder box) at the top
  of the main screen, in both light and dark mode
- Connection status between iOS and the Chrome extension is verified accurate
  by directly testing: sync a service, confirm iOS immediately reflects it
  correctly; let a sync go stale or disconnect a service, confirm iOS
  reflects that too — no false positives or false negatives in either
  direction
- A completely separate second account, tested independently on both iOS and
  the extension, works correctly with no bleed-over from any other account
  or hardcoded test data
- A real task completes successfully from the iPhone using a previously
  synced service after the syncing computer has been fully powered off
- No `localhost` or hardcoded local URLs remain anywhere in either the
  backend or iOS codebase
- A fresh account, on a fresh device, against the real deployed backend, can
  sign up, connect a service, and complete a real task successfully start
  to finish
- The user data model and request-handling structure have been reviewed and
  confirmed reasonably ready to accommodate future billing/rate-limiting
  without a disruptive rework, without any such features actually being
  implemented yet