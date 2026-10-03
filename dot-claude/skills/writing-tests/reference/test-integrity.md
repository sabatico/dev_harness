# Test integrity — a green suite that proves nothing

## Contents
- T1 · A fixture must build a state production can produce
- T2 · A negative control is not optional
- T3 · Global, paged or counted results
- T4 · A silent skip is not a pass
- T5 · Bite-verify
- T6 · Judge a cross-authored suite
- History

Coverage answers *"was this line executed?"* — never *"was anything asserted about it?"*. Each
class below is a way a suite stays green while protecting nothing; each was seen in practice.

## T1 · A fixture must build a state PRODUCTION CAN PRODUCE

The most expensive test defect: it fails in the safest-looking direction — the suite passes, against
a world that does not exist. Three instances from one project, one shape:
- fixtures wrote rows with a column combination the real write path can never produce — every
  test using them exercised an impossible state, and one permanently broke an unrelated query;
- tests passed a **share index** where production passes a **person id**, so a join of the two
  could never match — the feature would have refused every request while the suite stayed green;
- a fixture inserted an approval row directly instead of going through the approval path, so the
  join production depends on was never exercised.

**Rules:**
- **Seed through the real write path** (the store/service function), not raw inserts — unless the
  test is specifically about a state the API cannot produce, and then say so in a comment.
- When a fixture bridges two identifier spaces, **write down which is which**. A column named
  `owner_id` that holds an index is a permanent trap: name it, or rename the column.
- A test that needs an impossible state **constructs it explicitly and loudly**, so the next reader
  sees it is deliberate.

## T2 · A negative control is not optional

An assertion that something is *absent* proves nothing unless the mechanism is also shown to
produce a *present*: "the sweep did not return X" is satisfied both by "X was correctly excluded"
and by "the sweep was broken and returned nothing".

Every "must not happen" test needs a sibling showing the same machinery **does** happen for a case
that should. In one project the negative control was the half that broke — the positive assertion
kept passing, and without the control the test would have proved nothing indefinitely.

## T3 · A test that reads a GLOBAL, PAGED or COUNTED result is correct only while the data is small

A `LIMIT 100` query, a global count, "page 0 contains my row" — fine on a fresh database, rotting
as the system fills. The failure lands on whoever touched the tree last and looks like flakiness in
a test they never opened.

- **Scope every assertion to the test's OWN data** — filter by its ids, or exhaust the query in
  batches rather than trusting the first page.
- **Prove it with a volume soak:** a gate that seeds N hundred unrelated rows and re-runs the
  suite. The soak catches this class before a colleague does.

## T4 · A silent skip is not a pass

A suite that skips when an environment variable is absent prints `ok` and exits 0.
- **Read results verbosely** in the gates (`-v` or equivalent) — a bare `ok` hides a skipped file.
- **A gate must fail on a skipped suite**, or the skipped tests are made runnable. A test that
  *cannot* run anywhere is tracked as an explicit registered gap, exactly like a deferred test.

## T5 · Bite-verify: watch the guard FAIL before you trust the test

A passing test is not evidence the guard works. **Remove the guard, watch a NAMED test go red,
restore byte-identically.** Both properties matter: the failure names the specific test, and the
restore is verified identical, not assumed.

Scale it with a **mutation manifest** — a short list of security-critical guards, each with the
edit that removes it and the test that must notice — run as a gate. **Beware the instrument:** a
mutation tester once reported guards as protected when the fault was in the tester (a "mutation"
that was a logical no-op; an anchor mangled by escaping). A mutation that cannot be *applied*
proves nothing while looking like it ran — check for stale anchors explicitly.

## T6 · Judge a cross-authored suite; never apply it blind

Cross-authoring works only if the receiving side **judges** what comes back. An adversarial author
is confidently wrong at a predictable rate — in one project three of a suite's claims failed on
inspection: a factual error about the language's own standard library (asserted twice, on
different days), two new dependencies added for assertion sugar, and a call to a function that did
not exist.

**Keep the cases, not necessarily the scaffolding:** the *case list* is where an independent mind
pays for itself. Take the cases, write them against the real fixtures, and **record each rejected
claim with its reason**, so the next reader knows the suite was judged rather than pasted.

## History

- Formerly the "Test INTEGRITY" half of the tests-and-coverage SOP (`test-and-coverage.md`).
