# Changelog

One entry per harness version, newest first. Each version is a git tag (`vX.Y`) on GitHub; `VERSION`
holds the current one. Before tagging a version that changes what an agent reads or how it is
steered, benchmark it against the previous tag with the separate **harness-bench** project (kept
private and out of reach of harness sessions, so nobody tunes the harness to the exam). Record here
only its verdict and per-version means — never task names or contents.

## How to cut a version

1. Bump `VERSION`, add the entry below (what changed, why, the bench verdict).
2. Commit, then tag: `git tag -a vX.Y -m "harness vX.Y"` on that commit.
3. Push the commit and the tag (`git push origin master vX.Y`).

## v1.9 — 2026-10-28

Full runs only on the owner's request or before a push. Not yet benchmarked: it changes what runs at a merge, so run
harness-bench against v1.8 before relying on the tag.

- **R9 — three test levels** (`ci/token-budget.md`; `following-core-rules` rule 12 (e); `orchestrating-agents`
  section 10 "Scoped PROOF"; the `CLAUDE.md` token-discipline bullet): while working, the changed code only (R8);
  at a merge into the main branch, the affected set (changed packages plus what imports them; containers only when
  the branch touches what runs against them); the full set only when the owner asks or before a push. Narrows R8's
  "heavy run once per branch before the final commit". Each stack's test runner should offer an "affected" mode.

## v1.8 — 2026-10-28

Scoped checks while working. The first adopting project found that its builder briefs asked every agent
for the heavy test run (whole tree, an integration database in a container) as proof, so parallel
builders queued behind each other for a 10-minute run, and one hung-looking container check restarted
a healthy Docker. Ported in generic form. Not yet benchmarked: it changes what an agent runs as proof,
so run harness-bench against v1.7 before tagging.

- **R8 — scoped checks while working; heavy checks only at a commit or a full scan** (`ci/token-budget.md`;
  `following-core-rules` rule 12 (e); `orchestrating-agents` section 10 "Scoped PROOF"; the `CLAUDE.md`
  token-discipline bullet). Builders and testers run only the checks of the code they changed; the
  heavy run happens once per branch, by the last agent before the final commit, and in the full gate
  run before a push (R7 unchanged). Each stack's test runner should offer a fast mode that names itself
  "not a full run", writes no receipt and still fails on zero or skipped tests.
- **Time limits in scripts must work on macOS** (`CONVENTIONS.md`): macOS has no `timeout`; use
  `perl -e 'alarm N; exec @ARGV' <command>`.

## v1.7 — 2026-10-27

Token discipline and the agent-work toolkit. The first adopting project improved its harness after
v1.6, mostly to cut AI token use after a weekly usage limit stopped every session for four days. Its
changes are ported here in generic form: no product names, paths or ids; every project number is a
`harness.conf` knob. Not yet benchmarked: it changes how agents wait, brief and report, so run
harness-bench against v1.6 before tagging.

- **Token discipline (R1–R7)** — new `ci/token-budget.md` (the measurement: waiting checks were 35%
  of all tokens; the rules; the published guidance; how to re-measure), `following-core-rules` rule
  12 "Spend context like money" (wait without polling, read summaries, return summaries, small
  slices), `orchestrating-agents` section 10 (the session cap `HARNESS_MAX_SESSIONS`, default 4;
  react, do not poll; a fresh lead after a wave) and brief item 13 (the context budget), a
  `CLAUDE.md` standing rule. R7: the quality process does not change.
- **Model policy: plan and judge strong, build mid** — replaces "by code area". «strong model»
  plans, briefs (GOAL · PROOF · LIMIT), plan-reviews risky slices before coding, and judges;
  «mid model» writes all code and most tests; a «floor model» tier. For an easy step lower the
  effort, not the model (a switch throws away the prompt cache).
- **The check-the-work review step** — new `scripts/check-the-work.sh` (+ `lib/review_tally.py`,
  `lib/review-prompt-header.txt`) and `ci/review-step.md`: every sub-session brief opens with a GOAL
  block; before its commit the configured second opinion (`second-opinion.sh`) reads the work against
  the goal; every finding is judged FIXED / REJECTED / DEFERRED; tags (`nit`, `pre-existing`; a P0/P1
  is never a nit); a round cap of 3 with the lead's quoted yes; delta rounds; an optional vote that
  fails closed without a pre-send secret scan; a hook point `check-the-work.d/` (a missing enforcing
  hook exits 3); `verify --branch` for the lead before a merge. The hooks get the base check-the-work
  resolved (`CTW_BASE`) and otherwise derive it from `HARNESS_BASE_REF`, so a repository whose main branch
  is `master` works; `init.sh` removes the kit's own review logs (`.harness/agents`) from a new project. The reviewer test-set method is
  documented; its scorer is not shipped (its cases are a project's own bugs).
- **Session resilience** — new `ci/session-resilience.md`: `session-state.sh` (a resumable record in
  the worktree's git dir) and `resume-brief.sh` (a fenced brief for a fresh session; at most 2
  resumes, then the best partial result); the FINAL report contract (`lib/report-contract.sh`,
  hook `20-report-contract.sh`: `COMMITS:` `GATES:` `BUGS:` `DEFERRED:` `QUESTIONS:`); the
  success-criterion guard (hook `10-success-criterion.sh`: a branch that changes code AND what judges
  it must declare who wrote the tests); the fair heavy-run queue (`heavy-run.sh`, numbered tickets,
  one queue per repository in its common git dir, a symlink lock that works on macOS and Linux).
- **The agent-run log and the proof audit** — `scripts/log-agent-run.py` is the only door into
  `runs.jsonl` (templates in `running-files/agents/`); a claim without its proof is logged as a
  `correction` row (`UNPROVEN:`, `WRONG CLAIM:`, `WRONG DIAGNOSIS:`).
- **The reference index** — `scripts/refs.sh` (+ `refs-index.py`): "what points at X" for a known
  id or path, with id variants a text search misses; a token saver for lookups. The librarian skill
  and `CLAUDE.md` name it before `find.sh` for a known id.
- **second-opinion.sh** — extra reviewers asked in parallel beside the chain (`HARNESS_ALSO_ASK`,
  each with a time limit), the failing reviewer's reason printed, and a worktree call handed to the
  main checkout's own copy when only the main checkout holds the key file (`lib/main-checkout.sh`,
  `HARNESS_KEY_FILE`).
- **Skills and evals** — `hunting-bugs` scales down to one pasted function (four-part report in the
  reply; style remarks only on the parked list); `reviewing-adversarially` knows the check-the-work
  answer shape; 13 generic edge-case classes (C8–C15, D6–D7, E7–E9) in the catalog; the
  sub-session reference gains the GOAL block, the duties table, the new merge checks and the
  dead-session procedure; eval scenarios for token discipline and small-scope hunts; the evals
  README describes `claude plugin eval`.
- **Gates** — `review-tally-matrix` joins the fast tier; seven slow matrices (40 s to over 10 min)
  run with `--full` / `--all` and are named NOT RUN in a fast run; a fast receipt does not cover them.
  The grown second-opinion matrix (about 90 s) stays in the fast tier: it holds the key hand-over.
- **Not ported, on purpose** — the agent dashboard and its publishing (project-specific page), the
  stall/loop status view (reads one launcher's session notes), the reviewer test-set scorer and its
  cases (project bugs), the shrink-only baseline-growth gate (a follow-up), and every product
  feature commit.

## v1.6 — 2026-10-16

Parallel sub-sessions. The way of working was decided and proven in an installed project
(KidsEarnScreenTime) on 2026-10-16, in two waves, and is ported here in generic form. Not yet
benchmarked: it changes how a lead steers work, so run harness-bench against v1.5 before tagging.

- **New reference `orchestrating-agents/reference/parallel-sub-sessions.md`** (no new skill: it is
  the lead's side of spawning, which this skill already owns). Rules, each with its WHY: one
  sub-session per area on disjoint file sets, each in its own worktree and branch; start the next
  as soon as an untouched area has ready work; a brief written for a fresh context; inside a
  sub-session the builder writes zero tests, one cross-author test agent of a different model,
  every test watched red against a mutation restored byte-identically, task-named scratch folders,
  helpers stopped when reported; a sub-session runs only its own area's checks, commits only to its
  own branch, never pushes and never edits the shared running files (it lists the changes in its
  report); a missing product decision goes to the lead as a main and a backup proposal, and the lead
  checks in with every running sub-session; the lead verifies each report, merges with `--no-ff`,
  runs the full gates once and pushes; each sub-session is deleted when merged, and finished helpers
  and everything a task started are stopped; a 10-minute total cap on a long reviewer call; the
  tracker records each wave.
- **`orchestrating-agents` SKILL.md:** description and section 1 name the two sizes of spawn
  (sub-agent, sub-session); brief checklist item 5 now separates "sub-agent: never commit or push"
  from "sub-session: commits only to its own branch, never pushes"; new section 8 points to the
  reference. `shared-checkout.md` is unchanged (it is still the case for when worktrees are not used).
- **Also:** a fourth eval scenario in `evals/orchestrating-agents.json`; a cheat-sheet block; one
  sentence in the `CLAUDE.md` Git line; the README tree line.
- The source project's read-only "list what this task left running" script is described in the
  reference, not shipped: the kit has no scripts area for stack-specific process checks.

## v1.5 — 2026-10-11

Gate-running logic, "ask before you judge", and a model policy by code area. All three were made and
proven first in an installed project (KidsEarnScreenTime, on v1.4) and are ported here in generic form.
Not yet benchmarked: items 2 and 3 change how an agent is steered, so run harness-bench against v1.4
before tagging.

- **`run-all-gates.sh --docs`: the record gates only** (links, paths, index, skills, markers,
  bug evidence, citations, the two rotation limits), in seconds, for documentation-only work. It never
  writes a receipt, and it refuses `--full`/`--lint`/`--all` (exit 3) rather than guess which was meant.
- **Scoped self-test matrices.** A bare run records every `*-matrix` stage as SKIPPED (named, never a
  pass) when `git status --porcelain --untracked-files=all` shows no change under `scripts/`,
  `harness.conf` or the settings file — an unchanged script cannot change its answer. A failed git call
  counts as changed. `--matrices`, `--full` and `--all` always run them. Any scoped skip means **no
  receipt**: for a push receipt, run `--matrices` (or `--full`/`--all`). In the kit a bare run used to
  write the receipt, so this is the one behaviour change to know; the hosted-CI example in
  `ci/gates.md` now passes `--matrices`, because a fresh checkout always looks unchanged.
  Docs: `scripts/README.md` (row and receipt section), `ci/gates.md`, `ci/platform-layer.md` P8, and
  the `writing-docs` verify step (which now names `--docs`).
- **Ask before you judge** (agents in development, tests and risk analysis made false claims for lack
  of context). `following-core-rules` rule 11: look the context up; still missing → return QUESTIONS,
  not conclusions (`NEEDS-CONTEXT` when it touches the main result), and mark any claim resting on a
  guess `ASSUMPTION`. Wired into: the `orchestrating-agents` brief checklist (item 11, two-step
  questions-then-judge for reviews, risk analyses and test designs of consequence) and integration
  checklist (answer from sources, resume the same agent); step 0 of `reviewing-adversarially`,
  `writing-tests` and `hunting-bugs`; the two-step send in the `recording-decisions` second-ideator
  rule; an "Ask before you judge" section in the `red-team` agent; one sentence in `CLAUDE.md`; and
  the same rule for outside reviewer models in `AGENTS.md`.
- **Model policy by code area.** `CLAUDE.md` and `orchestrating-agents` now hold a per-area placeholder
  instead of "routine → mid, hard → strong", with the example: UI and auxiliary code → Sonnet (latest);
  core server and core endpoint code (communications, database queries, API architecture) → Opus
  (latest). Hard, risky or security-critical work still goes to the strong model. Floor unchanged:
  never Haiku.

## v1.4 — 2026-10-07

Fixes from the first install on Linux. Installing v1.3 into a new project (AnyTutor) in a Debian
container found three defects the maintainer's macOS checkout could not show. Not benchmarked: no
change to how an agent is steered.

- **init left the copied docs pointing at the kit layout.** The kit's docs cite kit paths
  (`ci/gates.md`, `running-files/tickets/`, `dot-claude/...`), which resolve only while the originals
  sit beside the copies, so init's own advice (remove the originals) turned the doc-paths gate red:
  11 violations, in `docs/ci/gates.md`, `docs/ci/platform-layer.md` and `docs/tickets/security.md`.
  init now re-points every backticked kit path at the installed layout as it copies (`docs/`,
  `docs/ci/`, `.claude/`). Five sentences in `ci/platform-layer.md` that described the kit-to-install
  mapping itself, or named the per-machine `settings.local.json` by path, were reworded so they read
  right in both layouts. A fresh install's doc-paths baseline is now 0 entries, as the baseline header
  always claimed (it froze 1). The closing advice now says to remove all three originals
  (`git rm -r running-files ci dot-claude`, after comparing any file init kept).
- **New known-answer test `scripts/init-test.sh`, run by `selftest.sh` (row `init-layout`).** It runs
  init on a copy of the kit's working tree, checks the fresh baseline is empty, removes `running-files/`,
  `ci/` and `dot-claude/`, then asserts doc-paths, doc-links and skills pass and no copied doc still
  cites a kit path. Seen failing before the fix (4 of 8 rows, the 11 violations reproduced) and passing
  after, on macOS and on Debian. Exits 4 (selftest prints SKIP) in an installed project, which has no
  originals to remove.
- **`find-test.sh`: the zsh row reports SKIP when zsh is not installed** (most Linux images), counted
  apart as unexercised, never a pass. It reported FAIL.
- **`hook-pretooluse-guard-test.sh`: the 200 KB row failed on Linux, and the guard was not at fault.**
  The test built each payload by passing the command to python3 as an argument. Linux caps a single
  argument at 128 KiB, so that call died, the guard received an empty payload and correctly failed
  closed (`rule=cannot-run`). The command now goes on stdin, as the real hook payload does. The guard
  is unchanged, and the row now proves it judges a 200 KB command in full on Linux too.
- **Found while verifying on a clean clone:** the kit's own doc-paths and skills gates passed only
  where a local `.claude/` existed (the maintainer's machine), and failed on any fresh clone.
  `check-skills.sh` stripped a claim's trailing slash before matching it to the kit's dot-claude
  folder, so a bare `.claude/` never matched (fixed, plus a new matrix row seen failing against the old
  linter). Two `ci/platform-layer.md` claims (`.claude/`, `.claude/settings.local.json`) were reworded
  as above. The stale triage note in `.harness/baselines/doc-paths.txt` (it said 7 entries; there were 0)
  now describes the kit-path-plus-rewrite scheme.

## v1.3 — 2026-10-03

Retrieval. The outside benchmark of v1 → v1.2 found no version a clear step forward on retrieval, and
that searches failed far more often than reads: agents searched a guessed subset of the repo and
concluded "nothing exists", never looked for an owner decision, had a search die silently in zsh, or met
two conflicting records and handled the conflict badly. All changes are generic — none is aimed at a
benchmark task.

- **One standard search: `scripts/find.sh`.** Every repo file (untracked, archives and dot-folders
  included; .gitignore respected; binaries skipped), case-insensitive OR of literal terms, files ranked
  by hits before any match line, every cap says TRUNCATED, and "no hits" (exit 1, with how many files
  it covered) can never be confused with a failed search (exit 2). Its own bash script on `git grep`,
  so the zsh unquoted-glob trap cannot touch it. Adopted from the benchmark's reference implementation
  and acceptance suite (`scripts/find-test.sh`, now the `find-matrix` gate), with fixes: one grep pass
  instead of one per hit file, accented file names (were printed escaped and then silently missed),
  options accepted after the terms, `--list`, over-long lines cut visibly, the harness's own files
  listed last (`HARNESS_FIND_LAST`), and the suite no longer runs `mkdir /repo` when macOS `mktemp`
  fails.
- **Absence is a claim:** a fifth shape in the recall rule — "nothing says X" needs a whole-repo search
  and says where it looked.
- **Owner decisions first, code second** for business questions; the librarian skill names the trigger.
- **Decisions live anywhere:** closed/archived tickets, archives, notes, logs, data files. The librarian
  sweep gained an "everything else" surface over every file its named surfaces skipped (with hits by
  folder), TRUNCATED notes, and a history pickaxe per term (was: the first term only). The bug-register
  template points at its archive.
- **One conflict rule:** when records disagree, quote both with where they live and their dates, say
  which looks newer, and ask the owner — unless a recorded decision already settles it. The three
  precedence rules that settled conflicts silently are qualified (quantity lookup order, "doc wins over
  ticket", locked decision records vs. a later owner ruling).
- **Status is checked, not repeated** before telling the owner something is still open.
- **ONBOARDING's current state is injected** at session start (status + decided-vs-open, bounded), with
  a loud line when those sections cannot be found.
- **Quick lookups are the main agent's job** (`find.sh` plus targeted reads); the librarian is for broad
  sweeps. "Do not read the corpus" became "do not read the WHOLE corpus".
- **Raw-search hygiene** in CONVENTIONS and the cheat sheet: quote globs, an error is not "no hits",
  list files first, never cap a broad search with `head`.
- **Found by the cross-author tests and fixed:** every session start waited **16 s** (against a 20 s
  hook timeout) — the session-brief watchdog left a `sleep` holding the hook's output open; now 0.1 s.
  The librarian sweep read a term starting with `-` as a grep option and reported 0 hits on every
  surface; skipped files whose names hold a quote or tab; and counted an accented macOS file name twice.
  `find.sh` split a file name containing a newline, and an empty term matched every line (now refused).
  The session brief ignored `HARNESS_ONBOARDING`, injected a comment opened mid-line, split accented
  letters when cutting long lines, and was silent when only one of its two sections was missing. Two
  older kit tests used a bare `mktemp -d`, which macOS runs outside `TMPDIR`. New gates:
  `librarian-sweep-matrix`, `session-start-matrix`; `find-matrix` grew to 84 cases.
- Bench verdict v1.2 → v1.3: *pending.*

## v1.2 — 2026-10-03

- **Procedures became real Agent Skills.** The rule documents in `sops/` are now 16 Claude Code skills
  (`.claude/skills/<name>/`), written to Anthropic's skill-authoring best practices: a precise
  "what + use when" description, a short body with a copyable checklist, detail moved to one-level
  reference files, and three evaluation scenarios each (`evals/`). New gates: `skills` and
  `skills-matrix`. The methods themselves (bug hunt, quality review, adversarial review, edge-case
  catalog, cross-authored tests, security baseline) are unchanged — an independent audit confirmed
  nothing was dropped or weakened.
- **Model floor: Sonnet.** Haiku is banned from the dev process for every role, evals included.
- **Skill fixes from evals:** the test author refuses to test code it built (checklist step 0 plus a
  worked example); owner reports gloss IDs from the record, never from imagination.
- **Versioning:** `VERSION`, this changelog, and git tags (`v1`, `v1.1`, `v1.2`) so every benchmark
  result names the versions it compared.
- **Benchmarked from outside:** versions are measured by the separate harness-bench project (sealed
  sessions, ≥3 runs per model per version, the mean is the result). The kit's own `harness-eval.sh`
  stays as the in-project retrieval probe.
- **Fix:** `rotate-bug-register.sh` created a new archive with the OPEN table's columns, and archived old
  misfiled rows verbatim under the wrong columns; its preview disagreed with a real run. Fixed, with
  regression rows in its matrix.
- Bench verdict v1 → v1.1 → v1.2 (270 sessions: Sonnet + Opus, 3 runs each): **no clear step forward
  on retrieval.** Mean quality — Sonnet 0.923 / 0.901 / 0.928; Opus 0.906 / 0.926 / 0.905. v1.2
  changed nothing about how agents look things up; v1.3 is the retrieval release.

## v1.1 — 2026-10-03

The 2026-09-29 batch (the platform layer measures itself: self-proofs, claim check, rotations,
security baseline; plain-English owner communication; configured second opinions; contribution
licence) plus the owner's pending edits committed on 2026-10-03 (guard hardening, repeat-check and
verify-check hooks, AGENTS.md). The harness as it stood before the skills refactor: procedures as `sops/*.md` documents, the
gen-2 platform layer (guard, claim-check, repeat-check and verify-check hooks, librarian), local
gates, running-file templates. Commit `d871ae2`.

## v1 — 2026-09-21 (baseline)

Everything up to and including commit `82fff38`: SOP documents, the adversarial-quality pillar (edge-case
catalog, bug hunt, bug register), coordination tickets, gate and test integrity, one-command init with
profiles, the first platform layer (guard, banner, librarian), language-neutral gates with stack packs.
