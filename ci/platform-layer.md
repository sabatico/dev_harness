# The platform layer — hooks, agents, rules, skills (and what each one enforces)

> **Where this came from.** The source project ran for two months on gates + prose alone, then
> audited itself (2026-08-24): it was using **1 of the agent platform's 30+ hook events, 0
> subagents, 0 real skills, 0 path-scoped rules** — and every context-handling rule it had was
> Class-D prose at ~25–36% compliance. One day of adopting the platform moved the un-movable rules,
> and the build itself produced the lessons below, each paid for with a live failure. This file is
> the doctrine; `dot-claude/` is the template; `scripts/hook-*.sh` are the implementations.

## P0. The enforcement-class map, updated

The original finding stands: a rule that matters must not stay in Class D (prose). What changed is
that the platform now offers a home for classes that used to be stuck there:

| Rule shape | Old class | Platform home | New class |
|---|---|---|---|
| "Never run X" (destructive commands) | D — hoped | **PreToolUse deny** (`hook-pretooluse-guard.sh`) | **A** — cannot run |
| "Read the state docs at session start" | D — a reading list | **SessionStart injection** (`hook-session-start.sh`) | structural — state arrives derived |
| "Load the right rules for this job" | D — a routing table | **path-scoped rules** (`dot-claude/rules/`, copied to your repo's dot-claude directory, + `paths:` frontmatter) | structural — loads on touch |
| "Follow the SOP when the owner says X" | D — remembered | **skills** (`/quality-review` etc.) | structural — invoked by name |
| "Check docs after every write" | A, but Write/Edit only | **PostToolUse on Bash too** (`hook-postbash-docgates.sh`) | A, all three write paths |
| "Delegate corpus reads" | D — cannot be a hard gate | **volume tripwire** (`hook-read-budget.sh`) + logged hits | **advisory-instrumented D** — measured, honestly labelled |
| "Does the cited decision still GOVERN this change?" | impossible for scripts | **prompt-type hook** (LLM evaluates, advisory) | first judgment-call control |

Two rules stay honestly un-gated: "should this read have been delegated" and "is this comment's WHY
still true" are judgment calls; the platform gives them advisories and measurements, not walls.

## P1. The banner is a liveness proof (the unprotected-session problem)

Hook config loads at **session start**. A session older than the config runs with NO hooks and NO
signal — a green session and an unprotected one look identical (the source project's fast-gates
hook shipped from a session that never once ran it). The fix is structural, not procedural: the
SessionStart hook prints a banner, and **the banner appearing IS the proof the hooks loaded**. Put
the contract in CLAUDE.md: *no banner ⇒ no hooks ⇒ run gates by hand, treat guard rules as
unenforced.* Absence is now visible, which no amount of prose could provide.

## P2. The guard, and the content-vs-command tension

`PreToolUse` is the only surface where "stop" precedes "done" — use it for exactly the actions that
cannot be undone (infra destroy, repo `rm -rf`, broad `git add`, checkout-over-uncommitted-work,
force-push, destructive SQL on protected DBs) and for writes to ARCHIVED/GENERATED paths. Three
laws, each paid for live:

1. **Hooks hot-reload; the guard can go live mid-session.** The source project's guard's first real
   deny was the commit SHIPPING it — the commit *message* named the forbidden commands.
2. **Anchor every pattern to command position** (line start or after `;` `&` `|` backtick, paren).
   A guard reading the whole command string sees its own vocabulary quoted in messages, echoes and
   heredocs; anchored, only an actual invocation matches. Residual tension: heredoc CONTENT with
   guard vocabulary at line starts still matches — the sanctioned path for such content is the
   agent's Write/Edit tools (whose guard branch checks paths, not content).
3. **The guard ships with a known-answer matrix** (`hook-pretooluse-guard-test.sh`) whose ALLOW
   rows are its actual false positives. Run it after any guard edit; the matrix lives in a FILE
   because inline test payloads are indistinguishable-by-grep from real chained commands and the
   live guard blocks its own test run (found live, twice).

Every deny reason names the sanctioned alternative — the model reads the reason and self-corrects.
A guard that false-positives gets disabled, which is worse than absent: deny narrowly.

## P3. The librarian (retrieval leaves the lead's window)

The corpus outgrows the context window in every project that documents itself seriously, and the
documented failure mode of recall is fabricated specifics that FEEL certain. RAG is the wrong tool
(a vector store returns the plausible neighbour — the same output distribution as the failure);
the right tool is a **read-only subagent** whose window absorbs the search and whose answers are
**verbatim quotes with file:line** (`dot-claude/agents/librarian.md`).

- **Delegation briefs carry five parts** (`dot-claude/skills/ask-librarian/SKILL.md`): question ·
  task behind it · every id/alias · **the caller's ASSUMPTIONS to confirm-or-refute** · extra
  surfaces. The assumptions are the high-value part — in the source project's first eval the
  librarian refuted the *evaluator's own planted ground truth*, with code quotes.
- **Coverage is measured, not judged**: `librarian-sweep.sh` accounts for every surface with a hit
  count (0 = searched-and-empty = evidence; ⚠ ABSENT = could-not-look, reported verbatim). Require
  the count table in every answer — measured on the source project, three probes in a row
  self-judged the sweep unnecessary and skipped it.
- **Delegation itself cannot be a hard gate** (targeted reads are mandatory elsewhere) — the
  read-budget hook is the honest proxy: volume advisories + a hit log, so the delegation rate is a
  number after two weeks, not a feeling.

## P4. What hot-reloads and what does not (verify, don't assume)

Measured on the source project, same day: **hooks** hot-reload on settings edits; **skills**
hot-load into a running session; **agent definitions do NOT** — a new or edited agent definition (your repo's dot-claude agents dir)
waits for the next session start. Consequence: never assume a just-written agent runs the
just-written protocol; the first spawn in a fresh session is the wiring proof. (Re-verify these
semantics on your platform version — this is exactly the class of claim that rots.)

## P5. Evaluating the harness (the planted-assumption method)

A retrieval agent is evaluated the same way a gate is: against KNOWN answers.
1. Ground-truth 2–3 facts yourself, from primary sources, BEFORE writing the probe.
2. Brief the librarian with those facts stated as assumptions — some true, some false, ideally one
   the register says was once gotten wrong.
3. Score: were false assumptions REFUTED with correct quotes? True ones CONFIRMED? Is the sweep
   accounting present? Did it surface drift you did not plant?
Run three probes; the aggregate (verdicts correct / fabricated citations / unprompted drift finds)
is the harness's retrieval quality number. Expect the eval to find harness bugs — the source
project's first eval found a stale services-inventory row, an alias blindness in a search tool, and
(chained through a follow-up) a live product invariant violation.

## P6. Session-scoped state, cross-clock time, and other lessons the hooks encode

- **Hook scratch state is per-session** (`${TMPDIR}/harness-*-${session_id}`): a shared fixed path
  lets two sessions cancel each other's stamps.
- **Measure an age on the clock that stamped it.** Any "idle window" comparing a DB-stamped time
  with the app clock breaks when the DB VM's clock lags after a host sleep — every fresh session
  reads as expired, and only the persona with the shortest window dies, which looks exactly like a
  flaky test suite (it cost the source project three red gate runs and a wrong register diagnosis).
- **Advisories are keyed to COMMITS, not the dirty tree** (`hook-stop-statecheck.sh`): dirty code
  mid-task is normal; nagging every turn trains everyone to ignore the advisory. Log every hit —
  two weeks of hit-rate decides whether an advisory ever earns the right to block.
- **Gate logs may be wiped by the gate runner** — read advisory hit-logs per run, not cumulatively.

## P7. Wiring order for a new project

1. Copy `dot-claude/` → `.claude/`, fill `harness.conf` (incl. the platform vars), copy scripts.
2. Start a session; **see the banner** (P1). No banner = fix wiring before trusting anything.
3. Run `hook-pretooluse-guard-test.sh`; adapt the ALLOW rows to your workflows.
4. Write one path-scoped rule per area you actually have (the rules dir); keep each ≤50 lines.
5. Trigger one real deny and one real doc-gate block through the production path — a control you
   have not watched fire is not a control (control-timing C3).
6. After the first week: read the stop-advisory and read-budget hit logs (under the gate-logs dir the hooks create); tune or delete
   what never fires.
