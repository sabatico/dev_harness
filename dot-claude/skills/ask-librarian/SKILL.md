---
name: ask-librarian
description: Enrich context before any job — delegate "what does the repo already say about X" to the read-only librarian agent with a COMPLETE brief. Use at the start of any task touching prior decisions, before a design pass, and whenever tempted to read the corpus directly.
argument-hint: [topic or question]
---
Delegate retrieval on: $ARGUMENTS

Spawn the **librarian** agent (Agent tool, subagent_type "librarian"). The quality of its answer is
capped by the brief you send — a bare topic word finds one surface and misses four. Your delegation
prompt MUST contain all five parts:

1. **The question**, precisely — not "tell me about X" but the decision you need to make.
2. **The task behind it**, one sentence — so the librarian can judge relevance, not just match text.
3. **Every identifier you already have**: decision-record numbers, ticket ids, feature ids, file
   paths, function names, table names, flag names. Synonyms too — the same subject lives under
   different names on different surfaces.
4. **What you currently BELIEVE about it** — stated as assumptions to confirm or refute. This is
   the highest-value part: a wrong assumption quoted back against the contradicting source is the
   exact failure this whole mechanism exists to catch.
5. **Where it should also look if the obvious search is thin** — e.g. "check the schema", "check
   the sibling repo", "check closed tickets".

The librarian runs `scripts/librarian-sweep.sh` across every surface and returns a per-surface hit
accounting. **REQUIRE the SWEEP ACCOUNTING count table in its answer — an answer without it has
unverifiable coverage; send the agent back for it** (measured on the source project: three probes
in a row self-judged the sweep unnecessary and skipped it). Expect counts, not vibes.

Then WAIT for the result and treat its quotes as ground truth over your recall. If its
CONTRADICTIONS section is non-empty, that outranks the task you were given. If its NOT SEARCHED
list names a surface your task depends on, ask it to go there — do not fill the gap from memory.

When NOT to delegate: reading one specific file you already know (the decision record a function
cites; the record you are drafting) — those reads are personal duties.
