# SOP — Bug Hunt (the defect-only adversarial sweep)

**Trigger:** the owner says **"bug hunt"** and names the **scope** (the whole codebase, a directory,
a feature, a diff). The scope is always given at invocation — there is no implicit baseline.

**What it is:** a function-by-function, procedure-by-procedure, screen-by-screen, seam-by-seam
**hunt for defects** through the edge-case / hostile-input / adversarial lenses, with a mandatory
duty per unit to **invent even nastier cases and propose them back**.

**What it is NOT (out of scope on purpose):** log/observability coverage · code quality/tuning
(duplication, naming, structure, dead code) · coverage percentages · refactoring. Those belong to
`quality-review.md` — a *different* exercise. If a hunter trips over one, ONE line in a "parked for
quality review" list, then keep hunting.

**Why separate from a quality review:** a quality review makes good code better (editorial). A bug
hunt assumes the code is **guilty until proven innocent** (adversarial). Mixing them dilutes both.

## 1. Scope → hunt units (write the coverage map FIRST)
Decompose the named scope into **hunt units** and list them before hunting — a hunt is only credible
if its own coverage is provable:
- **Backend:** one unit per exported function / handler / procedure.
- **UI:** one unit per screen / flow / interaction (a modal, a wizard step, a picker each count).
- **Data:** one unit per field family that crosses a trust boundary (every user-entered field,
  every upload, every client-supplied value).
- **Seams get their own units** — bugs cluster at boundaries: client↔server contract, module↔module,
  service↔service, app↔worker, webhook intake, schema/migration edges, serialization.

Each unit ends with a verdict: **CLEAN / FINDINGS(n) / NOT-HUNTED** — and NOT-HUNTED is stated out
loud in the report, never silently dropped.

**A whole-codebase hunt runs in waves ordered by blast radius** — define the order for *this* project
(e.g. ① anything touching the invariants → ② auth/session → ③ money/irreversible actions → ④ core
data CRUD → ⑤ admin/privileged → ⑥ the rest of the UI → ⑦ static/config/scripts). Record the wave
map in `running-files/bug-hunt-log.md` so a multi-session hunt resumes where it stopped.

**Overweight where bugs live:** the newest code, the least-tested code, units with prior bug history,
state machines, anything touching money/irreversible actions, and every seam.

## 2. The per-unit lens stack (run ALL on EVERY unit)
1. **Logic & correctness** — off-by-one, inverted comparisons, swallowed errors, wrong state
   transition, nil/undefined paths, integer/rounding edges, TOCTOU + races, missing idempotency,
   broken atomicity (crash between step 1 and 2), resource leaks, unchecked returns.
2. **Unexpected user behavior** — the `edge-case-catalog.md` families A–H against this unit
   (back/forward, refresh/close mid-flow, double-submit, act-then-exit, rapid open/close, concurrent
   clients, mid-action state/permission shifts, replay, and the server-side mirrors).
3. **Input data — catalog family I, special weight** — wrong-but-plausible, injection, bad metadata,
   character families + Unicode end-to-end, **normalization before every match/uniqueness compare** —
   every field this unit reads, client AND server.
4. **Adversarial / security** — per entry point: who can call this? (authorization + **IDOR**:
   another actor's IDs in the path/body), authn bypass, missing rate limit, replay, enumeration
   oracles (response/timing differences), info leaks in errors, secrets in logs/responses, and the
   **invariant boundaries** (could any path here break one?).
5. **UI-specific** (screen/flow units) — UI-state vs server-state desync (UI claims a success the
   server rejected), the **multi-width review** (full/half/one-third), focus/keyboard traps, stale
   props after optimistic updates, error states that dead-end the user.

## 3. The INVENT-NASTIER duty (mandatory per unit)
The catalog is the floor, not the ceiling. **Before leaving any unit**, explicitly ask:
*"what EVEN NASTIER, more unexpected thing could a user do HERE — or what WRONGER data could arrive
HERE?"* — cases the catalog does not have yet.
- Each invented case is **tried or traced** (does the code survive it?).
- Survivors and non-survivors go to the report's **"proposed additional cases"** list → owner/lead
  ruling (approve/reject **with a reason**) → **approved ⇒ a regression test is written** (by a
  different author/model than the code) **⇒ generalizable ⇒ folded into `edge-case-catalog.md`** as
  a new class. This is how each hunt makes the harness permanently smarter.

## 4. Verify before you report (no noise)
- Every finding is **CONFIRMED** (reproduced: a failing test, a real-driver walk, or an exact traced
  path with concrete inputs → wrong outcome) or **SUSPECTED** (plausible, not yet reproduced — say
  WHY: missing sandbox, blocked access, needs a live env).
- **Judge every finding before it reaches the report** — reject false positives with a reason (a
  second-pass reviewer over-flags; an "orphan" may have a caller outside the packet).
- Independent parallel hunters from **different models/vantage points** on the same wave catch
  different bugs — judge and merge.

## 5. Recording & response
- **Every confirmed bug → a `running-files/bug-register.md` row at discovery time** (severity ladder;
  an invariant breakage = top severity). The response ladder applies mid-hunt: **top-severity = stop
  hunting, fix now** (with a cross-author regression test + escape analysis); otherwise register +
  schedule and keep hunting.
- **"No bug, just untested" findings** → the proposed-tasks list, not the register.
- **Fixes during a hunt are minimal + scoped** (fix the defect, don't refactor); regression tests
  authored cross-family. Anything wider → parked for the quality review.

## 6. Report + close-out (per hunt session)
Append to `running-files/bug-hunt-log.md` (dated, newest first):
1. the **coverage map** (units: clean / findings / not-hunted — the remainder named as the next wave),
2. the **findings table**: `[sev] unit · defect · CONFIRMED/SUSPECTED · repro · register ID · fixed/scheduled`,
3. the **proposed additional cases** list (for owner/lead approval — §3),
4. the one-line **"parked for quality review"** list.
Then: register rows written, approved proposals folded (tests + catalog), escape analyses for any
top-severity finds (which phase let it in → what harness change stops the class), run the end-of-act
ritual, and **commit with a `bug-hunt:` prefix** (so a later delta hunt can scope "since the last
`bug-hunt:` commit").

## 7. Bug hunt vs quality review (don't blur them)
| | **Bug hunt** (this SOP) | **Quality review** (`quality-review.md`) |
|---|---|---|
| Trigger | "bug hunt" + a scope | "quality review" / a milestone |
| Scope | named (whole repo, feature, delta) | delta since the last `quality-review:` commit |
| Hunts for | defects: bugs, edge-case holes, hostile-input gaps, security | code quality, tests+coverage, observability, edge-case coverage |
| Ignores | style, logs, coverage %, refactors | (covers those) |
| Output | bug-register rows + proposed new cases + hunt log | findings table + `quality-review:` baseline commit |
| Posture | adversarial: assume the code is guilty | editorial: make the code better |

See also: `edge-case-catalog.md` · `test-and-coverage.md` (enrichment loop) ·
`running-files/bug-register.md` · `running-files/bug-hunt-log.md`.
