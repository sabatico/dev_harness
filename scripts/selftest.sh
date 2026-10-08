#!/usr/bin/env bash
# selftest.sh — prove every gate in this kit actually FAILS on the thing it claims to catch.
#
# ── WHY THIS EXISTS, AND WHY IT IS NOT A ONE-TIME RITUAL ─────────────────────
#
# gates.md G7 says: plant a violation, watch the gate go red, restore, watch it pass. Correct — and
# as a one-time authoring ritual it decays, because a gate can break LATER and a broken gate reports
# exactly what a clean tree reports: nothing.
#
# ci/run-integrity.md R5 is the generalisation: when a control's success condition is an ABSENCE,
# build the positive control INTO the run. This file is that positive control for the kit's own gates.
#
# It is also the honest answer to "have these scripts been tested?". Run it and you know, rather than
# trusting a claim in a README.
#
# For each gate it builds a throwaway fixture project and asserts THREE things:
#   1. clean fixture      → the gate PASSES   (no false positive)
#   2. planted violation  → the gate FAILS    (it can actually see the thing)
#   3. violation removed  → the gate PASSES   (it was the plant, not the fixture)
#
# Step 3 matters as much as step 2: a gate that fails on everything also "catches" the plant.
#
# ── AND IT IS PARAMETERISED BY YOUR LANGUAGE ─────────────────────────────────
#
# The fixture is built FROM THE ACTIVE STACK PACK (scripts/stacks/<HARNESS_STACK>.conf), not from a
# language chosen by whoever wrote this file. That is the whole point of the pack mechanism: a
# green run here proves the gates can see declarations, comments, skips and log calls **in the
# language you actually write**. A suite that only ever proved them in Go would be a suite that
# says nothing to a Python project — while printing the same reassuring green.
#
#   scripts/selftest.sh                  # the pack harness.conf selects
#   scripts/selftest.sh markers          # one gate
#   scripts/selftest.sh --stack python   # one named pack
#   scripts/selftest.sh --all-stacks     # every pack shipped in scripts/stacks/

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

ONLY=""; WANT_STACK=""; ALL_STACKS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all-stacks) ALL_STACKS=1 ;;
    --stack)      WANT_STACK="${2:-}"; shift ;;
    --stack=*)    WANT_STACK="${1#--stack=}" ;;
    -h|--help)    sed -n '2,40p' "$0"; exit 0 ;;
    *)            ONLY="$1" ;;
  esac
  shift
done

# Which pack is in play. Explicit flag wins; otherwise read the project's own harness.conf, so a
# bare `scripts/selftest.sh` in a real project tests THAT project's language.
resolve_stack() {
  local cfg; cfg="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/harness.conf"
  if [ -n "$WANT_STACK" ]; then printf '%s' "$WANT_STACK"; return; fi
  if [ -f "$cfg" ]; then
    local p; p="$(sed -n 's/^[[:space:]]*HARNESS_STACK=["'"'"']\{0,1\}\([A-Za-z0-9_-]\{1,\}\).*/\1/p' "$cfg" | tail -1)"
    [ -n "$p" ] && { printf '%s' "$p"; return; }
  fi
  printf 'generic'
}
STACK="$(resolve_stack)"
PACK="$HERE/stacks/$STACK.conf"
if [ ! -f "$PACK" ]; then
  echo "no such stack pack: $PACK (see scripts/stacks/README.md)" >&2; exit 2
fi
# shellcheck disable=SC1090
. "$PACK"
FIX_EXT="${HARNESS_FIX_SRC_NAME##*.}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; B=$'\033[1m'; Z=$'\033[0m'
else R=""; G=""; Y=""; D=""; B=""; Z=""; fi

PASS=0; FAIL=0; FAILED_GATES=""

# ── the fixture: a minimal, fully COMPLIANT project ──────────────────────────
build_fixture() {
  # macOS `mktemp -d` ignores TMPDIR; the template keeps every kit test on the same temp root.
  FX="$(mktemp -d "${TMPDIR:-/tmp}/selftest.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 3; }
  mkdir -p "$FX/docs/tickets" "$FX/src" "$FX/tests"
  ( cd "$FX" && git init -q . && git config user.email t@example.com && git config user.name t )

  # The fixture config names the pack under test. CODE_EXTS is pinned to the fixture's own
  # extension so the gates scan exactly what we planted and nothing else.
  cat > "$FX/harness.conf" <<CONF
HARNESS_STACK="$STACK"
HARNESS_DOC_DIRS="docs"
HARNESS_DOC_INDEX="docs/documentation-index.md"
HARNESS_CODE_DIRS="src tests"
HARNESS_CODE_EXTS="$FIX_EXT"
HARNESS_DECISION_DIR="docs/adr"
HARNESS_DECISION_PREFIX="ADR"
HARNESS_BUG_REGISTER="docs/tickets/bug-register.md"
HARNESS_MARKERS="DEFERRED-TEST:docs/deferred-test-registry.md"
HARNESS_SECRET_TERMS="password token secret"
HARNESS_BASELINE_DIR=".harness/baselines"
HARNESS_BASE_REF="origin/main"
CONF

  cat > "$FX/docs/documentation-index.md" <<'EOF'
# Documentation index
| Doc | Holds | Update when |
|---|---|---|
| `docs/ONBOARDING.md` | state | every act |
| `docs/deferred-test-registry.md` | owed tests | a marker lands |
| `docs/tickets/bug-register.md` | defects | at discovery |
EOF
  cat > "$FX/docs/ONBOARDING.md" <<'EOF'
# ONBOARDING
State lives here.
See the [bug register](tickets/bug-register.md).
EOF
  cat > "$FX/docs/deferred-test-registry.md" <<EOF
# Deferred tests
| Code site | Owed | Unblock |
|---|---|---|
| \`src/$HARNESS_FIX_SRC_NAME\` | provider round-trip | provider lands |
EOF
  cat > "$FX/docs/tickets/bug-register.md" <<'EOF'
# Bug register
## Open bugs
| ID | Sev | Summary | Status |
|----|-----|---------|--------|
| BUG-002 | P2 | open one | open |

## Closed bugs
| ID | Sev | Summary | Fix | Verified by (the test that went RED) | Escape analysis |
|----|-----|---------|-----|--------------------------------------|-----------------|
| BUG-001 | P1 | guard bypass | abc1234 | reverted the guard; TestGuard went red | design phase missed it |
EOF
  # ⬇ THE LANGUAGE-SHAPED HALF, entirely from the pack — nothing below this comment
  # knows what language the fixture is written in.
  printf "$HARNESS_FIX_GOOD" > "$FX/src/$HARNESS_FIX_SRC_NAME"
  printf "$HARNESS_FIX_TEST" > "$FX/tests/$HARNESS_FIX_TEST_NAME"
}

run_gate() { ( cd "$FX" && bash "$HERE/$1" >/dev/null 2>&1 ); echo $?; }

# check <gate-script> <label> <plant-fn>
check() {
  local script="$1" label="$2" plant="$3"
  local short="${label}"
  [ -n "$ONLY" ] && case "$script" in *"$ONLY"*) ;; *) return ;; esac

  build_fixture

  local rc_clean rc_planted rc_restored
  rc_clean="$(run_gate "$script")"
  cp -R "$FX" "$FX.bak"
  "$plant"
  rc_planted="$(run_gate "$script")"
  rm -rf "$FX"; mv "$FX.bak" "$FX"
  rc_restored="$(run_gate "$script")"

  local ok=1 why=""
  [ "$rc_clean"    = "0" ] || { ok=0; why="$why clean-run-exited-$rc_clean(false-positive);"; }
  [ "$rc_planted"  = "1" ] || { ok=0; why="$why planted-exited-$rc_planted(BLIND);"; }
  [ "$rc_restored" = "0" ] || { ok=0; why="$why restore-exited-$rc_restored;"; }

  if [ "$ok" = "1" ]; then
    printf '  %s✓%s %-20s clean=0 planted=1 restored=0  %s%s%s\n' "$G" "$Z" "$short" "$D" "$label" "$Z"
    PASS=$((PASS + 1))
  else
    printf '  %s✗%s %-20s %s\n' "$R" "$Z" "$short" "$why"
    FAIL=$((FAIL + 1)); FAILED_GATES="$FAILED_GATES $short"
  fi
  rm -rf "$FX" "$FX.bak"
}

# ── the plants: one per gate, each the exact thing the gate claims to catch ──
plant_doc_links()   { printf '\nSee [the missing one](nope-does-not-exist.md).\n' >> "$FX/docs/ONBOARDING.md"; }
plant_doc_paths()   { printf '\nThe handler lives in `src/nope-does-not-exist.%s` today.\n' "$FIX_EXT" >> "$FX/docs/ONBOARDING.md"; }
plant_doc_index()   { printf '# Orphan\nNot registered anywhere.\n' > "$FX/docs/orphan.md"; }
plant_markers()     { printf "$HARNESS_FIX_MARKER" > "$FX/src/helper.$FIX_EXT"; }
plant_bug_evidence(){ printf '| BUG-003 | P1 | another | def5678 | | |\n' >> "$FX/docs/tickets/bug-register.md"; }
plant_cond_skips()  { printf "$HARNESS_FIX_SKIP" >> "$FX/tests/$HARNESS_FIX_TEST_NAME"; }
plant_citations()   { printf "$HARNESS_FIX_UNCITED" > "$FX/src/undocumented.$FIX_EXT"; }
# The log-hygiene plant is a SOURCE SNIPPET IN THE PACK, never a live log call in this file: the
# gate scans the harness's own scripts, so a real one here would make the suite flag itself. (It
# did, once — the fix was to annotate the line; the fix now is that the line lives in a .conf.)
plant_log_hygiene() { printf "$HARNESS_FIX_LOG" >> "$FX/src/$HARNESS_FIX_SRC_NAME"; }

# ── --all-stacks: prove the MECHANISM, not just one language ─────────────────
# Re-invokes this script once per shipped pack. This is what makes the language-neutrality claim
# checkable rather than aspirational: if a gate can only see Go, exactly one row below goes red.
if [ "$ALL_STACKS" -eq 1 ]; then
  rc=0
  for pk in "$HERE"/stacks/*.conf; do
    nm="$(basename "$pk" .conf)"
    printf '%s══ stack: %s ══%s\n' "$B" "$nm" "$Z"
    bash "$0" --stack "$nm" ${ONLY:+"$ONLY"} || rc=1
    printf '\n'
  done
  if [ "$rc" -ne 0 ]; then
    printf '%sAt least one stack pack failed.%s A pack that cannot pass the self-test describes a\n' "$R" "$Z"
    printf 'language the gates cannot actually see — fix the pack, or stop claiming the language.\n'
    exit 1
  fi
  printf '%severy shipped stack pack verified%s — the gates see declarations, comments, skips and\n' "$G" "$Z"
  printf 'log calls in each of them, not just in whichever language this kit was written in.\n'
  exit 0
fi

printf '%s══ harness self-test ══%s  every gate must FAIL on its own violation\n' "$B" "$Z"
printf '   stack: %s%s%s (scripts/stacks/%s.conf) — the fixture is written in THIS language\n\n' "$B" "$STACK" "$Z" "$STACK"

# The shared file predicates run FIRST, because they decide what every gate below
# SKIPS. The checks after this one prove a gate fires on a violation it can see;
# nothing there would notice a predicate that had quietly moved violations out of
# view — an over-broad exclusion makes a gate greener and quieter at once, which
# is the one failure shape this suite is otherwise blind to.
if [ -f "$HERE/predicates-test.sh" ]; then
  if bash "$HERE/predicates-test.sh" >/dev/null 2>&1; then
    printf '  %s✓%s predicates          file-exclusion matrix (skip-scope is not over-broad)\n' "$G" "$Z"
  else
    printf '  %s✗%s predicates          file-exclusion matrix FAILED — run scripts/predicates-test.sh\n' "$R" "$Z"
    FAIL=$((FAIL + 1)); FAILED_GATES="$FAILED_GATES predicates"
  fi
fi

# init's install layout, end to end: init into a copy of the kit with THIS stack, remove the kit
# originals as init advises, and the doc gates must still pass. The per-gate checks below build their
# own fixture, so none of them could see a copied doc that cites a kit-layout path (the first real
# install found 11). Only the kit has originals to remove; an installed project reports a SKIP.
if [ -f "$HERE/init-test.sh" ] && { [ -z "$ONLY" ] || case "init-test.sh" in *"$ONLY"*) true ;; *) false ;; esac; }; then
  bash "$HERE/init-test.sh" "$STACK" >/dev/null 2>&1; rc_init=$?
  case "$rc_init" in
    0) printf '  %s✓%s init-layout         init + remove the kit originals → doc gates still pass\n' "$G" "$Z"
       PASS=$((PASS + 1)) ;;
    4) printf '  %s-%s init-layout         SKIP — not the kit (no originals to remove): unexercised, NOT a pass\n' "$Y" "$Z" ;;
    *) printf '  %s✗%s init-layout         FAILED (exit %s) — run scripts/init-test.sh %s\n' "$R" "$Z" "$rc_init" "$STACK"
       FAIL=$((FAIL + 1)); FAILED_GATES="$FAILED_GATES init-layout" ;;
  esac
fi

check check-doc-links.sh        "doc-links"         plant_doc_links
check check-doc-paths.sh        "doc-paths"         plant_doc_paths
check check-doc-index.sh        "doc-index"         plant_doc_index
check check-markers.sh          "markers"           plant_markers
check check-bug-evidence.sh     "bug-evidence"      plant_bug_evidence
check check-conditional-skips.sh "conditional-skips" plant_cond_skips
check check-citations.sh        "citations"         plant_citations
check check-log-hygiene.sh      "log-hygiene"       plant_log_hygiene

printf '\n'
if [ "$FAIL" -gt 0 ]; then
  printf '%s%d gate(s) did not behave as claimed:%s%s\n' "$R" "$FAIL" "$FAILED_GATES" "$Z"
  printf 'A gate marked BLIND cannot see the thing it exists to catch. Fix it before trusting any run.\n'
  exit 1
fi
printf '%sall %d gates verified%s — each passes clean, fails on its plant, and recovers.\n' "$G" "$PASS" "$Z"
