#!/usr/bin/env bash
# hook-session-start-test.sh — acceptance matrix for the ONBOARDING injection in
# scripts/hook-session-start.sh (v1.3). Only that part of the brief is pinned here.
#
# Pins: the "current state" block carries the status section and the decided section, each bounded
# to 10 lines; headings are matched by MEANING, not number (renumbered / reordered / unnumbered);
# HTML comments — multi-line and single-line — are never injected; with neither section the brief
# prints the ⚠ "could NOT be injected" line instead of nothing; lines are cut at 200 chars; no
# ONBOARDING → neither block. Every "must not appear" row has a sibling proving the same machinery
# DOES inject (T2).
#
# Each scenario is a throwaway git repo with its own docs/ONBOARDING.md (and no harness.conf); the
# hook runs with stdin from /dev/null and every HARNESS_* variable unset.
# Test seam, stated: `sleep` is shadowed by a wrapper that runs the real sleep with its output
# detached. The hook's bounded() leaves an orphan `sleep 8` holding the command-substitution pipe,
# so each run takes ~16 s (reported to the lead); the wrapper changes no timing the ONBOARDING code
# sees and keeps the matrix at a few seconds.
# Cross-authored 2026-10-03 by a test author who did not build the hook. Cases the hook currently gets
# WRONG are not rows; they went to the lead in the test author's report.
# Usage: scripts/hook-session-start-test.sh [path/to/hook-session-start.sh]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${1:-$HERE/hook-session-start.sh}"
[ -f "$HOOK" ] || { echo "no hook-session-start.sh at $HOOK" >&2; exit 2; }
HOOK="$(cd "$(dirname "$HOOK")" && pwd)/$(basename "$HOOK")"
T=$(mktemp -d "${TMPDIR:-/tmp}/ss-test.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
for v in $(env | sed -n 's/^\(HARNESS_[A-Z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$T/bin"; REAL_SLEEP="$(command -v sleep)"
printf '#!/bin/sh\nexec "%s" "$@" >/dev/null 2>&1 </dev/null\n' "$REAL_SLEEP" > "$T/bin/sleep"; chmod +x "$T/bin/sleep"
P=0; F=0; S=0; N=0
ok()   { if [ "$2" = 0 ]; then P=$((P+1)); echo "  ok    $1"; else F=$((F+1)); echo "  FAIL  $1"; [ -n "${3:-}" ] && printf '        %s\n' "$3"; fi; }
skip() { S=$((S+1)); echo "  SKIP  $1 — $2 (unexercised: NOT a pass)"; }
# repo → a fresh git repo (call it with `< <(…)` or a heredoc, never `… | repo`: a pipe runs it in a
# subshell and D/N are lost); ONBOARDING content comes on stdin, written to ${ONB_AT:-docs/ONBOARDING.md}.
repo() { N=$((N+1)); D="$T/r$N"; mkdir -p "$D/docs"; git -C "$D" init -q; [ "${1:-}" = none ] || cat > "$D/${ONB_AT:-docs/ONBOARDING.md}"; }
run()  { OUT=$(cd "$D" && PATH="$T/bin:$PATH" bash "$HOOK" </dev/null 2>"$T/err"); RC=$?; ERR=$(cat "$T/err"); }
has()  { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
CS="── current state ("; DV="  · decided vs open:"; WN="── what happens next ("
# The injected block: from the "current state" header to the first blank line. status = the lines before
# the "· decided vs open:" marker; decided = the lines after it.
block()   { printf '%s\n' "$OUT" | awk -v s="$CS" 'f && /^$/ { exit } f { print } index($0, s) == 1 { f = 1 }'; }
status_l(){ block | awk -v m="$DV" '$0 == m { exit } { print }'; }
decided_l(){ block | awk -v m="$DV" 'f { print } $0 == m { f = 1 }'; }
inblock() { block | grep -qF -- "$1"; }

echo "-- the block carries the status and the decided sections"
repo <<'EOF'
# Project — onboarding

## 1. Current status
- phase: building the cart
- tests green on main

## 2. Decided vs open
- DECIDED: ISO dates everywhere
- OPEN: refund window

## 3. Next steps
- wire the payment stub
EOF
run
ok "exit 0, banner printed (the hook ran)" $([ $RC = 0 ] && has '⚡ SESSION BRIEF'; echo $?) "rc=$RC $ERR"
ok "'── current state (docs/ONBOARDING.md …' header present" $(has "${CS}docs/ONBOARDING.md"; echo $?)
ok "status lines are injected (and only the status lines precede the decided marker)" $([ "$(status_l)" = "$(printf '  - phase: building the cart\n  - tests green on main')" ]; echo $?) "$(block)"
ok "decided lines are injected after '· decided vs open:'" $([ "$(decided_l)" = "$(printf '  - DECIDED: ISO dates everywhere\n  - OPEN: refund window')" ]; echo $?) "$(block)"
ok "the next section's lines are NOT pulled into the block" $(! inblock 'wire the payment stub'; echo $?)
ok "control: they DO appear under 'what happens next'" $(printf '%s\n' "$OUT" | sed -n "/$WN/,\$p" | grep -qF 'wire the payment stub'; echo $?)
ok "no ⚠ 'could NOT be injected' when both sections exist" $(! has 'could NOT be injected'; echo $?)

echo "-- bounded to 10 lines each (blank lines do not count)"
repo < <(printf '## Current status\n'; for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15; do printf -- '- s%s\n\n' "$i"; done
  printf '## Decided vs open\n'; for i in 01 02 03 04 05 06 07 08 09 10 11 12; do printf -- '- d%s\n' "$i"; done)
run
ok "status: exactly 10 lines (s01..s10), s11 and later dropped" $([ "$(status_l | grep -c .)" = 10 ] && status_l | grep -qx '  - s10' && ! inblock 's11' && ! inblock 's15'; echo $?) "$(status_l)"
ok "status: the blank lines between items did not eat the budget" $(status_l | grep -qx '  - s01' && ! status_l | grep -qx '  '; echo $?)
ok "decided: exactly 10 lines (d01..d10), d11/d12 dropped" $([ "$(decided_l | grep -c .)" = 10 ] && decided_l | grep -qx '  - d10' && ! inblock 'd11'; echo $?) "$(decided_l)"

echo "-- headings matched by meaning, not by number or order"
repo <<'EOF'
## 1. Read me first
- READ-ME line must not be injected
## 4. Decided vs Open
- dec-renumbered
## 7. CURRENT STATUS
- st-renumbered
### 7a. a sub-heading stays inside the section
- st-under-subheading
## 8. Session log
- LOG line must not be injected
EOF
run
ok "renumbered + reordered + upper-case: status found under '## 7. CURRENT STATUS'" $(status_l | grep -qx '  - st-renumbered'; echo $?) "$(block)"
ok "renumbered: decided found under '## 4. Decided vs Open'" $(decided_l | grep -qx '  - dec-renumbered'; echo $?) "$(block)"
ok "a ### sub-heading does not end the status section" $(status_l | grep -qx '  - st-under-subheading'; echo $?)
ok "sections with other meanings are not injected" $(! inblock 'READ-ME line' && ! inblock 'LOG line'; echo $?)
repo <<'EOF'
## Status
- st-unnumbered
## Decided
- dec-unnumbered
EOF
run
ok "unnumbered headings ('## Status', '## Decided') work too" $(status_l | grep -qx '  - st-unnumbered' && decided_l | grep -qx '  - dec-unnumbered'; echo $?) "$(block)"
repo < <(printf '## 1. Current status\r\n- st-crlf\r\n\r\n## 2. Decided vs open\r\n- dec-crlf\r\n')
run
ok "a CRLF file still injects both sections" $(inblock 'st-crlf' && inblock 'dec-crlf'; echo $?) "$(block | od -c | head -5)"

echo "-- HTML comments are never injected"
repo <<'EOF'
<!--
## Current status
- FAKE-status-in-comment
-->
## 1. Current status
<!-- single-line guidance: never injected -->
   <!-- an indented single-line comment -->
- st-before-comment
<!--
TEMPLATE GUIDANCE line one
TEMPLATE GUIDANCE line two
-->
- st-after-comment
## 2. Decided vs open
<!-- decided guidance -->
- dec-real
<!-- start of a comment
spanning -- with dashes -- inside
-->
- dec-after
EOF
run
ok "control: the real lines around the comments ARE injected" $(inblock 'st-before-comment' && inblock 'st-after-comment' && inblock 'dec-real' && inblock 'dec-after'; echo $?) "$(block)"
ok "multi-line comment body is never injected" $(! inblock 'TEMPLATE GUIDANCE' && ! inblock 'spanning --'; echo $?) "$(block)"
ok "single-line comments (incl. indented) are never injected" $(! inblock 'guidance' && ! inblock 'indented single-line'; echo $?)
ok "no comment delimiter leaks into the block" $(! inblock '<!--' && ! inblock '-->'; echo $?)
ok "a '## Current status' heading INSIDE a comment is not taken as the section" $(! inblock 'FAKE-status-in-comment'; echo $?)
repo <<'EOF'
## 1. Current status
<!-- template: replace this with the real status -->

## 2. Decided vs open
<!--
  - DECIDED: …
  - OPEN: …
-->
EOF
run
ok "both sections hold ONLY comments (untouched template) → ⚠ instead of an empty block" $(has '⚠ docs/ONBOARDING.md has no section headed' && ! has "$CS" && ! has 'DECIDED: …'; echo $?) "$OUT"

echo "-- a missing section is loud, never silent"
repo <<'EOF'
# Onboarding
## 1. Overview
- an overview
## 6. Next steps
- next-thing
EOF
run
ok "no status and no decided section → the ⚠ 'could NOT be injected' line" $(has '⚠ docs/ONBOARDING.md has no section headed '"'"'status'"'"' or '"'"'decided'"'"' — the current state could NOT be injected; read the file.'; echo $?) "$OUT"
ok "…and no empty 'current state' header" $(! has "$CS"; echo $?)
ok "…while 'what happens next' still runs (exit 0)" $([ $RC = 0 ] && has "$WN" && has 'next-thing'; echo $?)

echo "-- lines are cut at 200 chars"
repo < <(printf '## Current status\n'; printf -- '-%0249d\n' 0; printf -- '-%0199d\n' 7; printf '## Decided\n'; printf -- '-%0299d\n' 9)
run
L1="$(status_l | sed -n 1p)"; L2="$(status_l | sed -n 2p)"; L3="$(decided_l | sed -n 1p)"
ok "a 250-char status line → 2-space indent + its first 200 chars" $([ "$L1" = "  $(printf -- '-%0249d' 0 | cut -c1-200)" ] && [ "${#L1}" = 202 ]; echo $?) "len=${#L1}"
ok "a line of exactly 200 chars is kept whole" $([ "$L2" = "  $(printf -- '-%0199d' 7)" ]; echo $?) "len=${#L2}"
ok "a 300-char decided line is cut to 200 too" $([ "${#L3}" = 202 ]; echo $?) "len=${#L3}"

echo "-- which file, and no file"
repo none
run
ok "no ONBOARDING anywhere: neither block, no ⚠ line, exit 0" $([ $RC = 0 ] && ! has "$CS" && ! has 'could NOT be injected' && ! has "$WN"; echo $?) "$OUT"
ok "control: the hook did run (banner present)" $(has '⚡ SESSION BRIEF'; echo $?)
ONB_AT=ONBOARDING.md repo < <(printf '## Status\n- st-at-root\n')
run
ok "ONBOARDING.md at the repo root is used when docs/ has none" $(has "${CS}ONBOARDING.md" && inblock 'st-at-root'; echo $?) "$OUT"
printf '## Status\n- st-root-loses\n' > "$D/ONBOARDING.md"; printf '## Status\n- st-docs-wins\n' > "$D/docs/ONBOARDING.md"
run
ok "both present: docs/ONBOARDING.md wins" $(has "${CS}docs/ONBOARDING.md" && inblock 'st-docs-wins' && ! has 'st-root-loses'; echo $?) "$(block)"

if [ "$S" -gt 0 ]; then echo "hook-session-start-test: $P passed, $F failed, $S SKIPPED (unexercised — NOT passes)"
else echo "hook-session-start-test: $P passed, $F failed"; fi
[ "$F" = 0 ]
