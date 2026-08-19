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

Rules: **HIGH+ severity fails**; lower is reported for judgment. Route each finding into the ticket
system (`running-files/tickets/`): a live **defect** → `bug-register.md` (`BUG`); a **hardening /
coverage / accepted-false-positive** item → `security.md` (`SEC`, incl. the accepted-with-reason
rows, so a suppression is auditable, never silent). Fix inline only if quick + in scope; otherwise
the ticket is the record. Each section **skips loudly with an install hint** if its tool is absent —
a skip is not a pass. Pin scanners to the project's toolchain version so they don't fail with
"requires newer/older runtime".

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

---

# Gate INTEGRITY — the gates themselves are code, and they fail in ways that look like success

Everything above assumes a gate that reports green has *checked something*. That assumption is where
the expensive failures live. **In one project, three separate gates were found reporting "all clear"
after examining zero files, and the pattern that produced it was identical each time.** None of them
looked broken; each printed a confident summary line.

**Read this section as the answer to one question: how would I know if this gate were lying?**

## G1 · A gate must REFUSE to report success over an empty scan

The shape, and it is always the same:

```sh
FILES=$(git ls-files '*.ext' | grep ... || true)   # ← the `|| true` is the whole bug
for f in $FILES; do ...; done
echo "OK: all $COUNT files pass."                   # ← prints "all 0 files pass" and exits 0
```

`|| true` on the line that produces the **work list** is not defensive — it is a mute button. If the
enumeration breaks (a wrong path prefix, a failed VCS call, an over-eager filter), the loop runs zero
times and the gate congratulates you.

**Every gate that builds a work list must assert the list is non-empty**, or carry an explicit floor:

```sh
if [ -z "$WORK_LIST" ]; then
  echo "✗ enumerated ZERO items — the scanner is broken, not the tree. Refusing to report green." >&2
  exit 1
fi
```

**A worse variant, worth naming separately: a gate that HASHES.** A tree-hash or fingerprint computed
over an empty enumeration is not random — it is the hash of nothing, and it is **stable**. So a
receipt written while the enumeration was broken will **match** a later check made while it was still
broken, and the whole mechanism passes having verified an empty tree. If your gate produces a digest,
it must refuse to emit one for an empty input.

## G2 · Capture every gate's output, or a red can only be believed or ignored

A gate that fails inside a summarised run — `... | tail -4`, a CI step that prints only the last
lines — destroys the only copy of the evidence. The failure then cannot be *diagnosed*, only argued
about, and the usual outcome is "probably flaky, re-run it".

**Tee each gate to its own log** and print the path in the summary:

```sh
run_gate() {
  local name="$1"; shift
  "$@" 2>&1 | tee "$GATE_LOGS/$name.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] && PASS+=("$name") || FAIL+=("$name")
}
```

⚠ **`$?` after a pipeline is the LAST command's status, not your gate's.** `cmd | tee f; echo $?`
reports `tee`. Use `PIPESTATUS[0]`, or you will record passes for failing gates.

**This pays for itself the first time an unrelated suite goes red.** In one case a gate failed inside
a run touching a completely different subsystem, passed 3/3 on re-run, and would have been dismissed
as flakiness — the captured log named the exact line, and it was a real (load-dependent) defect.

## G3 · RATCHET a new gate; do not demand a clean sweep

A gate introduced against an existing codebase finds pre-existing violations. Blocking on all of them
means the gate does not ship — and the archaeology mostly produces guesses, which is worse than
silence.

**Freeze what exists, refuse what is new:**

```
scripts/<gate>-baseline.txt     # one frozen violation per line, with a header saying WHY
```

Rules that keep a baseline honest:
- Every line is a **known** violation at a known date — never a way to silence a new one.
- **Fix a line by deleting it**; the gate then guards that case forever.
- Say in the header **what the baseline is not**: it is not a to-do list, and it is not permission.
- **Report the count** on every run, so a growing baseline is visible.

Before freezing, **triage the initial violations** — in one case 47 hits were 4 categories, and 3 of
them were legitimate (paths in a sibling repo, forward references in a plan document, deliberate
records of a rename). Freezing without triage buries real findings among false ones.

## G4 · Bind the VERIFIED tree to the PUSHED tree

"Gates passed" and "gates passed on *this* code" are different claims. Between the run and the push,
a file changes and the claim silently becomes false.

**Write a receipt** — a hash of the working tree — when the gates pass, and have the pre-push hook
recompute it and compare. Two details decide whether it works:
- **Include untracked-but-not-ignored files.** A hash of tracked files only will not notice the new
  file you just wrote, which is exactly the code most likely to be unverified.
- **Use ONE shared hashing function** for both the writer and the checker. Two implementations drift,
  and the first symptom is a hook that refuses the very commit that created it.

## G5 · A gate cannot judge MEANING — say so, or a green will be over-read

Mechanical checks verify *shape*: does the file exist, does the token match the vocabulary, is the row
present. They cannot verify that the cited document is the right one, that the comment is true, or
that the test is meaningful.

**Write the limit into the gate's own header.** A gate whose green is over-read is worse than no gate,
because it converts an open question into a settled one. Two examples worth copying:
- a citation gate proves the pointer exists, never that it points anywhere true;
- a coverage gate proves lines executed, never that anything was asserted about them (see the
  mutation-testing note in `test-and-coverage.md`).

## G6 · Prefer checking against CODE over checking two prose surfaces against each other

A natural first instinct is to cross-check two documents — a status line against a tracker row, a
count in one file against a count in another. **This produces false alarms immediately**, because
prose says the same thing many ways: *"accepted — building"* and *"unblocked, not yet built"* are one
state in two vocabularies.

**Compare a claim against the artefact it describes.** Does a document claiming a feature is built
have code that references it? Does a path named in prose exist on disk? Those answers are binary. If
you genuinely need two documents to agree, **standardise the vocabulary first** and gate the token,
not the sentence.

## G7 · Watch a new gate FAIL before you trust it

The first run of a new gate is not evidence. Plant a known violation, watch it exit non-zero, remove
it, watch it pass, and confirm the removal was byte-identical.

**Do this even when — especially when — the gate reports a clean tree on its first run.** Of the
gates in the case above, one was written *specifically* to catch a class of error, reported a clean
tree, and was only found to be scanning nothing because its author planted a violation and it did not
notice.

## G8 · A gate's LOGIC and its WIRING are separate claims — verify both

G7 proves the gate's **logic**: plant a violation, watch it go red. Necessary, and not sufficient.

Three controls failed on one project in a single week, and **none of them had broken logic**. One ran
too late to matter, one was wired to its own weaker mode while the strict path sat uncalled, and one
was never loaded by the session that was supposed to be protected by it. G7 passes on all three.

> **Calling the script directly proves the script. The script was never the broken part.**

So adoption of any gate has two verification steps, not one:

1. **Logic** (G7) — plant a violation → red → remove → green → byte-identical restore.
2. **Wiring** (G8) — trigger it through the **real path**: the actual editor hook, the actual runner,
   the actual deploy command. Watch it fire *there*.

The second step is the only one that catches "installed but not loaded", "runs after the cost is
sunk", and "the strict mode exists and nothing calls it". A control that is **installed** is not a
control that is **running**.

Full treatment, including the write-time/push-time split and the blocking-vs-advisory tiering that
decides whether a hook survives contact with real work: **`ci/control-timing.md`**.

## Beyond one gate: multi-stage runs

Everything above governs a single gate. A nightly sweep, security suite, or end-to-end run fails in a
related but nastier way — the stages that worked produce a detailed, plausible report, and the stage
that scanned nothing contributes silence, so the whole run reads as clean because most of it is.

That needs a manifest, a status vocabulary, and an explicit COMPLETE/INCOMPLETE verdict:
**`ci/run-integrity.md`**.
