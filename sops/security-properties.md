# SOP — Security Properties (the perpendicular axis)

`edge-case-catalog.md` asks **"is this unit correct?"** and answers it deeply. Every rule in it is
scoped to *this slice, this unit* — the invent-nastier duty literally asks *"what could a user do
**here**"*. That depth is worth keeping and is not the problem.

This file is the other axis. It asks: **"does this PROPERTY hold everywhere, and what is NOT in my
work list?"**

**Why it earns a separate SOP:** on the project this comes from, **30% of all logged defects were one
class** — *a later step not re-checking what an earlier step relied on*. A unit-local lens cannot see
that class, because each unit is individually correct. An external assessment using this axis found
three real defects, and all three were in it.

Two rules govern when this runs: **at design time** (before code — it changes the design, not the
tests) and **at test time** (as a distinct pass, after the unit-local cases are written).

---

## THE FIVE QUESTIONS — ask on every feature, at design and at test

Short enough to actually ask. Each names the bug class that earned it.

| # | The question | The class it catches |
|---|---|---|
| **Q1** | **Which identity did you AUTHORIZE, and which one did you USE?** A request can carry an id in the path, the body, a token and the session. Name the authoritative one out loud. | The path is authorized and the body is used. A sibling handler does it correctly, so grepping for the pattern finds nothing. |
| **Q2** | **What state did the FIRST step rely on, and does the LAST step re-read it?** Enumerate that state as a **set**. Do not accumulate it one incident at a time. | Approval granted while a precondition held, consumed after it lapsed. Usually fixed twice by incident and never looked for a third time. |
| **Q3** | **Who else can spend this budget, and what goes QUIET when they do?** For any quota, cap, throttle, ceiling or alert budget. | A shared budget with an anonymous contributor is an availability control aimed at yourself: fill it with junk and the real signal is suppressed. |
| **Q4** | **Are you proving the DATA, or the status code?** Re-read the protected thing **as the victim** and compare bytes. | Every isolation test passes while the object is being silently overwritten, because they all tested reads and asserted on 403s. |
| **Q5** | **What is NOT in your work list?** Your tests cover what you thought of. Name the surface they do **not** cover, and say so out loud. | A cross-tenant matrix with five resources where the sixth was never added. An omission is invisible in a list you wrote yourself. |

> ⚠ **Q5 is the hardest to ask and does the most work.** The other four can be answered by looking at
> the code in front of you. Q5 requires looking at what is **not** in front of you — which is exactly
> what attention cannot do. So Q5 must be **mechanised**: derive the work list from the **contract**
> (the API spec, the schema, the route table), never from a list a human maintains. A machine can hold
> that question open indefinitely; a person cannot.

---

## The properties (P1–P8)

Name them, so a review can cite one instead of re-deriving the argument. Adapt the list to your
domain — the point is that it is short, written down, and referenced by number.

| # | Property | In one line |
|---|---|---|
| **P1** | **One identity per request** | The id you authorize must be the id you use. If they can differ, they will. |
| **P2** | **A finishing step re-reads what the starting step relied on** | Authorization is a snapshot; consumption happens later. Re-establish, do not assume. |
| **P3** | **Sink confirmation** | Prove the data, never the status code. Read it back as the party who must not see it. |
| **P4** | **Single-use capabilities are consumed under a lock** | A token, nonce, or one-time code that is checked and then used is a race with two winners. |
| **P5** | **Refusals are indistinguishable** | If "no such account" and "wrong password" differ in text, timing, or status, the refusal is an enumeration oracle. |
| **P6** | **Fail CLOSED when state cannot be established** | An unreachable dependency must deny, not default. The failure path is the one nobody tests. |
| **P7** | **Anything keyed by attacker-controlled input is BOUNDED** | Unbounded maps, caches, retries, and allocations are a denial of service with extra steps. |
| **P8** | **A control is not verified until it fires the way PRODUCTION fires it** | See `ci/control-timing.md` C4. Calling the script proves the script. |

---

## Declare the answers — a matrix, gated

The questions are worthless if asking them is optional. Make the **answer** an artefact:

1. Every operation in the contract (endpoint, job, message handler) gets a **row** in a property
   matrix: which properties apply, how each is satisfied, and **which test pins it**.
2. A gate walks the **contract** — not the matrix — and fails when an operation has no row, or cites a
   test that does not exist.
3. An **undeclared operation fails the build**. That is what makes Q5 mechanical: the work list comes
   from the machine-readable source of truth, so a new endpoint cannot quietly arrive uncovered.

```
operation                       P1   P2   P3   P4   P5   P6   P7   pinned by
POST /orders/{id}/confirm       ✓    ✓    ✓    ✓    -    ✓    ✓    order_confirm_test.go:TestCrossTenant
GET  /orders/{id}               ✓    -    ✓    -    ✓    ✓    ✓    order_read_test.go:TestVictimReadback
```

**The gate proves the row exists and the test exists. It cannot prove the test is meaningful** — that
is `gates.md` G5, and it applies here with full force. A green matrix means *declared*, never *safe*.

---

## The perpendicular pass (for the test author)

`test-and-coverage.md` gives the tester an invent-nastier duty that is deliberately unit-local. Add
one more pass, run **after** that one, that turns ninety degrees:

1. **Name the PROPERTY you just verified.** Not the case — the property. "Owner B cannot read owner
   A's document" is a case; **P3, sink confirmation** is the property.
2. **Ask where else that property must hold.** Every other resource type, every other verb, every
   other entry point into the same store.
3. **Say what is NOT in your work list.** Write the uncovered surface into the report explicitly. An
   unstated gap is indistinguishable from coverage.

Output goes into the test report as a section, not into a comment. The gaps it names are the next
work list — that is the whole point of writing them down.

---

## Where this sits relative to the other quality SOPs

| SOP | Question | Scope |
|---|---|---|
| `edge-case-catalog.md` | Is this unit correct under abnormal use? | one unit, deeply |
| `bug-hunt.md` | What defects exist in this scope right now? | a named scope, adversarially |
| **`security-properties.md`** | **Does this property hold everywhere, and what is missing?** | **one property, across the whole surface** |

Run all three. They fail to find different things, which is the only reason to have three.
