---
name: hardening-security
description: Holds an app's security doors shut — the per-slice security duty for any new route, input, query, response, log line or dependency (auth/cross-tenant/role matrices, rate limits, server-side validation, generic errors, audit, verified dependencies), the five property questions asked at design and test time (which identity is authorized vs used, re-checked state, victim read-back, what is not in the work list), the pre-launch 30-door map classed by what actually enforces each control, and the OS sandbox for unattended agent runs. Use when adding or changing an endpoint, auth, sessions, permissions, uploads, webhooks or dependencies; before the first real user or a launch; when the owner asks "are we secure?" or for a security review; or before an unattended or scheduled agent run.
---

# Hardening security

Two reference files, each canonical for its content:
- [reference/thirty-doors.md](reference/thirty-doors.md) — the 30 doors an attacker tries first, the
  strongest practical control for each, and what this kit ships.
- [reference/security-properties.md](reference/security-properties.md) — the perpendicular axis: the
  five questions (Q1–Q5), the properties (P1–P8), the gated property matrix, the perpendicular pass.

## The per-slice duty (every slice touching the backend)

Load this from the project's path-scoped backend rule (`.claude/rules/`), so new code cannot
quietly reopen a door. A slice that adds or changes a route, input, query, response, log line or
dependency answers before Done:

```
Security duty:
- [ ] In the unauthenticated / cross-tenant / role-boundary matrices (doors 6 / 7 / 11)
- [ ] A pre-auth route that verifies a secret has a rate-limit class (12)
- [ ] Validated server-side; generated/parameterised queries; no raw-HTML sink (13 / 14 / 15)
- [ ] A fixed error to the client, the detail only in the log (27 / 28)
- [ ] A state change is audited — who did what (29)
- [ ] A new dependency is locked and verified to exist in its registry (5 / 24)
- [ ] Q1: the identity authorized == the identity used — name the authoritative one
- [ ] Q2: the state the first step relied on is re-read by the last step (as a set)
- [ ] Q3: any shared budget/quota — who else can spend it, what goes quiet when they do
- [ ] Q4: isolation proven by re-reading the DATA as the victim, not by asserting a 403
- [ ] Q5: the uncovered surface is named out loud, the work list derived from the contract
```

Feedback loop: any unchecked box → fix it (or ticket it in `docs/tickets/security.md` with
the reason) → re-walk the list; Done only when every box is checked or explicitly ticketed. Ask the five
questions **at design time** (they change the design) and again **at test time**, where the test
author adds the perpendicular pass after the unit-local cases (details in the properties reference).

## The pre-launch map (before the first real user; keep it current)

```
Door map progress:
- [ ] 1. Copy the 30-door table into the project's security-baseline doc
- [ ] 2. First sweep: `consulting-the-librarian` with all 30 doors as the brief
- [ ] 3. Per door: the control that holds it TODAY + its class (GATED › CODE › DOC › NONE · N/A)
- [ ] 4. Verify EVERY NONE and EVERY contradiction yourself by reading the code
- [ ] 5. Every NONE/DOC row → a gate, a SEC ticket, or an explicit owner decision
- [ ] 6. Re-run steps 3–5 until no row is unowned; report to the owner in plain language
```

- **Map, don't restate.** Class by what ENFORCES the control, never by what a doc says. *WHY: on the
  source project the first mapping found 7 of 30 doors gated and 5 with no control at all — and a code
  comment falsely claiming a rate limit that a severity decision then relied on; only a code read
  caught it.*
- **Close gaps with checks, not sentences.** *WHY: an empirical survey of 481 CLAUDE.md files found
  "only 4.4% of security rules are backed by a real control".* A DOC row is a hope; label it.

## Unattended runs: turn on the OS sandbox

The destructive-command guard decides WHETHER an un-undoable command runs; it cannot limit WHERE an
allowed command reaches. When nobody is watching — headless runs, scheduled or cloud agents, a long
auto-mode job — add Claude Code's built-in Bash sandbox, which confines commands at the OS level.
OS-level isolation + policy-as-code + per-agent audit trails is the baseline for automated or shared
contexts (Barbaste et al. 2026, arXiv 2609.00006, Recommendation 10); the guard and its deny log are
the other two.

1. Supported on macOS (built in) and on Linux and WSL2 (two system packages; `/sandbox` shows what is
   missing). Native Windows is not supported — run inside WSL2.
2. In the project's .claude/settings.json (template: `.claude/settings.json`, note
   `_comment_sandbox`) set exactly `"sandbox": {"enabled": true, "failIfUnavailable": true}`, then
   narrow `sandbox.network.allowedDomains` and `sandbox.filesystem.allowWrite` to what the project
   needs. `failIfUnavailable` matters for the same reason the guard fails closed: a sandbox that
   silently does not start looks exactly like one that did.
3. Leave `sandbox.autoAllowBashIfSandboxed` off until you have read what it auto-approves.
4. Check it interactively with `/sandbox` before starting the run.

## History

- The 30-door baseline was generalised on 2026-09-29 from a live project, where the first mapping
  found 7 of 30 doors gated and 5 with no control.
- The property axis comes from the same project: 30% of its logged defects were one class (a later
  step not re-checking an earlier step's state), and an external assessment using the axis found three
  real defects, all in that class.
