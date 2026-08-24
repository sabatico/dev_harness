---
paths:
  - "**/*_test.go"
  - "**/*.test.ts"
  - "**/*.test.tsx"
  - "**/*.spec.ts"
---

# Writing or changing tests (auto-loaded — TAILOR ME: point at your test-authoring SOP)

1. **You are the OTHER role — try to BREAK it.** A vacuous green is worse than no test.
2. **A test cites the decision record whose property it pins** — a test whose reason is unrecorded
   gets deleted by the next person who finds it inconvenient.
3. **A test that WRITES leaves shared state as it found it** — cleanup helpers, one line, cascades.
4. **A skip may state a missing PRECONDITION, never absorb an ERROR** — `if err != nil { skip }`
   converts "my query is wrong" into green, and both print `ok`.
5. **Watch a guard test FAIL before trusting it**: break it, see red, restore byte-identically.
6. **Seed through the real write path** — a raw INSERT in a test is a claim the API cannot reach
   that state; if you must, comment why.
7. **Drive UI tests through the real event pipeline** (userEvent-style helpers that await each
   input, never synchronous event dispatch): under CPU-starved suite runs, synchronously-dispatched
   input commits get read as empty by the next handler, and the resulting flake reads "slow
   machine" while being a lost event. Assert multi-hop flows PER HOP, so a red names the hop that
   died.
8. **A test with a shared, wall-clock-bounded credential or window will fail when the suite grows
   or a clock skews** — mint per test; measure ages on the clock that stamped them.
