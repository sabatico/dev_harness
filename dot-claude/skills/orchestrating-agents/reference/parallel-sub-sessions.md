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
- Inside a sub-session
- What a sub-session never does
- Questions and open decisions
- Lead: integrate
- Clean-up
- Time cap and the tracker

## Lead: when to split, when to start, the brief

| Rule | Why |
|---|---|
| **Split by AREA, one area per sub-session** (the server, each client endpoint, the harness), only where the file sets are **disjoint**. | Two sessions on one file collide, and the merge costs more than the parallel work saved. |
| **Each sub-session gets its OWN worktree and its own branch.** | A separate checkout has no shared working tree and no shared scratch files. This is the cure for the class in `shared-checkout.md`. |
| **Do not wait.** Start a new sub-session as soon as there is ready work for an area that no running sub-session touches. | The owner's ruling: you do not need to wait for one to finish to start a new one, as long as the work is ready and does not affect the running ones. |
| **Write the brief for a fresh context.** It holds: the slice · the decisions and files to read first · the model per the project's model policy (by code area) · the exact files it may edit · the checks to run · the Definition of Done · the report format. | The sub-session has no memory of the lead's session. A missing item becomes a guess. Build the brief with the checklist in `SKILL.md` section 3. |

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
- [ ] Read the final report. It is a report, not ground truth.
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
