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

## Non-negotiables
Destructive action → explain blast radius + get approval. Secrets never in chat/commits/logs/external models. The project **invariants** never break; the guardrail suite is never weakened.
