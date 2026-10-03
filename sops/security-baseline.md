# SOP — Security baseline: the 30 doors, and how to hold each one shut

> An attacker's first 30 tries against a new app (a Google security engineer's pre-launch list),
> turned into a harness duty. Generalised 2026-09-29 from a live project, where the first mapping found
> 7 of 30 gated and 5 with no control at all — and a code comment falsely claiming a rate limit that a
> severity decision then relied on. **Do this map BEFORE the first real user, and keep it current.**

## How to use it

1. **Map, don't restate.** Copy the table into a security-baseline doc in your project's docs; for each
   door write the control that holds it TODAY and its class. Have the librarian do the first sweep
   (`/ask-librarian` with all 30 as the brief), then **verify every NONE and every contradiction
   yourself** — the source project's sweep surfaced a false "rate-limited" claim only a code read confirmed.
2. **Class by what ENFORCES it**, never by what a doc says:
   **GATED** (a gate/hook/test fails) › **CODE** (the implementation enforces it, with a test) ›
   **DOC** (a rule nobody checks — a hope; label it) › **NONE** (ticket it) · **N/A** (say why).
3. **Close gaps with checks, not sentences.** An empirical survey of 481 CLAUDE.md files found "only
   4.4% of security rules are backed by a real control". Each NONE/DOC row gets a gate, a ticket, or an
   explicit owner decision.
4. **Make it a per-slice duty** (bottom of this file) and load it from the path-scoped backend rule, so
   new code cannot quietly reopen a door.

## The 30 doors — and the strongest practical control for each

| # | Door | Hold it with | This kit ships |
|---|---|---|---|
| 1 | `.env` in `.gitignore` before the first commit | CODE: the ignore line in commit #1; `git check-ignore -v .env` | `.gitignore` template |
| 2 | Secret scanning as a pre-commit hook | GATED: gitleaks `protect --staged` in `pre-commit`, **failing CLOSED** when no scanner is available | — (wire gitleaks; see `ci/gates.md`) |
| 3 | Rotate any key that ever touched GitHub | DOC + runbook: deletion is not remediation — rotate, then scan history | constitution rule text |
| 4 | No API keys in the frontend bundle | CODE: only public config in `VITE_`/`NEXT_PUBLIC_` vars; secrets fetched server-side | — |
| 5 | Pin versions, commit lockfiles | GATED: lockfiles committed + a vuln scan over them; **container images pinned** | `check-image-pins.sh` (ratchet; baseline file image-pins.txt in HARNESS_BASELINE_DIR) |
| 6 | Auth on every API route (server-side) | GATED: an "unauthenticated matrix" test that calls EVERY route with no session | — (pattern in `security-properties.md`) |
| 7 | Change the ID in the URL: can A read B? | GATED: a cross-tenant matrix — A's session against B's ids, per route | — (`security-properties.md`) |
| 8 | Row-level security on every table | CODE: DB RLS, or app-level owner scoping + the matrix in 7 (an explicit architecture decision either way) | — |
| 9 | Use a real auth provider | DECISION: a managed IdP unless a hard requirement (e.g. zero-knowledge) says otherwise — record it | — |
| 10 | Short-lived access tokens; revoke on logout | CODE + test: logout kills the server-side session/refresh token; **the ADR matches the code** | — |
| 11 | Admin checks on the server | GATED: a role-boundary matrix over every staff route; allow-list, never deny-list | — |
| 12 | Rate-limit login, signup, password reset | CODE + test: a limiter class for EVERY pre-auth route that verifies a secret — including admin logins | — |
| 13 | Validate everything server-side | CODE: spec-driven request validation (middleware) beats per-handler checks | — |
| 14 | Parameterised queries only | GATED: a query generator (sqlc/prisma/…) + a semgrep SQLi rule | — |
| 15 | Escape user content before render | CODE: framework escaping + a strict CSP + a lint rule banning raw-HTML sinks | — |
| 16 | CORS locked, never `*` | CODE: explicit origin allow-list (or no CORS at all for a same-origin app) | — |
| 17 | Storage buckets private by default | CODE (IaC): public-access blocks + an IaC scanner (trivy/checkov) in the security tier | — |
| 18 | File uploads processed in a sandbox | CODE: parse untrusted files in an isolated worker, never the app process — or never parse them | — |
| 19 | Verify webhook signatures | CODE + test: the provider's verify call; a tampered-signature test | — |
| 20 | Hard spending caps (AI + cloud) | OWNER ACTION: budget alarms + provider hard caps; record them in the third-party-services running file | `running-files/third-party-services.md` |
| 21 | Rate-limit AI endpoints | CODE: a per-user + global limiter on any route that spends model tokens | — |
| 22 | Treat anything a model reads as untrusted | DOC (constitution) + outside text FENCED as `<untrusted>` in every agent brief + bound the blast radius with 23/26 — no prompt makes a denied action allowed | constitution rule text; `sops/agent-skills.md` rule 10 |
| 23 | No model runs tools/SQL/shell without limits | GATED: a PreToolUse guard that judges the DEOBFUSCATED command (wrappers stripped, flags as sets) with a known-answer matrix, and that refuses edits to its own wiring; least-privilege permissions; the OS sandbox for unattended runs (below) | `hook-pretooluse-guard.sh` + `guard-check.py` + matrix (gated) |
| 24 | Check AI-suggested packages exist | GATED (security tier): every NEW dependency must exist in its registry and be established; `ignore-scripts` on installs | — (proposal on the source project) |
| 25 | Read every CLAUDE.md/SKILL.md/MCP config like code | GATED (review): CODEOWNERS over `CLAUDE.md`, `.claude/**`, `.mcp.json`, hooks, skills | `dot-claude/` layout |
| 26 | Production credentials out of the agent's reach | GATED: an agent cannot print `.env` values or dump the environment; prod keys never live in a dev `.env` | `hook-pretooluse-secretread.sh` + matrix (gated) |
| 27 | Generic errors, no stack traces | GATED: a grep gate — no `err.Error()` / `%v` of an error / stack reaches a response (argued exceptions listed) | — (per stack; the source project's Go gate is the template) |
| 28 | Strip secrets and PII from logs | GATED: a log-hygiene gate over every logging call | `check-log-hygiene.sh` |
| 29 | Log who did what | CODE + GATED: an append-only audit trail + a gate that every write path is covered (for the AGENT itself: every guard deny is logged — rule, tool, session) | `guard.log` in `HARNESS_LOG_DIR` (agent side only) |
| 30 | Back up the DB AND test a restore | CODE (IaC retention) + a scheduled, recorded **restore drill** — a backup never restored is a hope | — |

## Unattended runs: turn on the OS sandbox

The guard decides WHETHER an un-undoable command runs; it cannot limit WHERE an allowed command
reaches. When nobody is watching the session — headless runs, scheduled or cloud agents, a long
auto-mode job — add Claude Code's built-in Bash sandbox, which confines commands at the operating-system
level. The harness-engineering source study (Barbaste et al. 2026, arXiv 2609.00006, Recommendation 10)
puts OS-level isolation plus policy-as-code plus per-agent audit trails as the baseline for automated
or shared contexts; the guard and its deny log are the other two.

- Supported on macOS (built in) and on Linux and WSL2 (two system packages; `/sandbox` shows what is
  missing). Native Windows is not supported — run inside WSL2.
- In your project's .claude/settings.json (template: `dot-claude/settings.json`): `"sandbox": {"enabled": true, "failIfUnavailable": true}`, then narrow
  `sandbox.network.allowedDomains` and `sandbox.filesystem.allowWrite` to what the project needs.
  `failIfUnavailable` matters for the same reason the guard fails closed: a sandbox that silently does
  not start looks exactly like one that did.
- Leave `sandbox.autoAllowBashIfSandboxed` off until you have read what it auto-approves.
- Check it interactively with `/sandbox`. The settings template carries the same note
  (`dot-claude/settings.json`, `_comment_sandbox`).

## The per-slice duty (put this in your path-scoped backend rule)

A slice that adds or changes a route, input, query, response, log line or dependency answers, before
Done: in the unauth / cross-tenant / role matrices (6/7/11) · a pre-auth secret-verifying route has a
rate-limit class (12) · validated server-side, generated queries, no raw HTML (13/14/15) · a fixed error
to the client, detail to the log (27/28) · a state change is audited (29) · a new dependency is locked
and verified to exist (5/24).
