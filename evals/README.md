# Skill evaluations

One file per skill: `evals/<skill-name>.json` — a JSON array of **three** scenarios
(Anthropic Agent Skills best practices: build evaluations before extensive documentation).

```json
{"skills": ["hunting-bugs"], "query": "the task as the owner would phrase it", "files": [],
 "expected_behavior": ["observable behaviour 1", "observable behaviour 2", "observable behaviour 3"]}
```

**How to run one** (there is no built-in runner): give a fresh agent the scenario's `query` with
the skill available, then grade each `expected_behavior` line PASS / FAIL against what it did.
Run the same scenario with **Sonnet and Opus** — the models the harness actually uses. A skill that
works for Opus may under-specify for Sonnet. **Haiku is banned from the dev process** (owner
decision), so it is not a test target; the Anthropic guide's advice to also test Haiku is
deliberately not followed here.
Record results in `evals/RESULTS.md` (date, model, scenario, per-line verdicts) and fix the skill
when a line fails; re-run until it passes. `scripts/check-skills.sh` checks structure only — it
cannot tell whether a skill actually changes behaviour; these scenarios do.
