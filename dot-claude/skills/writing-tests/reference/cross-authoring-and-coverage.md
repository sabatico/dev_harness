# Cross-authoring, coverage and deferred tests

## Contents
- Cross-authored tests
- Coverage is part of Done
- Deferred tests
- Edge-case coverage is part of Done
- The tester-enrichment loop
- The test pyramid
- History

The principle: **the role that writes code does not write that code's tests**, coverage is **part
of Done**, and a test that cannot be written yet is **deferred and registered**, never dropped.

## Cross-authored tests

- The **builder** (whatever model/agent wrote the implementation) writes **zero** tests for it —
  not even one-liners.
- A **different model/agent** authors the tests. Use a rotation so the test author is reliably
  ≠ the builder, e.g. strong-model build → mid-model tests; mid-model build → other-model tests.
  Who counts as "different" is configured (`HARNESS_SECOND_OPINION`, `scripts/second-opinion.sh`).
- **Mechanical fixes by the builder are allowed** when integrating cross-authored tests: imports,
  formatting, a wrong mock name, an expected literal updated for a *deliberate* behavior change,
  harness params. **New test logic is not.** If the cross author is unavailable, leave a
  `TODO(cross-family-test):` marker (in the language's comment syntax) and register it; never write
  the assertion yourself.
- **Why:** the builder tests what it *expected* to build; an independent author tests what the
  code *actually does*. The delta is where the bugs are.

## Coverage is part of Done

- **Measure** coverage on the new/changed code every slice, not only a global number. Use the
  language's tool — the stack pack proposes it as `HARNESS_COVERAGE_CMD`; confirm it against how
  the project actually builds, because a pack cannot know the layout or flags.
- Hit the **target band**, set per project («e.g. 80–100%»): the top of the band for
  safety-critical code; a lower floor only where heavy mocking or fault injection is genuinely
  required.
- Generated code and the `main()`/bootstrap are exempt.
- The gates enforce a **per-layer floor** so coverage cannot silently erode.

## Deferred tests

When a test genuinely cannot be written yet (missing sandbox, unbuilt module, external dependency):

1. Tag the code site `DEFERRED-TEST: <what + why + the blocking dependency>`.
2. Add a row to `docs/deferred-test-registry.md`: site · what is owed · why deferred ·
   the unblock dependency · how to test · target.
3. `scripts/check-markers.sh` fails if a marker exists with no registry row.
4. **Resurface rule:** when the dependency lands, write the owed test in that same slice, remove
   the marker, delete the row — the gap cannot be quietly forgotten and rediscovered later.

## Edge-case coverage is part of Done

Coverage % proves lines ran; it does NOT prove the flow survives abnormal use (back/forward,
refresh mid-flow, double-submit, hostile input, a concurrent tab). Three phases own it, against
the catalog in `covering-edge-cases`:

1. **Build:** the builder instantiates the catalog into a feature-specific checklist (every
   applicable class → Handled / N/A-why / DEFERRED), with special weight on input-data validity
   (family I), and ships it with the change.
2. **Test:** the cross author **attacks the checklist** — every `Handled` gets a test; cases the
   unit harness cannot see (back/forward, session restore, real timers/streams) go to a
   real-driver test; untestable-yet cases become `DEFERRED-TEST:` rows, never dropped.
3. **Review:** the quality review's axis 4 (`reviewing-code-quality`) asks "did we cover all the
   unexpected gaps and abnormal-usage scenarios?". A case that can break a **project invariant**
   is a hard gate, not a suggestion.

## The tester-enrichment loop

The cross author must **propose its OWN additional cases** beyond the builder's checklist and
beyond the catalog — nastier user actions, wronger data, specific to this feature. Then:

1. Proposals come back for review (lead/owner) — **approve or reject each, with a reason.**
2. Every approved proposal gets its test written **in the same change**, by the cross author.
3. Anything that **generalizes** is folded into the edge-case catalog as a new class, so every
   future feature inherits it.

The same invent-nastier duty runs at hunt time (`hunting-bugs`).

## The test pyramid

- Many fast **unit** tests (pure logic, mocked edges).
- Fewer **integration** tests (real DB/store/contract).
- A thin layer of **end-to-end / use-case** tests driven from `docs/use-case-runbook.md`.
- Plus the **guardrail suite** for the project invariants — owner-owned, never weakened.

## History

- Formerly the first half of the tests-and-coverage SOP (`test-and-coverage.md`); the "Test
  integrity" half moved to its own reference file in this skill.
