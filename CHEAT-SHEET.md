# Harness Cheat-Sheet (pin this)

## Every act ends with (mandatory, before yielding)
1. **Verify green** — build + full tests + all gates, *watched* not assumed.
2. **Update the running files** for anything that changed:
   - `ONBOARDING.md` (status + session-log line)
   - `runner.md` (flip statuses / add items)
   - `feature-catalog.md` (add/flip rows)
   - `use-case-runbook.md` (changed flows + new stories)
   - `tickets/*` (USER/DEC/FEAT/DOC/BIZ + `tickets/bug-register.md` BUG + `tickets/security.md` SEC) / `backlog-tickets.md` / `bug-hunt-log.md` / `tbd-parking-lot.md` / `third-party-services.md` (if touched)
   - `build-tracker.md`
3. **Commit** with a clear message.

## Building anything
- Smallest valuable slice. Decision of consequence → ADR first (don't re-litigate locked ones).
- **Builder ≠ test author.** Tests come from a different model/agent.
- Coverage to target, or `DEFERRED-TEST:` + register it.
- **Instantiate the edge-case checklist** (`sops/edge-case-catalog.md`): back/forward, refresh/close mid-flow, double-submit, rapid open/close, concurrency, replay + the server mirrors — and **hostile input (family I)** on every field, client + server. Tester attacks it AND proposes its own cases.
- UI work → read `sops/ui-development-guardrails.md` first; tokens + components, zero inline styles.
- Design mockup → pixel-perfect → read `sops/mockup-implementation.md`; ask for the structured handoff, extract values (don't eyeball), verify by rendered-HTML diff.

## Spawning a sub-agent
- Only if work is parallelizable + **file sets disjoint**.
- Give it: the contract + its file set + the DoD.
- **Integrate BEFORE removing its worktree** (agents leave work uncommitted → lost otherwise).
- Verify its claims yourself.

## "Quality review" (on request / at milestones)
`git log --grep='^quality-review:' -1` = baseline → diff since → **4 axes** (code quality · tests+coverage · observability · **edge-case/abnormal-usage coverage** — "did we cover the unexpected?") → **lead + independent 2nd reviewer** → **lead judges** (accept / reject-with-reason / defer) → resolve → green → commit `quality-review:` (= new baseline).

## "Bug hunt" (on request — DIFFERENT from a quality review)
Owner names a **scope**. Hunt **defects only** unit-by-unit (function/procedure/UI/seam) through logic · edge-case families · hostile input (family I) · adversarial/security (authz/IDOR/replay/invariants). **NOT** logs/quality/coverage. **Per unit, invent even nastier cases → propose back** → approved ⇒ tests + catalog. Confirmed defect → `tickets/bug-register.md` (P0/P1 + escape analysis); security-hardening (not a defect) → `tickets/security.md` (`SEC`); **fix inline only if quick + in scope, else file the ticket**; map+report → `bug-hunt-log.md`; commit `bug-hunt:`.

## Where things go
| It's a… | Put it in |
|---------|-----------|
| in-flight *engineering* task this wave | `runner.md` |
| an action only the human can do | `tickets/user-actions.md` (`USER-##`) |
| a pending human decision | `tickets/decisions.md` (`DEC-##`) → record the outcome as an ADR |
| a feature that just became BLOCKED | `tickets/blocked-features.md` (`FEAT-##`, visibility only; closes on unblock) |
| doc work not doable inline | `tickets/doc-work.md` (`DOC-##`) |
| a business / go-to-market / admin action | `tickets/business.md` (`BIZ-##`) |
| a defect found anywhere (at discovery) | `tickets/bug-register.md` (`BUG`; P0–P3; P0/P1 → escape analysis) |
| a security-hardening item (not a live defect) | `tickets/security.md` (`SEC`) |
| a bug-hunt coverage map + report | `bug-hunt-log.md` |
| a new abnormal-usage / hostile-input pattern | a class in `sops/edge-case-catalog.md` |
| *engineering* bug/feature not yet scheduled | `backlog-tickets.md` |
| work punted by a constraint / an open question | `tbd-parking-lot.md` |
| owed test, blocked | `deferred-test-registry.md` |
| locked decision | `adr/` |
| capability that now exists | `feature-catalog.md` + a `use-case-runbook.md` story |
| external service | `third-party-services.md` |

> **Tickets vs engineering:** the `tickets/*` files are the human's **coordination** queue (replacing a project board — the *types* are the value). **Engineering work is never a ticket** — it lives in `ONBOARDING.md` + the ADR + `runner.md`/`backlog-tickets.md`. If a ticket and a doc disagree, the doc wins.

## Before you trust a gate (both steps, every time)

1. **Logic** — plant a violation, watch it go **red**, remove it, watch it go green, confirm the
   restore was byte-identical.
2. **Wiring** — trigger it **the way production does**: the real hook, the real runner, the real
   deploy command. Calling the script proves the script, and the script is not the part that breaks.

If you have not **seen a hook fire this session**, assume you do not have one — hook config loads at
session start and an unprotected session looks identical to a protected one. (`ci/control-timing.md`)

## Reading a multi-stage run (nightly sweep, security suite, e2e)

Read in this order, and stop at the first bad answer:

1. **The manifest** — what each stage *actually did*. It **outranks** the tools' own prose.
2. **The verdict** — `COMPLETE` or `INCOMPLETE`. INCOMPLETE means a stage never reached its target.
3. Only then, the findings.

**Never call an INCOMPLETE run clean, green, or passing**, however few findings it produced. Zero
findings from a stage that scanned nothing is not a pass. Report the gap **first**, in plain words:
*"the run did not actually test X"*. A `skipped` stage is an honest non-result — still not a pass, so
name what went uncovered. (`ci/run-integrity.md`)

## The perpendicular pass (after the unit-local test cases)

1. Name the **property** you verified — not the case.
2. Ask **where else** it must hold: every other resource, verb, entry point.
3. State what is **NOT** in your work list, in the report. An unstated gap reads as coverage.

The five questions: whose identity did you authorize vs **use** · what did the first step rely on that
the last step must **re-read** · who else can spend this **budget** · are you proving the **data** or
the status code · **what is missing**. (`sops/security-properties.md`)

## Non-negotiables
Destructive action → explain blast radius + get approval. Secrets never in chat/commits/logs/external models. The project **invariants** never break; the guardrail suite is never weakened.

## Platform layer (ci/platform-layer.md)

| You want | Run / do |
|---|---|
| Prove hooks are live | look for the ⚡ SESSION BRIEF banner at session start — no banner, no hooks |
| Verify the guard after editing it | `scripts/hook-pretooluse-guard-test.sh` (known-answer matrix) |
| Sweep every surface for a topic | `scripts/librarian-sweep.sh <term> <alias> …` (0 = evidence, ABSENT = could not look) |
| Delegate a corpus question | `/ask-librarian <topic>` — 5-part brief, require the sweep accounting table back |
| See if advisories are firing | `.gate-logs/stop-advisory.log`, `.gate-logs/read-budget.log`, `.gate-logs/compaction.log` |
| Add an area rule | `.claude/rules/<area>.md` with `paths:` frontmatter, ≤50 lines, pointer to the SOP |
