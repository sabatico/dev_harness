# When sessions share one checkout

Separate worktrees per agent prevent this class. This file is what happens when that rule is not
followed — often, because sharing a checkout costs nothing until suddenly it costs a morning.

**Field case:** three sessions worked one checkout in a single day and repeatedly cancelled each
other's verified state — roughly ten minutes lost per collision, several times over, plus two owner
interventions to get one push out.

**The mechanism (not obvious — the reason this is written down):** the push gate hashes the
**whole working tree, including untracked files** (it must — `docs/ci/gates.md` G4: a hash of tracked
files only would miss the new file just written, the code most likely to be unverified). So **one
session's scratch file invalidates another session's green run.** Neither session did anything
wrong; the second one just saved a log.

> **The gate is not weakened, and that is the right call.** Asked whether to relax the hash, the
> owner said no: the gate is what stops unverified code shipping, and the clash is caused by how
> the sessions work, not by the check. Fix the collision at its source. Re-proposing "just exclude
> untracked files" re-opens G4.

| Do | Why |
|---|---|
| **A separate tree per concurrent session** (`git worktree`) whenever more than one session is live | Removes the class: no shared working tree, no shared hash, no cross-cancellation. |
| **Session-scoped temp files, always** — a per-session scratch dir, never a fixed `/tmp/<name>.log` | A shared filename collides even without a gate. Half-using a scratch dir and half-using a fixed `/tmp` log is how it bites. |
| **Scoped `git add` by path. Never `git add -A`** | One commit swept four of another session's in-flight files. The shared-tree case is where this rule actually fires. |
| **Never `git checkout <file>` to undo something** while uncommitted work is in the tree | It reverts everything since the last commit, not your change. It once cost a full written document. |
| **Declare the INDEX, not just the working tree, at handover** | `git rm` stages instantly, and the next commit by ANY session sweeps it. This broke a main branch once. |

**Verifying a handover:** check out HEAD in a **throwaway worktree** and inspect it there.
Verifying in your own tree proves your tree — the thing you already knew about.
