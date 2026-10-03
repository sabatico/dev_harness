---
name: writing-docs
description: Writes or updates repository documentation and running files so they stay true — states the WHY and the rejected alternatives, keeps one home per fact and links instead of copying, verifies every claim, path and number against the code at writing time, never hand-edits generated docs, registers new docs so the doc gates pass, and sends outward-facing prose for owner sign-off. Use when writing or editing any doc, decision record, running file (status, runner, catalog, runbook, registries), SOP or README, when acting as the scribe, or when a doc gate (links, paths, index, claims) fails.
---

# Writing docs

Load with `following-core-rules`. Canonical sources: `CONVENTIONS.md` (doc authoring) and
`CLAUDE.md` (running files, recall-is-not-a-source); on conflict they win and this skill is the
copy to fix.

## Workflow

Copy this checklist and tick it off:

```
Doc progress:
- [ ] 1. Find the fact's ONE home (grep for it first); edit there, link from elsewhere
- [ ] 2. Write: the WHY + alternatives considered and why they lost; a fallback where advising
- [ ] 3. Every claim true TODAY: paths from ls/grep, numbers from code/computed, quotes quoted
- [ ] 4. Generated doc or block? change its source and regenerate — never hand-edit
- [ ] 5. New doc? register it where the index gate expects it
- [ ] 6. Run the doc gates; fix → re-run until clean
- [ ] 7. Outward-facing prose? style handbook + owner sign-off before it ships
```

## Rules

- **The conventions doc binds:** explain WHY, not just what; give the alternatives and why they
  lost (decisions of consequence graduate to a decision record — `recording-decisions`); give a
  fallback when recommending; write for a cold start — the next reader is an agent with no memory
  of this session.
- **One home per fact.** Link, don't copy: a copied fact rots on its own clock. Counts and
  inventories that can be generated are generated (`docs/ci/gates.md`, generated-facts-block pattern).
- **Claims are true TODAY**, verified while writing: a path from `ls`/`grep` this session, a
  quantity from the code constant, what another doc says quoted, a result from the raw output.
  "Not built", "blocked by", "still to do" claims are checked against the code before writing —
  the quality review's claims-vs-code audit (`reviewing-code-quality`) will check them anyway.
- **Running files** (status, runner, feature catalog, use-case runbook, registries, tickets) are
  updated for everything the work changed, at the end of the act; the status log stays an index
  of ≤10 lines per entry, details live in the owning doc.
- **Timeless instructions:** dated provenance goes in a `## History` section, not in the rules.
- **Owner-facing text** follows `communicating-with-the-owner`: plain language, every term glossed.
- **Outward-facing prose** (public README, release notes, anything a customer reads) follows
  «the style handbook» and ships only with owner sign-off.

## Verify (feedback loop)

Run `scripts/check-doc-links.sh`, `scripts/check-doc-paths.sh` and `scripts/check-doc-index.sh`
(or the whole `scripts/run-all-gates.sh`). Red → fix the doc (not the baseline) → re-run. Editing a
skill file instead? Use `authoring-skills` and `scripts/check-skills.sh`.

## History

- Formerly the `skill-doc-authoring` skeleton in the agent-skills SOP.
