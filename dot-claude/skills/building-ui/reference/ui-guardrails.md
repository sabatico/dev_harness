# UI development guardrails

## Contents
- 1. Foundation before screens
- 2. The styling-stack decision is locked for the wave
- 3. Hard rules
- 4. UI ahead of backend
- 5. Definition of Done for a UI slice
- 6. The emotional brief
- History

Applies whenever a project has (or is getting) a user interface and more than one agent will touch
it. **The problem:** a swarm of agents building UI without one written ruleset each invents its own
colors, spacing and components — and the inconsistency you were removing just moves around. This
is the ruleset: one design-system foundation first, then every screen migrated onto it.

## 1. Foundation before screens

A redesign (or a first real UI) is not a re-paint of one screen — it introduces the design-system
layer that does not exist yet, then moves everything onto it. Build the foundation first; screens
never carry raw styling.

```
tokens (the ONE source of branding)          color, type, spacing, radius…
   ↓ consumed by
scoped styles (per component)                every rule references a token, never a raw value
   ↓ wrapped by
primitive component library (Button, Card…)  the ONLY things screens compose
   ↓ composed by
screens / pages                              layout + data, NEVER raw styling
```

## 2. The styling-stack decision is locked for the wave

Pick **one** stack and record it as a decision record (`recording-decisions`); reopen it only by a
new decision record, never mid-slice. Choose for **agent-reliability** above novelty — the
most-trained, least-hallucinated, fewest-version-pitfalls target a cheaper builder model cannot get
subtly wrong.

> **Sensible default** for a minimal-dependency repo: native CSS-custom-property tokens + scoped
> CSS Modules + a typed primitive-component library. No CSS framework, no inline styles, no
> CSS-in-JS runtime. Zero runtime deps, branding centralized structurally, the most
> agent-reliable target. Record the choice, the rejected alternatives (e.g. Tailwind, CSS-in-JS,
> vanilla-extract) and why. Project's choice: «fill the chosen stack here».

## 3. Hard rules (enforced by lint, not just convention)

- **One token source.** All brand values live in one tokens file; no component hardcodes a color or
  size — it references a token.
- **Zero inline styles.** No `style={{…}}` or inline-style sprawl — a lint error, so it is enforced,
  not hoped for.
- **Consistency lives in the component layer.** Screens compose `<Button variant="primary">`, never
  a div with nine copy-pasted style props.
- **A design export is a REFERENCE, not source.** Never copy a design-tool export's markup or
  inline styles into the app. Read it for intent — layout, copy, color, spacing, hierarchy — then
  rebuild faithfully on tokens + components (`implementing-mockups` for pixel parity).
- **Adopt the information architecture fully.** No cherry-picked screens; take the IA as designed
  so navigation stays coherent.
- **Three window widths on every surface** (users snap the browser to work side by side): full
  (~1440) / half (~960) / one-third (~640) of a desktop display, plus the mobile widths already
  targeted. At each: no horizontal body scroll, no overlapping or clipped controls, everything
  operable, the design still intentional (the compact/mobile composition is acceptable at
  one-third — "looks okay and works", not "identical layout"). Automate it once a real-browser test
  layer exists (loop the width / no-overlap / no-horizontal-scroll assertions over the three
  viewports); until then it is a review-blocking manual check.
- **Untrusted input renders as inert text.** Every user-supplied string a screen displays is
  escaped by default; never build markup from it, never feed it to a raw-HTML / `href` / `src` sink
  unsanitized. The client is not the security gate — the server is — but a UI that reflects hostile
  input is its own bug (edge-case family I, `covering-edge-cases`).

## 4. UI ahead of backend → defer explicitly

A screen whose backend is not ready ships with stubbed data and a `TBD-UI: <what is missing>`
marker, registered in `docs/tbd-parking-lot.md` (or a dedicated UI-deferred registry).
"The backend isn't there yet" never becomes an invisible gap: the screen ships, the wiring is
tracked.

## 5. Definition of Done for a UI slice

1. Only tokens + primitive components (no raw values, no inline styles — lint passes).
2. Faithful to the design intent (layout, copy, hierarchy, emotional tone).
3. Responsive + accessible to the project's stated bar (keyboard, contrast, focus, aria).
4. Three-width check passed — full (~1440) / half (~960) / one-third (~640): no horizontal body
   scroll, no overlapping or clipped controls, everything operable, design still intentional.
5. Edge-case checklist instantiated and attacked — the surface's abnormal-usage cases (back/forward
   through gated steps, refresh/close mid-flow, double-submit, rapid open/close, mid-action
   lock/expiry, concurrent tabs) each Handled-with-test / N/A-justified / DEFERRED; hostile input
   (family I) on every field.
6. Any missing backend stubbed + `TBD-UI:`-registered.
7. Tests per the cross-author rule (`writing-tests`); running files updated.

## 6. Keep the emotional brief in front of you

A product has a *feeling* to hit. Write the one-line brand/emotional brief at the top of the
project's UI doc («e.g. warm and calm, never clinical») and check every screen against it — tone is
a guardrail too, not just spacing.

## History

- Formerly the UI-development-guardrails SOP (`ui-development-guardrails.md`), read "before any UI
  work".
