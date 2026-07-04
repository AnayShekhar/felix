# Lumis — Fix "Cheap" Visual Quality Issues

This is a refinement pass on the already-built panel/scribble redesign. The
structure and flow are correct — this fixes specific visual execution issues
that are making the app read as cheap or AI-generated rather than premium.

Do not add any new font beyond the existing two-font system (New York serif
for hero moments only, SF Pro for everything else) — the issue is disciplined
use of weight and hierarchy within that system, not font variety. Reference:
Anthropic's own Claude app uses exactly this same two-font restraint.

Investigate the current implementation first, then apply these fixes in a way
consistent with the existing codebase structure.

---

## 1 — Give the scribble shape real visual confidence

Currently the scribble reads as washed out and static — low enough contrast
against the background that it looks more like a faint texture than a
deliberate, alive brand element. Increase its presence: strengthen the
linework's opacity/saturation so it clearly reads as intentional at a glance,
not something still loading or barely visible. It should look confident and
alive even at rest, not apologetic. Re-test this specifically in both light
and dark mode — contrast that works on one background may not automatically
work on the other, so verify both rather than assuming.

---

## 2 — Introduce real surface contrast, not one flat grey wash

Right now nearly everything — background, chat bar, cards — sits at very
similar grey values, so nothing separates or pops, and the whole app reads as
slightly muddy rather than crisp. Establish a clearer distinction between the
base background and elevated surfaces (the chat input bar, sidebar, settings
cards, sheets) — elevated surfaces should generally read as cleaner and
lighter than the base background in light mode (approaching a true white
where appropriate), and correspondingly distinct in dark mode, rather than a
near-identical shade of the same grey. This is what gives an interface real
depth instead of a flat wash.

---

## 3 — Establish real typographic hierarchy through weight and size, not just bold

Audit every screen for overuse of bold weight applied broadly and flatly (the
Settings title, the sidebar header, the profile name, etc. all currently sit
at a similar heavy weight with little differentiation). Rework this so there
is a clear, small number of distinct levels — for instance, one clearly
dominant heading per screen, meaningfully larger and heavier than everything
else, with body and secondary text pulling back to lighter weights and
smaller sizes. When many things are bold, nothing feels important — the goal
is for weight and size to be used deliberately to draw the eye to one clear
focal point per screen, with everything else receding in comparison.

---

## 4 — Build one consistent, considered icon set for Settings and connected services

The current icons (envelope, grid, document, person-in-circle, speech bubble,
dot-grid, etc.) come across as mismatched in density and line weight, like
they were pulled individually rather than chosen as a set. Rebuild this list
using a single icon family with consistent stroke weight, consistent corner
treatment, and consistent visual density across every icon used — the exact
source library matters less than internal consistency across all of them.
Take a pass through every icon in the app, not just this one screen, with the
same lens.

---

## 5 — Commit to one accent color, including for success/status states

The blue-grey tint is the established single accent, but green checkmarks for
"Connected" states introduce a second, competing accent color. Pick one
approach and apply it consistently: either success states also use the
established tint color (differentiated by a checkmark glyph or subtle
treatment rather than a different hue), or, if you deliberately want a
distinct semantic color for success/error states specifically, make sure that
is a conscious, limited exception clearly reserved only for status
indication — not something that then also creeps into other decorative uses
elsewhere. Whichever direction you choose, apply it uniformly everywhere
success/connected states appear, not just on this one screen.

---

## 6 — Give the camera screen real brand presence

Currently the camera view is a stock, unstyled camera interface — a plain
white circular shutter button, default black scrim, and a generic pill — with
no visual connection to the rest of the app at all, making it feel like a
different, cheaper product was dropped in for this one screen. Reskin the
shutter button, the "Say Hey Lumis" listening pill, and the close control
using the app's actual established visual language (the tint color, the
typography, the corner-radius and spacing conventions used elsewhere) so this
screen clearly belongs to the same product as everywhere else, while keeping
the camera preview itself unobstructed and functional.

---

## 7 — Tighten and correct spacing throughout the sidebar and Settings

Go through the sidebar and Settings screens specifically and correct
inconsistent or cramped spacing — for example, the "Verify" text sitting with
almost no breathing room beneath each connected service's description, and
any divider placement that feels arbitrary rather than deliberately marking a
clear grouping boundary. Apply the spacing scale already established in the
design system consistently here rather than one-off values — inconsistent
spacing is one of the fastest ways an interface reads as assembled rather
than designed, even when every individual element is otherwise fine.

---

## 8 — General pass

After making the above changes, look at each affected screen as a whole,
side by side if possible, and confirm they now read as coming from one
considered, disciplined design system — consistent surface treatment,
consistent type hierarchy, one accent color used the same way everywhere,
one consistent icon language, and even, deliberate spacing throughout. Fix
anything still standing out as inconsistent with the rest before considering
this complete.

---

## Verification

- The scribble shape is clearly, confidently visible at rest in both light
  and dark mode — never reading as faint or unfinished
- Elevated surfaces (chat bar, sidebar, settings cards) are visibly distinct
  from the base background, not the same flat grey
- Each screen has one clear dominant heading, meaningfully bolder/larger than
  supporting text — bold weight is no longer applied broadly across many
  elements at once
- Every icon in Settings and connected services shares consistent stroke
  weight and visual density
- Success/connected states use one deliberate, consistent color treatment
  that does not compete with the app's single established accent color
- The camera screen's shutter button, listening pill, and controls visually
  match the rest of the app's established design language
- Spacing in the sidebar and Settings follows the established spacing scale
  consistently, with no cramped or arbitrary gaps remaining
- Viewing the redesigned screens together, they read as one coherent,
  deliberately designed product rather than individually assembled screens