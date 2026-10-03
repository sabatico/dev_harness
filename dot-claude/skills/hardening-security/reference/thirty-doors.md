# The 30 doors — and the strongest practical control for each

An attacker's first 30 tries against a new app (a Google security engineer's pre-launch list). Copy
this table into your project's security-baseline doc and, per door, write the control that holds it
TODAY and its class. The procedure is in the `hardening-security` skill.

**Classes — by what ENFORCES it, never by what a doc says:**
**GATED** (a gate/hook/test fails) › **CODE** (the implementation enforces it, with a test) ›
**DOC** (a rule nobody checks — a hope; label it) › **NONE** (ticket it) · **N/A** (say why).

The "Hold it with" column below names the strongest practical control and its class; "This kit
ships" names what the harness already provides.

| # | Door | Hold it with | This kit ships |
|---|---|---|---|
| 1 | `.env` in `.gitignore` before the first commit | CODE: the ignore line in commit #1; `git check-ignore -v .env` | `.gitignore` template |
| 2 | Secret scanning as a pre-commit hook | GATED: gitleaks `protect --staged` in `pre-commit`, **failing CLOSED** when no scanner is available | — (wire gitleaks; see `docs/ci/gates.md`) |
| 3 | Rotate any key that ever touched GitHub | DOC + runbook: deletion is not remediation — rotate, then scan history | constitution rule text |
| 4 | No API keys in the frontend bundle | CODE: only public config in `VITE_`/`NEXT_PUBLIC_` vars; secrets fetched server-side | — |
| 5 | Pin versions, commit lockfiles | GATED: lockfiles committed + a vuln scan over them; **container images pinned** | `check-image-pins.sh` (ratchet; baseline file image-pins.txt in HARNESS_BASELINE_DIR) |
| 6 | Auth on every API route (server-side) | GATED: an "unauthenticated matrix" test that calls EVERY route with no session | — (pattern: the property matrix in `hardening-security`) |
| 7 | Change the ID in the URL: can A read B? | GATED: a cross-tenant matrix — A's session against B's ids, per route | — (the property matrix in `hardening-security`) |
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
| 20 | Hard spending caps (AI + cloud) | OWNER ACTION: budget alarms + provider hard caps; record them in the third-party-services running file | `docs/third-party-services.md` |
| 21 | Rate-limit AI endpoints | CODE: a per-user + global limiter on any route that spends model tokens | — |
| 22 | Treat anything a model reads as untrusted | DOC (constitution) + outside text FENCED as `<untrusted>` in every agent brief + bound the blast radius with 23/26 — no prompt makes a denied action allowed | constitution rule text; the untrusted-fence rule in `orchestrating-agents` |
| 23 | No model runs tools/SQL/shell without limits | GATED: a PreToolUse guard that judges the DEOBFUSCATED command (wrappers stripped, flags as sets) with a known-answer matrix, and that refuses edits to its own wiring; least-privilege permissions; the OS sandbox for unattended runs (below) | `hook-pretooluse-guard.sh` + `guard-check.py` + matrix (gated) |
| 24 | Check AI-suggested packages exist | GATED (security tier): every NEW dependency must exist in its registry and be established; `ignore-scripts` on installs | — (proposal on the source project) |
| 25 | Read every CLAUDE.md/SKILL.md/MCP config like code | GATED (review): CODEOWNERS over `CLAUDE.md`, `.claude/**`, `.mcp.json`, hooks, skills | `.claude/` layout |
| 26 | Production credentials out of the agent's reach | GATED: an agent cannot print `.env` values or dump the environment; prod keys never live in a dev `.env` | `hook-pretooluse-secretread.sh` + matrix (gated) |
| 27 | Generic errors, no stack traces | GATED: a grep gate — no `err.Error()` / `%v` of an error / stack reaches a response (argued exceptions listed) | — (per stack; the source project's Go gate is the template) |
| 28 | Strip secrets and PII from logs | GATED: a log-hygiene gate over every logging call | `check-log-hygiene.sh` |
| 29 | Log who did what | CODE + GATED: an append-only audit trail + a gate that every write path is covered (for the AGENT itself: every guard deny is logged — rule, tool, session) | `guard.log` in `HARNESS_LOG_DIR` (agent side only) |
| 30 | Back up the DB AND test a restore | CODE (IaC retention) + a scheduled, recorded **restore drill** — a backup never restored is a hope | — |
