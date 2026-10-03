---
name: authoring-skills
description: Writes or revises a harness skill (a .claude/skills/«name»/SKILL.md) and the rule files around it, following Anthropic's Agent Skills best practices adapted to this harness. Use when creating a new skill, turning a procedure or rule document into a skill, editing any SKILL.md, agent or rule file, or when scripts/check-skills.sh fails.
---

# Authoring skills

The source standard is Anthropic's "Skill authoring best practices"
(platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices). This file is the
harness's working subset; on conflict, the source wins.

## Workflow

Copy this checklist and tick it off:

```
Skill progress:
- [ ] 1. Gap: write the 3 eval scenarios first (evals/<name>.json) — what fails without the skill?
- [ ] 2. Frontmatter: name + description (rules below)
- [ ] 3. Body: the procedure as a checklist; detail moved to reference/ files
- [ ] 4. Validate: scripts/check-skills.sh — fix every finding, re-run until clean
- [ ] 5. Links: scripts/check-doc-links.sh and scripts/check-doc-paths.sh clean
- [ ] 6. Try it: run one eval scenario with a fresh agent; fix what it missed
```

## Frontmatter

- `name`: lowercase letters, digits, hyphens; ≤ 64 chars; **gerund form** (`hunting-bugs`,
  `writing-tests`) — every skill in this harness uses it; no `claude` / `anthropic`; no XML tags.
- `description`: ≤ 1024 chars, non-empty, no XML tags, **third person** ("Runs…", "Writes…" — never
  "I…" / "You…"). Say WHAT it does, then "Use when …" with the concrete triggers (the owner's
  words, the file types, the task types). This line is all an agent sees before choosing the skill.
- Claude Code extras are allowed when needed: `argument-hint`, `allowed-tools`, `context: fork`,
  `agent`, `disable-model-invocation`, `model`.

## Body

- **Concise.** The reader is a capable model: no tutorials, no restating what it knows. Every
  paragraph must earn its tokens. Keep the body under 500 lines; aim far lower.
- **Workflow as a copyable checklist**, with a **feedback loop** wherever quality matters:
  run the validator → fix → re-run; proceed only when clean.
- **Degrees of freedom match the risk:** exact commands for fragile or destructive steps
  ("run exactly …"); heuristics where judgment is the point.
- **One default, one escape hatch** — never a menu of equal options.
- **Progressive disclosure:** long tables, catalogs and rationale go to `reference/<topic>.md`
  inside the skill folder, linked **directly from SKILL.md** (one level deep — a reference file
  never sends the reader to another reference file). Reference files over 100 lines open with a
  `## Contents` list.
- **Scripts:** say whether to RUN them or READ them; prefer running. Scripts handle their own
  errors and justify their constants.
- **Timeless wording:** no "as of <date>" or "since last month" in instructions. Dated history and
  provenance go in a `## History` section at the end (or a reference file).
- **One term per concept** across all skills (see the glossary below). Forward slashes in paths.

## Harness conventions

- A skill that governs other docs names its **canonical source**; on conflict the canonical doc
  wins and the skill is the copy to fix.
- Project-specific values stay as `«placeholders»` (this is a kit, adapted by `TAILORING.md`).
- Referencing another skill: by name in backticks (`hunting-bugs`), never by its internal file path.

## Glossary (use these words, not synonyms)

| Use | Not |
|---|---|
| owner | user, human, client (when meaning the person who decides) |
| lead | orchestrator, main agent |
| gate | check, CI step (when meaning a `scripts/run-all-gates.sh` stage) |
| slice | ticket, story, chunk (a unit of delivered work) |
| decision record (ADR) | design doc, RFC |
| running files | state docs, living docs |
| builder / test author | developer / QA |
