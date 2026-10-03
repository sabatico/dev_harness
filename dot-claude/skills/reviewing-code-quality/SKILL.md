---
name: reviewing-code-quality
description: Runs the harness quality review — everything changed since the last quality-review commit, across five axes (code quality, tests and coverage, observability, edge-case and abnormal-usage coverage, and a whole-docs claims-vs-code truth audit), with an independent second reviewer whose findings the lead judges, findings ticketed, gates green, and a quality-review-prefixed baseline commit. Use when the owner says "quality review" or "code quality review", at a milestone, or before declaring a body of work clean. Not a bug hunt (defects in a named scope) — that is hunting-bugs.
---

# Reviewing code quality

**Goal:** catch what the build sessions missed and leave a clean, green, auditable baseline. Editorial
posture — make good code better. For an adversarial defect sweep of a named scope, use `hunting-bugs`.

## Workflow

Copy this checklist and tick it off:

```
Quality review progress:
- [ ] 1. Baseline + scope (commands below)
- [ ] 2. Lead review (the strong model): read the diff, findings per axis 1–5 (axis 5 over the WHOLE running-docs set)
- [ ] 3. Independent second review of the same diff (axes 1–4) by a different model/agent
- [ ] 4. Lead judges every finding: accept / reject (why) / defer (register the missing harness)
- [ ] 5. Resolve accepted findings; ticket every one not fixed inline
- [ ] 6. Verify: build + full tests + all gates green → if red, fix and re-run
- [ ] 7. Commit "quality-review: …" (resolved / rejected+reasons / deferred) = the next baseline
- [ ] 8. End-of-act: update the running files
```

**1 — Baseline and scope.** The scope is everything changed since the last quality-review commit.
Run exactly:

```
git log --grep='^quality-review:' -1                             # the baseline commit
git diff --stat <baseline>..HEAD -- «production code globs»      # the scope
```

Exclude generated code, vendored deps and the bootstrap entrypoint. Production code is the subject of
axis 1; the changed tests are inputs to axis 2.

**3 — The second reviewer is configured, never assumed.** Pipe the prompt (the diff + axes 1–4) into
`scripts/second-opinion.sh`; exit 3 means "use the local reviewer subagent" — spawn it and label its
output "same-family review". Record who actually reviewed. On a large diff, scope it to the
highest-risk files; a flaky or empty return ⇒ retry focused, never skip silently.

**4 — Judging.** The second reviewer lacks full context and will raise non-issues: reject them
explicitly, with the reason, on the record. It will also catch real bugs the lead missed — that is the
entire point. *WHY: the builder and the lead share blind spots (they reasoned their way into the
code); a reviewer reasoning from the artifact catches the leak, edge case or duplication they
rationalized away. The judging step is what makes its false flags net-positive.*

**5 — Resolve and ticket.** Builder-family edits are fine for fixes; new test coverage is authored by
the cross-family role (`writing-tests`). A finding never lives in the report alone: **fix it inline if
quick and in scope** (the fix is its record), otherwise file it at discovery under
`docs/tickets/`:
- a defect → `docs/tickets/bug-register.md` (`BUG`). Every OPEN P0/P1 row carries its
  **escape analysis** — which phase should have caught it → why it didn't → the harness patch that
  stops the class → the patch commit → the cross-author regression test. A P0/P1 without one is
  itself a finding;
- security hardening/coverage, not a live defect → `docs/tickets/security.md` (`SEC`);
- needs the owner → `docs/tickets/user-actions.md` or `docs/tickets/decisions.md`;
- doc work → `docs/tickets/doc-work.md`.

The review's security-sweep pass (`docs/ci/gates.md`, "The security sweep") routes its findings the same
way. The report then *points* at the tickets it opened.

**7 — Commit.** Prefix `quality-review:`; the body lists *resolved*, *rejected (with reasons)* and
*deferred*. That commit becomes the next baseline.

## The five axes

**Axis 1 — Code quality.** Duplication, dead/orphaned code, missed or incomplete wiring, logic bugs,
resource leaks (handles, streams, listeners, object URLs, connections), state that can get stuck,
error/edge paths, race conditions, security smells.

**Axis 2 — Tests and coverage.** Which NEW behaviours lack a test? **Measure** coverage on the changed
code — is it in the target band? Do the tests assert behaviour, not just execute lines?

**Axis 3 — Observability.** Are meaningful outcomes logged/traced so production issues are
diagnosable? Does anything log a secret or sensitive value? Is a "log the raw error" leaking data?

**Axis 4 — Edge-case and abnormal-usage coverage.** Per functionality in the diff, ask verbatim:
**"did we cover all the unexpected gaps and abnormal-usage scenarios of this functionality?"** Walk the
`covering-edge-cases` catalog against each new/changed flow — Back→Forward through gated steps,
refresh/close mid-flow, double-submit, act-then-instantly-exit, rapid open/close, concurrent clients,
mid-action lock/expiry/entitlement shifts, replay, and the server-side idempotency mirrors — with
**special weight on input data (family I)** on every new/changed field, client AND server:
wrong-but-plausible values, injection, bad metadata, unexpected character families, Unicode +
normalization before any match/uniqueness compare. Expect the builder's instantiated checklist
(Handled / N/A-why / DEFERRED) plus the test author's reviewed enrichment proposals; a missing
checklist or an unhandled applicable class is a finding. Anything that can break a project invariant
is hard-gate, not a suggestion.

**Axis 5 — Claims-vs-code truth audit (WHOLE running-docs scope, NOT diff-scoped).** Prose claims rot
on their own clock: "X is still to do" when X shipped weeks ago, a backlog ticket for a built feature,
"blocked by Y" where Y resolved, a hand-typed count that fell behind. No code axis can see this.
- Walk a **generated** claim checklist (a small script grepping the running files for "still to do" /
  "not built" / "blocked by" / "in progress" / non-terminal decision-record statuses / hand-typed
  counts — the claims-checker pattern in `docs/ci/gates.md`) and verify **every** line against the code by
  grep/inventory, never memory — or fix the doc.
- For each "blocked by Y": is Y still unresolved? A resolved blocker gets unblocked NOW.
- Auto-verify countables with the generated-facts-block pattern (`docs/ci/gates.md`) so counts cannot drift.
- Never quote a stale-claim literal in prose the checker reads — it self-flags.
- The report counts claims verified / fixed / findings.
