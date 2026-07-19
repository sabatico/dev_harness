# SEC tickets — security-hardening register — «PROJECT»

> **`SEC-##` — a security-hardening / coverage / posture item that is NOT itself a live defect.**
> A concrete exploitable/broken thing is a **`BUG`** (`bug-register.md`, automatic P0 if it breaks a
> project invariant). A `SEC` is the *hardening* work around it: adopt a stricter config, scope a
> permission down, add a missing control, seed a scanner corpus, or **annotate a scanner
> false-positive** so it stays quiet with a reason. It's tracked with the same discipline as a bug —
> registered at discovery, closed truthfully — but it isn't fixed reflexively: **SEC items are
> triaged and scheduled, resolution waits for an explicit owner request** (a `BUG`-grade defect does
> not wait).
>
> This is where the **security sweep / scanners** send everything that isn't a defect (see
> `ci/gates.md` → the security sweep). Defects they surface go to `bug-register.md`; hardening,
> coverage gaps, and accepted-with-reason findings land here.

**Kind:** 🛡 harden (adopt a control) · 🔭 coverage (a scanner/test gap) · 📝 annotate (accepted false-positive, with reason) · ⚙ config (tighten a setting).
**Status:** ☐ open · ▶ in progress · ✅ done · 🅰 accepted (won't-fix, reason recorded)

| ID | Kind | Title | What / why (+ the risk if left) | Source | Status |
|----|------|-------|---------------------------------|--------|--------|
| SEC-001 | 🛡 | «the hardening item» | «what to change + the risk it reduces» | «sweep / review / audit» | ☐ |
| SEC-002 | 📝 | «accepted scanner finding» | «why it's a false-positive or accepted risk — the reason the annotation records» | «security sweep» | 🅰 |

## Rules
1. **Defect vs hardening.** If a finding is a *live* weakness (an exploit path, a broken control, an invariant at risk) → it's a **`BUG`**, not a `SEC` — and it follows the bug ladder (P0/P1 → escape analysis). `SEC` is for hardening/coverage/config/annotation that reduces risk without being a present defect.
2. **Triage, don't reflex-fix.** A `SEC` item is registered and scheduled; it's fixed on an explicit owner request (or when a review/deploy touches that surface). Only a `BUG`-grade defect triggers drop-everything.
3. **Accepted findings are recorded, not deleted.** A scanner false-positive or an accepted residual risk gets a `🅰 accepted` row with the *reason* — the same reason the in-code/scanner-config annotation carries (so the suppression is auditable, never silent).
4. **Run cadence.** The security sweep runs every quality review + before every deploy + monthly regardless (new CVEs land on their own clock). Each run's findings are triaged into `BUG`/`SEC` rows; keep a run log if the project has one (`ci/gates.md`).
5. **No secrets** — describe the weakness/mechanism at a level safe for the repo; a live exploit's proof-of-concept detail lives with the `BUG` row's controlled handling, not here.

> **Distinct from `BUG` (`bug-register.md`):** BUG = a defect to fix; SEC = hardening to schedule. A security *defect* is always a BUG (and a security bug's row stays deliberately thin — area + severity, never the exploit mechanism).
