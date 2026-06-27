# Deferred-Test Registry — «PROJECT»

> The single source of truth for **test coverage we owe but cannot write yet** because a dependency is missing. Marker in code = `DEFERRED-TEST:`. A CI check fails if a marker has no row here.
> **Goal:** no silent coverage gaps. The coverage a slice *would* have had — if the dependency existed — is recorded so it **resurfaces and gets written the moment the dependency lands**, instead of being quietly dropped and rediscovered when the project is large.

| Code site | What's owed | Why deferred (missing dependency) | Unblock trigger | How to test (when unblocked) | Target |
|-----------|-------------|-----------------------------------|-----------------|------------------------------|--------|
| `path/to/file` (`Func`) | «the assertions owed» | «the missing harness/sandbox/module/external dep» | «what lands to unblock it» | «the test to write» | «coverage target» |

## Un-gating (when a dependency lands)
1. Write the owed tests **in the same slice** that lands the dependency (the resurface rule).
2. Remove the `DEFERRED-TEST:` marker from the code.
3. Delete the row above.
4. Re-run the registry CI check (clean) + confirm the slice meets its coverage target.
