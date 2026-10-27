# Session resilience — a dead session, a starved queue and a moved goal

Many sub-sessions can run at once (the `orchestrating-agents` skill, section 8). This doc covers what
keeps that work safe when a session dies, when heavy runs queue up, and when one session changes both
the work and what judges it. The scripts are the law; this doc is the WHY and the map.

**Field case (the first adopting project).** Three sessions and agents died mid-task on a weekly
usage limit. Each lost its in-flight context: the goal, the done steps, the last test lines and the
open questions lived only in the dead conversation, so the lead re-briefed from memory. The same day
22 test jobs waited on one shared lock. A plain file lock is not first-come-first-served, so one
session waited two hours while later jobs went first; the 8-core machine ran at a load of about 28.

**Sources.** A published study of multi-agent self-supervision (MASS): output contracts and hop
order carried most of the gains; a validator after each phase recalls the named failed agent with a
failure trace, a narrowed scope and a fallback; retries are capped at 2; identical runs can win or
lose; and an episode that changed the meaning of success still got 5 of 6 favourable judgements. A
production checklist for agent graphs: objective, metric, reversibility, artifact contract,
provenance, budget, monitoring, recovery — and "return the best partial result with a stop reason".

## Contents

- S1 · A resumable state record per sub-session
- S2 · The FINAL report contract
- S3 · The success-criterion guard
- S4 · The fair heavy-run queue
- What is NOT held

---

## S1 · A resumable state record per sub-session

**Rule.** Every sub-session keeps `scripts/session-state.sh` current at each step: `init --goal` at
the start (the brief's GOAL block), `step add / doing / done`, `gate` (the raw last lines of each test
or gate run), `question`, `note`. The record is one file in the worktree's own git folder
(`git rev-parse --absolute-git-dir`): it is never committed, never shows as uncommitted work, and
outlives the session that wrote it.

**Recovery.** `scripts/resume-brief.sh <worktree> --reason "<why it stopped>"` turns the record and
the worktree's git facts into a brief for a fresh session: the goal as first given, the checklist
(the DOING step marked), the last raw gate lines, the questions, the commits and uncommitted files.
The scope narrows to the steps not done, and the new session first re-checks the newest done step's
proof. Text from the record is fenced as `<untrusted>` data: an agent wrote it.

**Cap.** At most 2 resumes (`HARNESS_RESUME_CAP`, the study's cap). Past the cap the script prints a
STOP summary of the best partial result and exits 1: the lead merges what is proven and re-plans the
rest. A third retry of the same work buys luck, not progress.

## S2 · The FINAL report contract

**Rule.** A FINAL report has five fixed fields (`scripts/lib/report-contract.sh`, the one copy):

| Field | Content | `none` allowed? |
|---|---|---|
| `COMMITS:` | each commit as `<sha> <subject>` | only as `none — <why>` |
| `GATES:` | the raw summary line of each gate or test run | only as `none — <why>` |
| `BUGS:` | the register ids filed or fixed | yes |
| `DEFERRED:` | what is left and where it is recorded | yes |
| `QUESTIONS:` | what the lead or the owner must answer | yes |

`STOP-REASON:` is optional: a best partial result says why it stopped short. The first line of every
sub-session message is exactly `FINAL — DONE`, `INTERIM` or `QUESTION`, so a finished session is
never missed.

**Held by.** `scripts/check-the-work.d/20-report-contract.sh --file <report>` REFUSES (exit 1) a
FINAL report that misses a field, or names a commit that is not in the repository. As a `verify` hook
of `scripts/check-the-work.sh` it finds the branch's FINAL report (`HARNESS_REPORT_DIR`). No report
found is "NOT CHECKED" (exit 4), printed loudly — but `check-the-work.sh verify` treats a hook's exit 4
as "not checked" and still exits 0, and `HARNESS_REPORT_DIR` is empty by default. So the contract is
held only when the lead runs the hook on the report (`--file`, as the merge checklist says) or sets
`HARNESS_REPORT_DIR`. INTERIM and QUESTION reports are not checked.

## S3 · The success-criterion guard

**Problem.** One session can change the code AND the tests, gates or goal text that decide whether
the code passes. The study saw an episode that redefined success still win 5 of 6 favourable
judgements; a reviewer that reads the new test against the new code finds them consistent.

**Rule.** `scripts/check-the-work.d/10-success-criterion.sh scan` lists every JUDGING file the branch
changed together with code (tests, fixtures and test data, gates and their baselines and allow-lists,
the deferred-test registry, these hooks, `CHECK_THE_WORK_JUDGE_GLOBS`) and a goal replaced in the
session-state record, with weakening signals: `LINES-REMOVED`, `DELETED`, `SKIP-MARKERS-ADDED:n`.
The sub-session appends `scan --section` to its review summary, so the reviewer checks each one, and
records its answer with `answer --text "<who wrote the judging files and why no criterion was
weakened>"`. As the `judge` hook it refuses a flagged branch with no answer, and logs the answer in
`criterion.jsonl` in `HARNESS_AGENT_DIR`, committed with the work. As the `verify` hook it prints the flag
and the answer for the lead, who rules, and fails a flagged branch with no answer row.

**Limit, stated plainly.** Git cannot tell which agent wrote a file: every commit of a session has one
author. So the guard flags EVERY branch that changes code and its judges, and the authorship is a
declaration the lead reads, not a proof. The "builder ≠ test author" row of `CLAUDE.md`'s
enforced-vs-unenforced table stays in the attention column.

## S4 · The fair heavy-run queue

**Rule.** Heavy runs (full suites, `run-all-gates.sh --all`, mutation batches) go through
`scripts/heavy-run.sh -- <command>`, never a bare lock.

**How.** Each caller takes a numbered ticket under a short lock, then may start when fewer than N live
tickets are ahead of it: the order is the ticket order. A ticket whose process is gone is dropped on
the next check, so a killed session never blocks the queue. While it waits, the run prints its
position when it changes and at least every few minutes. Each run appends a row to the wait-time log
(`HARNESS_HEAVY_LOG`): queued time, seconds waited, seconds run, exit code, slots, label. `--status`
shows the queue. The queue lives in the repository's common git folder by default
(`HARNESS_HEAVY_LOCK_DIR`), so every worktree of one repository shares it and nothing lands in the
tree.

**Slots.** N is `HARNESS_HEAVY_SLOTS` (default 1). Raise it only after measuring: on the field case's
machine, wider parallel runs only raised the load.

**Waiting is not polling.** A session that starts a heavy run starts it as one background command and
ends its turn (`ci/token-budget.md` R1); the queue does the waiting.

## What is NOT held

- **That a sub-session keeps its record.** Nothing forces `session-state.sh` calls; the brief asks for
  them (`orchestrating-agents` reference `parallel-sub-sessions.md`).
- **That heavy runs use the queue.** A bare lock still works and still bypasses the order. A hook that
  warns on one would hold it: hook wiring, owner-only.
- **Authorship.** See S3: a declaration, not a proof. A commit trailer per agent (for example
  `Tests-by: <agent>`) checked by a commit-msg hook would make it a record; owner-only.
- **Stall and loop detection.** The first adopting project also has a status view that flags a
  session with no new output for 30 minutes ("STALLED?") or the same failing gate three times
  ("LOOPING?"). The kit does not ship it yet: it reads the desktop app's session notes, which other
  launchers do not have.
