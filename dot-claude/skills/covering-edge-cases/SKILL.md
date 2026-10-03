---
name: covering-edge-cases
description: Instantiates the harness edge-case catalog (abnormal usage — back/forward, refresh or close mid-flow, double-submit, concurrency, permission shifts, replay — plus hostile input on every field, client and server) into a per-slice checklist where every applicable class is marked Handled, N/A with why, or DEFERRED, and grows the catalog when a new pattern escapes. Use when building, testing or reviewing any feature, form, flow or endpoint, when the owner asks "did we cover the edge cases / unexpected gaps?", or when a bug came from abnormal usage or bad input data.
---

# Covering edge cases

**Why:** a spec→build→test→review loop verifies the *intended* flow; almost nothing verifies the
unintended one, so abnormal-usage bugs slip straight through ("press Back then Forward and a
verification step gets skipped"). Coverage % proves lines ran, not that the flow survives abnormal
use. This skill is the owned objective for that gap.

The catalog itself — families A (navigation & lifecycle), B (input & interaction), C (timing &
concurrency), D (state/permission shifts), E (device & environment), F (data extremes), G (repetition
& replay), H (server-side mirrors), I (input-data validity & hostile input) — is in
[reference/catalog.md](reference/catalog.md). That file is canonical for the classes; this one for the
procedure.

## The contract — three phases per slice

1. **BUILD** (the builder): instantiate the catalog into a slice-specific checklist and ship it with
   the change. Cheap at design time, expensive to retrofit.
2. **TEST** (the cross-author test author, `writing-tests`): **attack** the checklist — every
   `Handled` row gets a test; cases a unit harness cannot see (back/forward, session restore, real
   timers) go to a real-driver test — and **enrich** it: propose new cases → owner/lead ruling →
   approved ones become tests → generalizable ones are folded into the catalog. `writing-tests` owns
   that enrichment loop.
3. **REVIEW** (`reviewing-code-quality` axis 4): ask verbatim, **"did we cover all the unexpected gaps
   and abnormal-usage scenarios of this functionality?"** A missing or unaddressed checklist =
   changes requested.

**Severity lens:** any case whose mishandling could break a project invariant (the 1–3 properties in
`CLAUDE.md`) is automatically **hard-gate — must fix**. Everything else is normal-priority quality.

## Workflow (builder)

Copy this checklist and tick it off:

```
Edge-case progress:
- [ ] 1. Walk families A–I in reference/catalog.md against this slice; list every applicable class
- [ ] 2. Family I on EVERY touched field, client AND server (never skip — highest-value family)
- [ ] 3. Mark each row Handled (how + test) / N/A (why) / DEFERRED (registered)
- [ ] 4. Invariant-risk rows are hard-gate: must be Handled (fixed), not left as DEFERRED
- [ ] 5. Self-check: every Handled names its test; every N/A has a reason → fix gaps, re-check
- [ ] 6. Ship the table with the change; hand it to the test author to attack and enrich
```

**Instantiation format** (a table in the change's notes / PR):

| # | Catalog class | This slice's case | Expected behaviour | Verdict |
|---|---|---|---|---|
| A1 | Back→Forward | Back from step 3 to a skipped gate, then Forward | step re-guards; server re-checks | Handled — test `…` |

**DEFERRED is never "dropped":** a case the current harness cannot test yet is tagged at the site with
a `DEFERRED-TEST:` marker and gets a row in `docs/deferred-test-registry.md`.

## Family I — the minimum on every field

Never assume the data is what the form asked for. Per field, client AND server:
- **I1 wrong-but-plausible** → a specific human error, never silent acceptance, never a crash;
- **I2 attacking data** (SQL, XSS/HTML, CRLF, path traversal, template/command injection, JSON
  structural abuse, oversized bodies) → stored and re-rendered as **inert text**, or rejected — never
  interpreted, echoed into markup, or logged raw;
- **I3 bad metadata** (type/extension/content disagree, hostile filenames, 0-byte / at-cap+1);
- **I4 Unicode end to end** (UI → transport → storage → back → render);
- **I5 normalize (NFC) + trim + case-fold BEFORE any match / uniqueness / lookup / dedupe compare or
  store** — raw-byte comparison of human-entered strings is a bug.

## Grow the catalog

When a hunt, review, test author or user report surfaces a new abnormal-behaviour pattern, ADD it to
[reference/catalog.md](reference/catalog.md) so every future slice inherits the check. Never delete a
class because it "rarely happens" — on the flows that matter, stressed non-expert users make abnormal
behaviour the norm.

## Relationship to other practices

- Threat models / abuse cases cover *adversarial attackers*; this catalog covers *legitimate users
  behaving unexpectedly* (family I straddles both). A case can belong to both.
- `hunting-bugs` runs these same lenses adversarially over a named scope and feeds new classes back.
- `hardening-security` asks the perpendicular question — does one property hold *everywhere*.
