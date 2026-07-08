# SOP — UI Development Guardrails

**Read this BEFORE any UI work.** Applies whenever a project has (or is getting) a user interface and more than one agent will touch it.

**The problem it solves:** a swarm of agents building UI *without one written ruleset* will each invent their own colors, spacing, and components — and the inconsistency you were trying to remove just moves around. This SOP is the ruleset: establish **one design-system foundation** first, then migrate every screen onto it.

## 1. Establish the foundation BEFORE migrating screens
A redesign (or a first real UI) is not a re-paint of one screen — it's introducing the **design-system layer that doesn't yet exist**, then moving everything onto it. Build the foundation first; never let screens carry raw styling.

```
tokens  (the ONE source of branding)        ← design tokens: color, type, spacing, radius…
   ↓ consumed by
scoped styles (per component)               ← every rule references a token, never a raw value
   ↓ wrapped by
primitive component library (Button, Card…) ← the ONLY things screens compose
   ↓ composed by
screens / pages                             ← layout + data, NEVER raw styling
```

## 2. The styling-stack decision is LOCKED for the wave (record it as an ADR)
Pick **one** stack and lock it; reopen only via ADR, never mid-slice. Choose for **agent-reliability** above novelty — the most-trained, least-hallucinated, fewest-version-pitfalls target a cheaper builder model can't get subtly wrong.

> **Sensible default** for a minimal-dependency repo: **native CSS-custom-property tokens + scoped CSS Modules + a typed primitive-component library. No CSS framework, no inline styles, no CSS-in-JS runtime.** It adds zero runtime deps, centralizes branding structurally, and is the most agent-reliable styling target. Record the choice + the rejected alternatives (e.g. Tailwind, CSS-in-JS, vanilla-extract) and *why* in an ADR. `«fill the project's chosen stack here»`.

## 3. Hard rules (enforce by lint, not just convention)
- **One token source.** All brand values live in one tokens file. **No component hardcodes a color/size — it references a token.**
- **Zero inline styles.** No `style={{…}}` / inline-style sprawl. Make it a lint error, so it's enforced, not hoped for.
- **Consistency lives in the component layer.** Screens compose `<Button variant="primary">`, never a div with nine style props copy-pasted around.
- **A design export is a REFERENCE, not source.** If you're handed a design-tool export (inline-styled, class-less markup), **never copy its markup/inline styles** into the app. Read it for *intent* — layout, copy, color, spacing, hierarchy — then rebuild faithfully on the token + component system.
- **Adopt the information architecture fully.** Don't cherry-pick screens; take the IA as designed so navigation stays coherent.
- **Review every surface at three window widths** (the snap-to-side case — users resize the browser to work side-by-side): **full (~1440) / half (~960) / one-third (~640)** of a desktop display. At each, and at the mobile widths already targeted: no horizontal body scroll, no overlapping/clipped controls, everything operable, the design still intentional (the compact/mobile composition is acceptable at one-third — "looks okay and works", not "identical layout"). Automate it if you have a real-browser test layer (loop the width/no-overlap/no-horizontal-scroll assertions over the three viewports); until then it's a review-blocking manual check.
- **Untrusted input renders as inert text.** Every user-supplied string a screen displays is escaped by default; never build markup from it, never feed it to a raw-HTML/`href`/`src` sink unsanitized. (The client is not the security gate — the server is — but a UI that reflects hostile input is its own bug. See `edge-case-catalog.md` family I.)

## 4. UI ahead of backend → defer explicitly
When you build a screen whose backend isn't ready, **stub the data + mark it** — `TBD-UI: <what's missing>` — and register it in `running-files/tbd-parking-lot.md` (or a dedicated UI-deferred registry). Never let "the backend isn't there yet" become an invisible gap. The screen ships; the wiring is tracked.

## 5. Definition of Done for a UI slice
1. Uses only tokens + primitive components (no raw values, no inline styles — lint passes).
2. Faithful to the design intent (layout, copy, hierarchy, emotional tone).
3. Responsive + accessible to the project's stated bar (keyboard, contrast, focus, aria).
4. **Three-width check passed** — full (~1440) / half (~960) / one-third (~640): no horizontal body scroll, no overlap/clipped controls, everything operable, design still intentional.
5. **Edge-case checklist instantiated + attacked** (`edge-case-catalog.md`) — the surface's abnormal-usage cases (back/forward through gated steps, refresh/close mid-flow, double-submit, rapid open/close, mid-action lock/expiry, concurrent tabs) each Handled-with-test / N/A-justified / DEFERRED; hostile input (family I) on every field.
6. Any missing backend is stubbed + `TBD-UI:`-registered.
7. Tests per the cross-author rule; running files updated.

## 6. Keep the emotional/brand brief in front of you
A product has a *feeling* to hit. Write the one-line brand/emotional brief at the top of the project's UI doc (`«e.g. warm and calm, never clinical»`) and check every screen against it — tone is a guardrail too, not just spacing.
