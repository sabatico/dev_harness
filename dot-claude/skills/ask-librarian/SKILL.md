---
name: ask-librarian
description: Enrich context before any job — delegate "what does the repo already say about X" to the read-only librarian, which runs forked in its own context with the full per-surface sweep already run for it. Use at the start of any task touching prior decisions, before a design pass, before filing a ticket, and whenever tempted to read the corpus or answer from memory. ARGUMENTS = the complete 5-part brief — (1) the question/decision, precisely; (2) the task behind it, one sentence; (3) every identifier and synonym you have, ALSO as one line `TERMS: a | b | c`; (4) what you currently BELIEVE, as assumptions to confirm or refute (highest-value part); (5) extra surfaces to check. Its quotes outrank your recall. NOT for one specific file you already know (the decision record a function cites, the record you are drafting) — read that yourself.
argument-hint: "[5-part brief incl. a TERMS: a | b | c line]"
context: fork
agent: librarian
background: false
allowed-tools: Bash(bash *librarian-presweep.sh*)
---
<!--
WHY THIS SKILL FORKS (generalised 2026-09-29 from a live project). Its first harness eval measured the
librarian's one systematic weakness: all three probes "self-judged the full sweep unnecessary and
skipped" the per-surface accounting — an instruction competing with agent judgment loses. So the sweep
is INJECTED: `context: fork` + `agent: librarian` runs this body as the librarian's prompt, and the
injected shell block below runs before the prompt exists, so its output lands in the LIBRARIAN's window,
never the caller's. ARGUMENTS are substituted as RAW TEXT into that block, so the brief reaches the shell
only through a QUOTED heredoc (never parsed; $(…) and backticks in it are inert). Caller-side rules live
in the description, because a forked skill's caller never sees this body; the footer repeats them.
⚠ NEVER write the three-backticks-plus-bang opener anywhere in this file except the real block: the
loader matched it MID-SENTENCE inside a comment like this one and tried to run the comment plus the
brief as a shell command (a permission check refused it). Say "the injected shell block".
⚠ allowed-tools must pre-approve the command: in a forked skill with `agent`, an unapproved injected
command ABORTS the invocation, even in auto mode.
-->
# Retrieval request from the lead agent

$ARGUMENTS

# PRE-SWEEP — already run for you, on the caller's terms, before you started

```!
bash "${CLAUDE_PROJECT_DIR}/scripts/librarian-presweep.sh" <<'HARNESS_BRIEF_EOF'
$ARGUMENTS
HARNESS_BRIEF_EOF
```

# What to do

Follow your standing procedure, with one change: **step 1's sweep has been run for you** on the
caller's terms (above). That is a floor, not the whole job:

1. **Step 0 still applies.** Derive the aliases the caller did not know (glossary term, feature id,
   governing decision records, ticket ids, code names) and run `scripts/librarian-sweep.sh` once more
   with **only the NEW aliases** (skip it only if step 0 found none — say so).
2. Deep-read the hit files and answer in your standard format. The **SWEEP ACCOUNTING** section is the
   pre-sweep table above plus your alias sweep's table — both, verbatim counts.
3. Every stated assumption in the brief gets CONFIRMED / REFUTED / NOT FOUND with a verbatim quote and
   `file:line`, or the searches that came back empty.
4. End your answer with this footer, verbatim:

> **For the caller:** these quotes outrank your recall. A non-empty CONTRADICTIONS section outranks
> the task you were given. If NOT SEARCHED names a surface your task depends on, send me back
> there — do not fill the gap from memory.
