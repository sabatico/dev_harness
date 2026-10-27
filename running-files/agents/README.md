# Agent logs — what each agent run, review and claim produced

Three append-only logs, one JSON object per line. Scripts write them; nobody edits a line by hand.
The folder is `HARNESS_AGENT_DIR` in `harness.conf` (default `docs/agents`). In the kit's own repository
these files are empty templates; the kit logs its own reviews elsewhere, so no row ships to a new project.

| File | Written by | One row per |
|---|---|---|
| `runs.jsonl` | `scripts/log-agent-run.py` (the lead, at integration time) | agent run (model, role, task, outcome, tokens, minutes), judged review (`judgement`), confirmed model error or unproven claim (`correction`), machine problem that cost time (`infra`) |
| `reviews.jsonl` | `scripts/check-the-work.sh judge` (the sub-session, committed with its work) | judged check-the-work round: reviewer, label, verdict, each finding and its judgement |
| `criterion.jsonl` | `scripts/check-the-work.d/10-success-criterion.sh` (the `judge` hook) | branch that changed code and the files that judge it, with the declared authorship |

WHY they exist: without them nobody can see which model, brief or reviewer cost what or caught what.
The proof audit (`orchestrating-agents`, section 6) counts `correction` rows per model, so a tier that
reports "done" without proof shows up in numbers, not in memory. The review step's rules:
`ci/review-step.md`. The resilience hooks: `ci/session-resilience.md`.

Never put a secret, a token value or a device identifier in any row: these files are committed.
