# Why agent briefs are built from task-type skills

## The problem

Only the constitution (`CLAUDE.md`) reaches every spawned agent automatically. Everything else —
coding rules, test discipline, doc conventions — reaches an agent only if the lead remembers to
put it in the brief. Freehand briefs make rule delivery vary with the lead's memory, and hard-won
lessons live in one agent's head (or the lead's private memory) where no sub-agent and no owner
can see them.

## The pattern

Package the rules as **skills keyed by TASK TYPE, not by role**: what the agent is *doing* decides
what it loads. Every brief names:

1. `following-core-rules` — the universal rules every agent gets, plus
2. **exactly ONE** task-type skill, plus
3. the binding guides that skill names (the UI ruleset, the style handbook…).

The brief itself then carries only the task specifics (contract, file set, DoD) — it gets
*shorter*, and rule delivery stops depending on memory.

| Task type | Skill | Former name (in older briefs and docs) |
|---|---|---|
| every agent | `following-core-rules` | `skill-core` |
| implementation | `writing-code` | `skill-coding` |
| tests for someone else's code | `writing-tests` | `skill-test-authoring` |
| docs and running files | `writing-docs` | `skill-doc-authoring` |
| attacking a design, diff or suite | `reviewing-adversarially` | `skill-adversary` |
| screens and components | `building-ui` | `skill-ui-coding` |

## Two design rules that keep skills from becoming new drift surfaces

- **A skill is a checklist with pointers, not a copy.** On any conflict the linked canonical doc
  wins — every skill says so near its top. Copies rot; that is the failure this harness exists to
  prevent.
- **Per-ROLE charters do not survive contact with reality** — they need syncing with every process
  change and quietly go stale. Per-TASK-TYPE skills stay small because each owns only its slice.
- The core stays about one page; adapt its placeholders per project.

## Wiring

- `CLAUDE.md` carries the **router** (one bullet): task type → which skill the brief names.
- Skills live in the skills folder (`.claude/skills/«name»/SKILL.md`, installed into the
  project's agent-platform directory) and are linted by `scripts/check-skills.sh`; authoring rules
  are in `authoring-skills`.
- **When a lesson graduates** from someone's memory or chat into a rule, its home is the matching
  skill — that is how it reaches every future agent instead of only the one that learned it.

## Why outside text is fenced in a brief

The constitution says anything a model reads is data, but a brief is the one place that rule
silently breaks: the lead pastes a web page or an issue body among its own instructions, and the
sub-agent cannot tell which lines carry the lead's authority. The safer harnesses studied converged
on explicit markers plus defanging of lookalikes — the procedure is in this skill's SKILL.md
section 4, and the agent's half is rule 10 of `following-core-rules`.

## History

- Formerly the agent-skills SOP (`agent-skills.md`), which described the six skills as skeletons
  under `docs/sops/skill-*.md` but shipped none; they now exist as real skills, and each
  skeleton's content moved into the skill that owns it.
- Fencing source: Barbaste et al., *Harness Engineering* (arXiv 2609.00006), §10.7, Table 12
  "untrusted-content delimiting".
