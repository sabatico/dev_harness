---
# ⚠ TAILOR THESE PATHS TO YOUR STACK — they are the whole trigger.
#
# A rule with paths that match nothing never loads, and nothing says so: you get a silent
# no-op that looks exactly like a rule being obeyed. Set them to your test files, then PROVE
# it by opening one and checking the rule loaded.
#
# Mirror your harness.conf stack pack's HARNESS_TEST_GLOBS. The shipped set below is a
# multi-ecosystem union so a fresh clone matches something; narrow it to your language.
paths:
  - "**/*_test.*"
  - "**/*.test.*"
  - "**/*.spec.*"
  - "**/test_*.*"
  - "**/tests/**"
  - "**/__tests__/**"
---

# Writing or changing tests (auto-loaded — TAILOR ME: point at your test-authoring SOP)

Language-neutral by design: every rule below is about what a test must PROVE, not about a
framework's syntax. Where a rule needs a concrete form, your stack pack already names it
(`HARNESS_SKIP_RE` is your runner's skip call; `HARNESS_TEST_CMD` is how the suite runs).

1. **You are the OTHER role — try to BREAK it.** A vacuous green is worse than no test.
2. **A test cites the decision record whose property it pins** — a test whose reason is unrecorded
   gets deleted by the next person who finds it inconvenient.
3. **A test that WRITES leaves shared state as it found it** — cleanup helpers, one line, cascades.
4. **A skip may state a missing PRECONDITION, never absorb an ERROR.** Skipping from an error
   branch converts "my query is wrong" into a pass, and both print the same word. Gated by
   `scripts/check-conditional-skips.sh`, which reads your runner's skip call from the stack pack.
5. **Watch a guard test FAIL before trusting it**: break it, see red, restore byte-identically.
6. **Seed through the real write path** — a direct store write in a test is a claim the API cannot
   reach that state; if you must, comment why.
7. **Drive UI tests through the real event pipeline** (helpers that await each input, never
   synchronous event dispatch): under CPU-starved suite runs, synchronously-dispatched input gets
   read as empty by the next handler, and the resulting flake reads "slow machine" while being a
   lost event. Assert multi-hop flows PER HOP, so a red names the hop that died.
8. **A test with a shared, wall-clock-bounded credential or window will fail when the suite grows
   or a clock skews** — mint per test; measure ages on the clock that stamped them.
