# SOP — Tests & Coverage Discipline

The principle: **the role that writes code does not write that code's tests**, coverage is **part of Done**, and a test you can't write yet is **deferred and registered**, never dropped.

## Cross-authored tests (don't grade your own homework)
- The **builder** (whatever model/agent wrote the implementation) writes **zero** tests for that implementation — not even one-liners.
- A **different model/agent** authors the tests (the "cross-family" author). Pick a rotation so the test author is reliably ≠ the builder, e.g.:
  - strong-model build → mid-model tests
  - mid-model build → other-model tests
- **Mechanical fixes by the builder are allowed** when integrating cross-authored tests: imports, formatting, fixing a wrong mock name, updating an expected literal to match a *deliberate* behavior change, harness params. **New test logic is not** — if the cross author is unavailable, leave `// TODO(cross-family-test): …` and register it; never write the assertion yourself.
- **Why:** the builder tests what it *expected* to build; an independent author tests what the code *actually does*. The delta is where the bugs are.

## Coverage is part of Done
- **Measure** coverage on the new/changed code each slice (not just a global number). Use the language's tool (`go test -coverprofile`, `vitest --coverage`, `pytest --cov`, etc.).
- Hit the **target band** (set per project, e.g. 80–100%; the top of the band for safety-critical code; a lower floor only where heavy mocking/fault-injection is genuinely required).
- Generated code + the `main()`/bootstrap are exempt.
- **CI enforces a per-layer floor** so coverage can't silently erode.

## Deferred tests (make the gap visible)
When a test genuinely can't be written yet (missing sandbox, unbuilt module, external dependency):
1. Tag the code site with a `DEFERRED-TEST: <what + why + the blocking dependency>` marker.
2. Add a row to `docs/deferred-test-registry.md` (site · what's owed · why deferred · the unblock dependency · how to test · target).
3. A CI check (`list-deferred-tests --check`) fails if a marker exists with no registry row.
4. **When the dependency lands, write the owed test in that same slice**, remove the marker, delete the row. (The "resurface rule" — the gap can't be quietly forgotten and rediscovered later.)

## Edge-case coverage is part of Done (not just line coverage)
Coverage % proves lines ran; it does NOT prove the flow survives abnormal use (back/forward,
refresh-mid-flow, double-submit, hostile input, a concurrent tab). That objective is owned at three
phases against `sops/edge-case-catalog.md`:
1. **Build:** the builder instantiates the catalog into a **feature-specific checklist** (every
   applicable class → Handled / N/A-why / DEFERRED), with special weight on input-data validity
   (catalog family I), and ships it with the change.
2. **Test:** the cross-author tester **attacks the checklist** — every `Handled` gets a test; cases
   the unit harness can't see (back/forward, session restore, real timers/streams) go to a
   real-driver test; untestable-yet cases become `DEFERRED-TEST:` rows, never dropped.
3. **Review:** quality-review **axis 4** asks "did we cover all the unexpected gaps and abnormal-usage
   scenarios?" A case that can break a **project invariant** is a hard gate, not a suggestion.

## The tester-enrichment loop (the tester is not limited to the given cases)
The cross-author tester must **propose its OWN additional edge/use cases** beyond the builder's
checklist and beyond the catalog — nastier user actions, wronger data, specific to this feature.
Then:
1. Proposals **come back for review** (lead/owner) — **approve or reject each with a reason.**
2. Every **approved** proposal gets its **test written in the same change** (by the cross author).
3. Anything that **generalizes** is **folded into `sops/edge-case-catalog.md`** as a new class, so
   every future feature inherits it.

This is also executed at hunt time by `sops/bug-hunt.md` (its invent-nastier duty).

## The test pyramid (default shape)
- Lots of fast **unit** tests (pure logic, mocked edges).
- Fewer **integration** tests (real DB/store/contract).
- A thin layer of **end-to-end / use-case** tests driven from `docs/use-case-runbook.md`.
- Plus the **guardrail suite** for the project invariants — owner-owned, never weakened.
