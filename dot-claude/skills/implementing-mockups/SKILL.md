---
name: implementing-mockups
description: Reproduces a high-fidelity design (a design-tool handoff, Claude Design or Figma mockup, rendered-HTML export) faithfully on the project's token + component system by extracting exact values instead of eyeballing a picture, gating on a doc-vs-mockup reconcile, and verifying with a computed-style diff plus a pixel-diff score before owner sign-off. Use when the owner hands over a mockup, design handoff, prototype or screens to build "pixel-perfect", when implementing a redesign screen by screen, or when a built screen does not match its design.
---

# Implementing mockups

Builds screens on the token + primitive foundation from `building-ui`. This skill is canonical for
mockup work; `building-ui` is canonical for the token/component rules themselves.

**Why:** eyeballing a mockup as a *picture* inverts surface hierarchies and silently misses weights,
borders and radii — several rework passes per screen. A rendered design is a machine-readable
document; every value can be read exactly. **Extract, don't guess.**

## The two non-negotiables

1. **Structure preservation.** The app's DOM mirrors the mockup's DOM element-for-element — same
   boxes, nesting, order, grouping — but **rebuilt** as semantic, wired, token-styled components.
   Never copy the export's inline styles, generated IDs, source-map attributes or div-soup. Parallel
   structure is what makes style mapping and verification mechanical.
2. **Centralized style from extracted values.** Every visual value comes from the mockup's actual
   computed style, lifted into the token + component layer. **No inline styles** — the one exception
   is a genuinely dynamic value carried on a CSS custom property.

> Structure is preserved; markup is rebuilt. Style values are extracted; inline styles are not.

## Source of truth — get the best one, and ask for it

Precedence: **(1) a structured handoff** (component tree + the tokens actually used + layout
hierarchy + assets — e.g. Claude Design "Send to Claude Code", Figma Dev Mode / MCP) → **(2) the
rendered export, via computed-style extraction** → **(3) screenshots** (last resort — avoid). A
same-family structured handoff needs no pixel inference: write against the real tokens.

**Never fall back silently.** Without a structured handoff, ASK the owner to export one first, naming
the exact export menu. Brief whoever produces it with the checklist in
[reference/designer-brief.md](reference/designer-brief.md) (kept in the repo as the styling-context
manifest at «where the styling-context manifest lives»), and re-offer the handoff for every new
screen or wave — it deletes most of step 0.

## Workflow

Copy this checklist and tick it off:

```
Mockup progress:
- [ ] 0. Token lock (ONCE, before any screen) — owner signs off
- [ ] 1a. Extract the COMPLETE frame spec
- [ ] 1b. Reconcile spec vs designer docs — GATE: any discrepancy → STOP, ask the owner
- [ ] 1c. Read the geometry for structure (chrome vs content)
- [ ] 2. Mirror the structure + add what a static mockup lacks
- [ ] 3. Apply styles from the spec → tokens only
- [ ] 4. Verify: computed-style diff + pixel score → fix → re-diff until within tolerance
- [ ] 5. Owner approves the side-by-side → commit WITH it → next screen
```

**0 — Token lock.** Render the mockup and extract the complete style system into tokens +
primitives, then verify each primitive against the mockup with a computed-style diff:
- palette + semantic roles, with the **surface hierarchy measured** (page vs card vs header — cards
  may be *lighter* than the page; measure, don't assume);
- type scale — size **and weight** per role (export headings are often lighter than you'd guess) +
  font families;
- spacing, radii, shadows;
- the box style of every primitive: each button variant, pill/badge, card, input, nav-link
  active/inactive.

Skipping this is what causes the rework; lock it once and every screen after is pure structure.
Formalize the token tiers (primitive → semantic → component) per
[reference/verification.md](reference/verification.md).

**1a — Extract everything, not spot-measurements.** Walk the frame's DOM and emit every element:
`tag · box (x,y,w,h) · bg · border · radius · font/size/weight · color · padding · nesting`. This
artifact is the **build contract**. Colour spot-checks miss layout, alignment, nesting and small
parts (flush-left rails, bullets, dividers, borders); a complete spec lets a builder — even a cheaper
model — one-shot the screen.

**1b — Reconcile (hard gate, before any markup).** For each shared element and the layout, confirm
the measured mockup agrees with the designer's component/screen/token docs: nav **orientation + items**;
**layout** (columns, alignment, what is nested in what); **surfaces**; which **primitive**.
Match → proceed. **Any discrepancy → STOP, raise it with the owner, resolve before implementing.**
Mockup pixels are authoritative, but a conflict means the docs (or your reading) may be wrong
elsewhere too — never silently pick one. Also flag **shell variants** here (e.g. header + full-height
sidebar vs header + centred content) and decide them at the shell level.
*WHY: a doc said the account sub-nav was a "horizontal strip"; the mockup rendered a vertical rail —
building on the doc cost a full rework.*

**1c — Read the geometry for structure.** A complete spec is necessary, not sufficient. Before mapping
any major element to a `<div>`, classify it by its box against the frame edges and header: does it
**hug a frame edge** (`x≈0` / right), **dock to the header** (`y ≈ header height`), **run full height**
(`h ≈ frame height`)? If yes → it is **chrome (a shell element)**: build it as a shell-layout change,
not a styled div inside the existing content container — otherwise it renders detached (off the
edge, gapped from the header, only as tall as its content). Let the geometry dictate the structure;
don't bend the design to fit the shell you already have.
*WHY: a rail boxed `[x=1, y=header-bottom, full-height]` meant "sidebar docked under the header";
three independent builders matched its styling and all dropped it inside the content area.*

**2 — Mirror the structure** per the spec (columns, nesting, alignment), adding what a static mockup
lacks: semantic tags, ARIA roles/labels, keyboard/focus, responsive layout, state/data wiring.
What the mockup does NOT contain — hover/focus/active/disabled, error/empty/loading, breakpoints, dark
mode, long-content overflow, i18n — is **flagged per screen for an owner decision**, never invented.

**3 — Style from the spec → tokens.** Tokens + scoped styles only; map every hex/px to a token, never
by eye.

**4 — Verify (a final check, not the design loop).** Render both sides to HTML with styles resolved,
diff element by element, then score with a pixel-diff heatmap — procedure, thresholds and tooling
gotchas in [reference/verification.md](reference/verification.md). Feedback loop: **fix
structure/alignment first, re-score, then colour/type; repeat until the computed-style diff is within
tolerance and the %-match ≥ «threshold, e.g. 95%»** (text masked).

**5 — Sign-off and commit.** **Never commit a screen before the owner has reviewed the side-by-side
and approved it.** The agent brings the side-by-side + the measured diff; the owner approves or
annotates (red-line callouts are ideal); lock the screen, then the next. One screen locked at a time.

## Definition of Done (per screen)

- Structure mirrors the mockup; computed-style diff within tolerance; %-match ≥ «threshold».
- Every variant implemented as props; states + a11y verified (focus/hover/disabled, contrast, keyboard).
- 0 inline styles, tokens only; tests per the cross-author rule (`writing-tests`); running files updated.
- Committed with the side-by-side artifact.

"Pixel-perfect" means computed values match and the result is indistinguishable to the eye — not
byte-identical (font rasterization and the mockup's own scale differ).
