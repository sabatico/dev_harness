# Edge-case catalog — unexpected user and data behaviour

The single, growing list of ways real usage deviates from the happy path. How to instantiate it per
slice (Handled / N/A-why / DEFERRED) lives in the `covering-edge-cases` skill; this file is the list.
Add new classes here when a hunt, review, test author or user report surfaces one — never delete a
class because it "rarely happens".

## Contents

- [A. Navigation & lifecycle (stateful / multi-step flows)](#a-navigation--lifecycle-stateful--multi-step-flows)
- [B. Input & interaction](#b-input--interaction)
- [C. Timing, latency & concurrency](#c-timing-latency--concurrency)
- [D. State & permission shifts under the user's feet](#d-state--permission-shifts-under-the-users-feet)
- [E. Device & environment](#e-device--environment)
- [F. Data extremes & boundaries](#f-data-extremes--boundaries)
- [G. Repetition & replay](#g-repetition--replay)
- [H. Server-side mirrors (every client case has one — the server is the REAL gate)](#h-server-side-mirrors-every-client-case-has-one--the-server-is-the-real-gate)
- [I. Input-data validity & hostile input (EVERY field, client AND server — the highest-value family)](#i-input-data-validity--hostile-input-every-field-client-and-server--the-highest-value-family)

## A. Navigation & lifecycle (stateful / multi-step flows)
- **A1 Back → Forward** through a gated/multi-step flow — history/bfcache restores STALE state, so
  mount-time guards don't re-run *(the canonical "a check gets skipped" bug)*. Also Back mid-step.
- **A2 Refresh / relaunch mid-flow** — half-filled form, mid-upload, mid-operation.
- **A3 Deep-link / direct-URL into a mid-flow step**, skipping the steps before it.
- **A4 Duplicate tab / second instance** of the same in-progress flow.
- **A5 Close mid-submit** (request in flight); OS/app session-restore reopens it later.
- **A6 Navigate away while a request is in flight** — response lands on an unmounted/changed view.
- **A7 Leave and return much later** (switched apps to grab an emailed link) — stale token, expired
  session, changed server state.

## B. Input & interaction
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

## C. Timing, latency & concurrency
- **C1 Slow response** completing AFTER the user gave up / retried / left — what does it mutate?
- **C2 Timeout → user retries** — the first attempt may still land (duplicate effects → family H).
- **C3 Two clients at once** (tabs/devices/sessions) — edit-vs-delete, both submitting the same step.
- **C4 Session/auth expires mid-flow** — is half-done work preserved? is the user told honestly?
- **C5 Token/code expires while being read/used**; resend while the old is half-entered.
- **C6 Optimistic UI vs server reject** — does the shown "success" roll back visibly?
- **C7 Rapid repeated fires** — client throttle + server rate-limit surfaced as a human message.

## D. State & permission shifts under the user's feet
- **D1 Background lock/logout/expiry mid-action** — must fail closed and recover, never half-write.
- **D2 Role/permission change or admin action** mid-session (suspended, downgraded, revoked).
- **D3 Entitlement flips mid-session** — a plan/flag/quota changes between render and submit.
- **D4 Stale cached config** — server changed a setting/catalog/price; client acts on the old copy.
- **D5 Target object changed remotely** — edited record deleted/renamed elsewhere → save into the
  void (404/409, no silent recreate).

## E. Device & environment
- **E1 Small / resized viewport** — orientation change, on-screen keyboard covering the CTA, overlays
  occluding inputs. *(Multi-width review is its own rule — `building-ui`.)*
- **E2 Offline / flaky network mid-operation** — resume or fail honestly, never fake success.
- **E3 Process/tab discarded by the OS and restored** — in-memory state is gone; restore must
  re-gate, not crash.
- **E4 Permission denied/revoked mid-use** (camera, mic, location, notifications, clipboard).
- **E5 Storage unavailable** — private-mode storage off, quota exceeded, cookies blocked → degrade
  with a message, never a blank screen.
- **E6 DOM-mutating extensions / translators** — at minimum, don't corrupt data on submit.

## F. Data extremes & boundaries
- **F1 Zero state and the pathological many** — nothing yet vs hundreds/thousands (render windows).
- **F2 Size boundaries** — at-cap, one-over, 0-byte, wrong type, the very large file (measure).
- **F3 Numeric/date bounds** — negatives, overflow, leap days, timezone-crossing, epoch, far dates.
- **F4 Duplicates** — same entity twice, re-submit of a created thing, re-adding a just-deleted one.

## G. Repetition & replay
- **G1 One-time link/token used twice** — say "already used", don't error or re-fire.
- **G2 Resend-spam** (codes, invites) — cooldowns surfaced honestly.
- **G3 Back-button re-POST / history-forward re-firing a completed step** (A1's twin).
- **G4 Re-entering a COMPLETED flow** — idempotent view, never a second execution.
- **G5 Retry after partial failure** — step 2 of 3 failed: does retry redo step 1's side effects?

## H. Server-side mirrors (every client case has one — the server is the REAL gate)
- **H1 Idempotency on every mutating endpoint** a user can double-fire — dedupe keys, locks, unique
  constraints; never balance-affecting double execution.
- **H2 Requests that skip the client** (curl/replay) — server-side validation is the real gate; a UI
  that *looks* gated is not gated *(the "skipped check" bug is an H2 failure)*.
- **H3 Out-of-order / late arrival** (retries, webhooks after a later event) — don't let stale
  messages resurrect old state.
- **H4 Atomicity of multi-step writes** — a crash between step 1 and 2 must not leave an actionable
  half-state (check-then-act under a lock/transaction).
- **H5 Concurrent same-actor requests** on the same row (C3's server half).

## I. Input-data validity & hostile input (EVERY field, client AND server — the highest-value family)
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
