# Path-scoped rules — the routing table made structural

Files in `.claude/rules/` with `paths:` frontmatter load ONLY when the agent touches a matching
file. This is how the "your job → your rules" table stops being a Class-D remembered instruction:
a rule scoped to the files it governs cannot go unloaded while those files are edited.

Write one rule file per area (backend, tests, ui, docs, …). Keep each under ~50 lines: the rules
that catch people out + pointers to the authoritative doc — **the linked doc wins on detail; a rule
duplicated here is the copy that rots.**

`example-tests.md` shows the shape. Honest caveat: rules trigger when the agent READS or EDITS a
matching file — a brand-new file written blind through Bash can still miss the load. The
PostToolUse hooks are the backstop for that residue.
