---
name: recording-decisions
description: Records a decision of consequence as a decision record (ADR, Nygard-style — context, decision, alternatives rejected, consequences), gets an independent second opinion before locking a hard one, keeps the ADR index current, and changes a locked decision only by a new superseding ADR. Use when choosing architecture, a data model, a security or trust boundary, a key dependency or vendor, an API contract or a deployment locus; when the owner says "ADR", "decision record" or "write it up"; when a pending owner decision (DEC ticket) is answered; or when tempted to revisit an already-accepted decision.
---

# Recording decisions

**Principle:** decisions of consequence are recorded once, locked, and never re-litigated. Hard or
risky ones get an independent second opinion before they are locked.

## Does it warrant an ADR?

Yes, if it is **expensive to reverse** or **future work will depend on it**: architecture, data model,
a security/trust boundary, a key dependency or vendor, an API contract, a deployment locus.
No for routine, easily reversible choices (a helper's name, a CSS class) — don't bureaucratize.

## Workflow

Copy this checklist and tick it off:

```
Decision progress:
- [ ] 1. Read the ADR index (docs/adr/README.md): is this already decided?
         Accepted → build on it; to change it, go to "Re-opening" below — never re-argue in place
- [ ] 2. Hard/high-stakes? → second ideator: a different model/agent argues the options
- [ ] 3. Lead judges and drafts from docs/adr/ADR-template.md (Status: Proposed)
- [ ] 4. Check the draft: every real alternative has a "why it lost"; Decision is specific enough
         to build without re-deciding → fix and re-check until true
- [ ] 5. Next unused number; add the row (number · title · status) to the index
- [ ] 6. Accepted (by the owner where it is theirs to make) → locked; close any linked DEC ticket
```

**2 — The second-ideator rule.** Before locking a consequential decision, frame the problem and the
candidate options for an independent second opinion from a *different* model/agent
(`scripts/second-opinion.sh`; if it hands back to the local reviewer, label it same-family) and have
it argue for the best option and against the others. The lead stays the **judge**: deliberate harder,
incorporate what is right, and record the call with the rejected alternatives so the reasoning
survives. *WHY: a single reasoner rationalizes toward its first instinct; a genuine debate surfaces
the option it would have skipped and the failure mode it underweighted.*

## The format (Nygard-style)

```
# ADR-NNN — <short title>
Status: Proposed | Accepted | Superseded by ADR-MMM   ·   Date   ·   Related: …
## Context      — the forces at play; what problem, what constraints.
## Decision     — what we're doing (imperative, specific).
## Alternatives rejected — the other real options + WHY each lost. (The most valuable part.)
## Consequences — what this makes easy, what it makes hard, follow-ups, risks accepted.
```

The template in `docs/adr/ADR-template.md` is the fill-in copy. Keep the index
`docs/adr/README.md` (number · title · status). Number monotonically; **never reuse a number.**

## Locking and re-opening

- Once **Accepted**, an ADR is **locked** — later sessions build on it, never re-argue it.
- To change a locked decision, write a **new** ADR that **supersedes** the old one, updating the
  status on both. The history stays legible.
- The project's `CLAUDE.md` says: *"Never re-litigate a locked decision."*
