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

---

# Test INTEGRITY — a green suite that proves nothing

Coverage answers *"was this line executed?"* — never *"was anything asserted about it?"*. Everything
below is a way a suite stays green while protecting nothing, each seen in practice.

## T1 · A fixture must build a state PRODUCTION CAN PRODUCE

The most expensive test defect there is, because it fails in the safest-looking direction: the suite
passes, and it passes against a world that does not exist.

Three instances from one project, all the same shape:
- fixtures wrote rows with a column combination the real write path can never produce — every test
  using them exercised an impossible state, and one of them permanently broke an unrelated query;
- tests passed a **share index** where production passes a **person id**, so a query joining the two
  could never match — the feature would have refused every request while the suite stayed green;
- a fixture inserted an approval row directly instead of going through the approval path, so the
  join that production depends on was never exercised.

**Rules:**
- **Seed through the real write path** (the store/service function), not raw inserts, unless the test
  is specifically about a state the API cannot produce — and then say so in a comment.
- When a fixture bridges two identifier spaces, **write down which is which**. A column named
  `owner_id` that holds an index is a permanent trap; name it, or rename the column.
- If a test needs an impossible state, **construct it explicitly and loudly**, so the next reader sees
  it is deliberate.

## T2 · A negative control is not optional

An assertion that something is *absent* proves nothing unless you also show the mechanism can produce
a *present*. "The sweep did not return X" is satisfied both by "X was correctly excluded" and by "the
sweep was broken and returned nothing".

Every "must not happen" test needs a sibling showing the same machinery **does** happen for a case
that should. In one project the negative control was the half that broke — the positive assertion kept
passing, and without the control the test would have gone on proving nothing indefinitely.

## T3 · A test that reads a GLOBAL, PAGED or COUNTED result is correct only while the data is small

`SELECT ... LIMIT 100`, a global count, "page 0 contains my row" — all fine on a fresh database, all
rotting as the system fills. The eventual failure lands on whoever touched the tree last and looks
like flakiness in a test they never opened.

**Scope every assertion to the test's OWN data** — filter by its ids, or exhaust the query in batches
rather than trusting the first page. **Prove it with a volume soak**: a gate that seeds N hundred
unrelated rows and re-runs the suite. That soak is what catches this class before a colleague does.

## T4 · A silent skip is not a pass

A suite that skips when an environment variable is absent prints `ok` and exits 0. Two rules:
- **Read results verbosely** in CI (`-v` or equivalent) — a bare `ok` hides a skipped file.
- **A gate must fail on a skipped suite**, or make the skipped tests runnable. Track any test that
  *cannot* run anywhere as an explicit registered gap, exactly like a deferred test.

## T5 · Bite-verify: watch the guard FAIL before you trust the test

A passing test is not evidence the guard works. **Remove the guard, watch a NAMED test go red, restore
byte-identically.** Two properties make it real: the failure names the specific test, and the restore
is verified identical rather than assumed.

Scale it with a **mutation manifest** — a small list of security-critical guards, each with the edit
that removes it and the test that must notice. Run it as a gate. **Beware the instrument:** in one run,
a mutation tester reported guards as protected when the fault was in the tester (a "mutation" that was
a logical no-op, an anchor mangled by escaping). If a mutation cannot be *applied*, it proves nothing
while looking like it ran — check for stale anchors explicitly.

## T6 · Judge a cross-authored suite; never apply it blind

Cross-authoring (`Cross-authored tests`, above) works only if the receiving side **judges** what comes
back. An adversarial author is confidently wrong at a predictable rate — in one project, three of a
suite's claims failed on inspection: a factual error about the language's own standard library
(asserted twice, on different days), two new dependencies added for assertion sugar, and a call to a
function that did not exist.

**What to keep and what to drop:** the *case list* is usually the valuable part — it is where an
independent mind pays for itself. The *scaffolding* often is not. Take the cases, write them against
the real fixtures, and **record the rejected claims with the reason**, so the next reader knows the
suite was judged rather than pasted.
