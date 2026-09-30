# TAILORING — scale the harness to the project you are actually starting

**Read this before your first act on a fresh clone.** The kit ships at full size: every SOP, every
running file, every gate. That shape came from a long-lived, multi-agent, security-critical build. On
a 200-line CLI tool it is overhead that will be abandoned in week two — and **an abandoned harness is
worse than none**, because the repo then claims a rigour it does not have.

> **The rule:** start at the smallest profile that fits, and let each pillar **earn** its way in. Every
> optional pillar below names the **trigger** that promotes it. Adding one because a trigger fired is
> a good day. Adding all of them on day one is how the whole thing gets deleted on day thirty.

---

## The irreducible core — every project, no exceptions

Six things. If you keep only these, the harness still pays for itself.

| # | Keep | Why it survives every downsizing |
|---|---|---|
| 1 | **`CLAUDE.md`** with the «SLOT»s filled | The agent is stateless across sessions. Without a constitution, session 40 does not know what session 1 decided. |
| 2 | **One living state doc** (`ONBOARDING.md`) | Where the project *is*, and what happens next. On a small project this can be a single page. |
| 3 | **Verify, don't assume** + **recall is not a source** | The two standing rules that cost nothing and catch the most. Both are already in `CLAUDE.md`. |
| 4 | **A decision record** | Can be a *section* in `ONBOARDING.md` at small scale — the format matters far less than that reasons are written down where the next session reads them. |
| 5 | **A gate you actually run** | Even just `build + test + secret-scan` wired into one script. See `scripts/run-all-gates.sh`. |
| 6 | **Don't grade your own homework** | If the project has tests at all, a different agent/model writes them than wrote the code. Free, and it works. |

Everything else in this repo is optional and profile-dependent.

---

## Profiles — pick the smallest that fits

| Profile | Looks like | Keep, beyond the core |
|---|---|---|
| **P1 · Script / notebook / spike** | one-off analysis, a scraper, a prototype you may throw away | Nothing. Core only. Do not create a ticket system for a file you will delete. |
| **P2 · Library / CLI tool** | published package, versioned API, no user data | `sops/test-and-coverage.md` · `sops/decisions-adr.md` (a real ADR dir — a public API makes decisions expensive to forget) · `deferred-test-registry.md` |
| **P3 · Application** | web/mobile/desktop app, has users and UI, holds state | P2 + `sops/edge-case-catalog.md` · `sops/ui-development-guardrails.md` · `sops/mockup-implementation.md` (only if working from designs) · `feature-catalog.md` · `use-case-runbook.md` |
| **P4 · Service / multi-tenant system** | network surface, other people's data, auth | P3 + **`sops/security-properties.md`** · `sops/bug-hunt.md` · `tickets/security.md` · `ci/run-integrity.md` · the security sweep in `ci/gates.md` |
| **P5 · Long-lived agent-led program** | many sessions, parallel agents, a human owner giving acceptance | Everything. `sops/agents-and-roles.md` · `sops/agent-skills.md` · `sops/owner-communication.md` · `sops/quality-review.md` · the full `tickets/` taxonomy · `runner.md` |

**Most projects are P2 or P3 and think they are P5.** Be honest on day one; promote later. Promotion is
cheap because every file is still sitting in this repo's history.

---

## Promotion triggers — when an optional pillar earns its place

Do not adopt these on a schedule. Adopt them when the trigger fires, and say in the commit which
trigger it was.

| Pillar | File | Adopt it the first time… |
|---|---|---|
| **ADR directory** | `sops/decisions-adr.md`, `running-files/adr/` | …you re-argue a decision you already made, or you cannot remember why something is the way it is. |
| **Ticket taxonomy** | `running-files/tickets/` | …something needed from the human gets lost in chat. Before that, a list in `ONBOARDING.md` is enough. |
| **Feature catalog** | `running-files/feature-catalog.md` | …you cannot answer "what does this do, end to end?" without reading code, or an agent rebuilds something that already exists. |
| **Wave runner** | `running-files/runner.md` | …more than one workstream is in flight and you lose track of statuses. |
| **Edge-case catalog** | `sops/edge-case-catalog.md` | …the first bug arrives from a user doing something you did not think of. (It will.) |
| **Bug hunt SOP** | `sops/bug-hunt.md` | …you want defects found *on demand* rather than as a side effect of review. |
| **Quality review SOP** | `sops/quality-review.md` | …the codebase outgrows what you can review in one sitting. |
| **Security properties** | `sops/security-properties.md` | …the project gains a **network surface**, **more than one user**, or **untrusted input**. See its own applicability gate. |
| **Run integrity** | `ci/run-integrity.md` | …you have any job with **more than one stage** whose output you would report as "clean". |
| **Control timing / hooks** | `ci/control-timing.md` | …a gate catches something *after* you already built on the mistake. |
| **Roles & orchestration** | `sops/agents-and-roles.md` | …you spawn your first parallel sub-agent. |
| **Agent skills** | `sops/agent-skills.md` | …you brief sub-agents often enough that repeating the rules by hand starts producing drift. |
| **Owner communication** | `sops/owner-communication.md` | …a non-technical human depends on your reports. |
| **Third-party services** | `running-files/third-party-services.md` | …the second external dependency lands. |

---

## The platform layer — wiring `.claude/` (do this in every profile)

The hooks/agents/rules/skills under `dot-claude/` are profile-independent: even the smallest
project wants the guard and the banner. To wire (full doctrine: `ci/platform-layer.md`):

1. **`scripts/init.sh` already did this** — it installs `dot-claude/` into `.claude/` file by file
   (keeping anything of yours that was already there, and naming what it kept) and writes the
   platform vars into `harness.conf`. This used to be a manual step, and the predictable result
   was projects whose `CLAUDE.md` asserted the rules auto-loaded while no `.claude/` existed at
   all. If you are retrofitting an existing repo rather than running `init.sh`, copy
   `dot-claude/` into `.claude/` by hand and keep `settings.json`'s paths pointing at `scripts/`.
2. Fill the platform vars `init.sh` left empty: `HARNESS_PROTECTED_DBS` (dev DBs whose data must
   survive), `HARNESS_ARCHIVED_PATHS`, `HARNESS_GENERATED_PATHS` (glob=regen-command pairs),
   `HARNESS_SIBLING_REPOS`. Each one switches on a guard branch that is otherwise unexercised —
   `hook-pretooluse-guard-test.sh` reports those rows as *skipped*, never as passes.
3. Start a fresh session and **see the ⚡ banner** — no banner means the hooks are not loaded, and
   nothing else in this section exists yet.
4. Run `scripts/hook-pretooluse-guard-test.sh` (20+ known-answer rows must pass, and it names the
   rows it could not exercise); adapt its ALLOW rows to your legitimate workflows before adding
   DENY patterns. Note the guard **fails CLOSED**: without `python3` it denies everything rather
   than allowing blind, and the banner says why.
5. Rename `dot-claude/rules/example-tests.md` for your stack; add one rule file per area you
   actually have.
6. Trigger one deny and one doc-gate block through the REAL path before trusting either
   (`ci/control-timing.md` C3). Agent definitions do NOT hot-reload — restart after adding the
   librarian, then give it one planted-assumption probe (`ci/platform-layer.md` P5).

What to skip when: a docs-light prototype can drop `hook-read-budget` and the librarian; nobody
should drop the guard, the banner, or the bash-write doc gates.

### Code intelligence (LSP) — one plugin per stack, as a trial

Grep is a text search; a language server answers "where is this defined / who calls it" exactly, and
the official plugins also push compiler diagnostics into context after each edit. Enable the one(s)
for your stack at PROJECT scope, so the choice is recorded in `.claude/settings.json`:

```bash
claude plugin install gopls-lsp@claude-plugins-official --scope project
```

Also available: `rust-analyzer-lsp`, `typescript-lsp`, `pyright-lsp`, `clangd-lsp`, `jdtls-lsp`,
`kotlin-lsp`, `ruby-lsp`, `php-lsp`, `swift-lsp`, `csharp-lsp`, `lua-lsp`. The language-server binary
must be on PATH (`go install golang.org/x/tools/gopls@latest`, `rustup component add rust-analyzer`,
`npm install -g typescript typescript-language-server` …); each stack pack names its plugin.
Diagnostics cost some tokens on every edit; the source project's owner kept the plugins permanently after
one session (Go, Rust, then TypeScript). Add nothing else on speculation — the one ablation study found removing 80% of an agent's
tools raised success from 80% to 100%.

### Rule-vs-control audit — once, then whenever CLAUDE.md grows

For each rule in the constitution, write down its control: gated, guard-enforced, advisory hook, or
"attention only". A rule with no control is not wrong, but it is a HOPE — label it so in the file
(the source project did: `*(gated)*`, `*(guard-enforced)*`, "rides on your attention"). Then, per
unlabelled rule: build the check, or accept and label it, or delete it. The study behind P8
(`ci/platform-layer.md`) found only 4.4% of security rules in 481 CLAUDE.md files had a real control.

## Stack-neutrality — one setting, and what never changes

Nothing in `scripts/` hardcodes a language. Every language-shaped fact — what a function
declaration looks like, what a comment looks like, which files are tests, what "skip" is called,
what an error branch looks like, what is vendored or generated — is a variable, and a **stack pack**
(`scripts/stacks/<name>.conf`) fills them all in at once:

```sh
HARNESS_STACK="go"        # in harness.conf; or: scripts/init.sh "My Project" P3 go
```

Shipped: `generic` · `go` · `typescript` · `python`. Precedence is **pack < `harness.conf`**, so a
pack is a correct starting point you can still override — it cannot know your directory layout or
your runner's flags.

> **`generic` is the shipping state, not the operating state.** It is a union regex: it matches a
> lot and therefore proves little. On a Go codebase it misses every method with a receiver; on a
> Python one, a gate that only looks *above* a declaration reports every function as undocumented,
> because Python's docs are a docstring *below* it. **Adopt a real pack in your first act.**

**A pack is proven, not asserted.** `scripts/selftest.sh` builds its fixture project *from the
active pack*, so a green run means the gates can see declarations, comments, skips and log calls in
**your** language:

```sh
scripts/selftest.sh                # your project's pack
scripts/selftest.sh --all-stacks   # every shipped pack — the language-neutrality claim, checked
```

A language we do not ship is about twenty lines of config and no code —
`scripts/stacks/README.md` has the variable table and the fixture contract.

What you still set per project, because no pack can know it:

| Config | Set it to |
|---|---|
| `HARNESS_CODE_DIRS` | wherever your source actually lives |
| `HARNESS_TEST_CMD` / `HARNESS_COVERAGE_CMD` / `HARNESS_LINT_CMD` | confirm the pack's proposal against how this project really builds |
| `HARNESS_DECISION_PREFIX` | `ADR`, `RFC`, `DR` — whatever you call a decision record |
| `HARNESS_MARKERS` | your own marker types; the gate is generic |
| `HARNESS_SECRET_TERMS` | the identifier names that matter in your domain |

The dependency-CVE / SAST tools in `ci/gates.md` are a menu of per-ecosystem equivalents
(`govulncheck`, `pip-audit`, `npm audit`, `cargo audit`, `bundler-audit`); substitute yours and keep
the rule that **HIGH+ fails**.

**What never changes across stacks or profiles:** the exit vocabulary (`0` pass, `1` fail, **`3`
could-not-run**, `4` N/A), G1 (refuse to report green over an empty scan), G7+G8 (watch a gate fail, then watch
it fire through the real path), and *a skip is not a pass*. Those are properties of controls, not of
languages.

---

## Domain-specific SOPs — delete them if they do not apply

Three files in this kit assume a domain. Leaving an inapplicable SOP in place teaches the agent to
skim SOPs generally, which costs you the ones that *do* apply.

| File | Applies when | If not |
|---|---|---|
| `sops/ui-development-guardrails.md` | the project renders a user interface | delete |
| `sops/mockup-implementation.md` | you implement from design mockups | delete |
| `sops/security-properties.md` | multi-user, network surface, or untrusted input | delete, or keep only P6 (fail closed) and P7 (bound anything attacker-keyed) |

---

## Downsizing checklist for a fresh clone

1. Pick a profile above. Be honest, not aspirational.
2. **Delete the running files you will not maintain this month.** An empty template is a lie that the
   next session reads as a real state doc.
3. Fill every `«SLOT»` in `CLAUDE.md` — **especially the invariants.** If you cannot name 1–3 things
   that must never break, you are not ready to pick coverage targets or write guardrail tests.
4. Cut `CLAUDE.md`'s standing rules to the ones you will enforce. **A rule nobody enforces teaches the
   agent that rules here are decorative**, and that lesson generalises to the rules you meant.
5. Run `scripts/init.sh` to lay down the config and the registries your profile needs.
6. Run `scripts/selftest.sh` (proves every gate fails on its own violation), then verify one gate's
   **wiring** by hand (G8) so you know the enforcement layer is real and not just present.
7. Write the **enforced vs unenforced** table into `CLAUDE.md` (`ci/control-timing.md` C5), honestly.

## Growing back up

Promote a pillar by copying its file from this repo, wiring its gate, and noting in `ONBOARDING.md`
**which trigger fired**. That note is what stops the next person from asking whether the ceremony was
ever justified — and it is the same discipline as an escape analysis, applied to process instead of
code.
