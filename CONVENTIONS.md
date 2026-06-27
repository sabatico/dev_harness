# Conventions — «PROJECT»

How we write code and docs here, so a swarm of agents (and humans) produce one coherent codebase. These are the *authoring* rules; the *process* rules are in `CLAUDE.md` + `sops/`.

## Doc authoring
1. **Explain WHY, not just what.** Every non-trivial decision in a doc states the reasoning and the **alternatives considered + why they lost.** A doc that only says "we do X" is half a doc. (Decisions of consequence graduate to an ADR.)
2. **Give a fallback.** When you recommend an approach, note the backup if it doesn't pan out.
3. **Living docs are dated + owned.** Headers carry "Last updated" and a one-line "what changed." Stale = a bug.
4. **Write for a cold start.** Assume the reader has zero prior context (because the next session's agent does).

## Code authoring
1. **Match the surrounding code.** Comment density, naming, idioms, error handling — read the neighbors before you write. Consistency beats personal preference.
2. **Buildability by agents is a top-tier concern.** Prefer the most-trained, least-hallucinated, fewest-version-pitfalls option a cheaper builder model can't get subtly wrong. Novelty is a cost, not a feature.
3. **Every dependency is paid for** in supply-chain + audit + maintenance surface. Don't add one to save a few lines.
4. **Make the unfinished visible.** Intentional gaps get a marker (`DEFERRED-TEST:`, `STUB:NAME`, `TBD:`) + a registry row + a CI check — never a silent shortcut.
5. **Errors and outcomes are observable; secrets are not.** Log meaningful outcomes; never log a secret/PII/sensitive value.
6. **Small, reviewable slices.** A change should be reviewable as one coherent unit.

## Commits & branches
- «Branch policy — e.g. trunk-based with short-lived branches, or direct-to-main during early buildup.»
- Commit messages: imperative subject, a body that says *why* for anything non-obvious. Special prefixes the harness uses: **`quality-review:`** (a review baseline).
- «Co-author / attribution trailer, if any.»

## Naming
- «Project naming conventions: files, modules, tests, IDs (feature-catalog IDs, ADR numbers, ticket IDs).»

> Keep this short and real. A convention nobody follows is worse than none — prune the aspirational, keep the load-bearing.
