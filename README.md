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
| 8 | **Verify, don't assume** | "Done" means build + tests + gates are green and you watched them pass. | (in `CLAUDE.md` DoD) |
| 9 | **Adversarial quality** | Abnormal-usage + hostile-input coverage is owned at build/test/review; a defect-only **bug hunt** sweeps on demand; every escape patches the process. | `sops/edge-case-catalog.md`, `sops/bug-hunt.md`, `running-files/bug-register.md` |
| 10 | **One truth + a human-readable surface** | One home per fact — boards/trackers COORDINATE, files DECIDE; counts are generated, claims are audited; the owner gets plain language + a weekly digest; agents get their rules as task-type **skills**, not memory. | `sops/owner-communication.md`, `sops/agent-skills.md`, `ci/gates.md` |

---

## The core ideas, in plain terms

1. **The agent is stateless across sessions; the repo is not.** Everything the next session (human or AI) needs to cold-start lives in **running files**, not in anyone's head. Stale state is treated as a bug.

2. **One "act" = the unit of accountability.** An act is a coherent chunk of work that ends when you yield back to the owner. The end-of-act ritual (update running files, verify green) is mandatory — it's what keeps the docs honest and the build releasable.

3. **Don't let the builder grade its own homework.** The agent/model that writes code does **not** write that code's tests. A *different* role/model does. This catches the bugs the builder is blind to. The same idea powers the **second reviewer** in a quality review and the **second ideator** in a hard decision.

4. **A "lead" owns the seams; "builders" own the insides.** Parallel work is fine, but only when file sets are **disjoint**. The lead owns the contract boundary, integration, the running files, and the final judgment. Builders work in **isolated worktrees** so they can't collide.

5. **Make the unfinished visible.** Intentional gaps (stubs, deferred tests, TODOs) get a **marker + a registry + a CI check**, so nothing is silently incomplete and everything resurfaces when its blocker lands.

6. **Decisions are cheap to make and expensive to forget.** Record them as ADRs (context, decision, alternatives rejected, consequences). Lock them. Don't re-argue.


8. **Two sources of truth guarantee drift — and prose rots on its own clock.** The field test: engineering tickets on a visual board drifted from the code *within hours* (tickets for already-built features; agents obeying tickets instead of inventorying reality) — and the status doc's hand-typed counts drifted too, just slower. The cures, in order of strength: **generate** what a script can count (facts blocks, gate-checked) → **auto-collect** what needs judgment (a claims checklist the quality review walks) → **audit on a schedule** what's left (the claims axis). Boards keep only what a repo can't do: the owner's queue, deadlines, blockage visibility — in plain language the owner never has to decode.
7. **The happy path is the easy 80%; the bugs live in the other 20%.** Users go back-and-forward, double-click, close mid-save, paste the wrong thing, and send hostile data — and *that* is where features break. So abnormal-usage and hostile-input coverage is an **owned objective at build, test, and review** (a per-feature checklist from the edge-case catalog), a **defect-only bug hunt** sweeps it adversarially on demand, and **every escaped bug patches the process** (an escape analysis), not just the code. The harness gets smarter each time reality surprises it.

---

## The kit at a glance (file map)
```
dev_harness/
├── README.md                       ← this guide
├── CLAUDE.md                       ← the per-repo constitution template (fill the «slots»)
├── CHEAT-SHEET.md                  ← the end-of-act ritual + quality-review steps + "where things go"
├── ci/gates.md                     ← the enforcement layer (build/test/coverage/secret-scan/registry checks)
├── ci/gates.md                     ← gates (build/test/coverage/secret-scan/registry checks) + the security sweep + deploy/rollback; run locally when hosted CI isn't an option
├── sops/
│   ├── quality-review.md           ← 4-axis review (quality · tests+coverage · observability · edge-case coverage) → lead + independent 2nd → judge → quality-review: commit
│   ├── test-and-coverage.md        ← cross-authored tests + coverage-as-Done + deferred-test discipline + the edge-case enrichment loop
│   ├── edge-case-catalog.md        ← the growing catalog of unexpected user/data behavior (families A–I); instantiated per feature at build/test/review
│   ├── bug-hunt.md                 ← the defect-only adversarial sweep (invent-nastier duty); DIFFERENT from a quality review
│   ├── agents-and-roles.md         ← roles, when to spawn, worktree isolation, integrate-before-removal
│   ├── decisions-adr.md            ← ADR format + the second-ideator rule + locking
│   ├── ui-development-guardrails.md ← tokens + components + zero inline styles + the three-width review; read before any UI work
│   └── mockup-implementation.md    ← design mockup → pixel-perfect: structure preservation + extract values + rendered-HTML diff
└── running-files/                  ← the project's living memory (updated at the end of every act)
    ├── ONBOARDING.md               ← current state + append-only session log
    ├── runner.md                   ← the ACTIVE wave's in-flight work
    ├── backlog-tickets.md          ← bugs + features to do, not yet scheduled
    ├── bug-register.md             ← the ONE triaged defect list (P0–P3) + the escape-analysis loop
    ├── bug-hunt-log.md             ← bug-hunt coverage map (waves) + per-session reports
    ├── tbd-parking-lot.md          ← work deliberately deferred by a constraint (with resurface triggers)
    ├── feature-catalog.md          ← the enumerable "what does it do" inventory
    ├── use-case-runbook.md         ← user stories = manual-test script = playbook
    ├── third-party-services.md     ← every external dependency: what, why, config-by-name (no secrets)
    ├── deferred-test-registry.md   ← owed-but-blocked test coverage
    └── adr/{README.md, ADR-template.md}
```
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

1. Copy `CLAUDE.md` to the repo root; fill every `«SLOT»`.
2. Copy `running-files/*` into the repo (e.g. under `docs/`); fill the headers.
3. Keep the `sops/*` either in the repo (`docs/sops/`) or linked from `CLAUDE.md`.
4. Pick the project's **invariants** (pillar 7) — the 1–3 properties that must never break — and write the guardrail tests for them first.
5. Set up the **gates**: build, test, coverage floor, secret-scan, stub/deferred-registry checks, and the security sweep (dependency-CVE + secret + SAST). Wire them into one `run-all-gates` script — run it locally before every push if hosted CI isn't available.
6. Start the first act. At its end, run the end-of-act ritual. The habit is the harness.

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
