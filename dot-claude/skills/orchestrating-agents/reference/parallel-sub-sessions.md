# Parallel sub-sessions

A **sub-session** is a full agent session that the lead starts for one area of work (the desktop
app's start-session feature or an equivalent). It runs in its own git worktree on its own branch.
A **sub-agent** (a helper spawned inside a session) is smaller: it gets one brief and returns one
report. This file covers sub-sessions. Sub-agents stay under `SKILL.md` sections 1–6.

**Field case:** a project ran two waves of sub-sessions in one day, one per area (the server, each
client endpoint, the harness), each in its own worktree branch. In an earlier wave two agents had
shared one checkout and one scratch file name, and one restored its backups over the other's real
files. Separate checkouts removed that class.

## Contents

- Lead: when to split, when to start, the brief
- The GOAL block and the duties
- Inside a sub-session
- What a sub-session never does
- Questions and open decisions
- Lead: integrate
- A dead sub-session
- Clean-up
- Time cap and the tracker

## Lead: when to split, when to start, the brief

| Rule | Why |
|---|---|
| **Split by AREA, one area per sub-session** (the server, each client endpoint, the harness), only where the file sets are **disjoint**. | Two sessions on one file collide, and the merge costs more than the parallel work saved. |
| **Each sub-session gets its OWN worktree and its own branch.** | A separate checkout has no shared working tree and no shared scratch files. This is the cure for the class in `shared-checkout.md`. |
| **Do not wait — up to the cap.** Start a new sub-session as soon as there is ready work for an area that no running sub-session touches, while fewer than `HARNESS_MAX_SESSIONS` (default 4) sessions or builder agents are working. | The owner's ruling: you do not need to wait for one to finish to start a new one, as long as the work is ready and does not affect the running ones. The cap came later (`docs/ci/token-budget.md` R5): past about four, the extra sessions only queued for the heavy-run lock and polled while they waited. |
| **Write the brief for a fresh context.** It holds: the slice · the decisions and files to read first · the model per the project's model policy («mid model» builds, «strong model» plans and judges) · the exact files it may edit · the checks to run · the Definition of Done · the report format. | The sub-session has no memory of the lead's session. A missing item becomes a guess. Build the brief with the checklist in `SKILL.md` section 3. |

## The GOAL block and the duties

Every sub-session brief opens with a GOAL block, in exactly this shape:

```
GOAL:  what done looks like, in one sentence
PROOF: each command whose raw result line the FINAL report must quote (a test or gate summary,
       `git log --oneline -1`)
LIMIT: turns, hours or money
```

WHY (the owner of the first adopting project): "at every sub session run - the main agent should set
a goal. And a check the work step at end of every sub session, but before comits. An adversary model
should check it and report back, then subsession analyze and if need be improve". Use your own GOAL
block, not a built-in goal command whose judge is a model below your floor tier.

The brief also names these duties:

| Duty | How | WHY |
|---|---|---|
| **Check the work before the commit** | Save the GOAL block to a file. Run `scripts/check-the-work.sh run --goal <file> --summary <file>`, judge every finding (`judge`: FIXED / REJECTED with why / DEFERRED to a named home), fix what is real, commit the judged review row with the work. At most 3 rounds; at the cap ask the lead. | A self-reported "done" reached the lead unchecked; a bug hunt then found six top-severity defects in "done" work. Details: `docs/ci/review-step.md`. |
| **Keep the state record** | `scripts/session-state.sh init --goal <file>`, then `step` / `gate` / `question` at each step. | A session that dies (usage limit, app restart) loses its context; the record lets a fresh session resume (`docs/ci/session-resilience.md` S1). |
| **Heavy runs through the queue** | `scripts/heavy-run.sh -- <command>`, never a bare lock. | A plain lock is not first-come-first-served; one session waited two hours while later jobs went first (S4). |
| **The FINAL report contract** | The first line of every message and turn-end summary is exactly `FINAL — DONE`, `INTERIM` or `QUESTION`. A FINAL report has the fields `COMMITS:` · `GATES:` (raw lines) · `BUGS:` · `DEFERRED:` · `QUESTIONS:`; check it with `scripts/check-the-work.d/20-report-contract.sh --file <it>`. | A finished session went unnoticed; a report without its proof cannot be judged (S2). |
| **Judging files declared** | Before `check-the-work.sh run`, append `scripts/check-the-work.d/10-success-criterion.sh scan --section` to the summary; before `judge`, answer a flag with `10-success-criterion.sh answer --text "<who wrote the tests and why nothing was weakened>"`. | A session that changes both the code and what judges it can redefine success (S3). |
| **Log every agent it runs** | `scripts/log-agent-run.py`, the usage block pasted whole; itself at the end (role `lead`). | Without the numbers nobody can see which model or brief cost what (`SKILL.md` section 6). |
| **Context budget** | `following-core-rules` rule 12 and brief item 13. | `docs/ci/token-budget.md`. |

## Inside a sub-session

- **The builder writes zero tests.** It spawns ONE test-author sub-agent of a DIFFERENT model. WHY:
  the builder must not grade its own work (`writing-tests`).
- **Every test is watched red** against a temporary mutation of the code under test. Then the
  mutation is restored byte-identically (check with `git diff`). WHY: a test that never failed
  proves nothing.
- **Scratch files go in a folder named for the task**, never a fixed shared name. WHY: fixed names
  collide even across worktrees when a path is shared (for example a system temp folder).
- **Never run a script you did not write.** WHY: a script found in the tree can do more than its
  name says, and the sub-session cannot check it.
- **Stop each helper agent (TaskStop) when its report is in.** WHY: a finished helper that stays
  listed as running hides what is really still working.

## What a sub-session never does

| Never | Why |
|---|---|
| Run the full gate set. It runs only its own area's checks. | The full set is slow and reads the whole tree. The lead runs it once, after the merges. |
| Commit anywhere except its own branch. Never push. | One pusher (the lead) keeps the push gate's receipt valid and the history in order. |
| Edit the shared running files: status doc, tracker, ticket registers, catalogs, dashboards, decision records. | Every sub-session editing the same files means a merge conflict on each branch. Instead, its final report **lists the changes those files need**. The lead applies them. |

## Questions and open decisions

- A sub-session that lacks a **product decision** asks the lead. It sends a **main proposal and a
  backup proposal** and does not guess. WHY: a guess on a product rule ships as a silent decision.
- **The lead checks in with every running sub-session** for open questions, so each has all the
  answers and inputs it needs. The lead answers from the records (quoted, not recalled) or takes
  the question to the owner. Resume the same sub-session with the answer — never start a new one
  for it.

## Lead: integrate

Do these in order, per sub-session, as its final report arrives:

```
Integration checklist (sub-sessions):
- [ ] A `FINAL` note is handled in the SAME turn: read the full report. It is a report, not ground
      truth.
- [ ] `scripts/check-the-work.sh verify --branch <its branch>`: exit 1 = the review was skipped or
      is over the round cap without the lead's yes → send it back, do not merge. A REJECTED finding is
      the sub-session's judgement, not proof: read the logged rejections.
- [ ] `scripts/check-the-work.d/20-report-contract.sh --file <its FINAL report>`: exit 1 = a field is
      missing or a commit does not exist → send it back.
- [ ] `CTW_BRANCH=<its branch> scripts/check-the-work.d/10-success-criterion.sh verify`, and READ the
      flag: the branch changed code and what judges it; rule on the answer (who wrote the tests,
      anything weakened?) before the merge.
- [ ] Verify each claim: re-run the area's tests on the main branch; watch the result.
- [ ] Merge the branch with `git merge --no-ff`. On a conflict, keep BOTH sides.
- [ ] Apply the running-file changes the report listed (status, tracker, registers, catalogs).
- [ ] File the sub-session's findings as tickets, per the project's ticket rules.
- [ ] After ALL merges of the wave: run the FULL gate set ONCE, then push through the
      project's push gate.
```

WHY `--no-ff`: the merge commit keeps each sub-session's work as one visible unit that can be
reverted whole. WHY the gate set once: it is slow and reads the whole tree, and only the merged
tree is what ships.

## A dead sub-session

A sub-session can stop without a FINAL report: a usage limit, an app restart, a crash.

- Run `scripts/resume-brief.sh <its worktree> --reason "<why it stopped>"` and start a fresh session
  with that brief in the SAME worktree. The brief holds the goal, the steps (done and doing), the last
  raw gate lines, the open questions and the git facts; the new session first re-checks the newest
  done step's proof.
- **At most 2 resumes** (`HARNESS_RESUME_CAP`). Past the cap the script prints the best partial result
  and a stop reason: merge what is proven and re-plan the rest. WHY: in a published study of
  multi-agent self-supervision, retries past two bought luck, not progress
  (`docs/ci/session-resilience.md`).

## Clean-up

The owner's ruling: delete your sub-sessions when they are done. After a branch is merged and
checked:

- **Delete the sub-session.** Its work is on the main branch; an old session is only noise.
- **Stop every finished helper agent**, so the task list never shows finished work as running.
- **Stop everything a task started:** containers, simulators, daemons, servers, browser tabs.
  A read-only leftover check helps. The source project had a small script that lists spun-up jobs
  and leaves them alone. The kit has no scripts area for it; write the equivalent for the stack
  (list containers, simulators and listening ports; kill nothing). Killing a leftover the owner
  did not start still needs the standing destructive-action approval rule in `CLAUDE.md`.
- Remove the worktree only after its branch is merged (`SKILL.md` section 6: integrate before
  removal).

## Time cap and the tracker

- **A long reviewer call has a total cap of 10 minutes, retries included.** WHY: a hung reviewer
  holds the whole wave. At the cap, stop the call and report the review as not completed.
- **The tracker records each wave and its sub-sessions** (`runner.md`): the area, the branch, the
  state (running / merged / deleted) and the report's date. WHY: after a context reset, the tracker
  is the only record of which sub-session owned which area.
