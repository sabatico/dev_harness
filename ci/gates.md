# CI Gates — the enforcement layer

The SOPs are honor-system until CI enforces them. These are the gates every project should wire so
the rules cannot quietly erode. Make them **required status checks** on the default branch.

> **No hosted CI? Run them locally.** Wire every gate into **one script** (`scripts/run-all-gates.sh`
> — a fast tier cheap enough to run constantly, plus `--full` for the suites, `--lint`, `--all`, and
> `--verify-receipt` for G4) and run it **before every push**. The security sweep is a separate,
> slower cadence, not a tier of the fast runner. State plainly in `CLAUDE.md` that CI is local, keep
> the workflow file below as a dormant reference, and make the runner **say what it skipped**
> (missing toolchain/service) — a skip is not a pass.

## Contents

- The gates (table; "Ships?" column first)
- The marker-and-registry pattern
- Example workflow skeleton
- The generated-facts-block pattern
- The claims-checker pattern
- The security sweep
- Deploy + rollback discipline
- Gate INTEGRITY: G1 empty scan · G2 capture output · G3 ratchet · G4 receipt · G5 meaning · G6 check against code · G7 watch it fail · G8 logic vs wiring
- Beyond one gate: multi-stage runs

## The gates

**Read the "Ships?" column first** (C5, `control-timing.md`, applied to the kit itself): **✅ = a
script in `scripts/` runs it today** (and `scripts/selftest.sh` proves it fails on its own
violation); **📄 = doctrine only — the script is yours to write.** Nothing enforces a 📄 until you do.

| Gate | Ships? | What it enforces | Fails when |
|------|--------|------------------|-----------|
| **build** | ✅ via `HARNESS_TEST_CMD`-style config (`--full`) | it compiles | build error |
| **test** | ✅ via `HARNESS_TEST_CMD` (`--full`) | the suite passes | any test fails |
| **coverage floor** | ✅ via `HARNESS_COVERAGE_CMD` (`--full`) | coverage-is-Done | new/changed code below the target band (per-layer floors) |
| **lint / format** | ✅ via `HARNESS_LINT_CMD` (`--lint`) | style + the UI no-inline-styles rule | a violation |
| **secret-scan** | 📄 use `gitleaks`/`trufflehog` — see the security sweep | no secrets committed | a key/token/credential pattern in the diff |
| **observability / log-hygiene** | ✅ `check-log-hygiene.sh` | no sensitive value in a log/console call | a forbidden token at a log call site (allow a justified `harness:allow-log <reason>` **on the offending line**) |
| **deferred-test registry** | ✅ `check-markers.sh` | no silent coverage gaps | a `DEFERRED-TEST:` marker with no row in the registry |
| **stub registry** | ✅ `check-markers.sh` (same gate, another pair) | no silent incomplete integration | a `STUB:NAME` / `TBD:` marker with no registry row |
| **security sweep** | 📄 wire your stack's tools | known-vuln deps, committed secrets, static-analysis smells | a HIGH+ dependency CVE, a secret in the tree, or a SAST finding |
| **doc-claims** | 📄 the claims-checker pattern below | countable doc claims match reality | a hand-typed count in a running file ("through ADR-N", "N endpoints") disagrees with the computed truth |
| **state-snapshot** | 📄 the facts-block pattern below | the generated facts block is current | regenerating the block would change it |

Also shipping, as harness hygiene rather than product gates: `check-doc-links.sh` (every markdown
link resolves — blocking at write time), `check-doc-paths.sh` (every bare backticked path exists,
ratcheted), `check-doc-index.sh` (every doc is registered), `check-bug-evidence.sh` (a closed bug
names its mutation + the test that went red), `check-conditional-skips.sh` (no test skips from an
error branch), `check-citations.sh` (a function you touched cites its decision record).
`scripts/README.md` has the full list.

## The marker-and-registry pattern (reused for each "make the unfinished visible" gate)

1. The code site carries a marker: `DEFERRED-TEST:`, `STUB:PROVIDER`, `TBD:`, `TBD-UI:`.
2. A registry file lists every marker with: what is owed · why · the unblock trigger · how to resolve.
3. A check script greps the codebase for markers and fails if any marker lacks a registry row (and
   vice-versa).
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
      - run: ./scripts/run-all-gates.sh   # the fast tier: docs, markers, citations, log-hygiene
      - run: «secret-scan»                # gitleaks / trufflehog — you supply this one
```

`run-all-gates.sh` is the whole fast tier; do not list the individual `check-*.sh` scripts here or a
new gate silently stays out of CI. Anything in angle brackets is yours to fill.

> Keep check scripts tiny and greppable — agents maintain them, so they must be obvious.
>
> **Never pipe the gate runner.** `run-all-gates | tail` reports the PIPE's exit code, not the
> gates' — a red gate sails through the `&&` and gets pushed (this shipped a red gate in the field).
> Run it bare, or capture to a file and check `$?`. The runner's exit code is the contract.

## The generated-facts-block pattern (hand-typed counts always rot)

Any countable fact in a running doc — number of ADRs and the highest, the migration head, endpoint
count, open bugs, open cards — WILL drift if typed ("ADRs through 68" while the tree says 78 is the
canonical field failure).

1. The doc carries a marked block: `<!-- GENERATED:state-snapshot BEGIN -->` … `END -->`.
2. A tiny script computes the facts from the tree (ls/grep, no builds) and rewrites the block; its
   `--check` mode diffs a fresh regeneration against the file and fails if stale.
3. Wire `--check` as a gate. Prose *explains around* the block; scripts do the counting.

## The claims-checker pattern (prose claims rot on their own clock)

Non-countable claims ("X is still to do", "blocked by Y", "in progress") cannot be auto-verified but
can be auto-COLLECTED: a script greps the running files for the claim patterns and prints every hit
as a checklist; the quality review's claims axis (axis 5) walks the list and verifies each against
the code. Auto-verify what is countable (the facts block); checklist what needs judgment. Never
quote a stale-claim literal in prose the checker reads — it self-flags.

## The security sweep (free, local tools — no paid scanner needed)

Run a dependency-CVE + secret + static-analysis sweep **every quality review, before every deploy,
and monthly regardless** (new CVEs land on their own clock). One free tool per concern; substitute
your stack's equivalent:

| Concern | Example free/local tool |
|---|---|
| Dependency CVEs | `npm audit` · `govulncheck` · `cargo audit` · `pip-audit` · `bundler-audit` · OWASP dependency-check |
| Committed secrets | `gitleaks` / `trufflehog` |
| Static analysis (SAST) | `gosec` · `bandit` · `semgrep` (community rules) · a linter's security ruleset |

Rules:
- **HIGH+ severity fails**; lower is reported for judgment.
- Route each finding into the ticket system (`running-files/tickets/`): a live **defect** →
  `bug-register.md` (`BUG`); a **hardening / coverage / accepted-false-positive** item →
  `security.md` (`SEC`, incl. accepted-with-reason rows, so a suppression is auditable, never
  silent). Fix inline only if quick + in scope; otherwise the ticket is the record.
- Each section **skips loudly with an install hint** if its tool is absent — a skip is not a pass.
- Pin scanners to the project's toolchain version so they do not fail with "requires newer/older
  runtime".

## Deploy + rollback discipline (even without hosted CI)

"Deployed" must mean "verified, and reversible". Three things must exist:

1. **A deploy script** — gates first, build, publish an artifact **tagged by commit SHA** (not just
   `latest`), release, then **smoke-test the live surface**. "Deployed" without a green smoke is not
   done.
2. **A post-deploy smoke test** — a handful of unauthenticated checks (home loads, a key page 200s,
   the API answers with its expected auth-required status, not 5xx). Distinguish "app down" from
   "can't reach it from here".
3. **A written rollback procedure** — the 5-minute answer to "get back to the last good version".
   With SHA-tagged artifacts, rollback = re-point the release at the previous SHA (no rebuild).
   Migration caveat: if migrations run on deploy, a *destructive* migration is not rollback-safe —
   prefer **additive** migrations so old and new code both tolerate the schema.

---

# Gate INTEGRITY — the gates themselves are code, and they fail in ways that look like success

A gate that reports green is assumed to have *checked something*. In one project three separate
gates reported "all clear" after examining zero files, by the same pattern each time, each printing a
confident summary. For every gate ask: **how would I know if it were lying?**

## G1 · A gate must REFUSE to report success over an empty scan

```sh
FILES=$(git ls-files '*.ext' | grep ... || true)   # ← the `|| true` is the whole bug
for f in $FILES; do ...; done
echo "OK: all $COUNT files pass."                   # ← prints "all 0 files pass" and exits 0
```

`|| true` on the line that produces the **work list** is a mute button: if the enumeration breaks (a
wrong path prefix, a failed VCS call, an over-eager filter) the loop runs zero times and the gate
congratulates you. **Every gate that builds a work list must assert the list is non-empty**, or
carry an explicit floor:

```sh
if [ -z "$WORK_LIST" ]; then
  echo "✗ enumerated ZERO items — the scanner is broken, not the tree. Refusing to report green." >&2
  exit 1
fi
```

**Hashing variant:** a tree-hash or fingerprint over an empty enumeration is the hash of nothing, and
it is **stable** — a receipt written while enumeration was broken will **match** a later check made
while it was still broken, verifying an empty tree. A gate that produces a digest must refuse to emit
one for empty input.

## G2 · Capture every gate's output, or a red can only be believed or ignored

A gate that fails inside a summarised run (`... | tail -4`, a CI step printing only the last lines)
destroys the only copy of the evidence; the failure can then only be argued about ("probably flaky,
re-run it"). **Tee each gate to its own log** and print the path in the summary:

```sh
run_gate() {
  local name="$1"; shift
  "$@" 2>&1 | tee "$GATE_LOGS/$name.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] && PASS+=("$name") || FAIL+=("$name")
}
```

`$?` after a pipeline is the LAST command's status (`cmd | tee f; echo $?` reports `tee`); use
`PIPESTATUS[0]` or you record passes for failing gates. This paid for itself when a gate failed
inside an unrelated run, passed 3/3 on re-run and would have been dismissed as flaky — the captured
log named the line, a real load-dependent defect.

## G3 · RATCHET a new gate; do not demand a clean sweep

A gate introduced against an existing codebase finds pre-existing violations; blocking on all of them
means it does not ship, and the archaeology mostly produces guesses. **Freeze what exists, refuse
what is new:**

```
.harness/baselines/<gate>.txt   # one frozen violation per line, under a header saying WHY
```
(`HARNESS_BASELINE_DIR` in `harness.conf`; written by a gate's `--write-baseline` mode.)

Keep a baseline honest:
- Every line is a **known** violation at a known date — never a way to silence a new one.
- **Fix a line by deleting it**; the gate then guards that case forever.
- The header says what the baseline is **not**: not a to-do list, not permission.
- **Report the count** on every run, so a growing baseline is visible.
- **Triage before freezing:** in one case 47 hits were 4 categories, 3 of them legitimate (paths in a
  sibling repo, forward references in a plan, deliberate records of a rename). Freezing untriaged
  buries real findings among false ones.

## G4 · Bind the VERIFIED tree to the PUSHED tree

"Gates passed" and "gates passed on *this* code" differ: between run and push a file changes. **Write
a receipt** (a hash of the working tree) when the gates pass, and have the pre-push hook recompute it
and compare. Two details decide whether it works:
- **Include untracked-but-not-ignored files** — the new file you just wrote is the code most likely
  to be unverified.
- **Use ONE shared hashing function** for writer and checker; two implementations drift, and the
  first symptom is a hook refusing the very commit that created it.

## G5 · A gate cannot judge MEANING — say so, or a green will be over-read

Mechanical checks verify *shape* (file exists, token matches the vocabulary, row present), never that
the cited document is the right one, the comment true, or the test meaningful. **Write the limit into
the gate's own header**: a green that is over-read converts an open question into a settled one.
Examples: a citation gate proves the pointer exists, never that it points anywhere true; a coverage
gate proves lines executed, never that anything was asserted (see the mutation-testing note in
`test-and-coverage.md`).

## G6 · Prefer checking against CODE over checking two prose surfaces against each other

Cross-checking two documents (a status line against a tracker row, a count in one file against
another) gives false alarms immediately, because prose says one thing many ways: *"accepted —
building"* and *"unblocked, not yet built"* are one state in two vocabularies. **Compare a claim
against the artefact it describes**: does a document claiming a feature is built have code that
references it? Does a path named in prose exist on disk? Those are binary. If two documents must
agree, **standardise the vocabulary first** and gate the token, not the sentence.

## G7 · Watch a new gate FAIL before you trust it

The first run of a new gate is not evidence.

1. Plant a known violation.
2. Watch the gate exit non-zero.
3. Remove the violation; watch the gate pass.
4. Confirm the removal was byte-identical.

Do this especially when the gate reports a clean tree on its first run: one gate, written
specifically to catch a class of error, reported a clean tree and was found to be scanning nothing
only because its author planted a violation and it did not notice.

## G8 · A gate's LOGIC and its WIRING are separate claims — verify both

G7 proves **logic**; it is necessary and not sufficient. Three controls failed on one project in a
week and none had broken logic: one ran too late, one was wired to its weaker mode while the strict
path sat uncalled, one was never loaded by the session it was meant to protect. G7 passes on all
three.

> **Calling the script directly proves the script. The script was never the broken part.**

Adopt a gate in two verification steps:

1. **Logic** (G7) — plant a violation → red → remove → green → byte-identical restore.
2. **Wiring** (G8) — trigger it through the **real path** (the actual editor hook, runner or deploy
   command) and watch it fire *there*. This catches "installed but not loaded", "runs after the cost
   is sunk" and "the strict mode exists and nothing calls it".

A control that is **installed** is not a control that is **running**. Full treatment, including the
write-time/push-time split and blocking-vs-advisory tiering: **`ci/control-timing.md`**.

## Beyond one gate: multi-stage runs

A nightly sweep, security suite or end-to-end run fails more subtly: the stages that worked produce a
plausible report and the stage that scanned nothing contributes silence. That needs a manifest, a
status vocabulary and an explicit COMPLETE/INCOMPLETE verdict: **`ci/run-integrity.md`**.
