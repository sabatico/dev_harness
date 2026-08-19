# Bug Register — «PROJECT» — the ONE triaged list of every known defect

> **Ticket type `BUG`** in the coordination taxonomy (`README.md`) — but kept in its own
> long-standing file, since defects have their own severity ladder + escape-analysis loop.

> **The single home for defects**, with one severity ladder and the escape-analysis loop. Distinct
> from `backlog-tickets.md` (that's the *scheduling queue* for planned work; this is *every defect,
> logged at discovery, whoever found it*). A defect can be referenced from both, but it is triaged
> here.
>
> **Intake rule:** every bug found ANYWHERE — user report, walkthrough, test, quality review, bug
> hunt, security sweep, post-deploy — gets a row here **at discovery time**. Detail may live
> elsewhere (a hunt report, a test-result file); this table is the index that makes the set
> triageable. Fixed rows move to **Closed** (append-only) — never deleted; the history is the
> pattern-detector.

## Severity ladder (tune the examples to this project's invariants)
| Sev | Meaning | Response |
|---|---|---|
| **P0** | Breaks a **project invariant** (`CLAUDE.md`), loses data, blocks a core journey, or takes the product down. | Drop everything; fix or roll back now. **Escape analysis mandatory.** |
| **P1** | A main flow is broken or a security gate is bypassable, limited blast radius / workaround exists. | Fix next cycle at the latest. **Escape analysis mandatory.** |
| **P2** | A feature misbehaves in an edge case; the UX actively misleads; degraded but usable. | Scheduled this milestone/wave. |
| **P3** | Cosmetic, polish, minor annoyance. | Batch with the next touch of that surface. |

- Severity is set at triage and may change on reproduction — record the change.
- **Anything that can break an invariant is automatically P0**, however small the trigger looks.

## The escape-analysis loop (P0/P1 — mandatory; this is how the harness learns)
Every P0/P1 gets a 5-line escape analysis before its row closes:
1. **Which phase should have caught it?** (spec / build / test / review / gates / hunt)
2. **Why didn't it?** (missing edge-case class? checklist not instantiated? vacuous test? gate gap?)
3. **What gets patched so this CLASS can't escape again?** (an `edge-case-catalog.md` class, a
   checklist item, a review question, a gate/check, a lint rule)
4. **Patch applied?** — link the commit. *The analysis without the patch is worthless.*
5. **Regression test written?** — cross-author (a different model/agent than wrote the code).

The quality review checks this register: an open P0/P1 with no escape analysis is itself a finding.
Escaped bugs are the primary source of new `edge-case-catalog.md` classes.

## Open bugs
| ID | Sev | Found | Where/how found | Summary | Status | Detail |
|----|-----|-------|-----------------|---------|--------|--------|
| BUG-001 | «P?» | «date» | «who/how» | «one-line defect» | ☐ open | «link to repro / hunt report / ticket» |

## Closed bugs (append-only; escape analysis inline for P0/P1)
| ID | Sev | Found → Closed | Summary | Fix (commit) | **Verified by** (the test that went RED) | Escape analysis (P0/P1) |
|----|-----|----------------|---------|--------------|------------------------------------------|--------------------------|
| — | | | | | | |

> **"Verified by" is not optional, and it is not the same as "Fix".** *Fixed* is a claim; the only
> thing that makes it a result is a demonstration that the defect could be reproduced and now cannot.
> Name the **mutation** (what you broke or reverted to re-create it) and the **test that went red**
> under it. Without that, a closed bug is indistinguishable from a bug that merely **moved** — and a
> disappearing symptom is not a diagnosis. Gated by `scripts/check-bug-evidence.sh`.

See also: `sops/bug-hunt.md` (its finds land here) · `sops/edge-case-catalog.md` (escaped bugs seed
new classes) · `backlog-tickets.md` (scheduling queue) · `sops/quality-review.md` (checks this list).
