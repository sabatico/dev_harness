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
- Bench verdicts v1 → v1.1 and v1.1 → v1.2: *pending — the first historical runs.*

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
