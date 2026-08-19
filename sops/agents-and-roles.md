# SOP — Roles, Agents & Orchestration

## The roles
| Role | Model tier | Owns |
|------|-----------|------|
| **Lead / Integrator** | strong | The contract boundary, integration, the running files, final judgment, hard/security-critical code, ADRs. Never delegates judgment. |
| **Builder** | cheap–mid | A scoped, multi-file implementation slice in an isolated worktree with a **disjoint file set**. Ships the slice's **edge-case checklist** (`edge-case-catalog.md` → Handled / N/A-why / DEFERRED). |
| **Tester (cross author)** | ≠ builder | Tests for code it did not write (see `test-and-coverage.md`). **Attacks the builder's edge-case checklist AND enriches it** — proposes its own additional cases → lead/owner ruling → approved ones become tests + fold into the catalog. |
| **Reviewer (second)** | ≠ lead | The independent pass in a quality review. |
| **Second ideator** | ≠ lead | Debates a hard decision so the lead isn't reasoning alone (see `decisions-adr.md`). |
| **Scribe** | cheap | Documents each finished item into the running files. |

The lead can play several roles itself across a session; the point is that **test authorship and second opinions come from a different vantage point than the work being checked.**

## When to spawn parallel agents (and when NOT to)
Spawn a sub-agent only when the work is **genuinely parallelizable and the file sets are disjoint** — otherwise do it inline. Two agents editing overlapping files will collide and waste the integration.

Good: "Build feature A (files X,Y) while feature B (files P,Q) is built separately." Bad: "Two agents refactor the same module."

## Isolation & integration rules
1. **Isolated worktrees.** Each builder agent works in its own git worktree so changes can't collide and are easy to review as a unit.
2. **⚠️ Integrate BEFORE removing a worktree.** Agents routinely leave work **uncommitted** in their worktree. **Commit / stash / copy it out before `git worktree remove`** or it is lost permanently. (The single most common way to lose agent work.)
3. **Scoped git operations.** Never `git add -A` across worktrees; add only the intended files.
4. **The lead owns the seam.** Builders implement to a contract the lead froze (types, interfaces, API shape). The lead reviews + integrates + writes the cross-family tests' integration glue + updates the running files.
5. **Definition of Done for a spawned slice** = builds, cross-authored tests green, no files outside its agreed set touched, running files updated by the lead on integration.

## Communicating with sub-agents
- **Briefs start from SKILLS, not from memory** (see `agent-skills.md`): inject BY PATH the
  universal `skill-core` + exactly one task-type skill (coding / test-authoring / doc-authoring /
  adversary / UI) + the binding guides that skill names. The brief itself then carries only the
  task specifics. Rule delivery must not depend on the lead remembering rules.
- Give the agent **the contract + the disjoint file set + the DoD**, not vague goals.
- Give cross-family test authors **rich context** (the real code under test + an existing test as the harness/style exemplar) so the output integrates with minimal mechanical fixup.
- Treat an agent's final message as a **report**, not ground truth — verify its claims (run the build/tests yourself).
- A denied tool call from an agent means the human/permission layer declined it — adapt, don't blindly retry.

---

## When sessions SHARE one checkout (the collision class worktrees are meant to prevent)

Worktrees are rule 1 above. This section is what happens when that rule is not followed — which is
often, because sharing a checkout costs nothing until suddenly it costs a morning.

**The field case:** three sessions worked one checkout in a single day and **repeatedly cancelled each
other's verified state** — roughly **ten minutes lost per collision**, several times over, plus two
human interventions to get one push out.

**The mechanism is not obvious, and it is the reason this needs writing down.** The push gate hashes
the **whole working tree, including untracked files** (it must — see `gates.md` G4: a hash of tracked
files only would miss the new file you just wrote, which is the code most likely to be unverified). So
**one session's scratch file invalidates another session's green run.** Neither session did anything
wrong; the second one just saved a log.

> **The gate was not weakened, and this is the right call.** When asked whether to relax the hash, the
> owner said no: the gate is what stops unverified code shipping, and the clash is caused by **how we
> work**, not by the check. Fix the collision at its source. Re-proposing "just exclude untracked
> files" re-opens G4.

| Do | Why |
|---|---|
| **A separate tree per concurrent session** (`git worktree`) whenever more than one session is live | Removes the class entirely: no shared working tree, no shared hash, no cross-cancellation. |
| **Session-scoped temp files, always** — a per-session scratch dir, never a fixed `/tmp/<name>.log` | A shared filename is a collision waiting to happen even without a gate. Half-using a scratch dir and half-using `/tmp/gates.log` is how this bites you. |
| **Scoped `git add` by path. Never `git add -A`** | One commit swept four of another session's in-flight files. (This is rule 3 above; it is repeated here because the shared-tree case is where it actually fires.) |
| **Never `git checkout <file>` to undo something** while uncommitted work is in the tree | It reverts everything since the last commit, not your change. Cost a full written document once. |
| **Declare the INDEX, not just the working tree, at handover** | `git rm` stages instantly, and the next commit by **any** session sweeps it. This broke a main branch once. |

**Verifying a handover:** check out HEAD in a **throwaway worktree** and inspect it there. Verifying in
your own tree proves your tree, which is the thing you already knew about.

## Briefing a sub-agent: every FACT is quoted or commanded, never summarised

`agent-skills.md` covers *rule* delivery (inject skills by path). This is about **facts**, and it fails
differently.

> **A sub-agent cannot check what you assert. It inherits it, acts on it, and your error becomes its
> output.**

Two hand-written briefs on one day carried wrong facts — that a table survives a parent delete, and
that a package had no complication it in fact had. Both were false, both were caught by the agent
after it had started, and both cost a full round trip.

- **Paste tool output**, not your reading of it. A context-gathering script's output goes in verbatim.
- **Quote schema, signatures and constants from the file.** A quote forces the read; a paraphrase lets
  memory answer.
- Everything in `CLAUDE.md`'s recall-is-not-a-source rule applies to **what you tell an agent** exactly
  as it applies to what you tell the owner. A path, a quantity, what a document says, a result: look
  it up before it goes in a brief.
