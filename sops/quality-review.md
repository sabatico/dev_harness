# SOP — Code Quality Review

**Trigger:** the owner says "code quality review" / "quality review" (or at a milestone).
**Goal:** catch what the build sessions missed — across quality, tests, observability, edge-case/abnormal-usage coverage, and doc-claim truth — with an independent second opinion, and leave a clean, green, auditable baseline.

## The baseline
The review scope is **everything changed since the last quality-review commit.**
```
git log --grep='^quality-review:' -1   # = the baseline commit
git diff --stat <baseline>..HEAD -- <production code globs>   # = the scope
```
Exclude generated code, vendored deps, and the bootstrap entrypoint. Focus on production code; the changed tests are inputs to axis 2, not the subject of axis 1.

## The 5 axes
**Axis 1 — Code quality.** Duplication, dead/orphaned code, missed or incomplete wiring, logical bugs, resource leaks (handles, streams, listeners, object URLs, connections), state that can get stuck, error/edge paths, race conditions, security smells.

**Axis 2 — Tests & coverage.** Which NEW behaviors lack a test? **Measure** coverage on the changed code; is it in the target band? Are the tests meaningful (assert behavior, not just execute lines)?

**Axis 3 — Observability.** Are meaningful outcomes logged/traced (so prod issues are diagnosable)? Conversely, does anything log a **secret or sensitive value**? Is any "log the raw error" actually leaking data?

**Axis 4 — Edge-case & unexpected-behavior coverage.** Ask, per functionality in the diff, verbatim: **"did we cover all the unexpected gaps and abnormal-usage scenarios of this functionality?"** Walk `sops/edge-case-catalog.md` against each new/changed flow — Back→Forward through gated steps, refresh/close mid-flow, double-submit, act-then-instantly-exit, rapid open/close, concurrent clients, mid-action lock/expiry/entitlement shifts, replay, and the server-side idempotency mirrors — **with special weight on INPUT DATA (family I):** wrong-but-plausible values, injection/attacking data, bad metadata, unexpected character families, Unicode + normalization (normalize before any match/uniqueness compare), on every new/changed field, client AND server. Expect the builder's **instantiated checklist** (Handled / N/A-why / DEFERRED) plus the tester's **reviewed enrichment proposals**; a missing checklist or an unhandled applicable class is a finding. Anything that can break a **project invariant** is hard-gate, not a suggestion.


**Axis 5 — Claims-vs-code truth audit (⚠ WHOLE running-docs scope, NOT diff-scoped).** Prose claims rot on their own clock, independent of the code diff: a status doc saying "X is still to do" when X shipped weeks ago, a backlog ticket for an already-built feature, "blocked by Y" where Y resolved, a hand-typed count that fell behind. None of the code axes can see this — so this axis reads the DOCS. Walk a **generated claim checklist** (a small script that greps the running files for the claim patterns: "still to do" / "not built" / "blocked by" / "in progress" / non-terminal ADR statuses / hand-typed counts) and verify **every** line against the code — grep/inventory, not memory — or fix the doc. For each "blocked by Y": is Y actually still unresolved? A resolved blocker gets unblocked NOW. Auto-verify the countables (see the generated-facts-block pattern in `ci/gates.md`) so counts can't drift at all. Convention: never quote a stale-claim literal in prose the checker reads (it self-flags). The report counts claims verified / fixed / findings.

## The process (lead + independent second reviewer)
1. **Lead review (the strong model):** read the diff, produce findings per axis (axis 5 walks the claim checklist against the WHOLE running-doc set).
2. **Independent second review:** a **different model/agent** reviews the *same* diff independently (give it the diff + the code axes 1–4; if the diff is large, scope it to the highest-risk files — a flaky/empty return ⇒ retry focused, never skip silently).
3. **Lead judges every finding** (its own and the second reviewer's): **accept**, **reject (false flag — say why)**, or **defer (needs a missing harness → register it)**. The second reviewer often lacks full context and will raise non-issues; reject them explicitly. It will also catch real bugs the lead missed — that's the entire point.
4. **Resolve** the accepted findings. Builder-family edits are fine for fixes; new test coverage is authored by the cross-family role.
5. **Verify green:** build + full test suite + all gates.
5b. **Ticket the findings (`running-files/tickets/`):** a review finding does not live in the report alone. **Fix it inline if it's quick and in scope** (then the fix is its record) — **otherwise file it as a ticket at discovery:** a defect → `../tickets/bug-register.md` (`BUG`; every OPEN P0/P1 row must carry its **escape analysis** — which phase should have caught it → why not → what harness patch prevents the class → patch commit → cross-author regression test; a P0/P1 without one is itself a finding); a security-hardening/coverage item (not a live defect) → `../tickets/security.md` (`SEC`); an item needing the human → `../tickets/user-actions.md`/`decisions.md`; doc work → `../tickets/doc-work.md`. The review report then *points* at the tickets it opened. (This is also where the review's **security-sweep pass** sends its findings — see `ci/gates.md`.)
6. **Commit with the `quality-review:` prefix** + a body that lists *resolved*, *rejected (with reasons)*, and *deferred*. **That commit becomes the next baseline.**
7. **Run the end-of-act ritual** (update the running files).

## Why the second reviewer matters
The builder and the lead share blind spots (they reasoned their way into the code). An independent reviewer reasoning from the *artifact* catches the leak/edge/duplication they rationalized away. Cost: it raises false flags. The lead's **judging** step is what makes it net-positive — accept the real, reject the noise, on the record.
