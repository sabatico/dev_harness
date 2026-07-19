# FEAT tickets — blocked features (VISIBILITY ONLY) — «PROJECT»

> **`FEAT-##` exists for exactly ONE reason: to make a blockage visible.** It is created the moment
> a feature **cannot proceed** — because it needs another feature, an ADR still awaiting acceptance,
> a `USER` or `DEC` action, or an external dependency — so the human can SEE what's stuck without
> reading ADRs. **It closes the moment it unblocks**, and the feature then proceeds the normal way
> (an ADR + `runner.md`), never through this ticket.
>
> **⚠ An UNBLOCKED feature NEVER gets a `FEAT` ticket.** Engineering work that is merely *to do* is
> not a ticket — it lives in `ONBOARDING.md` status + the owning ADR + `runner.md`/`backlog-tickets.md`.
> This file is only for work that is *blocked right now*.

**Status:** 🔒 blocked (the only open state) · ✅ unblocked (close it — the work moves to a runner)

| ID | Blocked feature (by path) | Blocked by | What unblocking looks like | Status |
|----|---------------------------|-----------|----------------------------|--------|
| FEAT-001 | «the feature/ADR, by path» | «FEAT-##/DEC-##/USER-##/an external dependency» | «the concrete thing that lifts the block» | 🔒 |

## Rules
1. **Create at blockage time** — the instant a feature becomes blocked, add a row. Not before (it wasn't blocked) and not "later" (the point is visibility *now*).
2. **Name the blocker precisely** — link the blocking ticket/ADR/dependency by ID or path, so the dependency arrow is real, not vague.
3. **Close at unblock time** — when the blocker lifts, close the row with a one-line note ("unblocked by …, work now in `runner.md`"). The feature does NOT get carried forward as a ticket.
4. **Never a build-ticket** — the body describes the *blockage*, not the implementation plan; the plan lives in the ADR/runner.

> **Distinct from `TBD` (`../tbd-parking-lot.md`):** a `TBD` is deferred *by our own choice* (a constraint we accept); a `FEAT` is blocked *involuntarily* by a dependency we're waiting on.
