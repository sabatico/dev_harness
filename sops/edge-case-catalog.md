# SOP — Edge-Case Catalog (unexpected user & data behavior)

**Read this when building or reviewing ANY feature.** It is the single, growing list of ways real
usage deviates from the happy path — close/reopen, back-and-forward, press-Enter-then-close,
double-submit, hostile input, concurrency — and the contract for handling them at **build, test,
and review**.

**The problem it solves:** a spec→build→test→review loop verifies the *intended* flow. Almost
nothing verifies the *unintended* one, so abnormal-usage bugs slip straight through — e.g. "press
Back then Forward and a verification step gets skipped." Coverage % proves lines ran; it does **not**
prove the flow survives abnormal use. This catalog is the owned objective for that gap.

## The contract (per feature — the three phases)
1. **BUILD:** while implementing, instantiate this catalog into a **feature-specific checklist** —
   every applicable class marked **Handled (how)** / **N/A (why)** / **DEFERRED** — and ship it with
   the change. Cheap at design time, expensive to retrofit.
2. **TEST:** the cross-author tester **attacks the checklist** (every `Handled` gets a test; cases
   the unit harness can't see — back/forward, session restore, real timers — go to a real-driver
   test) **and ENRICHES it**: proposes its *own* additional cases → owner/lead ruling → approved
   ones become tests → generalizable ones are folded back **here** (see `test-and-coverage.md`).
3. **REVIEW:** the reviewer asks, verbatim: **"did we cover all the unexpected gaps and
   abnormal-usage scenarios of this functionality?"** (quality-review axis 4). A missing/unaddressed
   checklist = changes-requested.

**Severity lens:** any edge case whose mishandling could break a **project invariant** (the 1–3
properties named in `CLAUDE.md`) is automatically **hard-gate — must fix**, not a nice-to-have.
Everything else is normal-priority quality.

**Instantiation format** (a table in the change's notes / PR):

| # | Catalog class | This feature's case | Expected behavior | Verdict |
|---|---|---|---|---|
| A1 | Back→Forward | Back from step 3 to a skipped gate, then Forward | step re-guards; server re-checks | Handled — test `…` |

**🟢 GROW IT.** When a hunt, review, or user report surfaces a new abnormal-behavior pattern, ADD
it here so every future feature inherits the check. Never delete a class because it "rarely
happens" — on the flows that matter, stressed non-expert users make abnormal behavior the norm.

---

## The catalog

### A. Navigation & lifecycle (stateful / multi-step flows)
- **A1 Back → Forward** through a gated/multi-step flow — history/bfcache restores STALE state, so
  mount-time guards don't re-run *(the canonical "a check gets skipped" bug)*. Also Back mid-step.
- **A2 Refresh / relaunch mid-flow** — half-filled form, mid-upload, mid-operation.
- **A3 Deep-link / direct-URL into a mid-flow step**, skipping the steps before it.
- **A4 Duplicate tab / second instance** of the same in-progress flow.
- **A5 Close mid-submit** (request in flight); OS/app session-restore reopens it later.
- **A6 Navigate away while a request is in flight** — response lands on an unmounted/changed view.
- **A7 Leave and return much later** (switched apps to grab an emailed link) — stale token, expired
  session, changed server state.

### B. Input & interaction
- **B1 Double-click / double-submit / mash the action** — duplicate operations (disable-on-first +
  server idempotency, family H).
- **B2 Keyboard-submit instead of the button** — same path/validation/disabling?
- **B3 Act, then instantly exit** — trigger + immediately close: does it complete? does the UI claim
  a success it didn't achieve?
- **B4 Rapid open/close/reopen** of modals/pickers/editors/capture surfaces — mount races, leaked
  resources (streams, listeners, timers).
- **B5 Cancel at every moment** — Escape / click-outside / X / OS-back, including mid-request.
- **B6 Paste** everywhere — into paste-blocked confirms, the wrong field, multiline into single-line.
- **B7 Autofill / password managers** — wrong field, no change event, stale value restored on Back.
- **B8 Text extremes** — empty, whitespace-only, very long, and the full hostile/Unicode set →
  deep-dive is **family I**.
- **B9 IME/composition + autocorrect/autocapitalize** on codes/keys/identifiers.
- **B10 Focus loss mid-typing** (blur-validation while still editing); tab-order into hidden controls.

### C. Timing, latency & concurrency
- **C1 Slow response** completing AFTER the user gave up / retried / left — what does it mutate?
- **C2 Timeout → user retries** — the first attempt may still land (duplicate effects → family H).
- **C3 Two clients at once** (tabs/devices/sessions) — edit-vs-delete, both submitting the same step.
- **C4 Session/auth expires mid-flow** — is half-done work preserved? is the user told honestly?
- **C5 Token/code expires while being read/used**; resend while the old is half-entered.
- **C6 Optimistic UI vs server reject** — does the shown "success" roll back visibly?
- **C7 Rapid repeated fires** — client throttle + server rate-limit surfaced as a human message.

### D. State & permission shifts under the user's feet
- **D1 Background lock/logout/expiry mid-action** — must fail closed and recover, never half-write.
- **D2 Role/permission change or admin action** mid-session (suspended, downgraded, revoked).
- **D3 Entitlement flips mid-session** — a plan/flag/quota changes between render and submit.
- **D4 Stale cached config** — server changed a setting/catalog/price; client acts on the old copy.
- **D5 Target object changed remotely** — edited record deleted/renamed elsewhere → save into the
  void (404/409, no silent recreate).

### E. Device & environment
- **E1 Small / resized viewport** — orientation change, on-screen keyboard covering the CTA, overlays
  occluding inputs. *(Multi-width review is its own rule — `ui-development-guardrails.md`.)*
- **E2 Offline / flaky network mid-operation** — resume or fail honestly, never fake success.
- **E3 Process/tab discarded by the OS and restored** — in-memory state is gone; restore must
  re-gate, not crash.
- **E4 Permission denied/revoked mid-use** (camera, mic, location, notifications, clipboard).
- **E5 Storage unavailable** — private-mode storage off, quota exceeded, cookies blocked → degrade
  with a message, never a blank screen.
- **E6 DOM-mutating extensions / translators** — at minimum, don't corrupt data on submit.

### F. Data extremes & boundaries
- **F1 Zero state and the pathological many** — nothing yet vs hundreds/thousands (render windows).
- **F2 Size boundaries** — at-cap, one-over, 0-byte, wrong type, the very large file (measure).
- **F3 Numeric/date bounds** — negatives, overflow, leap days, timezone-crossing, epoch, far dates.
- **F4 Duplicates** — same entity twice, re-submit of a created thing, re-adding a just-deleted one.

### G. Repetition & replay
- **G1 One-time link/token used twice** — say "already used", don't error or re-fire.
- **G2 Resend-spam** (codes, invites) — cooldowns surfaced honestly.
- **G3 Back-button re-POST / history-forward re-firing a completed step** (A1's twin).
- **G4 Re-entering a COMPLETED flow** — idempotent view, never a second execution.
- **G5 Retry after partial failure** — step 2 of 3 failed: does retry redo step 1's side effects?

### H. Server-side mirrors (every client case has one — the server is the REAL gate)
- **H1 Idempotency on every mutating endpoint** a user can double-fire — dedupe keys, locks, unique
  constraints; never balance-affecting double execution.
- **H2 Requests that skip the client** (curl/replay) — server-side validation is the real gate; a UI
  that *looks* gated is not gated *(the "skipped check" bug is an H2 failure)*.
- **H3 Out-of-order / late arrival** (retries, webhooks after a later event) — don't let stale
  messages resurrect old state.
- **H4 Atomicity of multi-step writes** — a crash between step 1 and 2 must not leave an actionable
  half-state (check-then-act under a lock/transaction).
- **H5 Concurrent same-actor requests** on the same row (C3's server half).

### I. Input-data validity & hostile input (EVERY field, client AND server — the highest-value family)
> Never assume the data is what the form asked for.
- **I1 Wrong-but-plausible** — passes a shape check but is semantically wrong: right format/wrong
  meaning, impossible-in-context, mismatched confirm fields, the right value in the wrong field.
  Expected: a specific human error, never silent acceptance, never a crash.
- **I2 Attacking data** — inject into every string field: **SQL** meta-chars (parameterized queries
  only) · **XSS/HTML/script** (escape by default; watch raw-HTML sinks + URL/attribute contexts) ·
  **CRLF/header injection** (values reaching headers/emails) · **path traversal** (`../`) ·
  **template / expression / command injection** · **JSON structural abuse** (deep nesting, dup keys,
  `__proto__`/prototype pollution) · **oversized bodies** (cap → 4xx, never OOM). Expected: stored &
  re-rendered as **inert text**, or rejected — never interpreted, echoed into markup, or logged raw.
- **I3 Bad metadata** — declared type/extension/content disagree (renamed executable), hostile
  embedded metadata, hostile filenames (traversal, absurd length, reserved names), 0-byte / at-cap+1;
  client-supplied context (user-agent, sizes, paths) treated as untrusted text.
- **I4 Character families — is it REALLY all Unicode, end to end?** Non-Latin scripts, **RTL + bidi
  overrides** (a control char can visually reverse a filename), multi-codepoint emoji (length caps &
  truncation must not split a grapheme), combining marks, zero-width chars, **homoglyphs** (look-
  alike letters across scripts — a matching/identity risk), control/null bytes, BOM, lone surrogates.
  Verify the FULL path: UI → transport → storage → back → render (no mojibake, no truncation mid-
  codepoint, no comparison surprises).
- **I5 Normalization & canonicalization** — the same visible string can be different bytes (NFC vs
  NFD; different systems emit different forms). Every field used for **matching / uniqueness / lookup
  / dedupe** must **normalize (NFC) + trim + case-fold BEFORE compare/store**; raw-byte comparison of
  human-entered strings is a bug. Also: whitespace rules, email casing, non-ASCII digit families. *(A
  normalization mismatch in an identity/match field can block a legitimate user — often an invariant
  risk.)*

---

## Relationship to other practices
- **Threat model / abuse cases** cover *adversarial attackers*; this catalog covers *legitimate
  users behaving unexpectedly* (plus family I, which straddles both). A case can belong to both.
- **`bug-hunt.md`** runs these same lenses adversarially over a named scope and feeds new classes
  back here. **`test-and-coverage.md`** owns the enrichment loop. **`quality-review.md` axis 4** is
  the review checkpoint.
