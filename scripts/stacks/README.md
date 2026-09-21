# Stack packs — where the language-neutral gates unfold back into specifics

Nothing in `scripts/` knows what language you write. Every language-shaped fact is a variable with
a loose union default (`lib/common.sh`). A **pack** replaces that union with exact values for one
language, and `HARNESS_STACK` in `harness.conf` selects it.

```sh
HARNESS_STACK="go"        # loads stacks/go.conf before harness.conf
```

**Precedence: defaults < pack < `harness.conf`.** The pack is a correct starting point for the
language; it cannot know your directory layout, your test runner flags, or your generated-code
conventions, so anything you set in `harness.conf` still wins. Naming a pack that does not exist is
a config error (`INCOMPLETE`), never a silent fall back to the union — a gate quietly checking
something other than what the project declared is the failure this whole kit is built around.

## Why a union default is the shipping state and not the operating state

A regex that matches `func|def|fn|function` matches a great deal and therefore proves very little.
It is there so a fresh clone does something useful before you have configured anything — not
because it is good enough. **Adopt a pack in your first act.** The difference is measurable: on a Go
codebase the generic declaration pattern misses every method with a receiver, and the gate reports a
confident zero over them.

## The pack is proven, not asserted

`scripts/selftest.sh` builds its fixture project **from the active pack** — the compliant source,
the test file, and one planted violation per gate all come from the pack's `HARNESS_FIX_*` values.
So running it proves the gates can see declarations, comments, skips and log calls **in your
language**, which is the only version of that claim worth anything.

```sh
scripts/selftest.sh                  # the pack harness.conf selects
scripts/selftest.sh --stack python   # one named pack
scripts/selftest.sh --all-stacks     # every pack shipped here
```

## Writing a pack for a language we do not ship

Copy the closest one and change the values. It is about twenty lines and no code.

| Variable | What it must match |
|---|---|
| `HARNESS_CODE_EXTS` | source extensions, space-separated, no dots |
| `HARNESS_DECL_RE` | a function/method declaration line (ERE) |
| `HARNESS_DECL_STRIP_RE` | a `sed -E` expression that removes everything before the name |
| `HARNESS_COMMENT_RE` | a comment line (ERE, anchored) |
| `HARNESS_TEST_GLOBS` | globs identifying test files |
| `HARNESS_SKIP_RE` | the test runner's skip call(s) |
| `HARNESS_ERROR_RE` | tokens that mean "something went wrong" in a condition |
| `HARNESS_EXCLUDE_GLOBS` | vendored, generated, build output |
| `HARNESS_LOG_FUNCS` | function-name fragments that count as logging |
| `HARNESS_TEST_CMD` / `HARNESS_COVERAGE_CMD` / `HARNESS_LINT_CMD` | your runner |
| `HARNESS_FIX_*` | the self-test fixture (see below) |

### The fixture values

Seven small snippets, written as `printf` format strings (`\n` for newline, `\t` for tab, `%%` for
a literal percent). Each one must be **exactly** what it claims, or the self-test proves the wrong
thing:

| Variable | Must be |
|---|---|
| `HARNESS_FIX_SRC_NAME` / `HARNESS_FIX_TEST_NAME` | filenames matching your `HARNESS_TEST_GLOBS` |
| `HARNESS_FIX_GOOD` | a **compliant** function: doc comment, an `ADR-001 §3` citation, a `DEFERRED-TEST:` marker |
| `HARNESS_FIX_TEST` | a **compliant** test: no skip, references `ADR-001` |
| `HARNESS_FIX_UNCITED` | a function with **no doc comment** (the citations plant) |
| `HARNESS_FIX_MARKER` | a documented+cited function carrying an **unregistered** marker (the markers plant) |
| `HARNESS_FIX_SKIP` | a test that **skips from an error branch** (the conditional-skips plant) |
| `HARNESS_FIX_LOG` | a documented+cited function that **logs a secret-named argument** (the log-hygiene plant) |

`selftest.sh` asserts the clean fixture passes, each plant fails, and removing it passes again. If
your pack's `HARNESS_FIX_GOOD` is not actually compliant you will see it immediately as a
false-positive on the clean run — which is the point.
