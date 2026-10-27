# Skill evaluations

One file per skill: `evals/<skill-name>.json` — a JSON array of **three** scenarios
(Anthropic Agent Skills best practices: build evaluations before extensive documentation).

```json
{"skills": ["hunting-bugs"], "query": "the task as the owner would phrase it", "files": [],
 "expected_behavior": ["observable behaviour 1", "observable behaviour 2", "observable behaviour 3"]}
```

**Built-in runner:** Claude Code's `claude plugin eval` runs a case with and without the skill
(several runs each) and grades it (docs: https://code.claude.com/docs/en/plugin-evals). It needs a
PLUGIN, so copy the skills (no symlinks) into a throwaway plugin outside the repo with
`evals/<case>/prompt.md` + `graders/*.md`. Always pass `--model` and `--judge-model` at or above your
floor tier (the default judge may be a smaller model), `--max-cost-usd` and `--no-publish`. Eval runs
load no `CLAUDE.md`, hooks or repo files, so grade opening behaviour and refusals. The judge stores
votes but no reasons: to learn why a grader failed, give the saved replies and the grader text to a
fresh agent. Field lesson (the first adopting project, hunting-bugs): most of a "failed" check was the
grader's wording and the judge's strictness, not the skill — write graders that default to PASS and
name exactly what FAILs, and keep the cases and graders so a rerun is reproducible.

**How to run one by hand:** give a fresh agent the scenario's `query` with
the skill available, then grade each `expected_behavior` line PASS / FAIL against what it did.
Run the same scenario with **Sonnet and Opus** — the models the harness actually uses. A skill that
works for Opus may under-specify for Sonnet. **Haiku is banned from the dev process** (owner
decision), so it is not a test target; the Anthropic guide's advice to also test Haiku is
deliberately not followed here.
Record results in `evals/RESULTS.md` (date, model, scenario, per-line verdicts) and fix the skill
when a line fails; re-run until it passes. `scripts/check-skills.sh` checks structure only — it
cannot tell whether a skill actually changes behaviour; these scenarios do.
