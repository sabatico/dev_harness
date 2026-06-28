# CLAUDE.md — «PROJECT NAME» (read this first, every session)

This repo holds **«PROJECT NAME»** — «one-paragraph description: what it is, who it's for, the core value».
Led by an AI lead agent + spawned role sub-agents; the human owner («role») gives final acceptance.

## 🧭 COLD START — read these IN ORDER for full context (do not skip)
1. **`docs/ONBOARDING.md`** — **ALWAYS FIRST.** The living state doc: current status, decided-vs-open, the active milestone, and the append-only session log (newest first). It always reflects *current* reality — trust it over older docs.
2. **`docs/adr/README.md`** — the **ADR log** (the running list of locked decisions). Never re-litigate a locked decision.
3. **`docs/feature-catalog.md`** — the **single inventory of EVERYTHING** the product does (every user-facing capability + every core module), with status, surface, tests. The fastest "what does this do, end to end?" answer.
4. **`docs/runner.md`** — the **live tracker for the active work wave** (what's in flight, statuses, open questions).
5. Then dive deeper as the task needs — `docs/architecture.md`, the relevant ADRs, `docs/sops/*`. **Touching «X subsystem»?** read «its doc» first. **Doing UI work?** read **`docs/sops/ui-development-guardrails.md`** FIRST (tokens + components, zero inline styles). **Implementing a design mockup pixel-perfect?** read **`docs/sops/mockup-implementation.md`** (structure preservation + extract values + rendered-HTML diff; ask for the structured handoff). **Touching an integration?** read **`docs/third-party-services.md`** first.
6. Work-to-do lives in **`docs/backlog-tickets.md`** (bugs + features, unscheduled); work deliberately deferred-by-constraint lives in **`docs/tbd-parking-lot.md`**.

## ⛔ Standing rules (non-negotiable — never miss these)

- **NEVER run a destructive / irreversible action** (delete/drop/destroy/`rm -rf`/force-push/teardown of real resources, data migrations that drop columns, etc.) **without first explaining exactly what it removes + the blast radius AND getting explicit owner approval.** Prefer reversible/targeted alternatives. Approval in one context does not extend to the next.
- **Invariants are sacred:** «list the project's 1–3 properties that must NEVER break — e.g. "no data loss", "no unauthorized access", "public API stays backwards-compatible"». The **guardrail test suite** that protects them is **owner-owned** — builders must pass it, never weaken or delete it.
- **No secrets in chat/docs/commits.** Credentials live in the gitignored secrets store (+ CI secrets). **Never send secrets/keys/tokens/real production data to any external model or service.** Code/specs only.
- **Model / role policy:** routine work → «cheap model»; mid → «mid model»; hard/risky/security-critical → «strong model» (the lead). **Tests are authored by a DIFFERENT model/agent than the builder** (the builder writes ZERO tests for its own code — see `docs/sops/test-and-coverage.md`). A **scribe** documents each finished item.
- **Coverage is part of Done:** every slice **measures** coverage on its new/changed code and hits «target band, e.g. 80–100%». A test you can't write yet (missing harness/dep) is **DEFERRED, never dropped** — tag the site `DEFERRED-TEST:`, register it, and write it the moment the dependency lands.
- **Git:** «branch/PR policy». End commits with the agreed co-author trailer.
- **Spend:** sub-«$N» de-risk validation is never a blocker — just do it, then clean up (per the destructive-action rule).
- **"Quality review" = run the SOP (`docs/sops/quality-review.md`):** review ALL code since the last `quality-review:` commit across 3 axes (code quality / tests+coverage / observability); lead leads + an **independent second reviewer**; lead **judges** each finding; resolve; verify green; commit with the `quality-review:` prefix.
- **Maintain state — no stale docs (check at the end of EVERY act, before yielding):** update ALL of these "running files" for anything the work changed (mandatory, exactly like ONBOARDING — don't wait for "session end"):
  - **`docs/ONBOARDING.md`** — status + decided/open + milestone + a session-log line.
  - **`docs/runner.md`** (the active wave runner) — flip every touched item's status + add new items.
  - **`docs/feature-catalog.md`** — flip the status / add the row for any capability added/changed/removed.
  - **`docs/use-case-runbook.md`** — update changed flows + add a story for any new capability.
  - **`docs/build-tracker.md`** — reflect progress.
  - *(if touched)* **`docs/backlog-tickets.md`** (move/close tickets), **`docs/tbd-parking-lot.md`** (add deferrals + fire resurface triggers), **`docs/third-party-services.md`** (new/changed integration).

## ✅ Definition of Done (a slice is not done until ALL are true)
1. It works (the happy path + the obvious edges).
2. Tests authored by a different role/model, measured to the coverage target (or deferred-and-registered).
3. Build + tests + **all gates** green — *watched*, not assumed.
4. Observability: meaningful outcomes are logged/traced; no secret material in logs.
5. Decisions of consequence recorded as ADRs; running files updated.
6. Committed with a clear message.

## 🔑 Quick facts
- **Repo / access:** «repo, how the agent has push/deploy access».
- **Stack:** «languages, frameworks, key tools».
- **Environments:** «dev / staging / prod; what's safe to touch».
- **Toolchains & non-obvious knobs:** «PATH bits, test DB ports, env vars, gotchas the agent will hit».
- **Secrets by NAME (never values):** «which secrets exist + where they live».
- **Phase:** «where the project is right now».
