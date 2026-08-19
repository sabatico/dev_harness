# USER tickets — actions only the human owner can do — «PROJECT»

> **`USER-##` — a thing only the human can perform**, because it needs their hands, their
> credentials, their account, or their signature (create/verify an account, click a button in a
> console the AI can't reach, run a command only they're authorized for, sign/approve something,
> make a purchase). **A *decision* is a `DEC` ticket, not a `USER` ticket** — this file is for
> *doing*, not *choosing*.
>
> **Written for the human, in plain language.** No IDs/acronyms/codenames without an immediate
> gloss. The test: if the owner would have to ask "what does that mean?", rewrite it first.
> See `README.md` for the whole taxonomy and the rules.

**Waits-on flag:** 🔴 = the human must act AND AI work is blocked on it (drop-everything) · 🟠 = the human should act, nothing is waiting.
**Status:** ☐ open · ✅ done · ✖ won't-do

| ID | Flag | Title | Why it matters (1 sentence) | Steps (plain, exact) | Done when… | Est. | Status |
|----|------|-------|-----------------------------|----------------------|-----------|------|--------|
| USER-001 | 🟠 | «what the human does» | «the one-sentence reason» | «1. …  2. …  3. … with exact links/button names» | «the observable result» / «then tell the AI …» | «~5 min» | ☐ |

## Rules
1. **Create at discovery time** — the moment the AI hits something only the human can do, add a row (never leave it only in chat).
2. **Plain steps only** — numbered, with exact links/button names/text, a "you're done when…", a "then tell the AI…", and an honest time estimate.
3. **Escalate honestly** — if AI work becomes blocked on an open row, flip it 🟠→🔴 and say so in chat; flip back when unblocked.
4. **Close truthfully** — append what the human did (quote their confirmation), when, and what it unblocked; then mark done. Never silent.
5. **No secrets** — never ask the human to paste a secret into a ticket, chat, or commit.

> **Distinct from `DEC` (`decisions.md`):** that's a choice to make; this is an action to take. A `USER` action that first needs a decision waits on its `DEC` ticket.
