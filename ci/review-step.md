# The review step — check the work before the commit

Every sub-session ends with a review BEFORE it commits. `scripts/check-the-work.sh` sends the work,
with the GOAL block of its brief, to the configured second opinion. The sub-session judges each
finding FIXED, REJECTED (with why) or DEFERRED (to a named home), improves the work, and commits the
judged review in `reviews.jsonl` in `HARNESS_AGENT_DIR` (default `docs/agents`) with the work. The lead
runs `check-the-work.sh verify --branch <b>` before the merge. The script header is the detailed
contract; this file gives the WHY.

**Origin.** The owner of the first adopting project asked for it: "at every sub session run - the
main agent should set a goal. And a check the work step at end of every sub session, but before
comits. An adversary model should check it and report back, then subsession analyze and if need be
improve". Before the step, a sub-session's work met a second pair of eyes only when its brief asked
for one, and a bug hunt the day before found six top-severity defects in work reported "done".

## Contents

- The flow
- Who reviews
- The four rules that keep findings useful
- The hook point
- Measuring the reviewers (a method, not a script)
- What is NOT held

## The flow

```
brief GOAL block → work → session-state + gates
  → check-the-work.sh run --goal <file> --summary <file>     (round 1: the whole change)
  → judge --judgement <file>                                   (every finding: FIXED / REJECTED / DEFERRED)
  → fix, then run again if needed                              (round 2+: only the new change)
  → commit the work + the judged review row
lead: check-the-work.sh verify --branch <b> → merge
```

`run` builds the prompt: the GOAL block, the sub-session's own summary of what it did and claims,
the change list and the diff (implementation first, then tests, then data, so data is cut first
when the prompt is too big). The reviewer answers in a fixed shape (`scripts/lib/review-prompt-header.txt`):
a `VERDICT:` line, a `GOAL:` line (MET / NOT MET / CANNOT TELL) and one line per finding
`F<n> [P0–P3] [important|nit|pre-existing] <file:line> — defect — evidence — fix`.
`scripts/lib/review_tally.py` is the one parser: the judge and the vote read findings the same way.

## Who reviews

The reviewer is the configured second opinion (`scripts/second-opinion.sh`, `HARNESS_SECOND_OPINION`):

| Mode | Who | Label in the review row |
|---|---|---|
| `external` | the outside chain in `HARNESS_EXTERNAL_REVIEWERS`; each wrapper scans for secrets before it sends | the reviewer's name |
| `local` | no outside answer: the sub-session spawns the local reviewer agent (`HARNESS_LOCAL_REVIEWER`) with the prompt file the script wrote, then stores the answer with `record` | "same-family review" |
| `off` | a checklist self-review, stored with `record` | "self-review" |

No outside service is required. A missing key falls back to the local agent and the step still runs.

## The four rules that keep findings useful

**Why (the first adopting project's numbers):** across its first 20 judged reviews, 47 findings were
FIXED, 20 REJECTED and 1 DEFERRED — about 3 findings in 10 were noise. There was no limit on rounds,
and every round sent the whole diff again. The practices below follow published advice from a team
that reviews code with models at scale: past incidents as an eval set, several independent reviewers,
findings sorted by kind, and few rounds.

| Rule | What the script does | Why |
|---|---|---|
| **Tags** | A `nit` needs no judgement and is logged under `nits`. A `pre-existing` finding is REJECTED, or FIXED/DEFERRED with its register row id (`HARNESS_BUG_PREFIX`-nnn or `SEC-nnn`) in the reason; `judge` refuses an id that is not a row of a register. An untagged finding counts as `important`. **A P0 or P1 finding is never a nit**, whatever its tag: it must be judged. | A defect that was there before is real work, but not this change's work: it goes to the register. Nits break nothing. A severe finding mis-tagged as a nit would skip the judgement. |
| **Round cap** | At most `CHECK_THE_WORK_MAX_ROUNDS` (default 3) judged rounds per branch. The next round stops with exit 1; only the lead's yes, quoted with `--lead-ok "<words>"`, opens one more, and the words are logged. `verify` re-checks with the LEAD's cap, so raising the cap in the sub-session's environment does not get round it. | Work that needs many rounds has a goal or an approach problem; more rounds of the same reviewer add noise, not proof. |
| **Delta rounds** | Round 2 and later show only the change since the tree the previous reviewer saw, plus the earlier findings and their judgements, plus in full any file the previous reviewer did not see (cut for size). A round with no change is refused. | The reviewer checks the fixes, does not raise a judged finding twice, and a cut file cannot stay unreviewed for good. |
| **Vote (optional, off)** | `HARNESS_REVIEW_VOTE=on`: the voters in `HARNESS_REVIEW_VOTERS` answer in parallel after ONE pre-send secret scan (`HARNESS_REVIEW_SCAN`; no scan command configured = nothing is sent); the local agent can be one more voter (`record`). A finding is kept only when 2 voters name the same file within a few lines; the rest are logged UNCONFIRMED and need no judgement. | Two independent model families seldom invent the same wrong finding. Off by default because each round then makes several paid outside calls: the owner approves the spend. |

The vote counts agreement mechanically (same file, nearby lines); no model decides whether two
findings agree, so the count cannot be talked into a result. Its limit: the same defect named at two
places far apart does not agree, and a finding with no file never agrees.

## The hook point

Other checks plug in without new lines in `check-the-work.sh`: every executable
`scripts/check-the-work.d/*.sh` runs, in name order, as `<hook> judge` (after the judgement is
accepted, before the row is written) and as `<hook> verify` (after "verify OK"). A non-zero exit
other than 4 ("not checked") stops the step and nothing is logged. A hook the step needs that is
missing or not executable makes the step exit 3 — a missing control is never a pass. The kit ships
two hooks (`ci/session-resilience.md`): `10-success-criterion.sh` (S3) and
`20-report-contract.sh` (S2). The files the hooks write (`reviews.jsonl`, `criterion.jsonl`) are never
part of the reviewed work, so writing them does not mark a review "changed after the review".

## Measuring the reviewers (a method, not a script)

The first adopting project built a **reviewer test set**: 20–30 confirmed P0/P1 rows of its own bug
register, each with the commit that ADDED the defective lines, plus about 5 clean changes. A scorer
sends each commit's diff to a reviewer under the review step's own instructions and counts: caught
(a finding names the defect's file and a nearby line), false alarm (any non-nit finding on a clean
change), and no answer.

What it taught:

- **A mechanical match is an upper bound, not the score.** The first run counted 24 catches; the
  lead's judged reading found 20 (four "catches" matched a common word in a finding about another
  defect). Report only JUDGED scores: the lead writes a ruling per case.
- The local same-family reviewer caught 20 of 25 known defects and 13 of 16 top-severity ones, and
  raised 17 findings on the 5 clean changes — the noise the vote is meant to cut.
- **Keep a change to a reviewer, its prompt or the vote rule only when it does not lower the catch
  rate or raise the false alarms on the set.**

The kit does not ship that scorer: its value is the cases, and the cases are a project's own bugs.
Build the set when your register holds about 20 confirmed P0/P1 rows with a findable introducing
commit.

## What is NOT held

- **That a sub-session RUNS the step before its commit.** `verify` catches a skip only when the lead
  runs it at the merge. A commit-msg hook would hold it; that is hook wiring, owner-only.
- **That a REJECTED finding was rightly rejected.** The rejection is the sub-session's judgement, not
  proof; the lead reads the logged rejections.
