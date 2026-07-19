# Tickets — the typed coordination queue — «PROJECT»

> **What this folder is:** the project's **coordination tickets**, one running file per **type**.
> It replaces a visual project board — the *types* are the value, not the UI. Each file is a small
> living register the AI and the human keep current at the end of every act.
>
> **The one rule that makes tickets worth having:** they carry ONLY what a repo can't already hold —
> the human's queue, pending decisions, deadlines, and at-a-glance blockage. **Engineering work is
> NOT a ticket.** A feature to build, tech debt, a residual, a productionization gap → it lives in
> the running docs (`ONBOARDING.md` status + the owning ADR + `runner.md`/`backlog-tickets.md`) at
> discovery time. Two sources of truth guarantee drift: tickets that duplicate engineering state go
> stale within hours. If a ticket and a doc disagree, **the doc wins and the ticket gets fixed.**

## The types (one file each)

| Prefix | Type | File | What it is | Closes when |
|--------|------|------|------------|-------------|
| `USER-##` | **User action** | `user-actions.md` | A thing only the **human owner** can do (create an account, click a console button, sign something, run a command only they have creds for). A *decision* is `DEC`, not `USER`. | the human does it + tells the AI (quoted in the close note) |
| `DEC-##` | **User decision** | `decisions.md` | A pending decision only the human can make. Body = the question + options (each with one honest consequence) + the AI's recommendation + what it unblocks. **The decision is recorded where decisions live — an ADR — and the ticket links there and closes.** | the decision is made + captured in an ADR |
| `FEAT-##` | **Blocked feature (visibility ONLY)** | `blocked-features.md` | Created the moment a feature **becomes blocked** — by another feature, an ADR awaiting acceptance, a `USER`/`DEC` action, or an external dependency — so the human can SEE the blockage without reading ADRs. Body = the blocked thing **by path** + "Blocked by: …" + what unblocking looks like. **An unblocked feature NEVER gets one.** | the blocker lifts (then the work proceeds via ADR + `runner.md`, never via the ticket) |
| `DOC-##` | **Doc work** | `doc-work.md` | Documentation work that can't be done inline in the current act (a runbook, a guide, a registry that needs writing). | the doc is written |
| `BIZ-##` | **Business / organisational** | `business.md` | Non-development actions: go-to-market, partnerships, legal/admin, procurement, hiring. | the action completes |
| `BUG-##` | **Defect** | `bug-register.md` | Every defect, at discovery time (the register row is the truth; P0/P1 close only with an escape analysis; automatic P0 if it breaks a project invariant). Has its own severity ladder, so it keeps a dedicated register file. | fixed (row moves to Closed) |
| `SEC-##` | **Security hardening** | `security.md` | A hardening / coverage / config / accepted-false-positive item that is NOT a live defect (a security *defect* is a `BUG`). Where the security sweep sends everything that isn't a bug; triaged + scheduled, not reflex-fixed. | done (or 🅰 accepted, reason recorded) |
| `TBD-##` | **Parked idea / open question** | `../tbd-parking-lot.md` | Work deliberately deferred by a constraint + open questions too big to classify. A reminder, not a commitment. Kept in its own file — linked here, not duplicated. | its resurface trigger fires (moves to a backlog/runner) |

`BUG` and `SEC` live in this folder (`bug-register.md`, `security.md`); `TBD` keeps its own file (`../tbd-parking-lot.md`) — this index names them all so the whole taxonomy is in one place. New IDs are the next number in that type's sequence; **IDs are never reused or renumbered.**

## Where quality reviews & bug hunts send their findings
A **quality review** or a **bug hunt** does NOT hold findings in the review report alone — each finding lands in its ticket at discovery, **unless it can be fixed inline in the same act (quickly, in scope)** — then the fix itself is the record, no ticket. Routing: a **defect** → `bug-register.md` (`BUG`); a **security hardening/coverage** item → `security.md` (`SEC`); an item needing the human → `user-actions.md`/`decisions.md`; doc work → `doc-work.md`; a newly-blocked feature → `blocked-features.md`. The review/hunt report then *points* at the tickets it opened (it is a summary, not a second home).

## The rules (all types)

1. **Create at discovery time.** The moment a coordination item exists (a user must act, a decision is owed, a feature just became blocked, a doc/business task appears), it gets a row in its type file — never only in chat or a commit message.
2. **`USER`/`DEC` rows are written in plain language** — why it matters (one sentence) → concrete numbered steps or clear options → "you're done when…" / "then tell the AI…" → an honest time estimate. If the human would have to ask "what does that mean?", rewrite it first.
3. **AI-executed rows** (`FEAT`/`DOC`/`BIZ` that the AI works) carry a context package usable without the originating conversation — goal + refs **by path** + Definition of Done.
4. **Closing is truthful, never silent.** Append a close note: what was done, where (commits/paths), **how it was verified**, and any follow-up (which goes to its home of record — engineering → the docs, not a new ticket). "Done" without verification evidence is forbidden.
5. **No secrets, ever** — same rule as chat, commits, and logs.
6. **Spawned sub-agents never create tickets** — only the lead, after review, routes discovered items to the right file.

## Session protocol (end of every act — only if a ticket was actually touched)

Most engineering acts touch none. When one does: close/update touched rows (§4), create rows only for the types above at discovery, and make sure no act leaves the human with stale work in `user-actions.md`.

> **Distinct from `runner.md`** (the active wave's in-flight *engineering* work) and **`backlog-tickets.md`** (unscheduled *engineering* features/bugs). Those are engineering truth; these are coordination. See the parent `CLAUDE.md` for the homes-of-record map.
