# TBD Parking Lot — Deliberately-Deferred Work — «PROJECT»

> **Ticket type `TBD`** in the coordination taxonomy (`tickets/README.md`) — kept in its own file.

> **Everything we consciously decided to develop *later* because of a constraint** — not forgotten, not unscheduled-by-accident, but **deferred on purpose** with a reason and a resurface trigger. The "we know, and here's why we're not doing it yet" list.
> **Distinct from `backlog-tickets.md`:** the backlog is "intend to do, just queued." This is "**blocked/punted by a specific constraint** — revisit when the constraint changes."
> **Distinct from `deferred-test-registry.md`:** that is specifically *owed test coverage*. This is *owed product/engineering work* of any kind.

Each item names **the constraint** (why now is wrong) and **the resurface trigger** (what flips it back into play) — so it can't rot silently and it comes back automatically when its blocker lifts.

| ID | Item | Why deferred (the constraint) | Resurface trigger | Code marker | Notes |
|----|------|-------------------------------|-------------------|-------------|-------|
| TBD-001 | «the work we punted» | «the dependency / decision / gate / cost / risk that makes now wrong» | «what must land/change to revisit» | `TBD: …` (if there's a code site) | «links» |

## Categories that commonly land here
- **Blocked on an external dependency** (a vendor sandbox, an unbuilt module, an approval, a license).
- **Blocked on a decision** (an ADR not yet made — cross-link the open question in ONBOARDING §5).
- **Gated by a milestone** (don't do X before the security/audit/perf gate).
- **Deliberate scope cuts** (a v1 simplification — "ship without per-item audience now, add with the People model").
- **Cost/risk punts** (worth doing, not worth the spend/risk yet).

## Rules
1. **A code site that's intentionally incomplete gets a `TBD:` marker** pointing here (optionally a CI check, like the deferred-test registry).
2. **When the resurface trigger fires, the item moves to `backlog-tickets.md`** (or straight into the active runner) — and the row is deleted here.
3. Review the triggers at each milestone so nothing stays parked past its constraint.
