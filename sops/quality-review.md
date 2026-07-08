# SOP — Code Quality Review

**Trigger:** the owner says "code quality review" / "quality review" (or at a milestone).
**Goal:** catch what the build sessions missed — across quality, tests, observability, and edge-case/abnormal-usage coverage — with an independent second opinion, and leave a clean, green, auditable baseline.

## The baseline
The review scope is **everything changed since the last quality-review commit.**
```
git log --grep='^quality-review:' -1   # = the baseline commit
git diff --stat <baseline>..HEAD -- <production code globs>   # = the scope
```
Exclude generated code, vendored deps, and the bootstrap entrypoint. Focus on production code; the changed tests are inputs to axis 2, not the subject of axis 1.

## The 4 axes
**Axis 1 — Code quality.** Duplication, dead/orphaned code, missed or incomplete wiring, logical bugs, resource leaks (handles, streams, listeners, object URLs, connections), state that can get stuck, error/edge paths, race conditions, security smells.

**Axis 2 — Tests & coverage.** Which NEW behaviors lack a test? **Measure** coverage on the changed code; is it in the target band? Are the tests meaningful (assert behavior, not just execute lines)?

**Axis 3 — Observability.** Are meaningful outcomes logged/traced (so prod issues are diagnosable)? Conversely, does anything log a **secret or sensitive value**? Is any "log the raw error" actually leaking data?

**Axis 4 — Edge-case & unexpected-behavior coverage.** Ask, per functionality in the diff, verbatim: **"did we cover all the unexpected gaps and abnormal-usage scenarios of this functionality?"** Walk `sops/edge-case-catalog.md` against each new/changed flow — Back→Forward through gated steps, refresh/close mid-flow, double-submit, act-then-instantly-exit, rapid open/close, concurrent clients, mid-action lock/expiry/entitlement shifts, replay, and the server-side idempotency mirrors — **with special weight on INPUT DATA (family I):** wrong-but-plausible values, injection/attacking data, bad metadata, unexpected character families, Unicode + normalization (normalize before any match/uniqueness compare), on every new/changed field, client AND server. Expect the builder's **instantiated checklist** (Handled / N/A-why / DEFERRED) plus the tester's **reviewed enrichment proposals**; a missing checklist or an unhandled applicable class is a finding. Anything that can break a **project invariant** is hard-gate, not a suggestion.

## The process (lead + independent second reviewer)
1. **Lead review (the strong model):** read the diff, produce findings per axis.
2. **Independent second review:** a **different model/agent** reviews the *same* diff independently (give it the diff + the 4 axes; if the diff is large, scope it to the highest-risk files — a flaky/empty return ⇒ retry focused, never skip silently).
3. **Lead judges every finding** (its own and the second reviewer's): **accept**, **reject (false flag — say why)**, or **defer (needs a missing harness → register it)**. The second reviewer often lacks full context and will raise non-issues; reject them explicitly. It will also catch real bugs the lead missed — that's the entire point.
4. **Resolve** the accepted findings. Builder-family edits are fine for fixes; new test coverage is authored by the cross-family role.
5. **Verify green:** build + full test suite + all gates.
5b. **Bug-register check (`running-files/bug-register.md`):** any bug found during this review gets a register row; every OPEN P0/P1 row must carry its **escape analysis** (which phase should have caught it → why not → what harness patch prevents the class → patch commit → cross-author regression test). A P0/P1 without one is itself a finding.
6. **Commit with the `quality-review:` prefix** + a body that lists *resolved*, *rejected (with reasons)*, and *deferred*. **That commit becomes the next baseline.**
7. **Run the end-of-act ritual** (update the running files).

## Why the second reviewer matters
The builder and the lead share blind spots (they reasoned their way into the code). An independent reviewer reasoning from the *artifact* catches the leak/edge/duplication they rationalized away. Cost: it raises false flags. The lead's **judging** step is what makes it net-positive — accept the real, reject the noise, on the record.
