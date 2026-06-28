# SOP — Implementing a design mockup pixel‑perfect

**Read this when a project is handed a high‑fidelity design** (a design‑tool export, a Claude Design /
Figma mockup, a rendered‑HTML export) **and must reproduce it faithfully** on the token + component
system. Pairs with [`ui-development-guardrails.md`](ui-development-guardrails.md) (which establishes the
token + primitive foundation this SOP builds screens on).

**The problem it solves:** treating the mockup as a *picture* and eyeballing colors/spacing from
screenshots inverts surface hierarchies and silently misses weights, borders, and radii — costing
multiple rework passes per screen. A rendered design is a **machine‑readable document**: every value can
be read exactly. **Extract, don't guess.**

## The two non‑negotiables
1. **Structure preservation.** The app's DOM mirrors the mockup's DOM **element‑for‑element** — same
   boxes, nesting, order, grouping — but **rebuilt as semantic, wired, token‑styled components** (never
   copy the export's inline styles, generated IDs/source‑map attrs, or div‑soup). Parallel structure is
   what makes both the style mapping and the verification *mechanical* instead of a guessing game.
2. **Centralized style application from extracted values.** Every visual value comes from the mockup's
   *actual* computed style, lifted into the **token + component layer** — no inline styles (the only
   exception is a genuinely dynamic value carried on a CSS custom property).

> Structure is preserved; **markup is rebuilt**. Style **values** are extracted; **inline styles are not**.

## Source of truth — get the BEST one, and ASK for it
Prefer a **structured handoff** (a machine‑readable spec: component tree + the actual design tokens used
on the canvas + layout hierarchy + assets) over a picture or a raw markup export. Modern design tools can
emit this directly — e.g. Claude Design's **"Send to Claude Code"** bundle, or **Figma Dev Mode / MCP**.
A same‑family structured handoff needs **no pixel inference** — you write against the real tokens.

**Precedence:** (1) structured handoff/spec → (2) the rendered export via computed‑style extraction →
(3) screenshots (last resort — avoid).

**Don't silently fall back.** If you don't have the structured handoff, **ASK the owner to export one**
before settling for reverse‑engineering — and make the ask actionable (tell them the exact export menu).

### Brief the designer (or design tool) BEFORE the handoff
Whoever produces the handoff — a design tool's export or a human designer — must be told the **same
checklist**, so the package comes back *implementation‑ready* instead of needing a translation pass.
Keep this as a **styling‑context manifest** in the repo and paste/link it every time
(`«where the styling-context manifest lives»`). The brief:

1. **Target stack.** Name the exact styling system the output must hit — framework + styling method
   (e.g. «CSS‑custom‑property tokens + CSS Modules», or the project's locked stack). These tools tailor
   output to the *declared* stack (Tailwind vs plain CSS vs React + CSS Modules), so this is the single
   highest‑leverage line.
2. **Token vocabulary.** Give the **semantic token names** to reference (or link the tokens file):
   "use these names — don't emit raw hex/px values."
3. **Component library.** List the **existing primitives to reuse** (names + their variants/props), so it
   doesn't re‑invent buttons/cards/inputs/nav.
4. **Output rules.** Emit components + scoped styles + `var(--token)` references; **no inline styles, no
   hardcoded colors/spacing, no new token system, no foreign‑framework utility classes.**
5. **Map + flag.** Map every value used on the canvas to a semantic token; **flag any value not in the
   palette** so it's added deliberately — never silently invented.
6. **Scope + format.** The **structured handoff** (component tree + tokens + layout hierarchy + assets),
   **all screens / the full IA** — not a single frame, and not a flat screenshot/PDF.
7. **Connect the codebase if the tool supports it.** Pointing the tool at the repo so it **auto‑ingests
   the tokens + components** is the biggest quality lever; the manifest is the fallback when it can't.

Re‑offer the handoff each new screen/wave — it deletes most of Step 0's manual work.

## Procedure

### Step 0 — Token‑lock pass (ONCE, before any screen)
Render the mockup and extract the **complete** style system into the tokens + primitives, then verify
each primitive against the mockup with a computed‑style diff:
- palette + **semantic roles** — and **get the surface hierarchy right** (which surface is the page vs the
  card vs the header; cards may be *lighter* than the page, not darker — measure, don't assume);
- type scale — size **and weight** per role (export headings are often a lighter weight than you'd guess)
  + the font families;
- spacing, radii, shadows;
- the box style of **every primitive**: each button variant, pill/badge, card, input, nav‑link
  active/inactive.

**Skipping this is what causes the rework.** Lock it once → every screen after is pure structure.

### Step 1 — Mirror the structure
Build the screen's components so the DOM hierarchy matches the mockup's section. Add what the static
mockup lacks: semantic tags, ARIA roles/labels, keyboard/focus, responsive layout, state/data wiring.

### Step 2 — Apply styles from tokens
Style via tokens + scoped styles only. Pull any value not already a token from the mockup's computed
style (never by eye).

### Step 3 — Verify (the core of this SOP)
**Render BOTH sides to HTML with all styles resolved inline, then diff element‑by‑element.** Because the
structures are parallel, the trees line up and a mismatch is a **fact** (`color #7A6F60 vs #9A8F7D`), not
an opinion. The computed‑style diff is the **source of truth for exact values**.

**Then quantify it** (don't just eyeball a side‑by‑side):
- Screenshot both at an **identical viewport**, generate a **pixel‑diff heatmap** (identical = black,
  differences = hot) + a **%‑match score, overall and per region**; track it across iterations and target
  **≥ `«threshold, e.g. 95%»`**. Per‑region scoring localizes the worst offender.
- **Mask text when scoring layout** — font rasterization differs between renderers and never reaches
  100% (layout‑only tops ~99.8%); judge text fidelity via the computed‑style diff instead. That's the
  honest ceiling. (Pixel‑matching *alone* is brittle — anti‑aliasing/fonts cause false positives — which
  is why the field moved toward perceptual / DOM‑layout comparison; the inline‑style diff *is* that.)

**Fix order: structure/alignment FIRST, then aesthetics.** Layout errors compound (a 1px row delta × 6
rows = a visible 6px drift) and masquerade as many separate bugs — fix the root cause, re‑score, then
refine color/type.

Walk the **per‑element checklist**: background · border (color / width / radius) · text (color, family,
size, weight, letter‑spacing, transform) · padding & gap · the exact copy · icons / pills · interactive
states. Fix every mismatch, re‑diff, then commit with the side‑by‑side as the approval artifact.

## Token tiers (formalize them)
**Primitive** (raw values, never used directly in components) → **Semantic** (role‑named: `--color-bg`,
`--space-4` …) → **Component** (a primitive's resolved set). One source of truth, names that convey
*purpose* not value; define core tokens (color, type, spacing) before anything composite.

## Gotchas (build them into the tooling)
- **Fonts:** wait for fonts to finish loading before any capture (`document.fonts.ready`) — otherwise the
  shot renders the *fallback* font and lies.
- **Secure context:** if the app needs one (WebCrypto, etc.), drive it over `localhost`/https, not a
  bare‑IP http origin.
- **Ignore the export's chrome:** design exports often wrap each screen in a preview frame and inject a
  runtime / source‑map attrs, and stack all sections on one page. Align crops/subtrees to the real screen
  edges; don't sample the frame.
- **Reach gated screens:** seed an account / use a harness to get past auth/billing/verification so every
  screen is capturable.
- **Data vs. copy:** the mockup uses stub persona data. Match the *design copy & styling*; let *real data*
  differ. Don't chase data as if it were a design defect.

## Drift audit (keep it locked)
Beyond the no‑inline‑styles lint, periodically **re‑diff the locked tokens against the mockup** and
**flag any hardcoded color/spacing ("magic numbers") that bypassed a token** — catches drift before it
spreads.

## What the mockup does NOT contain — decide, don't invent
Hover/focus/active/disabled states · error/empty/loading states · responsive breakpoints · dark mode ·
long‑content overflow · i18n. Flag these per screen for an owner decision.

## Definition of Done (per screen)
- Structure mirrors the mockup; computed‑style diff within tolerance; **%‑match ≥ `«threshold»`**;
- **every variant implemented as props**; **states + a11y verified** (focus/hover/disabled, contrast,
  keyboard); **0 inline styles**, tokens only; tests per the cross‑author rule; running files updated;
- committed **with the side‑by‑side artifact**.

## "Pixel‑perfect" — the honest definition
With a token system it means **computed values match + indistinguishable to the eye** — not byte‑identical
(font rasterization and the mockup's own scale differ). The realistic, verifiable bar is the
computed‑style diff + the %‑match score + an approved side‑by‑side.

## Collaboration loop
Token‑lock → owner sign‑off. **Per screen:** the agent brings a **side‑by‑side + the measured diff**; the
owner approves or annotates (red‑line callouts are ideal — precise + fast); lock the screen, then move to
the next. One screen locked at a time.
