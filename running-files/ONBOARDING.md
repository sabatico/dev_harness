# ONBOARDING — «PROJECT»: Living State & Cold-Start Brief

> **The first thing any human or agent reads.** It always reflects the *current* reality so anyone can cold-start without prior context. **Stale state here is a bug** — update it at the end of every act.
> **Last updated:** «date» · **Last session:** «2–4 sentence headline of what just happened + what's next». (Keep a short "Prior session:" tail so the recent arc is visible.)

## 1. What this is (stable)
«One paragraph: the product, the user, the value. Rarely changes.»

## 2. Reading order (stable)
«The cold-start path — which docs to read in what order for this project. Mirrors CLAUDE.md.»

## 3. Architecture at a glance (stable-ish)
«The big boxes + how they connect; links to deeper docs/ADRs.»

## 4. Current status (VOLATILE — keep current)
«Where we are right now: what's built, what's running, what's broken. The honest snapshot.»

## 5. Decided vs. open (VOLATILE)
- **Decided / locked:** «pointers to the ADRs + settled choices.»
- **Open questions:** «what still needs a decision, and who owns it.»

## 6. Active milestone (VOLATILE)
«The current goal + its slices. Links to `runner.md` for the live tracker.»

## 7. How to work here (stable)
«Build/test/run commands, the gotchas, the DoD pointer.»

## 8. Session log (append-only, NEWEST FIRST)
- **«date» (id)** — «what this act did: built/fixed/decided, the verification result (tests/gates green), and any deferrals. Dense but scannable. One entry per act.»
- **«date» (id)** — «…prior act…»

> **Maintenance rule:** append a §8 line and refresh §4/§5/§6 at the end of **every** act, before yielding. Stable sections (§1–§3, §7) change rarely.
