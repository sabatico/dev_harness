# Token budget — how agents spend context

Agents use fewer tokens when they wait without polling, keep their context small and return
summaries. **The quality process does not change** (R7). Short form for every agent:
`following-core-rules` rule 12. Lead side: `orchestrating-agents` section 10. Standing rule: the
"Token discipline" bullet in `CLAUDE.md`. The one project number (the concurrency cap) is a knob:
`HARNESS_MAX_SESSIONS` in `harness.conf` (default 4).

**Origin.** The owner of the first adopting project asked for this after the plan's weekly usage
limit stopped every session for four days. The owner's brief to the lead: "optimize without loosing
quality", and the details were delegated ("once decided yourself - implement").

## Contents

- Why: what a scan of one project measured
- Published guidance
- The rules R1–R9
- Trade-offs and what was not done
- How to re-measure in your project

## Why: what a scan of one project measured

The lead of the first adopting project scanned every saved conversation of that project (15 active
days, about 55,000 model calls). Weighted tokens = fresh input ×1, cache write ×1.25, cache read
×0.1, output ×5 (the API price shape; the plan-limit weights are not verified). A smaller project
of the same owner was the comparison.

| Fact | Number |
|---|---|
| Weighted tokens per active day, this project vs the comparison | 164M vs 24M |
| Weighted cost per call, this project vs the comparison | 44k vs 48k — the gap is the NUMBER of calls, not their size |
| **Waiting checks: 35% of all tokens** | re-reading a job log (9,150 calls), sleep-then-check (2,501 calls), checking processes (1,102 calls); sub-agents did two thirds of it |
| Cache rewrites: 18% | 1,156 times a conversation woke after a 5–60 minute gap and re-wrote its whole context |
| Sub-agents | 63% of all tokens; median 66 calls per sub-agent (16 in the comparison); median end context 263k tokens |
| Tool output kept in context | simulator screenshots, code reads, shell output, search output, test/gate output and log tails, in that order |
| Start size | new sessions about 93k tokens, sub-agents about 67k |

The lesson: **every tool call re-sends the whole context.** A cheap-looking `tail` of a log costs
the full 250–500k context each time. Waiting by checking is the biggest avoidable cost.

## Published guidance

These quotes were fetched on the day of the decision; re-check them before you rely on them.

- "Claude Code sends your full conversation with every request, and each time Claude uses tools it
  sends another request carrying that batch of tool results." — https://code.claude.com/docs/en/costs
- "your first message after a break longer than the cache lifetime misses the cache and reprocesses
  your full context." — https://code.claude.com/docs/en/costs
- "returns only a condensed, distilled summary of its work (often 1,000-2,000 tokens)." —
  https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- "Keep teams small. Each teammate runs its own context window, so token usage is roughly
  proportional to team size." — https://code.claude.com/docs/en/costs
- "multi-agent systems work best today when writes stay single-threaded." —
  https://cognition.com/blog/multi-agents-working
- "A fresh context improves code review since Claude won't be biased toward code it just wrote." —
  https://code.claude.com/docs/en/best-practices

## The rules R1–R9

- **R1 Wait without polling.** Run every long job (tests, gates, builds, anything that takes the
  heavy-run queue) as ONE background command with its output in a log file, then END THE TURN. The
  harness wakes the agent once when the command exits. Never: a sleep/check loop, a repeated `tail`
  of a log, repeated `ps`/`pgrep`/`lsof`, a monitor that wakes the model while it waits for a job.
  WHY: each check re-reads the whole context; 35% of all tokens went to this.
- **R2 Read summaries, not dumps.** Read a log once, at the end: `tail -40`, or a grep for
  FAIL / INCOMPLETE / rc=. Read files by section after `scripts/find.sh` (or `scripts/refs.sh` for a
  known id or path) locates the spot. Pipe long output through `tail`, `head` or `grep -c`.
  Screenshots: as few as the check needs, scaled down (0.5 or lower), text reads (accessibility tree,
  page text) first; for many screens, a short-lived checker sub-agent returns a text verdict.
- **R3 Return summaries.** A sub-agent's final report stays under about 1,500 words. Detail goes into
  a file in the scratchpad, never into a commit (logs and screenshots can hold device identifiers),
  and the report names the path.
- **R4 Small slices.** One sub-agent = one bounded job, aimed at about 40 tool calls. Bigger work runs
  as a sequence of fresh agents, each started from a short handoff file, not one agent whose context
  grows past 250k. A sub-agent never waits on the heavy-run queue in a loop: it starts the job in the
  background and ends its turn, or it hands back "ready for the heavy run" and the lead runs it.
- **R5 Concurrency cap.** At most `HARNESS_MAX_SESSIONS` (default 4) sessions or builder agents doing
  work at once; no new one starts while the cap is reached; each holds at most one heavy job in the
  queue (`scripts/heavy-run.sh`). Read-only reviewers and researchers may run in parallel; writes stay
  one per file set. WHY (the owner of the first adopting project): "i am ok to lower concomitent
  agents so we dont have them wait for test locks" — the extra agents only queued for the test lock,
  and polled while they waited.
- **R6 Lead side.** The lead reacts to session notes and task notifications. Its backup check is ONE
  scheduled wake-up about every 20 minutes — the only wake R1 allows, and it re-reads the whole
  context, so the lead keeps its context short. It reads another session's events with a small limit
  (about 6), and only when that session's status shows FINAL, QUESTION or an orphan. Every brief names
  the context budget: R1–R4 by reference, the exact files, and the facts pasted. After a wave the lead
  starts a fresh lead session from a handoff file instead of carrying a context of 500k tokens.
  Reviewer briefs carry the diff and the criteria, and ask for correctness findings only.
- **R7 What does NOT change.** A different agent writes the tests; the check-the-work review runs
  before every sub-session commit (`ci/review-step.md`); the gates and the push receipt are
  unchanged; questions come before guesses (`following-core-rules` rule 11).
- **R8 Scoped checks while working; heavy checks only at a commit or a full scan.** While a builder or
  a tester works, it runs only the tests and lint of the code it changed — seconds, no containers, no
  place in the heavy-run queue. The heavy checks (the whole-tree test run, integration tests against a
  database in a container, platform builds in a container, the full lint) run once per branch, by the
  last agent before the branch's final commit (normally the cross-author tester, after the tests are
  in), and again in the full gate run before a push (unchanged, R7). A change to shared code or to a
  contract still gets the heavy run before its commit. Each stack's test runner should offer a scoped
  fast mode (for example `--fast <packages>`) that prints, first and last, that it is NOT a full run,
  writes no receipt, and still fails on zero tests or a skipped test. WHY (the owner of the first
  adopting project): "write code , cover it with tests with another agent - pass gated tests and move
  forward. at commit or at full scans- perform dockertesting and such" and "running dockertets at
  every hagne - is too expensive" — two builders whose briefs asked for the full run as their proof
  queued more than 30 minutes behind each other for a 10-minute container-backed test run.
- **R9 Full runs only on the owner's request or before a push; merges test what the change can affect.** This
  narrows R8's "the heavy run once per branch, by the last agent before the final commit". Three levels: (1) while
  working — only the checks of the changed code (R8); (2) at a merge of a code branch into the main branch — the
  AFFECTED set: the changed packages or modules plus everything that imports them, with containers (an integration
  database, container builds) only when the branch changes code that runs against them; small and documentation-only
  commits run no code tests; (3) the full set (whole tree, containers, the push-receipt gate run) only when the owner
  asks, or before a push, which the owner requests after a longer series of commits. Each stack's test runner should
  offer an "affected" mode beside its fast mode. WHY (the owner of the first adopting project): "ful ltests only at my
  request or at push towards github - i usually request pushestowards fithub after a longer series of commits" — a
  10-minute container-backed run before a merge re-tested parts the branch did not touch.

**Model choice is part of the budget** (`orchestrating-agents` section 2): the strong model plans,
briefs and judges; the mid model writes the code. For an easy step, lower the EFFORT and keep the
model — a model switch inside a session throws away its prompt cache, so a cheaper model can cost
more over a job.

## Trade-offs and what was not done

- **A longer cache lifetime for sub-agents was NOT turned on.** It makes cache writes more expensive
  and pays only when an agent idles for minutes. The fix is that agents stop idling (R1, R4).
- **A smaller `CLAUDE.md` was not part of the change.** Every session starts with it, but trimming it
  risks losing rules. A later slice can measure what each line buys.
- **The concurrency cap costs some wall-clock time** when work could run wider. In the field case the
  queue made the extra agents wait (and poll) anyway, so the loss was small.

## How to re-measure in your project

1. Sum the per-message `usage` fields (input, cache creation, cache read, output) from the project's
   saved conversations (Claude Code keeps them as `.jsonl` files in the projects folder of its home settings folder),
   de-duplicated by message id (a streamed message appears several times).
2. Weight them as in the table above. Group by day, by agent (main or sub-agent) and by the tool call
   that came before each model call (a waiting check, a read, a test run).
3. Compare the waiting-check share and the weighted tokens per active day one week after you adopt
   the rules. Record the before and after in the decision record that adopted them.

Never send these files anywhere: they hold the full conversations. The measurement runs locally.
