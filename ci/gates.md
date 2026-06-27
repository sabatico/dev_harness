# CI Gates — the enforcement layer

The SOPs are honor-system until CI enforces them. These are the gates every project should wire so the rules can't quietly erode. Make them **required status checks** on the default branch.

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
