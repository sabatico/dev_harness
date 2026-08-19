# DEC tickets — pending user decisions — «PROJECT»

> **`DEC-##` — a decision only the human owner can make**, surfaced so it doesn't block silently.
> A `DEC` is not the decision's *home* — it's the *prompt*. **The decision itself is recorded where
> decisions live — an ADR** (context · decision · alternatives rejected · consequences) — and the
> `DEC` ticket links to that ADR and closes. This keeps the "why" auditable and stops the same
> question being re-argued later.
>
> **Written for the human, in plain language** (see `README.md`). A question too unformed to
> decide is a `TBD` (`../tbd-parking-lot.md`) until it ripens into a real choice.

**Status:** ☐ open · ✅ decided (→ ADR) · ✖ dropped

| ID | Title (the question) | Options (each + one honest consequence) | AI recommendation | Unblocks | Status → ADR |
|----|----------------------|-----------------------------------------|-------------------|----------|--------------|
| DEC-001 | «the question in one plain sentence» | «A — consequence · B — consequence · C — consequence» | «the AI's pick, marked as a recommendation» | «what proceeds once decided» | ☐ → «ADR-NNN when decided» |

## Rules
1. **Create at discovery** — the moment a build is blocked on a human choice, add a row (don't guess and proceed).
2. **Give real options** — each with ONE honest consequence line; link a deeper analysis doc if the trade-off is subtle. Mark the AI's recommendation *as* a recommendation, not a foregone conclusion.
3. **Record the outcome as an ADR** — when the human decides, write/settle the ADR, put its number in the row, and close the ticket. The ADR is the durable record; the ticket is just the pointer.
4. **A blocked feature waiting on a `DEC`** gets its own `FEAT` visibility ticket (`blocked-features.md`) pointing at this row.
5. **No secrets** in the question or options.

> **Distinct from `USER` (`user-actions.md`):** that's an action to take; this is a choice to make.
