# Path-scoped rules — the routing table made structural

Files in `.claude/rules/` with `paths:` frontmatter load ONLY when the agent touches a matching file,
so the "your job → your rules" table stops being a remembered (Class D) instruction: a rule scoped to
the files it governs cannot go unloaded while those files are edited.

Write one rule file per area (backend, tests, ui, docs, …), each under ~50 lines: the rules that catch
people out + pointers to the authoritative doc. **The linked doc wins on detail; a rule duplicated
here is the copy that rots.**

`example-tests.md` shows the shape. Its `paths:` are a multi-ecosystem union so a fresh clone matches
something; narrow them to your stack pack's `HARNESS_TEST_GLOBS` on day one. **A rule whose paths
match nothing never loads, and nothing tells you** — the invisible-absence failure the SessionStart
banner exists to expose. Rules trigger when the agent READS or EDITS a matching file; a brand-new file
written blind through Bash can still miss the load, and the PostToolUse hooks are the backstop.
