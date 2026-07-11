# CI Gates — the enforcement layer

The SOPs are honor-system until CI enforces them. These are the gates every project should wire so the rules can't quietly erode. Make them **required status checks** on the default branch.

> **No hosted CI? Run them locally.** Hosted CI (paid minutes) is not required for the value. Wire every gate into **one script** (`scripts/run-all-gates` — a fast tier that's cheap enough to run constantly, plus `--full` for the suites and `--security` for the sweep) and run it **before every push**. State plainly in `CLAUDE.md` that CI is local, keep the workflow file below as a dormant reference for when hosted CI becomes affordable, and make the runner **say what it skipped** (missing toolchain/service) — a skip is not a pass.

## The gates
| Gate | What it enforces | Fails when |
|------|------------------|-----------|
| **build** | it compiles | build error |
| **test** | the suite passes | any test fails |
| **coverage floor** | coverage-is-Done | new/changed code below the target band (per-layer floors) |
| **lint / format** | style + the UI no-inline-styles rule | a violation |
| **secret-scan** | no secrets committed | a key/token/credential pattern in the diff |
| **observability / log-hygiene** | no sensitive value in a log/console call | a forbidden token at a log call site (allow a justified `// loghygiene:allow <reason>`) |
| **deferred-test registry** | no silent coverage gaps | a `DEFERRED-TEST:` marker with no row in the registry |
| **stub registry** | no silent incomplete integration | a `STUB:NAME` / `TBD:` marker with no registry row |
| **security sweep** | known-vuln deps, committed secrets, static-analysis smells | a HIGH+ dependency CVE, a secret in the tree, or a SAST finding (see below) |
| **doc-claims** | countable doc claims match reality | a hand-typed count in a running file ("through ADR-N", "N endpoints") disagrees with the computed truth (see the claims-checker pattern) |
| **state-snapshot** | the generated facts block is current | regenerating the block would change it (someone forgot to re-run the script) |

## The marker-and-registry pattern (reused for each "make the unfinished visible" gate)
1. Code site carries a marker: `DEFERRED-TEST:`, `STUB:PROVIDER`, `TBD:`, `TBD-UI:`.
2. A registry file lists every marker with: what's owed · why · the unblock trigger · how to resolve.
3. A check script greps the codebase for markers and fails if any marker lacks a registry row (and vice-versa).
4. When the blocker lands: do the work, remove the marker, delete the row, re-run the check.

```sh
# sketch of a registry check (adapt per project)
markers=$(grep -rno 'DEFERRED-TEST:' src/ | wc -l)
rows=$(grep -c '^|' docs/deferred-test-registry.md)
# fail if markers exist with no matching rows; print the offenders
```

## Example workflow skeleton (GitHub Actions — adapt to your stack)
```yaml
name: gates
on: [push, pull_request]
jobs:
  gates:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: «setup toolchain»
      - run: «build»
      - run: «test --coverage»          # + assert the coverage floor
      - run: «lint»                      # incl. no-inline-styles for UI
      - run: ./scripts/secret-scan.sh
      - run: ./scripts/check-log-hygiene.sh
      - run: ./scripts/list-deferred-tests.sh --check
      - run: ./scripts/list-stubs.sh --check
```

> Keep the check scripts tiny and greppable — agents maintain them, so they must be obvious. The gate is only as good as it is unhallucinatable.
>
> **⚠ Never pipe the gate runner.** `run-all-gates | tail` reports the PIPE's exit code, not the
> gates' — a red gate sails through the `&&` and gets pushed. Run it bare (or capture to a file and
> check `$?`). This exact mistake has shipped a red gate in the field; the runner's exit code is
> the contract.

## The generated-facts-block pattern (hand-typed counts always rot)
Any countable fact that appears in a running doc — how many ADRs and the highest number, the
migration head, endpoint count, open bugs, open cards — WILL drift if a human or agent types it
("ADRs through 68" while the tree says 78 is the canonical field failure). The fix:
1. The doc carries a marked block: `<!-- GENERATED:state-snapshot BEGIN -->` … `END -->`.
2. A tiny script computes the facts from the tree (ls/grep, no builds) and rewrites the block;
   its `--check` mode diffs a fresh regeneration against the file and fails if stale.
3. Wire `--check` as a gate. Prose *explains around* the block; scripts do the counting.

## The claims-checker pattern (prose claims rot on their own clock)
The subtler sibling: non-countable CLAIMS ("X is still to do", "blocked by Y", "in progress")
can't be auto-verified — but they CAN be auto-COLLECTED. A script greps the running files for the
claim patterns and prints every hit as a checklist; the quality review's claims axis (axis 5)
walks the generated list and verifies each against the code instead of relying on anyone's memory.
Auto-verify what's countable (the facts block above); checklist what needs judgment. Convention:
never quote a stale-claim literal in prose the checker reads — it self-flags.

## The security sweep (free, local tools — no paid scanner needed)
A dependency-CVE + secret + static-analysis sweep, run **every quality review, before every deploy,
and monthly regardless** (new CVEs land on their own clock, not on your commit clock). One free tool
per concern — substitute your stack's equivalent:

| Concern | Example free/local tool |
|---|---|
| Dependency CVEs | `npm audit` · `govulncheck` · `cargo audit` · `pip-audit` · `bundler-audit` · OWASP dependency-check |
| Committed secrets | `gitleaks` / `trufflehog` |
| Static analysis (SAST) | `gosec` · `bandit` · `semgrep` (community rules) · a linter's security ruleset |

Rules: **HIGH+ severity fails**; lower is reported for judgment. A finding is fixed **or explicitly
accepted by the owner with a reason** (a `bug-register.md` row). Each section **skips loudly with an
install hint** if its tool is absent — a skip is not a pass. Pin scanners to the project's toolchain
version so they don't fail with "requires newer/older runtime".

## Deploy + rollback discipline (even without hosted CI)
Three things must exist so "deployed" means "verified, and reversible":
1. **A deploy script** — gates first, build, publish an artifact **tagged by commit SHA** (not just
   `latest`), release, then **smoke-test the live surface**. "Deployed" without a green smoke is not
   done.
2. **A post-deploy smoke test** — a handful of unauthenticated checks (home loads, a key page 200s,
   the API answers with its expected auth-required status, not 5xx). Distinguish "app down" from
   "can't reach it from here".
3. **A written rollback procedure** — the 5-minute answer to "get back to the last good version".
   With SHA-tagged artifacts, rollback = re-point the release at the previous SHA (no rebuild). Note
   the **migration caveat**: if migrations run on deploy, a *destructive* migration is not
   rollback-safe — prefer **additive** migrations so old and new code both tolerate the schema.
