# The Claude-Code Project Harness

A portable, project-agnostic operating system for software projects **led by an AI agent (Claude Code) with a human owner giving final acceptance.** It encodes the guardrails, living-documentation, role/orchestration, decision, and quality-review practices that keep an agent-driven build high-quality and auditable over many sessions.

> **What this is NOT:** a framework you import. It's a set of **conventions + templates + SOPs** you drop into a repo. The agent reads them every session and follows them. Humans read them to know what's going on.

---

## The 10 pillars

| # | Pillar | The one-line rule | Files |
|---|--------|-------------------|-------|
| 1 | **Constitution** | One file, loaded every session, is the supreme law. | `CLAUDE.md` |
| 2 | **Running files** | The project's state lives in living docs, updated at the end of **every** act. | `running-files/*` |
| 3 | **Decisions** | Hard/irreversible choices become ADRs; never re-litigate a locked one. | `running-files/adr/` |
| 4 | **Roles & orchestration** | A strong "lead" integrates; parallel work goes to isolated agents; tests are authored by a *different* agent than the builder. | `sops/agents-and-roles.md` |
| 5 | **Quality reviews** | "Quality review" = a repeatable 5-axis SOP (code, tests, observability, edge cases, **doc-claim truth**): lead + an independent second reviewer, lead judges, commit as the new baseline. | `sops/quality-review.md` |
| 6 | **Test & coverage discipline** | Coverage is part of Done; blocked tests are deferred-and-registered, never dropped. | `sops/test-and-coverage.md` |
| 7 | **Guardrails & safety** | Name the 1–3 invariants that must never break; confirm destructive actions; never leak secrets. | (in `CLAUDE.md`) |
| 8 | **Verify, don't assume** | "Done" means build + tests + gates are green and you watched them pass. **And the gates themselves are code that fails in ways that look like success** — a gate must refuse to report green over an empty scan, capture its own output, and be watched failing before it is trusted. | (in `CLAUDE.md` DoD), `ci/gates.md` (Gate INTEGRITY), `ci/run-integrity.md` (multi-stage runs) |
| 8b | **Recall is not a source** | A remembered fact arrives feeling exactly as certain as one just read, so "check when unsure" can never fire. Four **shapes** always get a lookup: a path, a quantity, what a document says, a result. Code names the decision that governs it, both directions. | (in `CLAUDE.md` standing rules) |
| 8c | **Controls have a WHEN, not just a WHAT** | A gate that is correct but late, wired to its weaker mode, or never loaded protects nothing — and all three print green. Fire cheap checks **at the write**; block on fact errors, advise on work-in-progress; verify a control **the way production triggers it**. | `ci/control-timing.md` |
| 8d | **A run that scanned nothing is not a clean run** | Multi-stage jobs record what each stage **actually did** in a manifest that outranks the tool output, and end in an explicit **COMPLETE / INCOMPLETE** verdict. A detector whose output is a zero proves it can still fire, every run. | `ci/run-integrity.md`, `scripts/lib/manifest.sh` |
| 9 | **Adversarial quality** | Abnormal-usage + hostile-input coverage is owned at build/test/review; a defect-only **bug hunt** sweeps on demand; every escape patches the process. Reviews & hunts file findings as `BUG`/`SEC` tickets unless fixable inline. | `sops/edge-case-catalog.md`, `sops/bug-hunt.md`, `running-files/tickets/bug-register.md`, `running-files/tickets/security.md` |
| 9b | **The perpendicular axis** | Unit-local testing asks *"is this unit correct?"*. A separate pass asks *"does this PROPERTY hold **everywhere**, and what is NOT in my work list?"* — the class that was **30% of one project's defect register**. Answers are declared per operation and gated from the contract. | `sops/security-properties.md` |
| 10b | **The platform layer** | The agent platform's own primitives carry the rules prose can't: a PreToolUse **guard** denies the un-undoable BEFORE it runs; a SessionStart **banner** proves hooks loaded (an unprotected session is otherwise invisible); path-scoped **rules** load on touch; SOPs are **skills**; retrieval is **delegated** to a read-only librarian agent that answers in verbatim quotes with per-surface hit accounting. | `ci/platform-layer.md`, `dot-claude/`, `scripts/hook-*.sh`, `scripts/librarian-sweep.sh` |
| 10 | **One truth + a human-readable surface** | One home per fact — boards/trackers COORDINATE, files DECIDE; counts are generated, claims are audited; the owner gets plain language + a weekly digest; agents get their rules as task-type **skills**, not memory. | `sops/owner-communication.md`, `sops/agent-skills.md`, `ci/gates.md` |

---

## Why so much of this is mechanised (the measurement that decides it)

One long session on the source project was audited defect by defect. Ten defects escaped into the
work. What caught each one:

| What caught it | Count |
|---|---|
| A second model reviewing | 4 |
| A gate or probe | 3 |
| Luck | 2 |
| The lead's own review | 1 |
| **A rule that had been read and was being complied with** | **0** |

Not "few" — zero. The rules were not obscure; they were in context the whole time.

The sharpest single case: an agent invented **five** plausible filenames for decision records that did
not exist, every one written with the rule that says *look them up* already loaded, several of them
after being caught doing it earlier the same day. The link gate caught 5 of 5. The rule caught 0 of 5.

The explanation is not carelessness, and this is the part that generalises:

> **A recalled fact arrives feeling exactly like one you just read. So a rule conditioned on
> *noticing* cannot fire, because the failure state is confidence, not doubt.**

Three consequences run through the whole kit:

1. **Prose sets direction; scripts hold the line.** Anything you actually depend on needs a gate
   (`ci/gates.md`, `scripts/`).
2. **The trigger must be the SHAPE of what you are writing, never your confidence in it** — a path, a
   quantity, what a document says, a result (pillar 8b).
3. **Publish which rules are enforced and which are not** (`ci/control-timing.md` C5). A harness that
   implies uniform coverage invites misplaced confidence. The rules that can never be undone —
   *never destroy without approval*, *never commit a secret* — are usually the **unenforced** ones,
   and that is exactly what a reader needs told.

---

## The core ideas, in plain terms

1. **The agent is stateless across sessions; the repo is not.** Everything the next session (human or AI) needs to cold-start lives in **running files**, not in anyone's head. Stale state is treated as a bug.

2. **One "act" = the unit of accountability.** An act is a coherent chunk of work that ends when you yield back to the owner. The end-of-act ritual (update running files, verify green) is mandatory — it's what keeps the docs honest and the build releasable.

3. **Don't let the builder grade its own homework.** The agent/model that writes code does **not** write that code's tests. A *different* role/model does. This catches the bugs the builder is blind to. The same idea powers the **second reviewer** in a quality review and the **second ideator** in a hard decision.

4. **A "lead" owns the seams; "builders" own the insides.** Parallel work is fine, but only when file sets are **disjoint**. The lead owns the contract boundary, integration, the running files, and the final judgment. Builders work in **isolated worktrees** so they can't collide.

5. **Make the unfinished visible.** Intentional gaps (stubs, deferred tests, TODOs) get a **marker + a registry + a CI check**, so nothing is silently incomplete and everything resurfaces when its blocker lands.

6. **Decisions are cheap to make and expensive to forget.** Record them as ADRs (context, decision, alternatives rejected, consequences). Lock them. Don't re-argue.

7. **The happy path is the easy 80%; the bugs live in the other 20%.** Users go back-and-forward, double-click, close mid-save, paste the wrong thing, and send hostile data — and *that* is where features break. So abnormal-usage and hostile-input coverage is an **owned objective at build, test, and review** (a per-feature checklist from the edge-case catalog), a **defect-only bug hunt** sweeps it adversarially on demand, and **every escaped bug patches the process** (an escape analysis), not just the code. The harness gets smarter each time reality surprises it.

8. **Two sources of truth guarantee drift — and prose rots on its own clock.** The field test: engineering tickets on a visual board drifted from the code *within hours* (tickets for already-built features; agents obeying tickets instead of inventorying reality) — and the status doc's hand-typed counts drifted too, just slower. The cures, in order of strength: **generate** what a script can count (facts blocks, gate-checked) → **auto-collect** what needs judgment (a claims checklist the quality review walks) → **audit on a schedule** what's left (the claims axis). Boards keep only what a repo can't do: the owner's queue, deadlines, blockage visibility — in plain language the owner never has to decode.

---

## The kit at a glance (file map)
```
dev_harness/
├── README.md                       ← this guide
├── CLAUDE.md                       ← the per-repo constitution template (fill the «slots»)
├── CHEAT-SHEET.md                  ← the end-of-act ritual + quality-review steps + "where things go"
├── TAILORING.md                    ← ⭐ READ FIRST ON A FRESH CLONE — profiles P1–P5, the irreducible
│                                      core, and the trigger that promotes each optional pillar
├── harness.conf.example            ← the ONE file you edit to point the scripts at your project
├── ci/
│   ├── gates.md                    ← the enforcement layer + the security sweep + deploy/rollback + Gate INTEGRITY (G1–G8)
│   ├── control-timing.md           ← WHEN a control fires: write-time vs push, blocking vs advisory, wiring ≠ logic
│   └── run-integrity.md            ← multi-stage runs: the manifest, the status vocabulary, COMPLETE/INCOMPLETE
├── scripts/                        ← the EXECUTABLE layer — config-driven gates, drop-in, bash 3.2 / BSD-safe
│   ├── README.md                   ←   what each gate holds + the two-step adoption ritual (G7 logic, G8 wiring)
│   ├── init.sh                     ←   bootstrap a fresh clone: layout, name substitution, config,
│   │                                    doc index, baseline; PRINTS what to prune, deletes nothing
│   ├── run-all-gates.sh            ←   the local CI: tiered, per-gate output capture, skip-is-not-a-pass
│   ├── hook-fast-gates.sh          ←   the same gates, fired at the moment of the write
│   ├── check-*.sh                  ←   doc-links · doc-paths · doc-index · markers · bug-evidence · conditional-skips · citations · log-hygiene
│   └── lib/{common,manifest}.sh    ←   the shared exit vocabulary + the manifest/verdict library
├── sops/
│   ├── quality-review.md           ← 4-axis review (quality · tests+coverage · observability · edge-case coverage) → lead + independent 2nd → judge → quality-review: commit
│   ├── test-and-coverage.md        ← cross-authored tests + coverage-as-Done + deferred-test discipline + the edge-case enrichment loop
│   ├── edge-case-catalog.md        ← the growing catalog of unexpected user/data behavior (families A–I); instantiated per feature at build/test/review
│   ├── bug-hunt.md                 ← the defect-only adversarial sweep (invent-nastier duty); DIFFERENT from a quality review
│   ├── security-properties.md      ← the perpendicular axis: the five questions, P1–P8, the gated property matrix
│   ├── agents-and-roles.md         ← roles, when to spawn, worktree isolation, integrate-before-removal
│   ├── decisions-adr.md            ← ADR format + the second-ideator rule + locking
│   ├── ui-development-guardrails.md ← tokens + components + zero inline styles + the three-width review; read before any UI work
│   └── mockup-implementation.md    ← design mockup → pixel-perfect: structure preservation + extract values + rendered-HTML diff
└── running-files/                  ← the project's living memory (updated at the end of every act)
    ├── ONBOARDING.md               ← current state + append-only session log
    ├── runner.md                   ← the ACTIVE wave's in-flight ENGINEERING work
    ├── tickets/                    ← the typed COORDINATION queue (one file per type — replaces a project board)
    │   ├── README.md               ←   the ticket taxonomy + rules + where reviews/hunts file findings
    │   ├── user-actions.md         ←   USER — actions only the human can do
    │   ├── decisions.md            ←   DEC  — pending human decisions (→ recorded as ADRs)
    │   ├── blocked-features.md     ←   FEAT — blocked-feature visibility ONLY (closes on unblock)
    │   ├── doc-work.md             ←   DOC  — documentation work not doable inline
    │   ├── business.md             ←   BIZ  — business / organisational actions
    │   ├── bug-register.md         ←   BUG  — the ONE triaged defect list (P0–P3) + escape-analysis loop
    │   └── security.md             ←   SEC  — security-hardening register (not live defects)
    ├── backlog-tickets.md          ← unscheduled ENGINEERING bugs + features
    ├── bug-hunt-log.md             ← bug-hunt coverage map (waves) + per-session reports
    ├── tbd-parking-lot.md          ← work deliberately deferred by a constraint + open questions  (TBD)
    ├── feature-catalog.md          ← the enumerable "what does it do" inventory
    ├── use-case-runbook.md         ← user stories = manual-test script = playbook
    ├── third-party-services.md     ← every external dependency: what, why, config-by-name (no secrets)
    ├── deferred-test-registry.md   ← owed-but-blocked test coverage
    └── adr/{README.md, ADR-template.md}
```
**Coordination tickets vs engineering state:** the `tickets/*` files carry only what a repo can't —
the human's queue, pending decisions, blockage visibility. **Engineering work is never a ticket**
(it lives in `ONBOARDING.md` + the ADR + `runner.md`) — two sources of truth for engineering state
guarantee drift. `BUG` and `TBD` keep their own long-standing files; the `tickets/README.md` index
names the whole taxonomy in one place.
The "ledgers of the incomplete" — `tbd-parking-lot`, `deferred-test-registry`, the stub rows in `third-party-services`/`feature-catalog` — share one pattern: **a marker in code + a registry row + a CI check**, so nothing is silently unfinished.

---

## The session cadence (what every session looks like)

```
COLD START   → read CLAUDE.md, then the running files in the prescribed order.
PLAN         → restate the goal; pick the smallest valuable slice; note open decisions.
BUILD        → implement; for hard/irreversible decisions, write/▲ an ADR first; instantiate the edge-case checklist.
TEST         → tests authored by a different role/model than the builder; attack + enrich the edge-case checklist.
VERIFY       → build + tests + gates green, watched (not assumed).
END OF ACT   → update ALL running files; commit; report outcomes faithfully.
```

The **quality review** is a periodic, deeper pass that runs across everything since the last review — not every act, but on demand and at milestones.

---

## How to bootstrap a new project

**Start here: [`TAILORING.md`](TAILORING.md).** The kit ships at full size — every SOP, every running
file, every gate — and that shape came from a long-lived multi-agent build. On a small project it is
overhead that gets abandoned in week two, and **an abandoned harness is worse than none**, because the
repo then claims a rigour it does not have. Pick the smallest profile that fits and let each pillar
earn its way in.

```sh
git clone <this repo> my-project && cd my-project
scripts/init.sh "My Project" P2      # P1 script · P2 library/CLI · P3 app · P4 service · P5 program
```

`init.sh` lays down `docs/`, substitutes the project name, writes `harness.conf`, generates the doc
index, and regenerates the path baseline against the real layout. It **prints** what your profile does
not need and **deletes nothing** — pruning has a blast radius, so it is a human's call. Then:

1. Fill every `«SLOT»` in `CLAUDE.md`.
2. Copy `running-files/*` into the repo (e.g. under `docs/`); fill the headers.
3. Keep the `sops/*` either in the repo (`docs/sops/`) or linked from `CLAUDE.md`.
4. Pick the project's **invariants** (pillar 7) — the 1–3 properties that must never break — and write the guardrail tests for them first.
5. Set up the **gates**. Copy `harness.conf.example` → `harness.conf`, fill in every path, copy
   `scripts/` into the repo, and run `scripts/run-all-gates.sh`. Add your stack's build, test,
   coverage floor, secret-scan and security sweep (dependency-CVE + secret + SAST) to the config.
   Run it locally before every push if hosted CI isn't available.
6. **Verify the gates.** `scripts/selftest.sh` does the G7 half for you — it plants a violation per
   gate and asserts each one goes red, then recovers. Then do the G8 half yourself: wire
   `hook-fast-gates.sh` into your agent harness and confirm you have **seen one fire** in this
   session (`ci/control-timing.md` C3 — an unloaded hook is invisible, and calling the script proves
   only the script).
7. Write the **enforced vs unenforced** table into `CLAUDE.md` (C5) and keep it current as gates land.
8. Start the first act. At its end, run the end-of-act ritual. The habit is the harness.

---

## Where this aligns with established practice (so it's not just our invention)
- **ADRs** — Michael Nygard's Architecture Decision Records.
- **Living docs / runbooks** — SRE + ops practice (Google SRE workbook).
- **Definition of Done + test pyramid** — Agile/XP.
- **Code-review checklists & "review the diff since baseline"** — standard PR hygiene.
- **Separation of authorship for tests/review** — "don't mark your own homework"; here re-cast for agents/models.
- **Adversarial / negative testing + fuzzing** — decades of QA practice (boundary values, abuse cases, input fuzzing); here made an *owned objective* via the edge-case catalog, the enrichment loop, and the bug hunt.
- **Blameless post-mortems** — SRE practice; here the per-bug **escape analysis** that patches the process, not just the code.
- **A per-repo agent constitution (`CLAUDE.md`) and worktree-isolated parallel agents** — the genuinely agent-era parts.

See `sops/` for the operating procedures and `running-files/` for the templates.
