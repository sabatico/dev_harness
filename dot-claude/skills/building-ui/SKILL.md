---
name: building-ui
description: Builds or changes user-interface screens and components on the project's design system — tokens as the one source of branding, primitive components as the only things screens compose, zero inline styles, the design source treated as canonical intent rather than markup to copy, untrusted strings rendered inert, every surface checked at three window widths, missing backend stubbed and registered, and the full build run rather than just a typecheck. Use when building, restyling or migrating a screen, page, component, CSS or template, implementing a design or redesign, or when a brief names the UI builder role; read it before any UI work.
---

# Building UI

Load with `following-core-rules`. This is the UI builder's one task-type skill, so it also carries
the builder duties of `writing-code` that apply. The binding ruleset is
[reference/ui-guardrails.md](reference/ui-guardrails.md) — read it before any UI work; on conflict
it (and the project's styling decision record) wins over this summary. For pixel parity with a
mockup, `implementing-mockups` binds as well.

## Workflow

Copy this checklist and tick it off:

```
UI progress:
- [ ] 1. Inventory: existing tokens, primitives and screens — reuse before new
- [ ] 2. Read the ruleset + the locked styling-stack decision record + the design source
- [ ] 3. Foundation exists for what you need? (token → scoped style → primitive) If not, build
        it there first — never raw styling in a screen
- [ ] 4. Edge-case checklist for the surface instantiated (`covering-edge-cases`)
- [ ] 5. Build the screen from primitives; missing backend → stub + `TBD-UI:` + registry row
- [ ] 6. Verify (loop below), including the three-width check
- [ ] 7. Report: DoD items, runner/tracker items touched, tests owed
```

## Rules (summary — the reference file is the law)

- **Tokens + primitive components only.** No hardcoded color or size, zero inline styles (lint
  error), consistency lives in the component layer.
- **The styling stack is locked for the wave** by a decision record; never switch it mid-slice.
- **The design source is canonical for intent** — layout, copy, color, spacing, hierarchy, tone.
  Never copy an export's markup or inline styles; rebuild it on tokens + components. Adopt the
  information architecture fully.
- **Untrusted strings render as inert text** — never a raw-HTML, `href` or `src` sink unsanitized.
- **UI ahead of backend:** stub the data, mark `TBD-UI: <what is missing>`, register it in
  `docs/tbd-parking-lot.md`.
- **The emotional brief** at the top of the project's UI doc («e.g. warm and calm, never
  clinical») is checked on every screen.
- **Builder duties still apply:** you write ZERO tests for your own UI (`writing-tests` authors
  them); the edge-case checklist ships with the change; no commit or push.

## Verify (feedback loop)

1. Run «the FULL build command» — not only the typecheck; a typecheck passes over broken CSS
   imports and templates — then `scripts/run-all-gates.sh`.
2. Render the surface and check it at full (~1440), half (~960) and one-third (~640) widths plus
   the targeted mobile widths: no horizontal body scroll, no overlap or clipped controls,
   everything operable, design still intentional.
3. Any red → fix → re-run from step 1. Report done only after a clean pass you watched.

## Report

Each Definition-of-Done item from the reference file (pass / why not) · the edge-case checklist ·
`TBD-UI:` markers + registry rows · **which runner and tracker items the work touched** · the cases
the cross author must test · build and gate output.

## History

- Formerly the `skill-ui-coding` skeleton in the agent-skills SOP plus the UI-development-guardrails
  SOP (now the reference file).
