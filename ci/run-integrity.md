# Run INTEGRITY — a multi-stage job that reports zero findings after scanning nothing

`gates.md` **G1** covers one gate refusing to report green over an empty scan. This file is the
generalisation to a **multi-stage job** — a nightly sweep, a security suite, a migration run, an
end-to-end pass — where the failure mode gets worse in a specific way: **the stages that worked
produce a confident, detailed, plausible report, and the stage that scanned nothing contributes
silence.** The report reads as clean because most of it is.

**The field case:** a nightly security run scored `PASS` for days on scanners pointed at their own
loopback address. They ran. They exited 0. They never touched the application. Nothing in the output
distinguished that from a genuinely clean scan, and every distinguishing fact — was the target
reachable, how long did the stage take, how many items did it examine — existed only inside the stage
that was lying.

You cannot fix this by reading findings more carefully. **The findings are correct.** There really
were zero. The missing information is whether anything was ever looked at, and only the job itself can
record that.

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

**The manifest is the run's record of truth, and it outranks the prose the tools printed.** When a
tool says "no issues found" and the manifest says `unreachable`, the manifest wins. Read it first —
before the summary, before the findings — every time.

## R2 · The status vocabulary, and why five words instead of pass/fail

| Status | Meaning | Counts as assurance? |
|---|---|---|
| `ok` | ran against a real target, found nothing wrong | yes |
| `findings` | ran against a real target, found something to triage | yes |
| `unreachable` | ran, but never reached its target | **no** → forces INCOMPLETE |
| `error` | broke | **no** → forces INCOMPLETE |
| `skipped` | honestly N/A, or a missing tool | **no** — but does not force INCOMPLETE |

`skipped` earns its own word because some stages are legitimately not applicable (a TLS check against
a plain-HTTP target). It is **never counted as a pass**, and the verdict lists every skip so the
report has to account for what went uncovered.

Two statuses that look similar and must not be merged: `skipped` is *"this correctly did not apply"*;
`unreachable` is *"this should have run and did not"*. Collapsing them into "skipped" is how a hole
becomes invisible.

## R3 · The run ends in a VERDICT, and INCOMPLETE is not a low finding count

```
VERDICT: COMPLETE   — every expected stage reached a real target.
VERDICT: INCOMPLETE — N stage(s) never reached a real target. This is NOT a clean result.
```

**Rules that make the verdict mean something:**

- **INCOMPLETE is reported FIRST**, above the findings, in the words *"the run did not actually test
  X"*. A report that leads with "0 high-severity findings" and mentions the broken stage in paragraph
  six has already misled the reader.
- **Never describe an INCOMPLETE run as clean, green, or passing** — no matter how few findings it
  produced. Zero findings from a stage that scanned nothing is not a pass.
- The verdict goes in the **run log / commit message**, so a later reader cannot mistake a hollow run
  for a good one. This matters more than it sounds: the natural summary of a mostly-working run is
  optimistic, and six months later only the summary survives.

## R4 · Declare the expected stages — a block that records ZERO rows is invisible

The subtlest failure in the whole pattern, and it was found by accident.

A stage block that calls `record()` **zero times** contributes nothing to the manifest. Its absence is
not an anomaly the verdict can see — the verdict iterates rows that exist. So the job reports
`COMPLETE` **as a structural constant**, and it will do so forever.

On the project this came from, two of four stage blocks had never called `record()` at all. Their
`COMPLETE` verdicts had been meaningless from the day the control was written, and this went unnoticed
because the *other* two blocks populated the manifest, so nothing looked empty.

**The fix is to declare the work list up front and check it at the end:**

```sh
manifest_expect code-scan dep-audit api-probe tls-check
...
# verdict step: any declared stage with no row at all → MISSING → INCOMPLETE
```

This is the same principle as G1 (assert the work list is non-empty), applied one level up: **assert
the stage list is fully accounted for**, not merely that each stage that spoke was happy.

## R5 · Prove the detector fires — every run, not once at authoring time

G7 says watch a new gate fail before trusting it. For a job whose entire output is a **zero**, that
one-time ritual is not enough, because the harness can break *later* and the zero looks identical.

**Build the positive control into the run itself, as a stage that runs first:**

```
stage                 status  detail
bola-selftest         ok      detector proven to fire (read + mutation detection both trip)
bola                  ok      cross-tenant isolation held (B cannot read/change A's objects)
```

The self-test deliberately triggers the condition the detector is supposed to catch, and the run
aborts if the detector stays quiet. Only then is the real stage's zero meaningful.

Without it, *"0 breaches found"* and *"the harness has been broken since March"* produce byte-identical
output. With it, they cannot.

Apply this to anything whose success condition is an absence: intrusion checks, leak scanners,
invariant monitors, alerting paths, "no regressions" suites.

## R6 · A run that is INCOMPLETE for the same reason twice is a ticket, not a note

A stage that goes `unreachable` once is an incident. The same stage `unreachable` on three consecutive
runs is a **control that has silently stopped protecting you**, and it needs a register row with a
severity, not a line in a report nobody diffs.

Rule: **the second consecutive INCOMPLETE for the same stage opens a ticket** in the security or bug
register, with the coverage that has been missing since the first occurrence named explicitly. On one
project this exact rule was the difference between "the authenticated scan has been down for eleven
days" being discovered and being discovered *eventually*.

---

## Reference implementation

`scripts/lib/manifest.sh` in this kit implements R1–R4 in ~90 lines of POSIX-ish bash:
`manifest_init`, `record`, `manifest_expect`, `manifest_verdict`, and `status_from_exit`. Source it
from any multi-stage job. R5 is per-domain and must be written for the detector you actually have.
