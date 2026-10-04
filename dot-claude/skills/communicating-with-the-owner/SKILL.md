---
name: communicating-with-the-owner
description: Makes every owner-facing message readable by a non-technical owner — reports end in plain language, every ticket ID, decision number, acronym or codename is glossed in the same sentence, every question carries 2-3 sentences of context and a recommendation — and keeps the weekly plain-language digest and the coordination tickets (never engineering tickets) honest. Use when writing any report, summary, status update or question to the owner, when creating or closing a ticket or board card, at the first session of a week, or when the owner had to ask "what does that mean?".
---

# Communicating with the owner

Two field failures this prevents:
1. The non-technical owner reads reports full of card IDs, decision numbers and codenames, and has to
   re-ask in other words. **Every re-ask is a defect in the report, not in the owner.**
2. A ticket board used as an **engineering tracker** drifts from the code within hours (tickets for
   already-built features; agents following tickets instead of inventorying reality). Two sources of
   truth guarantee drift: code truth lives in the running files; tickets coordinate humans.

## The plain-language protocol (binding on every owner-facing message)

- **Every report or turn addressed to the owner ends in plain language.** No card IDs, ADR numbers,
  acronyms or codenames without an immediate plain-words gloss ("BUG-13 — the re-seal button doesn't
  check whether a release is running").
- **Glosses come from the record, never from imagination.** Look each ID up in its register or
  decision record and paraphrase what it says. If you cannot find it, say so or leave the item out —
  NEVER invent what a ticket or decision is about; a plausible made-up gloss is worse than the bare ID.
- **Plain English, not a wall of terms.** A technical word only when needed, explained in the same
  sentence. A reader who has not followed the session must understand every line.
- **Every question carries its context in 2–3 short sentences, no more:** what it is, why it matters,
  what you recommend. Never a bare few-word question ("BUG-236 — which model?").
- **No ticket or card is created without one plain sentence in chat**: what it is, and whether the
  owner needs to care. Spawned sub-agents never create tickets — only the lead, after review.
- **Status is checked, not repeated.** Before listing anything as open, pending, blocked or not built,
  check it against the current-state doc (ONBOARDING) and the code. A ticket's status is a claim to
  verify, not a fact; telling the owner to do something already done is a defect. If the records
  disagree, show both with their dates and ask (`CLAUDE.md`, the conflict rule).
- **The test:** if the owner would have to ask "what does that mean?", rewrite it first.

## Before sending — the feedback loop

Copy this checklist and run it on the draft:

```
Owner-message check:
- [ ] 1. Scan for IDs (BUG-/SEC-/DEC-/ADR-/FEAT-…), acronyms, codenames, file paths
- [ ] 2. Each one: LOOK IT UP (register / decision record), then gloss it in plain words in the
        same sentence — or delete it. Not found → say "not found", never guess
- [ ] 3. Each question: what it is · why it matters · your recommendation (2–3 sentences)
- [ ] 4. Numbers are honest (zeros included); "done" carries how it was verified
- [ ] 5. The last paragraph is plain language and says what (if anything) waits on the owner
- [ ] 6. Re-read as someone who missed the session; any "what does that mean?" → back to 1
```

## The weekly digest (the owner's one-glance view)

At the **first session of each week**, refresh the singleton digest («where the digest lives» — ONE
page or pinned card): the body is **replaced**, never accumulated. About 10 lines of plain language:
what got built · what broke and got fixed · what waits on the owner · what's next · one honest health
number (e.g. open bugs + gate status). It exists so the owner never has to read the technical docs to
know where things stand. Honest numbers only — zeros are honest numbers.

## Coordination tickets, never engineering tickets

The typed ticket files under `docs/tickets/` (index: `docs/tickets/README.md`,
canonical for the types and their rules) carry only what a repo cannot already hold: the owner's
queue, pending decisions, deadlines, blockage. **A feature to build, tech debt or a residual is never
a ticket** — it goes to the running files (status doc + backlog file + the owning ADR) at discovery
time. If a ticket and a doc disagree, the doc wins and the ticket gets fixed.

Adding a visual board on top (GitHub Projects etc.)? Follow
[reference/coordination-board.md](reference/coordination-board.md): allowed card types, the actor
colour code, owner-executed card format, truthful closing, the committed snapshot.

## History

- The 2–3-sentence context rule for questions became a standing rule after the owner of the source
  project had to come back and ask what bare questions like "BUG-236 — which model?" meant.
