# SOP — Owner Communication & the Coordination Board

Two failure modes this SOP prevents, both observed in the field:
1. The non-technical owner reads agent reports full of card IDs, ADR numbers, and codenames — and
   has to re-ask in other words. Every re-ask is a defect in the report, not in the owner.
2. A visual ticket board gets used as an **engineering tracker** — and drifts from the code within
   hours (tickets for already-built features; agents following tickets instead of inventorying
   reality). **Two sources of truth guarantee drift.** Code truth lives in the running files;
   boards coordinate humans.

## 1. Plain-language protocol (binding on every owner-facing message)

- **Every report/turn addressed to the owner ends in plain language.** No card IDs, ADR numbers,
  acronyms, or project codenames without an immediate plain-words gloss ("BUG-13 — the re-seal
  button doesn't check whether a release is running").
- **No ticket/card is created without one plain sentence in chat**: what it is, and whether the
  owner needs to care. Sub-agents never create cards at all — only the lead, after review.
- The test: *if the owner would have to ask "what does that mean?", rewrite it first.*

## 2. The weekly digest (the owner's one-glance view)

At the first session of each week, refresh a **singleton digest** (ONE pinned card/page, body
REPLACED weekly, never accumulated): ~10 lines of plain language — what got built · what broke and
got fixed · what waits on the owner · what's next · one honest health number (e.g. open bugs +
gates status). It exists so the owner never needs to read the technical docs to know where things
stand. Honest numbers only — zeros are honest numbers.

## 3. If you add a visual board (GitHub Projects etc.): COORDINATION-ONLY

A board earns its keep for what a repo can't do — the owner's queue, deadlines, at-a-glance
blockage — and destroys value the moment it duplicates engineering state. The rules:

- **Allowed card types ONLY** (adapt names, keep the shape):
  **owner-action** · **owner-decision** (question → options with one honest consequence line each →
  the lead's recommendation → what it unblocks; the decision gets *recorded* where decisions live —
  an ADR — and the card links there and closes) · **bug** (only if not fixed inline; mirrors the
  bug-register row — the row is the truth) · **blocked-feature** (visibility ONLY: created the
  moment a feature becomes blocked — by another feature, an ADR awaiting acceptance, an owner
  action, or an external dependency — linking the blocked thing to its blocker; **closes the moment
  it unblocks**; an unblocked feature NEVER gets a card) · **doc-work** (not doable inline) ·
  **business/organisational actions** · **parked ideas/questions** · plus the one digest singleton.
- **NEVER engineering build-tickets.** A feature to build, tech debt, a residual → the running
  files (status doc + backlog file + the owning ADR), at discovery time. If a card and a doc
  disagree, the doc wins and the card gets fixed.
- **Visual actor code** so the owner can scan: red = owner acts AND work waits on it; orange =
  owner acts, nothing waits; blue = the AI acts; assign the owner to their cards; short honest due
  dates (~1 day quick, ~3 days bigger); escalation orange→red is the AI's duty when its work
  becomes blocked.
- **Owner-executed cards are written in plain steps** (exact links, exact button names, "you're
  done when…", "then tell the AI…", honest time estimate). Owner-written cards can be a bare
  title — the next session enriches them.
- **Closing is truthful**: a completion note (what/where/how-verified) then Done — never silent;
  "done" without verification evidence is forbidden.
- **Keep a greppable snapshot in the repo** (a generated mirror file, committed) so agents read
  the board without API calls and its history is versioned.
