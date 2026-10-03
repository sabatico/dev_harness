---
name: hunting-bugs
description: Runs a defect-only adversarial bug hunt over the scope the owner names (whole codebase, a directory, a feature, a diff) — unit by unit (function, screen, field family, seam) through a six-lens stack (logic, abnormal usage, hostile input, security/authz/IDOR, UI desync, wiring/reachability), with a mandatory per-unit duty to invent nastier cases and propose them back for a ruling, findings registered at discovery, and a bug-hunt-prefixed commit. Use when the owner says "bug hunt", "hunt for bugs", or asks what defects exist in a named area. Not a quality review — style, logs, coverage % and refactors are out of scope.
---

# Hunting bugs

**Posture:** the code is guilty until proven innocent. A bug hunt is NOT a quality review
(`reviewing-code-quality` makes good code better; this finds defects) — mixing them dilutes both.

**Scope is always named by the owner** at invocation (whole codebase / directory / feature / diff);
there is no implicit baseline. A delta hunt scopes "since the last `bug-hunt:` commit".

**Out of scope on purpose:** log/observability coverage · code quality and tuning (duplication,
naming, structure, dead code) · coverage percentages · refactoring. Trip over one → ONE line in the
"parked for quality review" list, then keep hunting.

## Workflow

Copy this checklist and tick it off:

```
Bug hunt progress:
- [ ] 1. Coverage map FIRST: list every hunt unit (waves by blast radius for a whole-codebase hunt)
- [ ] 2. Per unit: all six lenses (reference/lens-stack.md)
- [ ] 3. Per unit: invent nastier cases → try or trace each → add to the proposals list
- [ ] 4. Per finding: CONFIRMED (repro) or SUSPECTED (why not reproduced); judge → reject false positives with a reason
- [ ] 5. Record at discovery: register row; top severity → STOP, fix now
- [ ] 6. Unit verdict: CLEAN / FINDINGS(n) / NOT-HUNTED → next unit (back to 2)
- [ ] 7. Report → docs/bug-hunt-log.md; fold approved proposals; commit "bug-hunt: …"
```

**1 — Hunt units.** A hunt is credible only if its own coverage is provable, so list the units
before hunting:
- **Backend:** one unit per exported function / handler / procedure.
- **UI:** one unit per screen / flow / interaction (a modal, a wizard step, a picker each count).
- **Data:** one unit per field family that crosses a trust boundary (every user-entered field,
  upload, client-supplied value).
- **Seams get their own units** — bugs cluster at boundaries: client↔server contract,
  module↔module, service↔service, app↔worker, webhook intake, schema/migration edges, serialization.

A whole-codebase hunt runs in **waves ordered by blast radius**, defined per project (e.g. ① anything
touching the invariants → ② auth/session → ③ money/irreversible actions → ④ core data CRUD →
⑤ admin/privileged → ⑥ the rest of the UI → ⑦ static/config/scripts). Record the wave map in
`docs/bug-hunt-log.md` so a multi-session hunt resumes where it stopped.

**Overweight where bugs live:** the newest code, the least-tested code, units with prior bug history,
state machines, anything touching money or irreversible actions, every seam — and areas of recent
deletion/refactor (a deletion orphans callers and hooks silently; the survivors all still compile).

**2 — The lens stack** (run ALL on EVERY unit; detail in [reference/lens-stack.md](reference/lens-stack.md)):
1 logic & correctness · 2 unexpected user behaviour (catalog families A–H) · 3 input data
(family I, special weight) · 4 adversarial/security incl. authz, IDOR and the invariant boundaries ·
5 UI-specific · 6 wiring & reachability — correct code that is disconnected is a defect.

**3 — Invent nastier (mandatory per unit).** The `covering-edge-cases` catalog is the floor, not the
ceiling. Before leaving any unit, ask: *"what EVEN NASTIER, more unexpected thing could a user do
HERE — or what WRONGER data could arrive HERE?"* Each invented case is tried or traced. Survivors and
non-survivors go to the **proposed additional cases** list → owner/lead ruling (approve/reject **with
a reason**) → approved ⇒ a regression test by a different author/model than the code ⇒ if
generalizable, folded into the `covering-edge-cases` catalog as a new class. This is how each hunt
makes the harness permanently smarter.

**4 — Verify before you report (no noise).** CONFIRMED = reproduced: a failing test, a real-driver
walk, or an exact traced path with concrete inputs → wrong outcome. SUSPECTED = plausible, not
reproduced — say WHY (missing sandbox, blocked access, needs a live env). Judge every finding before
it reaches the report: a second-pass reviewer over-flags; an "orphan" may have a caller outside the
packet. Independent parallel hunters from different models/vantage points on the same wave catch
different bugs — judge and merge.

**5 — Record and respond.**
- Every confirmed bug → a `docs/tickets/bug-register.md` row **at discovery** (severity
  ladder; an invariant breakage = top severity).
- **Top severity = stop hunting, fix now**, with a cross-author regression test + an escape analysis
  (which phase let it in → why → the harness change that stops the class). Otherwise register,
  schedule, keep hunting.
- A defect fixable inline quickly and in scope may be fixed in the same act — it still gets its row.
  Fixes are minimal and scoped (fix the defect, don't refactor); regression tests are authored
  cross-family (`writing-tests`). Anything wider → registered, or parked for the quality review.
- Security hardening that is NOT a live defect (a missing control, a coverage gap, an accepted
  scanner false positive) → `docs/tickets/security.md` (`SEC`). A security *defect* is a
  `BUG` (top severity if it risks an invariant).
- "No bug, just untested" → the proposed-tasks list, not the register.

**6 — Unit verdict.** Each unit ends with a verdict: **CLEAN / FINDINGS(n) / NOT-HUNTED** — and
NOT-HUNTED is stated out loud in the report, never silently dropped. Then the next unit.

**7 — Report and close-out.** Append to `docs/bug-hunt-log.md` (dated, newest first):
1. the **coverage map** — units clean / findings / not-hunted, the remainder named as the next wave
   (NOT-HUNTED is stated out loud, never silently dropped);
2. the **findings table**: `[sev] unit · defect · CONFIRMED/SUSPECTED · repro · register ID · fixed/scheduled`;
3. the **proposed additional cases** list (for the ruling in step 3);
4. the one-line **parked for quality review** list.

Then: register rows written, approved proposals folded (tests + catalog), escape analyses for any
top-severity finds, the end-of-act running-file update, and commit with a `bug-hunt:` prefix.

## Bug hunt vs quality review

| | Bug hunt (this skill) | Quality review (`reviewing-code-quality`) |
|---|---|---|
| Trigger | "bug hunt" + a scope | "quality review" / a milestone |
| Scope | named (whole repo, feature, delta) | delta since the last `quality-review:` commit |
| Hunts for | defects: bugs, edge-case holes, hostile-input gaps, security | code quality, tests+coverage, observability, edge-case coverage |
| Ignores | style, logs, coverage %, refactors | (covers those) |
| Output | register rows + proposed new cases + hunt log | findings table + `quality-review:` baseline commit |
| Posture | adversarial: assume the code is guilty | editorial: make the code better |

For one property across the whole surface (rather than units), add `hardening-security`'s
perpendicular pass.
