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

## Unreleased — fixes from the first install on Linux (AnyTutor, 2026-10-07)

Installing v1.3 into a new project in a Debian container found three defects the maintainer's macOS
checkout could not show. Not benchmarked: no change to how an agent is steered.

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
