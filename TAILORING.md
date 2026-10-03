# TAILORING — scale the harness to the project you are actually starting

**Read this before your first act on a fresh clone.** The kit ships at full size, shaped by a
long-lived, multi-agent, security-critical build. On a 200-line CLI tool that is overhead abandoned
in week two — and **an abandoned harness is worse than none**, because the repo then claims a rigour
it does not have.

> **The rule:** start at the smallest profile that fits, and let each pillar **earn** its way in.
> Every optional pillar names the **trigger** that promotes it. Adding one because a trigger fired is
> a good day; adding all on day one is how the whole thing gets deleted on day thirty.

## Contents

- The irreducible core
- Profiles — pick the smallest that fits
- Promotion triggers
- The platform layer — wiring `.claude/` (every profile), incl. Code intelligence and the rule-vs-control audit
- Stack-neutrality — one setting, and what never changes
- Domain-specific SOPs — delete them if they do not apply
- Downsizing checklist for a fresh clone
- Growing back up

---

## The irreducible core — every project, no exceptions

If you keep only these six, the harness still pays for itself.

| # | Keep | Why it survives every downsizing |
|---|---|---|
| 1 | **`CLAUDE.md`** with the «SLOT»s filled | The agent is stateless across sessions; without a constitution, session 40 does not know what session 1 decided. |
| 2 | **One living state doc** (`ONBOARDING.md`) | Where the project *is* and what happens next; a single page on a small project. |
| 3 | **Verify, don't assume** + **recall is not a source** | The two standing rules that cost nothing and catch the most; both are already in `CLAUDE.md`. |
| 4 | **A decision record** | A *section* in `ONBOARDING.md` suffices at small scale — what matters is that reasons are written where the next session reads them. |
| 5 | **A gate you actually run** | At least `build + test + secret-scan` in one script (`scripts/run-all-gates.sh`). |
| 6 | **Don't grade your own homework** | If the project has tests, a different agent/model writes them than wrote the code. Free, and it works. |

Everything else is optional and profile-dependent.

---

## Profiles — pick the smallest that fits

| Profile | Looks like | Keep, beyond the core |
|---|---|---|
| **P1 · Script / notebook / spike** | one-off analysis, a scraper, a throwaway prototype | Nothing. Core only. No ticket system for a file you will delete. |
| **P2 · Library / CLI tool** | published package, versioned API, no user data | the `writing-tests` skill · the `recording-decisions` skill (a real ADR dir — a public API makes decisions expensive to forget) · `deferred-test-registry.md` |
| **P3 · Application** | web/mobile/desktop app, has users and UI, holds state | P2 + the `covering-edge-cases` skill · the `building-ui` skill · the `implementing-mockups` skill (only if working from designs) · `feature-catalog.md` · `use-case-runbook.md` |
| **P4 · Service / multi-tenant system** | network surface, other people's data, auth | P3 + **the `hardening-security` skill** · the `hunting-bugs` skill · `tickets/security.md` · `ci/run-integrity.md` · the security sweep in `ci/gates.md` |
| **P5 · Long-lived agent-led program** | many sessions, parallel agents, an owner giving acceptance | Everything. the `orchestrating-agents` skill · the `orchestrating-agents` skill · the `communicating-with-the-owner` skill · the `reviewing-code-quality` skill · the full `tickets/` taxonomy · `runner.md` |

**Most projects are P2 or P3 and think they are P5.** Be honest on day one; promote later — every
file is still in this repo's history.

---

## Promotion triggers — when an optional pillar earns its place

Adopt a pillar when its trigger fires, and say in the commit which trigger it was.

| Pillar | File | Adopt it the first time… |
|---|---|---|
| **ADR directory** | the `recording-decisions` skill, `running-files/adr/` | …you re-argue a decision you already made, or cannot remember why something is the way it is. |
| **Ticket taxonomy** | `running-files/tickets/` | …something needed from the owner gets lost in chat. Before that, a list in `ONBOARDING.md` suffices. |
| **Feature catalog** | `running-files/feature-catalog.md` | …you cannot answer "what does this do, end to end?" without reading code, or an agent rebuilds something that exists. |
| **Wave runner** | `running-files/runner.md` | …more than one workstream is in flight and you lose track of statuses. |
| **Edge-case catalog** | the `covering-edge-cases` skill | …the first bug arrives from a user doing something you did not think of. |
| **Bug hunt SOP** | the `hunting-bugs` skill | …you want defects found *on demand* rather than as a side effect of review. |
| **Quality review SOP** | the `reviewing-code-quality` skill | …the codebase outgrows what you can review in one sitting. |
| **Security properties** | the `hardening-security` skill | …the project gains a **network surface**, **more than one user**, or **untrusted input** (see its own applicability gate). |
| **Run integrity** | `ci/run-integrity.md` | …any job with **more than one stage** has output you would report as "clean". |
| **Control timing / hooks** | `ci/control-timing.md` | …a gate catches something *after* you already built on the mistake. |
| **Roles & orchestration** | the `orchestrating-agents` skill | …you spawn your first parallel sub-agent. |
| **Agent skills** | the `orchestrating-agents` skill | …you brief sub-agents often enough that repeating the rules by hand produces drift. |
| **Owner communication** | the `communicating-with-the-owner` skill | …a non-technical owner depends on your reports. |
| **Third-party services** | `running-files/third-party-services.md` | …the second external dependency lands. |

---

## The platform layer — wiring `.claude/` (do this in every profile)

The hooks/agents/rules/skills under `dot-claude/` are profile-independent: even the smallest project
wants the guard and the banner. Full doctrine: `ci/platform-layer.md`.

1. **`scripts/init.sh` already installed it** — `dot-claude/` into `.claude/` file by file (keeping
   and naming anything of yours already there) plus the platform vars in `harness.conf`. When
   retrofitting an existing repo instead, copy `dot-claude/` into `.claude/` by hand and keep
   `settings.json`'s paths pointing at `scripts/`.
2. Fill the platform vars `init.sh` left empty: `HARNESS_PROTECTED_DBS` (dev DBs whose data must
   survive), `HARNESS_ARCHIVED_PATHS`, `HARNESS_GENERATED_PATHS` (glob=regen-command pairs),
   `HARNESS_SIBLING_REPOS`. Each switches on a guard branch that is otherwise unexercised —
   `hook-pretooluse-guard-test.sh` reports those rows as *skipped*, never as passes.
3. Start a fresh session and **see the ⚡ banner** — no banner means the hooks are not loaded, and
   nothing else in this section exists yet.
4. Run `scripts/hook-pretooluse-guard-test.sh` (20+ known-answer rows must pass, and it names the
   rows it could not exercise); adapt its ALLOW rows to your legitimate workflows before adding DENY
   patterns. The guard **fails CLOSED**: without `python3` it denies everything rather than allowing
   blind, and the banner says why. It also refuses edits to its own wiring (the
   `.claude/settings*.json` files, `scripts/hook-*.sh`, the judge scripts, `harness.conf`): for a
   tailoring or harness-upgrade session the OWNER launches with `HARNESS_ALLOW_CONTROL_EDITS=1` (the
   banner shows it is lifted), then starts the next ordinary session without it. Two advisories start
   in advise mode — `HARNESS_VERIFYCHECK_MODE` (code changed, nothing checked it) and
   `HARNESS_REPEAT_LIMIT` (same call N times); read their logs for two weeks before switching
   verify-check to `block`. Unattended runs: also turn on the OS sandbox (the `hardening-security` skill,
   Unattended runs).
5. Rename `dot-claude/rules/example-tests.md` for your stack; add one rule file per area you actually
   have.
6. Trigger one deny and one doc-gate block through the REAL path before trusting either
   (`ci/control-timing.md` C3). Agent definitions do NOT hot-reload — restart after adding the
   librarian, then give it one planted-assumption probe (`ci/platform-layer.md` P5).

**What to skip when:** a docs-light prototype can drop `hook-read-budget` and the librarian; nobody
should drop the guard, the banner or the bash-write doc gates.

### Code intelligence (LSP) — one plugin per stack, as a trial

A language server answers "where is this defined / who calls it" exactly, and the official plugins
push compiler diagnostics into context after each edit. Enable the one(s) for your stack at PROJECT
scope, so the choice is recorded in `.claude/settings.json`:

```bash
claude plugin install gopls-lsp@claude-plugins-official --scope project
```

Also available: `rust-analyzer-lsp`, `typescript-lsp`, `pyright-lsp`, `clangd-lsp`, `jdtls-lsp`,
`kotlin-lsp`, `ruby-lsp`, `php-lsp`, `swift-lsp`, `csharp-lsp`, `lua-lsp`. The language-server binary
must be on PATH (`go install golang.org/x/tools/gopls@latest`, `rustup component add rust-analyzer`,
`npm install -g typescript typescript-language-server` …); each stack pack names its plugin.
Diagnostics cost tokens on every edit. Add nothing else on speculation — the one ablation study found
removing 80% of an agent's tools raised success from 80% to 100%.

### Rule-vs-control audit — once, then whenever CLAUDE.md grows

1. For each rule in the constitution, write down its control: gated, guard-enforced, advisory hook, or
   "attention only".
2. Label a rule with no control as a HOPE in the file (`*(gated)*`, `*(guard-enforced)*`, "rides on
   your attention").
3. Per unlabelled rule: build the check, or accept and label it, or delete it.

Only 4.4% of security rules in 481 `CLAUDE.md` files had a real control (study cited in
`ci/platform-layer.md` History).

## Stack-neutrality — one setting, and what never changes

Nothing in `scripts/` hardcodes a language. Every language-shaped fact (declaration form, comment
form, test files, the skip call, error branches, vendored/generated paths) is a variable, and a
**stack pack** (`scripts/stacks/<name>.conf`) fills them all at once:

```sh
HARNESS_STACK="go"        # in harness.conf; or: scripts/init.sh "My Project" P3 go
```

Shipped: `generic` · `go` · `typescript` · `python`. Precedence is **pack < `harness.conf`**: a pack is
a correct starting point you can override; it cannot know your directory layout or runner flags.

> **`generic` is the shipping state, not the operating state.** It is a union regex that matches a
> lot and proves little: on Go it misses every method with a receiver; on Python a gate that looks
> only *above* a declaration reports every function as undocumented, because docs are a docstring
> *below* it. **Adopt a real pack in your first act.**

A pack is **proven, not asserted**: `scripts/selftest.sh` builds its fixture project *from the active
pack*, so green means the gates can see declarations, comments, skips and log calls in **your**
language.

```sh
scripts/selftest.sh                # your project's pack
scripts/selftest.sh --all-stacks   # every shipped pack — the language-neutrality claim, checked
```

A language we do not ship is ~20 lines of config and no code — `scripts/stacks/README.md` has the
variable table and fixture contract.

Set per project, because no pack can know it:

| Config | Set it to |
|---|---|
| `HARNESS_CODE_DIRS` | wherever your source actually lives |
| `HARNESS_TEST_CMD` / `HARNESS_COVERAGE_CMD` / `HARNESS_LINT_CMD` | confirm the pack's proposal against how this project really builds |
| `HARNESS_DECISION_PREFIX` | `ADR`, `RFC`, `DR` — whatever you call a decision record |
| `HARNESS_MARKERS` | your own marker types; the gate is generic |
| `HARNESS_SECRET_TERMS` | the identifier names that matter in your domain |

The dependency-CVE / SAST tools in `ci/gates.md` are a menu of per-ecosystem equivalents
(`govulncheck`, `pip-audit`, `npm audit`, `cargo audit`, `bundler-audit`); substitute yours and keep
**HIGH+ fails**.

**What never changes across stacks or profiles:** the exit vocabulary (`0` pass, `1` fail, **`3`
could-not-run**, `4` N/A), G1 (refuse to report green over an empty scan), G7+G8 (watch a gate fail,
then watch it fire through the real path), and *a skip is not a pass*. These are properties of
controls, not languages.

---

## Domain-specific SOPs — delete them if they do not apply

An inapplicable SOP left in place teaches the agent to skim SOPs generally, costing you the ones that
*do* apply.

| File | Applies when | If not |
|---|---|---|
| the `building-ui` skill | the project renders a user interface | delete |
| the `implementing-mockups` skill | you implement from design mockups | delete |
| the `hardening-security` skill | multi-user, network surface, or untrusted input | delete, or keep only P6 (fail closed) and P7 (bound anything attacker-keyed) |

---

## Downsizing checklist for a fresh clone

1. Pick a profile above. Be honest, not aspirational.
2. **Delete the running files you will not maintain this month** — an empty template is read by the
   next session as a real state doc.
3. Fill every `«SLOT»` in `CLAUDE.md` — **especially the invariants.** If you cannot name 1–3 things
   that must never break, you are not ready to pick coverage targets or write guardrail tests.
4. Cut `CLAUDE.md`'s standing rules to the ones you will enforce. **A rule nobody enforces teaches the
   agent that rules here are decorative**, and that generalises to the rules you meant.
5. Run `scripts/init.sh` to lay down the config and the registries your profile needs.
6. Run `scripts/selftest.sh` (proves every gate fails on its own violation), then verify one gate's
   **wiring** by hand (G8).
7. Write the **enforced vs unenforced** table into `CLAUDE.md` (`ci/control-timing.md` C5), honestly.

## Growing back up

Promote a pillar by copying its file from this repo, wiring its gate, and noting in `ONBOARDING.md`
**which trigger fired**. That note stops the next person asking whether the ceremony was justified —
the escape-analysis discipline applied to process instead of code.
