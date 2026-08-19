# Control TIMING — a gate that is right but late is nearly worthless

`gates.md` asks whether a gate is *correct*. This file asks a different question, and in the field it
turned out to be the more expensive one: **when does the gate speak?**

Three controls failed in a single week on one project. **Not one of them was wrong.**

| The control | Its state | How it failed |
|---|---|---|
| The push gates | correct, passing | **too late** — they ran at the end of a ~10 minute push run |
| A deploy check | correct, wired | **wired to its weaker mode** — the strict path existed and nothing called it |
| The write-time hook | correct, committed | **not loaded** — the session predated the config, and nothing said so |

A harness that only audits gate *logic* finds none of these. Every one is a wiring, timing, or
lifecycle defect, and all three produced confident green output while protecting nothing.

---

## C1 · Fire the control at the moment of the write, not at the end of the run

The failure is not that the gate missed something. It caught it — forty minutes late.

A doc link pointing at a non-existent file was written. **Three paragraphs of reasoning were built on
top of it.** The push gate then flagged the dead link, correctly, long after the work that depended on
it was done. The cost was already sunk; the gate's correctness bought nothing.

**Move the cheap checks to the edit itself.** Same scripts, same exit codes, different moment:

```
Write/Edit ─┬─► sub-second gates ──► BLOCK (exit 2) ──► the agent fixes it before continuing
            └─► everything else deferred to the push run
```

The economics are not subtle. A check that costs two seconds and fires immediately prevents the
downstream work entirely. The same check at push costs nothing extra to run and prevents nothing,
because the reasoning it would have invalidated is already written.

**Rule of thumb for what moves:** if the check is sub-second and its failure is a *fact error* (a path
that does not exist, a marker with no registry row), it belongs at the write. If it needs a build, a
service, or the whole tree, it stays at push.

## C2 · Split blocking from advisory, or the hook gets switched off

This is the part that decides whether the mechanism survives contact with real work.

| Tier | Applies to | Why |
|---|---|---|
| **BLOCKING** | docs, registries, config — anything where the failure is a **fact error** | There is no legitimate in-progress state where a doc points at a file that does not exist. Everything downstream inherits a false premise. Fail loudly, now. |
| **ADVISORY** | source code | A half-written function is a **legitimate state**. The doc comment lands after the signature; the citation lands after the function has a name. |

Block on code and you interrupt every second keystroke. The author's rational response is to disable
the hook — and then you have nothing.

> **A control annoying enough to disable has a real enforcement value of zero.**
> Tier aggressively. An advisory notice that is *read* beats a block that is *removed*.

Advisory does not mean unenforced: the same check runs blocking at push. The write-time pass is an
early warning, not the enforcement point.

## C3 · Hook config loads at SESSION START — an unprotected session is indistinguishable from a protected one

The trap that cost the most, because it has **no symptom**.

A session already running when the hook config was created **does not have the hook**. No warning, no
error, no missing-config notice. It looks exactly like a protected session and behaves like an
unprotected one.

The proof this is real: on one project, **the session that wrote the hook never once ran it** — the
transcript predated the config file by four days. That session duly wrote two dead doc links, which
only the push gate caught, days later.

**What to do about it:**

- If you did not **see a hook fire** this session, assume you do not have one. Run the fast gates by
  hand after doc edits.
- Make at least one hook produce **visible output on success** during adoption, so its silence is
  informative rather than ambiguous.
- Treat "the config exists in the repo" and "the config is loaded in this process" as **different
  claims**. Only the second one protects anything.

The general form of this, worth carrying to any lifecycle-loaded control (linters, editor plugins,
pre-commit frameworks, env-var-driven behaviour): **a control that is installed is not a control that
is running.**

## C4 · Verify a control the way PRODUCTION triggers it

`gates.md` **G7** says: plant a violation, watch the gate go red. That is necessary and it is not
sufficient, because it tests the **script**, and in all three failures above the script was fine.

> **Calling the script directly proves the script. The script was never the broken part.**

| What you did | What it actually proved |
|---|---|
| Piped a test payload at the hook script | The script parses payloads |
| Ran `check-x.sh` in a terminal | The check logic works |
| **Edited a real file through the agent and watched the block arrive** | **The control is wired, loaded, and firing** |

So the verification ritual has two halves, and adoption is not complete until both are done:

1. **Logic** (G7): plant a violation → red → remove it → green → confirm byte-identical restore.
2. **Wiring** (C4): trigger it through the **real path** — the actual editor, the actual runner, the
   actual deploy command — and watch it fire.

The second half is what catches "wired to its weaker mode", "not loaded", and "runs too late". None of
those are visible from inside the script.

## C5 · Record which controls are ENFORCED and which are not — publish the honest list

The most useful line in a project constitution turned out to be a table nobody expected to be useful:
a two-column split of every standing rule into **held by a script** and **held only by your
attention**.

It reads as an admission of weakness. It functions as a targeting system.

```
Held by a script (it will stop you)   |  Held only by you (nothing will stop you)
doc paths · citations · registries    |  never destroy without approval · no secrets
the two passes · the push gate        |  verify before you report · plain language
```

Two effects, both large:

- It tells the reader **where not to relax**. On the project this came from, the two rules that can
  never be undone — *never destroy without approval*, *never commit a secret* — were both in the
  right-hand column. That is exactly the guidance you want surfaced, and a uniform "follow all rules"
  framing actively hides it.
- It stops a green run from being over-read. A harness that **implies** uniform coverage invites
  uniform, and therefore misplaced, confidence.

Keep the list current as gates land. Moving a rule from right to left is the clearest possible
statement of progress this harness can make.
