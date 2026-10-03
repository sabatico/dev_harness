---
name: writing-code
description: Builds an implementation slice as a builder — reads the governing decision record and subsystem docs before touching code, records a decision first for new backend features, keeps migrations additive and reversible, regenerates generated code instead of hand-editing it, marks every deliberate gap with a registered marker, logs outcomes without secrets, ships the slice's edge-case checklist, writes ZERO tests for its own code, and runs the gates before reporting. Use when implementing or changing backend, library, script or service code, fixing a bug in code, or when a brief names the builder role; for screens and components use building-ui instead.
---

# Writing code (the builder)

Load with `following-core-rules`. Canonical sources: `CLAUDE.md` (standing rules, Definition of
Done), `CONVENTIONS.md` (code authoring), `docs/ci/gates.md`. On conflict they win and this skill is the
copy to fix.

## Workflow

Copy this checklist and tick it off:

```
Build progress:
- [ ] 1. Inventory: what already exists (catalog, grep, status doc) — reported first
- [ ] 2. Read before touch: the decision record + section each touched function cites, and the
        subsystem doc for every area touched (table below)
- [ ] 3. New backend feature? decision record FIRST (`recording-decisions`), before code
- [ ] 4. Edge-case checklist instantiated for the slice (`covering-edge-cases`)
- [ ] 5. Build, inside the agreed file set only
- [ ] 6. Gaps marked + registered; WHY comments updated
- [ ] 7. Verify: gates green (loop below)
- [ ] 8. Report: tests owed, checklist, evidence
```

## Rules while building

- **Read-before-touch pointers:** «subsystem → the doc to read first, e.g. auth → its decision
  record; integrations → `docs/third-party-services.md`». A function you touch names its
  governing decision record and section in its doc comment; read it before changing the function;
  when the body changes, re-read the comment and fix it or confirm it still holds. Comments say
  WHY, not what.
- **Generated code and contracts are regenerated, never hand-edited** — change the source of the
  generation and re-run «the codegen command».
- **Migrations are additive and reversible.** A structural change to stored data is agreed with
  the owner first (a decision record) and ships as its own small migration — never as a silent
  side effect of a code change.
- **Make the unfinished visible.** Every deliberate gap gets a marker + a registry row + the gate
  that pairs them (`docs/ci/gates.md`, marker-and-registry pattern): `DEFERRED-TEST:` →
  `docs/deferred-test-registry.md`; `TBD:` / `TBD-UI:` → `docs/tbd-parking-lot.md`;
  `STUB:«NAME»` → «the stub registry». `scripts/check-markers.sh` fails on a marker with no row.
- **Logging:** log meaningful outcomes and errors; never a secret, token, or raw personal data
  (`scripts/check-log-hygiene.sh` is a name-based floor, not a proof).
- **Dependencies are paid for** (supply chain, audit, maintenance) — none added to save a few
  lines; prefer the most-trained, least-surprising option.
- **Destructive or irreversible actions** follow `CLAUDE.md`: explain the blast radius and get
  owner approval first.

## Tests: owed, never written by you

- You write **ZERO tests** for your own code — not even one-liners. A different model/agent writes
  them (`writing-tests`). If no cross author is available, leave `TODO(cross-family-test):` at the
  site and list it; never write the assertion yourself.
- Allowed when integrating someone else's tests: mechanical fixes only (imports, formatting, a
  wrong mock name, an expected literal after a *deliberate* behavior change, harness params).
- Coverage on new/changed code must land in «the target band, e.g. 80–100%» once the cross author
  is done; a test that cannot be written yet is `DEFERRED-TEST:`-registered, never dropped.

## Verify (feedback loop)

Run exactly `scripts/run-all-gates.sh` (never piped; read the per-gate logs). Red → fix → re-run.
Report "done" only on a green run you watched; a skipped gate is not a pass.

## Report

State: what already existed; files changed (all inside the agreed set); the edge-case checklist
(each class Handled / N/A-why / DEFERRED); **the tests owed** — the cases the cross author must
cover and which checklist rows they fold into; markers added and their registry rows; the gate
output; discovered work for the lead to route.

## History

- Formerly the `skill-coding` skeleton in the agent-skills SOP; fleshed out from `CLAUDE.md`,
  `CONVENTIONS.md` and the tests-and-coverage rules.
