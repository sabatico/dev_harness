# SOP — Agent Skills (task-type briefing packs)

**The problem this solves:** only the constitution (`CLAUDE.md`) reaches every spawned agent
automatically. Everything else — coding rules, test discipline, doc conventions — reaches an agent
only if the lead remembers to put it in the brief. Freehand briefs mean rule delivery varies with
the lead's memory, and hard-won lessons quietly live in one agent's head (or the lead's private
memory) where no sub-agent and no human can see them.

**The pattern:** package the rules as **SKILLS** — small briefing docs keyed by **task type** (not
by role): what the agent is *doing* decides what it loads. Every agent brief injects, **by path**:

1. **`skill-core`** — the universal rules EVERY agent gets, plus
2. **exactly ONE task-type skill** — coding / test-authoring / doc-authoring / adversary / UI,
3. plus the task's own binding guides that the skill names (the UI ruleset, the style handbook…).

Then the brief itself only carries the task specifics (the contract, the file set, the DoD) — it
gets *shorter*, and rule delivery stops depending on memory.

**Two design rules that keep skills from becoming new drift surfaces:**
- **A skill is a checklist with pointers, not a copy.** On any conflict, the linked canonical doc
  wins — say so in every skill's header. Copies rot; that's the failure mode this harness exists
  to prevent.
- **Per-ROLE charters don't survive contact with reality** (they need syncing with every process
  change and quietly go stale). Per-TASK-TYPE skills stay small because each owns only its slice.

## The universal core (`skill-core` — adapt per project, keep ≤1 page)

1. **Inventory FIRST.** Before building anything — or claiming anything is unbuilt/blocked — check
   what exists: the feature catalog + grep the code + the status doc. Report what already exists
   BEFORE writing new code. **If reality contradicts your brief, STOP and say so.**
2. **Reuse before new.** Default to extending an existing primitive over a new variation.
3. **Worktree discipline.** Build freely in your isolated worktree; **NEVER commit or push** —
   leave everything uncommitted and report; the lead reviews, integrates, commits.
4. **The project invariants are sacred** (name them); the guardrail suite is never weakened.
   Locked ADRs are never re-litigated — if your task seems to require it, stop and report.
5. **No secrets, ever** — in code you print, docs, reports, or calls to external models.
6. **Blocked ≠ improvise.** Missing dep, ambiguous spec, contradictory docs → report; never invent
   a workaround that crosses an ADR or an invariant.
7. **Verify before reporting.** The gates run GREEN before "done"; partial is partial; failures
   come with output; "done" requires evidence.
8. **Discovered work goes in your report, not into trackers.** Agents never create tickets/cards;
   the lead routes findings (bugs → the register; engineering → the running files).
9. **Environment quirks:** «the project's PATH/tooling gotchas, by pointer».

## The five task-type skills (skeletons — flesh out per project)

- **`skill-coding`** — ADR-first for new backend features; read-before-touch pointers per
  subsystem; contracts/codegen regenerate (never hand-edit); migrations additive + reversible;
  stub markers + registries; logging rules; the coverage band + DEFERRED-TEST; cross-author tests
  owed (state the fold in the report); the edge-case checklist at build time; the verify commands.
- **`skill-test-authoring`** — you are the OTHER author (attack, don't confirm); the edge-case
  catalog is the floor; the INVENT-NASTIER duty; **call-site assertions for side-effect hooks**
  (test the chain fires end-to-end, not the hook body); no new test deps without approval;
  coverage measured; report proposed cases for the lead to judge.
- **`skill-doc-authoring`** — the conventions doc binds (why + alternatives); registration gates;
  never hand-edit generated docs; **one home per fact** (link, don't copy); claims true TODAY
  (verified at writing time); outward-facing prose = style handbook + owner sign-off.
- **`skill-adversary`** — real failure modes only (scenario + severity + minimal fix); verdict
  honesty (CONFIRMED vs PLAUSIBLE); the lens stack (invariants → edge cases → security →
  wiring/reachability → divergence-from-docs); expect the lead to judge and reject false flags;
  park out-of-scope observations in one line.
- **`skill-ui-coding`** — the UI ruleset binds (tokens/components/no inline styles); the design
  source is canonical (mockup SOP for parity); missing backend → marker + registry; the full
  build command (not just typecheck); state which runner/tracker items the work touched.

## Wiring it up

- `CLAUDE.md` carries the **router** (one bullet): task type → which skill to inject, by path.
- Skills live with the other SOPs (`docs/sops/skill-*.md`) and are registered like any doc.
- When a lesson graduates from someone's memory/chat into a rule, its home is the matching skill —
  that's how it reaches every future agent instead of only the one who learned it.
