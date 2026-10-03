# The per-unit lens stack

Run ALL six on EVERY hunt unit. Each lens sees a defect class the others miss.

1. **Logic and correctness** — off-by-one, inverted comparisons, swallowed errors, wrong state
   transition, nil/undefined paths, integer/rounding edges, TOCTOU + races, missing idempotency,
   broken atomicity (crash between step 1 and 2), resource leaks, unchecked returns.
2. **Unexpected user behaviour** — the `covering-edge-cases` catalog families A–H against this unit:
   back/forward, refresh/close mid-flow, double-submit, act-then-exit, rapid open/close, concurrent
   clients, mid-action state/permission shifts, replay, and the server-side mirrors.
3. **Input data — catalog family I, special weight** — wrong-but-plausible, injection, bad metadata,
   character families + Unicode end to end, **normalization before every match/uniqueness compare** —
   every field this unit reads, client AND server.
4. **Adversarial / security** — per entry point: who can call this? (authorization + **IDOR**: another
   actor's IDs in the path/body), authn bypass, missing rate limit, replay, enumeration oracles
   (response/timing differences), info leaks in errors, secrets in logs/responses, and the
   **invariant boundaries** (could any path here break one?).
5. **UI-specific** (screen/flow units) — UI state vs server state desync (the UI claims a success the
   server rejected), the multi-width review (full / half / one-third), focus/keyboard traps, stale
   props after optimistic updates, error states that dead-end the user.
6. **Wiring and reachability — correct code that is DISCONNECTED is a defect**, and no lens above sees
   it: every function can be individually right while the connection between them was deleted. Per
   unit:
   - (a) is it actually CALLED from a live path? Grep the callers; "believed live but orphaned" is a
     finding, not a quality nit;
   - (b) do its outbound side-effect hooks (notify / event emit / audit append / webhook fan-out)
     demonstrably fire on the happy path END TO END? Trace or test the chain, not the hook body;
   - (c) after any recent deletion or refactor near this unit, grep the deleted code for outbound
     calls and prove each one is re-fired on a surviving path.

   *WHY: a dead-code cleanup deleted the only caller of a "recipients notified" hook — every
   function stayed correct, users silently stopped being notified for a week, and nothing failed.*
