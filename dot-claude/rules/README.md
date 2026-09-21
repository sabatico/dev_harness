# Path-scoped rules — the routing table made structural

Files in `.claude/rules/` with `paths:` frontmatter load ONLY when the agent touches a matching
file. This is how the "your job → your rules" table stops being a Class-D remembered instruction:
a rule scoped to the files it governs cannot go unloaded while those files are edited.

Write one rule file per area (backend, tests, ui, docs, …). Keep each under ~50 lines: the rules
that catch people out + pointers to the authoritative doc — **the linked doc wins on detail; a rule
duplicated here is the copy that rots.**

`example-tests.md` shows the shape — note its `paths:` are a multi-ecosystem union so a fresh
clone matches something; narrow them to your stack pack's `HARNESS_TEST_GLOBS` on day one. **A
rule whose paths match nothing never loads, and nothing tells you** — the same invisible-absence
failure the SessionStart banner exists to make visible. Honest caveat: rules trigger when the agent READS or EDITS a
matching file — a brand-new file written blind through Bash can still miss the load. The
PostToolUse hooks are the backstop for that residue.
