# The platform layer — hooks, agents, rules, skills (and what each one enforces)

The doctrine for the agent-platform layer: `dot-claude/` is the template, `scripts/hook-*.sh` are the
implementations. Origin and dated evidence: see **History** at the end.

## Contents

- P0 · The enforcement-class map
- P1 · The banner is a liveness proof
- P2 · The guard, and the content-vs-command tension
- P3 · The librarian (retrieval leaves the lead's window)
- P4 · What hot-reloads and what does not
- P5 · Evaluating the harness (the planted-assumption method)
- P6 · Session-scoped state, cross-clock time, and other lessons the hooks encode
- P7 · Wiring order for a new project
- P8 · Self-measurement and self-proofs
- P9 · Ideas taken from the harness-engineering source study
- History

## P0. The enforcement-class map

A rule that matters must not stay in Class D (prose). The platform gives the classes that used to be
stuck there a home:

| Rule shape | Old class | Platform home | New class |
|---|---|---|---|
| "Never run X" (destructive commands) | D — hoped | **PreToolUse deny** (`hook-pretooluse-guard.sh`) | **A** — cannot run |
| "Read the state docs at session start" | D — a reading list | **SessionStart injection** (`hook-session-start.sh`) | structural — state arrives derived |
| "Load the right rules for this job" | D — a routing table | **path-scoped rules** (`dot-claude/rules/`, copied to your repo's dot-claude directory, + `paths:` frontmatter) | structural — loads on touch |
| "Follow the SOP when the owner says X" | D — remembered | **skills** (`/reviewing-code-quality`, `/hunting-bugs` …) | structural — invoked by name |
| "Check docs after every write" | A, but Write/Edit only | **PostToolUse on Bash too** (`hook-postbash-docgates.sh`) | A, all three write paths |
| "Delegate corpus reads" | D — cannot be a hard gate | **volume tripwire** (`hook-read-budget.sh`) + logged hits | **advisory-instrumented D** — measured, honestly labelled |
| "Does the cited decision still GOVERN this change?" | impossible for scripts | **prompt-type hook** (LLM evaluates, advisory) | first judgment-call control |
| "Verify before you report" | D — the most-cited rule, caught 0 escapes | **Stop hook over the turn's tool calls** (`hook-stop-verifycheck.sh`) | **advisory-instrumented**, block-able — code changed with no check after it is mechanical |
| "Never switch off your own guard" | not even written down | **PreToolUse deny on the control paths** (`guard-check.py`, owner override at launch only) | **A** — for Write/Edit and the common shell writers |
| "Diagnose, don't re-run the same failing thing" | D | **PostToolUse + PostToolUseFailure repeat counter** (`hook-repeat-check.sh`) | advisory, logged |

Two rules stay honestly un-gated: "should this read have been delegated" and "is this comment's WHY
still true" are judgment calls; the platform gives them advisories and measurements, not walls.

## P1. The banner is a liveness proof (the unprotected-session problem)

Hook config loads at **session start**; a session older than the config runs with NO hooks and NO
signal, looking identical to a protected one. The fix is structural: the SessionStart hook prints a
banner, and **the banner appearing IS the proof the hooks loaded**. State the contract in
`CLAUDE.md`: *no banner ⇒ no hooks ⇒ run gates by hand, treat guard rules as unenforced.*

## P2. The guard, and the content-vs-command tension

`PreToolUse` is the only surface where "stop" precedes "done". Use it for exactly the actions that
cannot be undone (infra destroy, repo `rm -rf`, broad `git add`, checkout-over-uncommitted-work,
force-push, destructive SQL on protected DBs) and for writes to ARCHIVED/GENERATED paths. Laws:

1. **Hooks hot-reload; the guard can go live mid-session.** The guard's first real deny was the
   commit shipping it — the commit *message* named the forbidden commands.
2. **Judge the commands a string RUNS, not the string** (`scripts/guard-check.py`). Reading the whole
   string flags its own vocabulary quoted in messages, echoes and heredocs; anchoring regexes to
   command position fixes prose but not spelling. The judge therefore:
   - splits on the same separators as the shell (quote-blind on purpose — quote-aware splitting is a
     bypass: one apostrophe in a heredoc swallows every later separator), **plus** a QUOTE-AWARE pass;
     a command found by either pass is judged;
   - tokenises each piece, strips wrappers (`sudo`/`env`/`command`, `bash -c`/`eval` strings,
     here-strings, `echo … | bash`), reads flags as SETS, checks targets one by one;
   - normalises every target: `$HOME`/`${HOME}`/`~user` expanded, relative paths joined to the
     payload's `cwd`, `..` folded (a relative path that stays inside the repo is still the repo's
     business); compares command names case-insensitively (`RM` runs `rm` on a case-insensitive
     filesystem);
   - covers whole families never named literally: hard reset, forced clean, force branch delete,
     plus-refspec push, stash clear, `find -delete`.

   A commit message is one argv token of `git commit`, so prose never matches. Residual tension:
   heredoc lines are judged as commands — use Write/Edit for such content.
3. **The guard ships with a known-answer matrix** (`hook-pretooluse-guard-test.sh`) whose ALLOW rows
   are its actual false positives. Run it after any guard edit. The matrix lives in a FILE because
   inline test payloads are indistinguishable-by-grep from real chained commands, and the live guard
   blocks its own test run.
4. **The guard guards its own off-switch.** Write/Edit/MultiEdit/NotebookEdit and the common shell
   writers (redirect, `sed -i`, `mv`, `rm`, `cp`-as-destination, `tee`, `git rm`) onto any
   `.claude/settings*.json`, `scripts/hook-*.sh`, the judge scripts or `harness.conf` are denied
   (`disableAllHooks` works from ANY settings file, including user-level; without this one injected
   sentence in a web page could ask the agent to remove its own safety net). The override,
   `HARNESS_ALLOW_CONTROL_EDITS=1`, is read from the hook's LAUNCH environment before `harness.conf`
   is sourced — nothing the agent does mid-session reaches it — and the SessionStart banner announces
   it while on. Paths compare case-insensitively and through symlinks; a copy INTO a folder is judged
   by the file it creates. Not covered: a write through an interpreter (`python -c`, an awk/sed
   script, a script file).
5. **Every deny is logged** (`guard.log` in `HARNESS_LOG_DIR`: time, session, tool, rule — never the
   command text, which can carry a secret). Read it at the two-week review: a rule that never fires,
   or fires mostly on legitimate work, is a rule to retune.

Every deny reason names the sanctioned alternative — the model reads it and self-corrects. A guard
that false-positives gets disabled, which is worse than absent: deny narrowly.

## P3. The librarian (retrieval leaves the lead's window)

The corpus outgrows the context window in every project that documents itself seriously, and the
failure mode of recall is fabricated specifics that FEEL certain. RAG is the wrong tool (a vector
store returns the plausible neighbour — the same output distribution as the failure); the right tool
is a **read-only subagent** whose window absorbs the search and whose answers are **verbatim quotes
with file:line** (`dot-claude/agents/librarian.md`).

- **Delegation briefs carry five parts** (`dot-claude/skills/consulting-the-librarian/SKILL.md`): question ·
  task behind it · every id/alias · **the caller's ASSUMPTIONS to confirm-or-refute** · extra
  surfaces. The assumptions are the high-value part: in the first eval the librarian refuted the
  *evaluator's own planted ground truth*, with code quotes.
- **Coverage is measured, not judged**: `librarian-sweep.sh` accounts for every surface with a hit
  count (0 = searched-and-empty = evidence; ⚠ ABSENT = could-not-look, reported verbatim). Require
  the count table in every answer — three probes in a row self-judged the sweep unnecessary and
  skipped it.
- **Delegation itself cannot be a hard gate** (targeted reads are mandatory elsewhere) — the
  read-budget hook is the honest proxy: volume advisories + a hit log, so the delegation rate is a
  number after two weeks, not a feeling.

## P4. What hot-reloads and what does not (verify, don't assume)

**Hooks** hot-reload on settings edits; **skills** hot-load into a running session; **agent
definitions do NOT** — a new or edited agent definition (your repo's dot-claude agents dir) waits for
the next session start. Never assume a just-written agent runs the just-written protocol; the first
spawn in a fresh session is the wiring proof. Re-verify these semantics on your platform version —
this class of claim rots.

## P5. Evaluating the harness (the planted-assumption method)

Evaluate a retrieval agent like a gate: against KNOWN answers.

1. Ground-truth 2–3 facts yourself, from primary sources, BEFORE writing the probe.
2. Brief the librarian with those facts stated as assumptions — some true, some false, ideally one
   the register says was once gotten wrong.
3. Score: were false assumptions REFUTED with correct quotes? True ones CONFIRMED? Is the sweep
   accounting present? Did it surface drift you did not plant?
4. Run three probes; the aggregate (verdicts correct / fabricated citations / unprompted drift finds)
   is the harness's retrieval quality number.

Expect the eval to find harness bugs (a stale services-inventory row, an alias blindness in a search
tool, a live product invariant violation in the source project).

## P6. Session-scoped state, cross-clock time, and other lessons the hooks encode

- **Hook scratch state is per-session** (`${TMPDIR}/harness-*-${session_id}`): a shared fixed path
  lets two sessions cancel each other's stamps.
- **Measure an age on the clock that stamped it.** An "idle window" comparing a DB-stamped time with
  the app clock breaks when the DB VM's clock lags after a host sleep: every fresh session reads as
  expired, and only the shortest-window persona dies — which looks like a flaky suite (it cost three
  red gate runs and a wrong register diagnosis).
- **Key advisories to COMMITS, not the dirty tree** (`hook-stop-statecheck.sh`): dirty code mid-task
  is normal, and nagging every turn trains everyone to ignore the advisory. Log every hit — two weeks
  of hit-rate decides whether an advisory earns the right to block.
- **Gate logs may be wiped by the gate runner** — read advisory hit-logs per run, not cumulatively.

## P7. Wiring order for a new project

1. Run `scripts/init.sh` — it installs `dot-claude/` → `.claude/` per file and seeds the platform
   vars in `harness.conf`. (Retrofitting an existing repo: do that copy by hand.)
2. Start a session; **see the banner** (P1). No banner = fix wiring before trusting anything.
3. Run `hook-pretooluse-guard-test.sh`; adapt the ALLOW rows to your workflows.
4. Write one path-scoped rule per area you actually have (the rules dir); keep each ≤50 lines.
5. Trigger one real deny and one real doc-gate block through the production path — a control you have
   not watched fire is not a control (control-timing C3).
6. After the first week, read the guard, stop-advisory, read-budget, claim-check, verify-check and
   repeat-check logs (in `HARNESS_LOG_DIR`, default .harness-logs — NOT a directory your gate run
   clears); tune or delete what never fires.

---

## P8. Self-measurement and self-proofs

The platform layer's weakest parts were the ones that MEASURE it. Everything below ships as
config-driven scripts with a known-answer matrix, and each matrix is mutation-checked (break the
thing, watch the matrix go RED) before it is trusted.

**Self-proofs are gates.** "Run the guard matrix after ANY edit" is prose until a gate runs it.
`run-all-gates.sh` runs every hook matrix (`guard-matrix`, `read-budget-matrix`,
`claim-check-matrix`) and the rotation matrices.

**The read-budget measures what the agent receives** (`scripts/hook-read-budget.sh`): bytes actually
returned (`tool_response.file.content`), not whole-file size (a 3-line read of a 523 KB register must
not "cost" 523 KB); Bash corpus reads at what arrives (≤ `BASH_MAX_OUTPUT_LENGTH`, default 30000
chars, else a 2 KB preview — 269.6 KB of output arrived as a file path + the first 2 KB), since auto
mode reads through `cat`/`sed`; librarian delegations logged, so the log answers "read directly vs.
delegated"; the log lives in `HARNESS_LOG_DIR`, never a directory a gate run deletes.

**The librarian's sweep is injected, not requested** (`dot-claude/skills/consulting-the-librarian/SKILL.md` +
`scripts/librarian-presweep.sh`). Probes skip a per-surface sweep they are merely asked to run. A
skill with `context: fork` + `agent: librarian` runs its injected shell block before the prompt
exists, so the sweep output lands in the LIBRARIAN's window, never the caller's. Traps: the skill's
arguments are substituted as RAW TEXT into that block (so the brief goes through a quoted heredoc);
the loader matches the block opener MID-SENTENCE inside an HTML comment and tries to execute the
comment plus the brief; and in a forked skill with `agent`, the command must be pre-approved in
`allowed-tools` or the invocation aborts, even in auto mode.

**A claim check for chat** (`scripts/claim-check.py`, Stop hook). Every doc gate fires on a FILE;
answers from memory land in CHAT. Three shapes are mechanically checkable: a linked or `file:line`
path (resolved exactly, then by suffix across the repo + `HARNESS_SIBLING_REPOS`); a decision/bug id
at or below the highest existing number that appears nowhere; a quotation ATTRIBUTED to a repo source
that appears nowhere the agent could have read it (cited file, corpus, the session's tool output and
user messages, the whole repo incl. code comments). Design rule: **silent unless definitely false**,
which must be MEASURED — the first version raised 50 flags on 673 real turns, nearly all false (the
owner's own words in quotes, tool output, bare filenames, an IP:port, quote marks paired across code
spans); the calibrated version raised 0 on 1,093. It is a tripwire: the owner's "answers from memory"
mostly live in shapes with no mechanical form (paraphrased rulings, wrong numbers), which the eval
below measures. **Start in advise mode; switch to `block` (the model must correct a definitely-false
claim once before finishing) only on the same calibration evidence.**

**A task-embedded retrieval eval** (`scripts/harness-eval.sh` + `scripts/harness-eval-probes.json`).
P5 measures the librarian when CALLED; this measures whether the main agent CALLS anything. A direct
question always triggers a lookup, so each probe is an ordinary task where one repo fact is
incidental; fresh headless sessions (plan mode) run it and the scorer reads the transcript: looked
up / right / wrong / what the claim check flags. It spends money — owner-triggered, never gated. The
standalone CLI must be logged in (`claude`, `/login`); a run returning "Not logged in" is refused as
a measurement.

**Post-compaction warning** (`scripts/hook-session-start.sh`, `source == compact`): facts read before
a compaction survive only as paraphrase; the brief says so at the one moment it is certainly true.

**Rotation as gates** (`scripts/rotate-bug-register.sh`, `scripts/rotate-onboarding.sh`). "Move the
row when it is fixed" and "archive old log entries" were prose steps; on the source project 86 closed
rows sat in the OPEN table (register 523 KB, 13 open bugs) and the handover file hit its budget. Both
now move text VERBATIM (ids and lines conserved, proven by their matrices), gate a
`--check`/`--limits`, and keep TWO floors for history — the newest N AND everything younger than D
days — so cleaning never cuts a handover thin; a handover block still live carries a keep marker
(script header).

**Quiet gate output for agents** — this kit's `run_gate` shape (one line per gate, failures only, logs
to a per-run dir). Gates that TEE'd ~265 KB left the agent only the 2 KB preview of the START and
never the verdict at the bottom. Keep it quiet.

**Code intelligence**: the official LSP plugins (`rust-analyzer-lsp`, `gopls-lsp`, `typescript-lsp`,
`pyright-lsp` …) — see TAILORING §Code intelligence. They replace grep for definition/references and
push compiler diagnostics after edits, at a per-edit token cost.

**Traps these scripts encode** (each is a comment where it bites):
- macOS bash 3.2 mis-parses a heredoc nested in `$( )`/`<( )` whose body holds a backtick.
- One apostrophe inside a `python3 -c '…'` block makes the whole hook fail to PARSE — and a hook that
  fails to parse is silent.
- A script that treats an unknown flag as "do the default write" (`--help` performed a real rotation).
- `CLAUDECODE=1` is also set in IDE terminals, so "am I talking to an agent" also needs a non-tty
  stdout.

---

## P9. Ideas taken from the harness-engineering source study

Barbaste et al., *Harness Engineering: Anatomy, Architecture, and Evolution of Coding Agents* (arXiv
2609.00006) read the source of eleven production coding harnesses and closed with 18 design
recommendations. Most concern building an agent runtime, which this kit sits on top of. Eight ideas
are applied. Its central finding — *behavioural policy is migrating from the prompt, where the model
reads it, to configuration, where the platform enforces it* — is this kit's founding measurement
(README, "Why so much of this is mechanised").

| Idea from the study | What the kit had | What it has now |
|---|---|---|
| Match on a deobfuscated command (§10.7 Hermes, §10.9 OpenCode) | anchored regexes; 14/14 probed disguises passed | `guard-check.py` judges argv (P2 law 2) |
| A policy floor that survives "YOLO" (§10.7, Rec. 11) | the agent could edit its own hook wiring | control-path deny, launch-only override (P2 law 4) |
| Verify-on-stop guard (§6.2 Hermes, Table 12) | "verify before you report" was prose | `hook-stop-verifycheck.sh` + `verify-check.py`, advise → block on evidence; a check counts only when it RUNS at command position and was not refused (mentioning `pytest` fooled the first version) |
| Per-agent audit trail (Rec. 10) | denies left no trace | `guard.log` (P2 law 5) |
| Cheap stuck detection (Rec. 18) | none | `hook-repeat-check.sh`: N identical calls in a row → "diagnose" (advisory) |
| Untrusted-content delimiting (Table 12) | "data, not instructions" as prose | `<untrusted>` fences + defanging in every brief (the `orchestrating-agents` skill rule 10) |
| Read your neighbours' context files (Rec. 6) | `CLAUDE.md` only | `AGENTS.md` pointer, so Codex/Gemini/Cursor reviewers load the same rulebook |
| OS sandbox for automated contexts (Rec. 10) | not mentioned | the `hardening-security` skill §Unattended runs + the `_comment_sandbox` in the settings template |

**Already held, and validated by the study:** path-scoped rules = its "conditional activation"; SOPs
as skills = its "deferred loading"; the compaction log + post-compaction re-brief; deterministic
retrieval (the librarian greps; 0 of 11 harnesses index code with embeddings); a second reviewer
outside the turn loop = its "outer verification loop".

**Deliberately not taken:** loop architecture, edit formats, provider coupling, ACP — Claude Code's
job, not the kit's. Agent-maintained memory (Codex) — the position stays "auto-memory is a pointer,
never a source"; lessons graduate into skills through the owner (the `orchestrating-agents` skill, Wiring it
up), the study's human-gated variant (Gemini CLI's review inbox).

**Wiring note:** the repeat counter must be on PostToolUseFailure as well as PostToolUse — a Bash
command that exits non-zero arrives ONLY on the failure event, and failed repeats are the case that
matters. Both events accept `hookSpecificOutput.additionalContext`, which the model sees.

**Known open bypasses** (decided, listed in `CLAUDE.md` footnote ¹): variables, git aliases,
interpreter writes, alternating calls.

---

## History

Dated provenance for the rules above; nothing here adds a rule.

- **2026-08-24 — the founding audit.** The source project ran two months on gates + prose alone, then
  audited itself: it used **1 of the platform's 30+ hook events, 0 subagents, 0 real skills, 0
  path-scoped rules**, and every context-handling rule was Class-D prose at ~25–36% compliance. One
  day of adopting the platform moved the un-movable rules; the build produced the P1–P7 lessons, each
  paid for with a live failure.
- **2026-09-29 — follow-up review (P8).** After a survey of the top Claude Code harnesses and the one
  empirical study of them (marmelab's *State of AI Harness Engineering 2026*: the same model through
  eight harnesses scored 68% → 88%; "only 4.4% of security rules are backed by a real control"), the
  weakest parts proved to be the ones that MEASURE the layer; P8 is the result. The read-budget had
  counted whole-file size, never seen Bash reads, and logged into a directory the source project's
  gate run deleted. The destroy-guard's matrix said "run after ANY edit" and no gate ran it.
- **2026-09-30 — judging argv (P2 law 2).** A probe of 14 everyday disguises (split flags,
  `bash -c`/`eval` wrappers, `sudo`/`env`/`command` prefixes, `$HOME` for `~`, and unnamed families)
  let **14 of 14** through the anchored-regex guard; the argv judge replaced it. A second pass, found
  by the cross-author test matrix and not the builder, covered a quoted argument holding a `;` that
  hid the target, `..` climbing out of an excluded folder, `RM` on a case-insensitive filesystem, a
  `${HOME}` brace cut by the splitter, unknown wrappers, here-strings and `echo … | bash` — hence the
  quote-aware pass and target normalisation.
- **2026-09-30 — control-path deny (P2 law 4).** Until then the agent could edit its own
  project settings file or hook scripts and the guard allowed it.
- **2026-09-30 — source-study additions (P9).** The cross-author matrix caught what the builder could
  not see: the builder's own probes passed 14 of 14, then the separate test author's
  invent-nastier pass listed 31 more cases across the three new hooks, most real failures — the
  README's measurement one level down. Fixed in the same change: the guard bypasses above, the verify
  check counting a MENTION of a test as a run, `HARNESS_CODE_DIRS="."` switching it off, a zero repeat
  limit firing on every call, a relabelled retry resetting the repeat counter, a session id able to
  forge guard-log lines. Also found in OLDER code: both Stop-hook wrappers resolved their own
  directory after `cd`, so a run by relative path silently checked nothing.
