# BIZ tickets — business / organisational actions — «PROJECT»

> **`BIZ-##` — non-development work the project needs**: go-to-market, marketing, partnerships,
> sales, legal/admin, procurement, hiring, finance. It sits in the ticket system (not the docs)
> because it's coordination, not engineering — but it's tracked with the same discipline: created at
> discovery, closed truthfully, no secrets.

**Actor:** 👤 human-run · 🤖 AI-run · 👥 joint.
**Status:** ☐ open · ▶ in progress · ✅ done · ✖ dropped

| ID | Actor | Title | Goal (1 sentence) | Next step | Status |
|----|-------|-------|-------------------|-----------|--------|
| BIZ-001 | 👤 | «the business action» | «why it matters» | «the immediate next move» | ☐ |

## Rules
1. **Create at discovery** — the moment a non-dev action is owed, add a row.
2. **Human-run rows are plain-language** with concrete steps (same rule as `USER` tickets); AI-run rows carry a self-contained context package (goal + refs by path + Definition of Done).
3. **Bind outward-facing artifacts to the project's rules** — anything published externally follows the style rules and needs owner sign-off before it goes out.
4. **Close truthfully** — what was done, where, how verified.
5. **No secrets** — no account credentials, keys, or contract terms that shouldn't be in the repo.

> **Scope note:** if a business action turns out to need engineering (e.g. a landing page, an integration), the *engineering* half is NOT tracked here — it goes to the runner/backlog/ADR like any build; the `BIZ` ticket tracks only the business action.
