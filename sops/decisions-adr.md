# SOP — Decisions & ADRs

**Principle:** decisions of consequence are recorded once, locked, and never re-litigated. Hard/risky ones get an independent second opinion before they're locked.

## What warrants an ADR
Anything that is **expensive to reverse** or that **future work will depend on**: architecture, data model, a security/trust boundary, a key dependency or vendor, an API contract, a deployment locus. Routine, easily-reversible choices do **not** need one — don't bureaucratize.

## The ADR format (Nygard-style)
```
# ADR-NNN — <short title>
Status: Proposed | Accepted | Superseded by ADR-MMM   ·   Date   ·   Related: …
## Context      — the forces at play; what problem, what constraints.
## Decision     — what we're doing (imperative, specific).
## Alternatives rejected — the other real options + WHY each lost. (This is the most valuable part.)
## Consequences — what this makes easy, what it makes hard, follow-ups, risks accepted.
```
Keep an `../adr/README.md` index (number · title · status). Number monotonically; never reuse a number.

## The second-ideator rule (for hard/high-stakes decisions)
Before locking a consequential decision, the lead gets an **independent second opinion** from a *different* model/agent: frame the problem + the candidate options, have it argue for the best one and against the others. The lead stays the **judge** — it deliberates harder, incorporates what's right, and records the call (often *with* the rejected alternatives, so the reasoning survives).

Why: a single reasoner rationalizes toward its first instinct. A genuine debate surfaces the option it would have skipped and the failure mode it underweighted.

## Locking & re-opening
- Once **Accepted**, an ADR is **locked** — don't re-argue it in later sessions; build on it.
- To change a locked decision, write a **new** ADR that **supersedes** the old (status updated on both). The history stays legible.
- `CLAUDE.md` should say: *"Never re-litigate a locked decision."*
