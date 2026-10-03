# A visual board: coordination-only

A board earns its keep for what a repo cannot do — the owner's queue, deadlines, at-a-glance
blockage — and destroys value the moment it duplicates engineering state.

## Allowed card types ONLY (adapt the names, keep the shape)

- **owner-action** — something only the owner can do.
- **owner-decision** — question → options, each with one honest consequence line → the lead's
  recommendation → what it unblocks. The decision is *recorded* where decisions live (an ADR, via
  `recording-decisions`); the card links there and closes.
- **bug** — only if not fixed inline; it mirrors the `docs/tickets/bug-register.md` row,
  and the row is the truth.
- **blocked-feature** — visibility ONLY. Created the moment a feature becomes blocked (by another
  feature, an ADR awaiting acceptance, an owner action, or an external dependency), linking the
  blocked thing to its blocker; **closes the moment it unblocks**. An unblocked feature NEVER gets a
  card.
- **doc-work** — not doable inline.
- **business / organisational actions.**
- **parked ideas / questions.**
- plus the one **digest** singleton.

**NEVER engineering build-tickets.** A feature to build, tech debt, a residual → the running files
(status doc + backlog file + the owning ADR), at discovery time. If a card and a doc disagree, the doc
wins and the card gets fixed.

## Visual actor code

So the owner can scan: **red** = the owner acts AND work waits on it · **orange** = the owner acts,
nothing waits · **blue** = the AI acts. Assign the owner to their cards. Short honest due dates (~1 day
quick, ~3 days bigger). Escalating orange → red is the AI's duty when its work becomes blocked.

## Owner-executed cards

Written in plain steps: exact links, exact button names, "you're done when…", "then tell the AI…",
an honest time estimate. Owner-written cards can be a bare title — the next session enriches them.

## Closing is truthful

A completion note (what / where / how verified), then Done — never silent. "Done" without
verification evidence is forbidden.

## Keep a greppable snapshot in the repo

A generated mirror file, committed, so agents read the board without API calls and its history is
versioned.
