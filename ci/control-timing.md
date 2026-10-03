# Control TIMING — a gate that is right but late is nearly worthless

`gates.md` asks whether a gate is *correct*. This file asks **when the gate speaks** — in the field
the more expensive question.

## Contents

- The three field failures
- C1 · Fire the control at the moment of the write
- C2 · Split blocking from advisory
- C3 · Hook config loads at session start
- C4 · Verify a control the way production triggers it
- C5 · Record which controls are enforced and which are not

## The three field failures

Three controls failed in one week on one project. **None was wrong.**

| The control | Its state | How it failed |
|---|---|---|
| The push gates | correct, passing | **too late** — ran at the end of a ~10 minute push run |
| A deploy check | correct, wired | **wired to its weaker mode** — the strict path existed and nothing called it |
| The write-time hook | correct, committed | **not loaded** — the session predated the config, and nothing said so |

Auditing gate *logic* finds none of these. Each is a wiring, timing or lifecycle defect that produced
confident green output while protecting nothing.

---

## C1 · Fire the control at the moment of the write, not at the end of the run

A doc link to a non-existent file was written; three paragraphs of reasoning were built on it; the
push gate flagged it, correctly, forty minutes later. The gate's correctness bought nothing.

Move the cheap checks to the edit itself — same scripts, same exit codes, different moment:

```
Write/Edit ─┬─► sub-second gates ──► BLOCK (exit 2) ──► the agent fixes it before continuing
            └─► everything else deferred to the push run
```

**What moves:** a check that is sub-second and whose failure is a *fact error* (a path that does not
exist, a marker with no registry row) belongs at the write. A check that needs a build, a service or
the whole tree stays at push.

## C2 · Split blocking from advisory, or the hook gets switched off

| Tier | Applies to | Why |
|---|---|---|
| **BLOCKING** | docs, registries, config — failures that are **fact errors** | No legitimate in-progress state has a doc pointing at a missing file; everything downstream inherits a false premise. |
| **ADVISORY** | source code | A half-written function is a **legitimate state**: the doc comment lands after the signature, the citation after the name. |

Blocking on code interrupts every second keystroke; the author's rational response is to disable the
hook, leaving nothing.

> **A control annoying enough to disable has a real enforcement value of zero.** An advisory notice
> that is *read* beats a block that is *removed*.

Advisory does not mean unenforced: the same check runs blocking at push. The write-time pass is an
early warning, not the enforcement point.

## C3 · Hook config loads at SESSION START — an unprotected session looks protected

A session already running when the hook config was created **does not have the hook**, with no
warning, error or missing-config notice. Proof: on one project the session that wrote the hook never
ran it (its transcript predated the config by four days) and wrote two dead doc links that only the
push gate caught, days later.

1. If you did not **see a hook fire** this session, assume you have none; run the fast gates by hand
   after doc edits.
2. During adoption, make at least one hook produce **visible output on success**, so its silence is
   informative.
3. Treat "the config exists in the repo" and "the config is loaded in this process" as different
   claims; only the second protects anything.

General form, for any lifecycle-loaded control (linters, editor plugins, pre-commit frameworks,
env-var behaviour): **a control that is installed is not a control that is running.**

## C4 · Verify a control the way PRODUCTION triggers it

`gates.md` **G7** (plant a violation, watch the gate go red) tests the **script**, and in all three
failures above the script was fine.

> **Calling the script directly proves the script. The script was never the broken part.**

| What you did | What it proved |
|---|---|
| Piped a test payload at the hook script | The script parses payloads |
| Ran `check-x.sh` in a terminal | The check logic works |
| **Edited a real file through the agent and watched the block arrive** | **The control is wired, loaded and firing** |

Adoption is complete only after both halves:

1. **Logic** (G7): plant a violation → red → remove it → green → confirm byte-identical restore.
2. **Wiring** (C4): trigger it through the **real path** — the actual editor, runner or deploy
   command — and watch it fire. This is what catches "wired to its weaker mode", "not loaded" and
   "runs too late".

## C5 · Record which controls are ENFORCED and which are not — publish the honest list

Keep, in the constitution, a two-column split of every standing rule into **held by a script** and
**held only by attention**:

```
Held by a script (it will stop you)   |  Held only by you (nothing will stop you)
doc paths · citations · registries    |  never destroy without approval · no secrets
the two passes · the push gate        |  verify before you report · plain language
```

It reads as an admission of weakness and works as a targeting system:

- It tells the reader **where not to relax**. On the source project the two irreversible rules —
  *never destroy without approval*, *never commit a secret* — were both in the right-hand column; a
  uniform "follow all rules" framing hides that.
- It stops a green run being over-read; a harness that implies uniform coverage invites uniform,
  misplaced confidence.

Keep the list current as gates land. Moving a rule from right to left is the clearest statement of
progress the harness can make.
