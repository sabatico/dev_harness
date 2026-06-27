# SOP — Roles, Agents & Orchestration

## The roles
| Role | Model tier | Owns |
|------|-----------|------|
| **Lead / Integrator** | strong | The contract boundary, integration, the running files, final judgment, hard/security-critical code, ADRs. Never delegates judgment. |
| **Builder** | cheap–mid | A scoped, multi-file implementation slice in an isolated worktree with a **disjoint file set**. |
| **Tester (cross author)** | ≠ builder | Tests for code it did not write (see `test-and-coverage.md`). |
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
- Give the agent **the contract + the disjoint file set + the DoD**, not vague goals.
- Give cross-family test authors **rich context** (the real code under test + an existing test as the harness/style exemplar) so the output integrates with minimal mechanical fixup.
- Treat an agent's final message as a **report**, not ground truth — verify its claims (run the build/tests yourself).
- A denied tool call from an agent means the human/permission layer declined it — adapt, don't blindly retry.
