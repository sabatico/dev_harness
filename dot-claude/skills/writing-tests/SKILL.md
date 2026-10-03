---
name: writing-tests
description: Writes tests as the cross author for code it did not build — attacks the builder's edge-case checklist, invents nastier cases and proposes them for a ruling, asserts side-effect hooks at the call site, builds fixtures through the real write path, pairs every negative assertion with a positive control, watches each guard test fail before trusting it, measures coverage on the changed code, and registers any test it cannot write yet. Use when writing, reviewing or judging tests, when a brief names the test-author role, when coverage is measured, when a DEFERRED-TEST marker is added or resolved, or when a builder is tempted to test its own code.
---

# Writing tests (the cross author)

Load with `following-core-rules`. Canonical sources: `CLAUDE.md` (builder ≠ test author, coverage
is part of Done) and this skill's reference files; on conflict `CLAUDE.md` wins.

**First check: did you build the code under test?** Then stop — the builder writes ZERO tests for
its own code. Report it; the lead assigns another author. Why: the builder tests what it
*expected* to build; an independent author tests what the code *actually does*, and the delta is
where the bugs are.

## Workflow

Copy this checklist and tick it off:

```
Test progress:
- [ ] 1. Read the real code under test + the existing test exemplar from the brief
- [ ] 2. Read the builder's edge-case checklist; `covering-edge-cases` is the floor
- [ ] 3. Every `Handled` row → a test; cases the unit harness cannot see (back/forward,
        session restore, real timers/streams) → a real-driver test; untestable now → DEFERRED-TEST
- [ ] 4. INVENT NASTIER: propose your own extra cases (wronger data, nastier user actions)
- [ ] 5. Side-effect hooks: assert at the CALL SITE that the chain fires end-to-end,
        not just the hook body
- [ ] 6. Integrity pass on every test (T1–T6 below)
- [ ] 7. Bite-verify each guard test: break the guard, watch the NAMED test go red, restore
        byte-identically
- [ ] 8. Measure coverage on the new/changed code; hit «the target band»
- [ ] 9. Run the suite verbosely + the gates; red → fix → re-run
- [ ] 10. Report proposed cases for the lead to judge
```

- **No new test dependencies without approval** — assertion sugar is not worth a supply-chain entry.
- Attack, don't confirm: a test that only restates the implementation proves nothing.

## Integrity — a green suite that proves nothing (T1–T6)

Coverage answers "was this line executed?", never "was anything asserted?". Before reporting, each
test must pass all six:

- **T1** the fixture builds a state production CAN produce — seeded through the real write path.
- **T2** every "must not happen" assertion has a sibling proving the mechanism DOES happen.
- **T3** assertions on global, paged or counted results are scoped to the test's own data.
- **T4** no silent skip: results read verbosely; a skipped suite fails the gate.
- **T5** the guard was watched failing (bite-verify; mutation manifest for critical guards).
- **T6** a cross-authored suite received from elsewhere is JUDGED, not pasted.

Details, field cases and the exact rules: [reference/test-integrity.md](reference/test-integrity.md).

## Cross-authoring, coverage, deferral, the enrichment loop

The builder's allowed mechanical fixes, the author rotation, the coverage band and exemptions, the
`DEFERRED-TEST:` marker-and-registry procedure, the three phases that own edge-case coverage, the
tester-enrichment loop and the default test pyramid:
[reference/cross-authoring-and-coverage.md](reference/cross-authoring-and-coverage.md).

## Report

Tests written (and the checklist rows each covers) · coverage on changed code, measured · guards
bite-verified (which test went red) · deferred tests with their registry rows · **proposed extra
cases, each for an approve/reject ruling** · claims from the code or brief you found false.
