# Harness Cheat-Sheet (pin this)

## Every act ends with (mandatory, before yielding)
1. **Verify green** — build + full tests + all gates, *watched* not assumed.
2. **Update the running files** for anything that changed:
   - `ONBOARDING.md` (status + session-log line)
   - `runner.md` (flip statuses / add items)
   - `feature-catalog.md` (add/flip rows)
   - `use-case-runbook.md` (changed flows + new stories)
   - `backlog-tickets.md` / `tbd-parking-lot.md` / `third-party-services.md` (if touched)
   - `build-tracker.md`
3. **Commit** with a clear message.

## Building anything
- Smallest valuable slice. Decision of consequence → ADR first (don't re-litigate locked ones).
- **Builder ≠ test author.** Tests come from a different model/agent.
- Coverage to target, or `DEFERRED-TEST:` + register it.
- UI work → read `sops/ui-development-guardrails.md` first; tokens + components, zero inline styles.

## Spawning a sub-agent
- Only if work is parallelizable + **file sets disjoint**.
- Give it: the contract + its file set + the DoD.
- **Integrate BEFORE removing its worktree** (agents leave work uncommitted → lost otherwise).
- Verify its claims yourself.

## "Quality review" (on request / at milestones)
`git log --grep='^quality-review:' -1` = baseline → diff since → **3 axes** (code quality · tests+coverage · observability) → **lead + independent 2nd reviewer** → **lead judges** (accept / reject-with-reason / defer) → resolve → green → commit `quality-review:` (= new baseline).

## Where things go
| It's a… | Put it in |
|---------|-----------|
| in-flight task this wave | `runner.md` |
| bug/feature not yet scheduled | `backlog-tickets.md` |
| work punted by a constraint | `tbd-parking-lot.md` |
| owed test, blocked | `deferred-test-registry.md` |
| locked decision | `adr/` |
| capability that now exists | `feature-catalog.md` + a `use-case-runbook.md` story |
| external service | `third-party-services.md` |

## Non-negotiables
Destructive action → explain blast radius + get approval. Secrets never in chat/commits/logs/external models. The project **invariants** never break; the guardrail suite is never weakened.
