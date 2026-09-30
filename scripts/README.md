# scripts/ — the executable layer

Everything else in this kit is conventions and SOPs: the agent reads them and follows them. **This
directory is the part that does not depend on anyone reading anything.**

It exists because of a measurement worth repeating (see the README's evidence section): over one
audited session, of ten defects, the count caught by *a rule that was read and being complied with*
was **zero**. Gates caught three. So the prose sets direction; these scripts hold the line.

## Status — verified, and what that does and does not mean

Run this first, and after any change to a gate:

```sh
scripts/selftest.sh
```

For every gate it builds a throwaway fixture project and asserts three things: the clean fixture
**passes**, a planted violation makes it **fail**, and removing the plant makes it **pass again**.
That third assertion matters as much as the second — a gate that fails on everything also "catches"
the plant.

**All 8 gates currently pass their self-test.** It is not decoration: the first run found
`check-log-hygiene.sh` completely **blind** — its function match was case-sensitive, so it saw none of the
capitalised forms every ecosystem actually uses, and reported a confident zero on a line that
logged a password. Three other gates were fixed the same way (a register format it could not parse, a resolver
that flagged correct prose, and one that flagged itself).

**What the self-test proves:** each gate can see the specific violation it claims to catch, and does
not fire on a clean tree.

**What it does NOT prove** (`gates.md` G5, and worth stating because a green here is easy to
over-read): that a gate catches every real-world variant of its class. `check-log-hygiene.sh` is a
name-based heuristic and cannot see a secret flowing through a neutrally-named variable;
`check-citations.sh` proves a pointer exists, never that it points anywhere true. The self-test raises
the floor. It does not make any of these proofs.

**And it does not prove WIRING.** `selftest.sh` calls the scripts directly, which is exactly the
verification `ci/control-timing.md` C4 warns is insufficient. Before trusting the write-time hook,
trigger it the way production does — edit a real file through your agent and watch the block arrive.

## Setup

```sh
cp harness.conf.example <your-repo>/harness.conf   # then edit every path
cp -r scripts <your-repo>/scripts
scripts/run-all-gates.sh
```

`harness.conf` is the only file you edit. Nothing here hardcodes a language, directory layout or
project name: the language-shaped facts come from a **stack pack** (`stacks/<name>.conf`, selected
by `HARNESS_STACK`) and everything else from the config. See `stacks/README.md`. A setting left empty **disables** the gate
that needs it, and the gate says so out loud — an unconfigured check reports INCOMPLETE, never PASS.

## What is here

| Script | Enforces | Notes |
|---|---|---|
| `selftest.sh` | **that every other gate here actually fails on its own violation** | run it first, and after touching any gate |
| `init.sh` | bootstraps a fresh clone into a project skeleton | deletes nothing; prints a prune list |
| `run-all-gates.sh` | the whole fast tier, then optional suites; writes the G4 push receipt on green | tiered: bare, `--full`, `--lint`, `--all`; `--verify-receipt` re-checks the tree |
| `hook-fast-gates.sh` | the sub-second gates **at the moment of the write** | see `ci/control-timing.md`; blocking on docs, advisory on code |
| `check-doc-links.sh` | every markdown link resolves | **blocking** at write time — a dead link is a fact error |
| `check-doc-paths.sh` | every **bare backticked** path exists | ratcheted; links are only half the surface |
| `check-doc-index.sh` | every doc is registered | proves *declared*, never *accurate* (G5) |
| `check-markers.sh` | marker ⇄ registry pairing | fully config-driven; add your own marker types |
| `check-bug-evidence.sh` | a closed bug names its mutation + the test that went red | contract is in the header |
| `check-conditional-skips.sh` | no test skips from an **error branch** | heuristic; suppress with `harness:allow-conditional-skip` |
| `check-citations.sh` | a function you touched cites the decision governing it | ratcheted vs `HARNESS_BASE_REF`; `--measure` first |
| `check-log-hygiene.sh` | no secret-shaped identifier reaches a log call | name-based heuristic — a floor, not a proof |
| `lib/common.sh` | the shared exit vocabulary, config loading, ratchet helpers, the tree hash | source it from any new gate |
| `hook-pretooluse-guard-test.sh` | **that the guard denies what it claims, and allows its known false positives** | known-answer matrix; reports unexercised rows as skipped, not passes |
| `lib/manifest.sh` | `ci/run-integrity.md` R1–R4 in ~90 lines | for multi-stage jobs |
| `stacks/*.conf` | **the language-shaped facts every gate reads** | `HARNESS_STACK` picks one; `stacks/README.md` |
| `predicates-test.sh` | that "is this a test file / vendored?" has not gone over-broad | known-answer matrix; an over-broad exclusion makes gates quieter, not louder |

## The exit vocabulary — honour it in every gate you add

```
0  PASS        the check ran and found nothing wrong
1  FAIL        the check ran and found something wrong
3  INCOMPLETE  the check SHOULD have run and could not — missing tool, absent target, no harness.conf
4  N/A         the check is deliberately not configured here (its setting is empty in an EXISTING
               harness.conf). Reported as `skipped`: never a pass, always listed — but it does not
               force the run to INCOMPLETE.
```

**3 vs 4 is the whole point of having four codes.** Collapsing them either hides a real hole
(everything becomes N/A) or trains people to ignore the verdict (everything becomes INCOMPLETE).
`lib/common.sh` gives you `gate_incomplete` and `gate_not_applicable` — use the right one.

**`3` is the one that matters.** A check that scanned nothing must never exit `0`. Every expensive
failure this harness is built around comes from "nothing was checked" rendering as "nothing was
wrong". If you add a gate and skip this, you have added a control that lies in the reassuring
direction.

## The push receipt (G4) — "gates passed" vs "gates passed on THIS code"

`run-all-gates.sh` writes `.gate-receipt` when a run is COMPLETE with zero findings, and only then:
a receipt over an INCOMPLETE run would certify a tree the gates never covered.

```sh
scripts/run-all-gates.sh                   # green → writes the receipt
scripts/run-all-gates.sh --verify-receipt  # 0 = still this tree · 1 = stale · 3 = no receipt
```

Wire `--verify-receipt` into a pre-push hook and the gap between verifying and pushing closes. Two
details from G4 are load-bearing and are implemented in **one** shared function
(`harness_tree_hash` in `lib/common.sh`): untracked-but-unignored files are **included** (the file
you just wrote is the code most likely to be unverified), and writer and checker hash **identically**
— two implementations drift, and the first symptom is a hook refusing the run that created it.

It also honours G1's hashing corollary: **it refuses to emit a digest over an empty enumeration.**
The hash of nothing is stable, so a receipt written while enumeration was broken would happily match
a later check made while it was still broken — passing, having verified no files at all.


## Measure before you enforce

```sh
scripts/check-citations.sh --measure
```

Prints the current adoption rate and fails nothing. **A rule with no baseline is a wish** — and the
number is usually not what anyone guessed. Freeze what exists (`--write-baseline` where supported),
then enforce forward. See `gates.md` G3 for what keeps a baseline honest, including the requirement to
**triage before freezing**: burying real findings among false ones is the standard way a ratchet goes
wrong.

## Portability

Bash 3.2 compatible (stock macOS — no associative arrays, no `mapfile`) and BSD-safe (no GNU-only
flags). The harness has to run on the machine the developer actually has, not the one CI has.

## Platform-layer hooks (wired via dot-claude/settings.json — see ci/platform-layer.md)

| Script | Event | Does |
|---|---|---|
| `hook-session-start.sh` | SessionStart (incl. `compact`) | Injects derived state + the ⚡ liveness banner (~a page); after a `compact`, warns that pre-compaction facts are paraphrase until re-looked-up |
| `hook-pretooluse-guard.sh` | PreToolUse Bash/Write/Edit | Denies destructive commands + archived/generated-path edits, with the sanctioned alternative in the reason. Anchored to command position; test matrix: `hook-pretooluse-guard-test.sh` |
| `hook-postbash-docgates.sh` | PostToolUse Bash | Runs the blocking doc gates when a doc was written through Bash (the Write/Edit hook cannot see those) |
| `hook-read-budget.sh` | PostToolUse Read\|Bash\|Agent\|Task\|Skill | Counts corpus bytes the MAIN session actually received (Read content, Bash stdout at the 30000-char/2 KB-preview ceiling) and logs librarian delegations; advisory past the budget. Matrix: `hook-read-budget-test.sh` |
| `hook-stop-statecheck.sh` | Stop | Advisory when HEAD changed code but no running doc; once per commit; hit-logged |
| `hook-precompact-log.sh` | PreCompact | One log line per compaction, for attribution |
| `hook-stop-claimcheck.sh` + `claim-check.py` | Stop | Checks the reply's linked/`file:line` paths, decision/bug ids and ATTRIBUTED quotes; silent unless definitely false; advise or block (`HARNESS_CLAIMCHECK_MODE`). Matrix: `hook-stop-claimcheck-test.sh` |
| `librarian-sweep.sh` | (used by the librarian agent) | Per-surface hit accounting over every knowledge surface incl. git history and sibling repos |
| `librarian-presweep.sh` | (injected by the forked `/ask-librarian` skill) | Extracts terms from the brief (TERMS: line, ids, `code`, "phrases"), ERE-escapes them, runs the sweep before the librarian starts; always exits 0 |
| `rotate-bug-register.sh` | (gate: `--check`) | Moves long-closed rows — incl. FIXED rows left in the open table — VERBATIM to the archive; ids conserved. Matrix: `rotate-bug-register-test.sh` |
| `rotate-onboarding.sh` | (gate: `--limits`; `--check` once floors are set) | Log-entry diet + order; rotates old log entries / dated handover blocks VERBATIM past TWO floors (newest N AND younger than D days). Matrix: `rotate-onboarding-test.sh` |
| `second-opinion.sh` | (called by agents/SOPs) | One entry point for an independent reviewer: tries the configured outside models, falls back to the local `red-team` agent, never fails the run; names who answered. Matrix: `second-opinion-test.sh` |
| `harness-eval.sh` | (owner-run, spends money) | Task-embedded retrieval probes (`harness-eval-probes.json`): does the main agent look a fact up or answer from memory? |
