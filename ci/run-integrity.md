# Run INTEGRITY — a multi-stage job that reports zero findings after scanning nothing

`gates.md` **G1** covers one gate refusing to report green over an empty scan. This file generalises
it to a **multi-stage job** — a nightly sweep, security suite, migration run or end-to-end pass —
where the stages that worked produce a confident, detailed report and the stage that scanned nothing
contributes silence. The report reads as clean because most of it is.

**Field case:** a nightly security run scored `PASS` for days on scanners pointed at their own
loopback address. They ran, exited 0 and never touched the application. Every distinguishing fact —
was the target reachable, how long did the stage take, how many items did it examine — existed only
inside the stage that was lying. Reading findings more carefully cannot fix this: the findings are
correct (there really were zero). Only the job itself can record whether anything was looked at.

## Contents

- R1 · Every stage records what it actually did
- R2 · The status vocabulary
- R3 · The run ends in a verdict
- R4 · Declare the expected stages
- R5 · Prove the detector fires, every run
- R6 · The same INCOMPLETE twice is a ticket
- Reference implementation

---

## R1 · Every stage records what it ACTUALLY did — and the manifest outranks the tool output

Each stage writes one row to a machine-readable manifest as it completes:

```
stage                status       detail                                        evidence
code-scan            ok           412 files, 0 findings                         code-scan.log
dep-audit            findings     3 medium, 0 high                              dep-audit.json
api-probe            unreachable  target refused connection — NOTHING scanned   api-probe.log
tls-check            skipped      N/A: plain-HTTP target by design              -
```

**The manifest outranks the prose the tools printed.** When a tool says "no issues found" and the
manifest says `unreachable`, the manifest wins. Read it first — before the summary and the
findings — every time.

## R2 · The status vocabulary, and why five words instead of pass/fail

| Status | Meaning | Counts as assurance? |
|---|---|---|
| `ok` | ran against a real target, found nothing wrong | yes |
| `findings` | ran against a real target, found something to triage | yes |
| `unreachable` | ran, but never reached its target | **no** → forces INCOMPLETE |
| `error` | broke | **no** → forces INCOMPLETE |
| `skipped` | honestly N/A, or a missing tool | **no** — but does not force INCOMPLETE |

`skipped` is *"this correctly did not apply"* (a TLS check against a plain-HTTP target);
`unreachable` is *"this should have run and did not"*. Never merge them — collapsing them into
"skipped" is how a hole becomes invisible. `skipped` is never counted as a pass, and the verdict
lists every skip so the report accounts for what went uncovered.

## R3 · The run ends in a VERDICT, and INCOMPLETE is not a low finding count

```
VERDICT: COMPLETE   — every expected stage reached a real target.
VERDICT: INCOMPLETE — N stage(s) never reached a real target. This is NOT a clean result.
```

- **Report INCOMPLETE FIRST**, above the findings, as *"the run did not actually test X"*. A report
  that leads with "0 high-severity findings" and mentions the broken stage in paragraph six has
  already misled the reader.
- **Never describe an INCOMPLETE run as clean, green or passing**, however few findings it produced.
- Put the verdict in the **run log / commit message**: the natural summary of a mostly-working run
  is optimistic, and months later only the summary survives.

## R4 · Declare the expected stages — a block that records ZERO rows is invisible

A stage block that calls `record()` zero times contributes nothing to the manifest, and the verdict
iterates only rows that exist — so the job reports `COMPLETE` **as a structural constant**, forever.
On the source project two of four stage blocks had never called `record()`; their verdicts were
meaningless from day one, unnoticed because the other two blocks populated the manifest.

Declare the work list up front and check it at the end:

```sh
manifest_expect code-scan dep-audit api-probe tls-check
...
# verdict step: any declared stage with no row at all → MISSING → INCOMPLETE
```

This is G1 applied one level up: assert the stage list is fully accounted for, not merely that each
stage that spoke was happy.

## R5 · Prove the detector fires — every run, not once at authoring time

G7's one-time "watch a new gate fail" is not enough for a job whose entire output is a **zero**: the
harness can break *later* and the zero looks identical. Build the positive control into the run as
a stage that runs first:

```
stage                 status  detail
bola-selftest         ok      detector proven to fire (read + mutation detection both trip)
bola                  ok      cross-tenant isolation held (B cannot read/change A's objects)
```

The self-test deliberately triggers the condition the detector should catch; the run aborts if the
detector stays quiet. Only then is the real stage's zero meaningful. Without it, *"0 breaches found"*
and *"the harness has been broken since March"* produce byte-identical output.

Apply it to anything whose success condition is an absence: intrusion checks, leak scanners,
invariant monitors, alerting paths, "no regressions" suites.

## R6 · A run that is INCOMPLETE for the same reason twice is a ticket, not a note

One `unreachable` is an incident; three consecutive is a **control that has silently stopped
protecting you**. Rule: **the second consecutive INCOMPLETE for the same stage opens a ticket** in
the security or bug register, with a severity and the coverage missing since the first occurrence
named explicitly. On one project this rule was the difference between discovering "the authenticated
scan has been down for eleven days" on day two and discovering it *eventually*.

---

## Reference implementation

Run, do not rewrite: `scripts/lib/manifest.sh` implements R1–R4 in ~90 lines of POSIX-ish bash
(`manifest_init`, `record`, `manifest_expect`, `manifest_verdict`, `status_from_exit`). Source it from
any multi-stage job. R5 is per-domain and must be written for the detector you actually have.
