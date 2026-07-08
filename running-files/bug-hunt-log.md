# Bug Hunt Log — «PROJECT» — coverage map + per-session reports

> The running record of every **bug hunt** (`sops/bug-hunt.md`): the persistent **coverage map** (so
> a whole-codebase hunt can span sessions and resume where it stopped) plus each session's dated
> report. Newest report first. Findings themselves live as rows in `bug-register.md` (this log points
> at them by ID); proposed new edge-cases live here until the owner/lead rules on them.

## Coverage map (whole-codebase hunt — waves by blast radius)
Status: ☐ not started · ◐ in progress · ✅ hunted. "Hunted" = every unit in the wave got the full
lens stack + the invent-nastier pass, with a verdict recorded. *(Define the waves for this project —
order by blast radius, invariants first.)*

| Wave | Scope | Status | Last hunted | Report |
|------|-------|--------|-------------|--------|
| ① | «anything touching the invariants» | ☐ | — | — |
| ② | «auth / session / access control» | ☐ | — | — |
| ③ | «money / irreversible actions» | ☐ | — | — |
| ④ | «core data CRUD» | ☐ | — | — |
| ⑤ | «admin / privileged surfaces» | ☐ | — | — |
| ⑥ | «the rest of the UI» | ☐ | — | — |
| ⑦ | «static / config / scripts / build» | ☐ | — | — |

## Proposed additional edge-cases awaiting owner/lead ruling
*(populated by the invent-nastier pass during a hunt; approved ones become cross-author tests + fold
into `sops/edge-case-catalog.md`; rejected ones stay here with the reason so they aren't re-proposed)*

| # | Unit | Proposed nasty case | Tried? outcome | Ruling |
|---|------|---------------------|----------------|--------|

## Reports (newest first)
*(the first report lands here when the owner invokes the first bug hunt)*

<!--
Report template:
### «date» — scope: «what the owner named»
- Coverage map: units clean / findings / NOT-HUNTED (name the remainder = next wave)
- Findings: | [sev] | unit | defect | CONFIRMED/SUSPECTED | repro | register ID | fixed/scheduled |
- Proposed additional cases: → table above
- Parked for quality review: «one-liners»
- Escape analyses for any P0/P1 (which phase let it in → harness patch)
-->
