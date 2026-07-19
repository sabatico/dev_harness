# DOC tickets — documentation work not doable inline — «PROJECT»

> **`DOC-##` — a piece of documentation work that can't be finished in the current act** (a runbook,
> a guide, a registry that needs writing, a doc that needs a real restructure). Most doc updates
> happen inline as part of the end-of-act ritual and need NO ticket — this file is only for doc work
> that is substantial enough to schedule on its own.

**Status:** ☐ open · ▶ in progress · ✅ done

| ID | Title | What's needed / acceptance | Where it lives (target path) | Status | Source |
|----|-------|-----------------------------|------------------------------|--------|--------|
| DOC-001 | «the doc to write» | «what it must contain + how we'll know it's complete» | «docs/…» | ☐ | «review / owner / gap» |

## Rules
1. **Inline first** — if the doc change belongs to the act you're finishing, just do it (the "maintain state" rule). Only open a `DOC` ticket when the work is too big for inline.
2. **Register the target** — name the file it will become; if it's a new running doc, it must also be added to the documentation manifest when created (so the docs-registration gate passes).
3. **Follow the authoring conventions** — `CONVENTIONS.md` (why + alternatives, cold-start readable); outward-facing prose additionally needs the project's style rules + owner sign-off.
4. **Close truthfully** — link the written doc + note how it was verified (renders, links resolve, gate green).

> **Distinct from a `bug-register` row:** a wrong/stale doc *claim* is caught by the quality review's claims axis and fixed there; a `DOC` ticket is for *missing* documentation that needs authoring.
