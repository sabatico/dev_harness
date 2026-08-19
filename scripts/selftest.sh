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
#   scripts/selftest.sh          # all gates
#   scripts/selftest.sh markers  # one gate

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ONLY="${1:-}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; B=$'\033[1m'; Z=$'\033[0m'
else R=""; G=""; Y=""; D=""; B=""; Z=""; fi

PASS=0; FAIL=0; FAILED_GATES=""

# ── the fixture: a minimal, fully COMPLIANT project ──────────────────────────
build_fixture() {
  FX="$(mktemp -d)"
  mkdir -p "$FX/docs/tickets" "$FX/src" "$FX/tests"
  ( cd "$FX" && git init -q . && git config user.email t@example.com && git config user.name t )

  cat > "$FX/harness.conf" <<'CONF'
HARNESS_DOC_DIRS="docs"
HARNESS_DOC_INDEX="docs/documentation-index.md"
HARNESS_CODE_DIRS="src tests"
HARNESS_CODE_EXTS="go"
HARNESS_DECISION_DIR="docs/adr"
HARNESS_DECISION_PREFIX="ADR"
HARNESS_BUG_REGISTER="docs/tickets/bug-register.md"
HARNESS_MARKERS="DEFERRED-TEST:docs/deferred-test-registry.md"
HARNESS_SECRET_TERMS="password token secret"
HARNESS_LOG_FUNCS="log print"
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
State lives here. Source is in `src/app.go`.
See the [bug register](tickets/bug-register.md).
EOF
  cat > "$FX/docs/deferred-test-registry.md" <<'EOF'
# Deferred tests
| Code site | Owed | Unblock |
|---|---|---|
| `src/app.go` | provider round-trip | provider lands |
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
  cat > "$FX/src/app.go" <<'EOF'
package app

// Guard rejects empty input so callers cannot construct an unnamed record.
// ADR-001 §3 — we fail closed rather than defaulting, because a default here is unauditable.
func Guard(s string) bool {
	// DEFERRED-TEST: provider round-trip
	return s != ""
}
EOF
  cat > "$FX/tests/app_test.go" <<'EOF'
package app

// TestGuard pins the ADR-001 §3 fail-closed behaviour.
func TestGuard(t *testing.T) {
	if !Guard("x") {
		t.Fatal("expected true")
	}
}
EOF
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
plant_doc_paths()   { printf '\nThe handler lives in `src/nope-does-not-exist.go` today.\n' >> "$FX/docs/ONBOARDING.md"; }
plant_doc_index()   { printf '# Orphan\nNot registered anywhere.\n' > "$FX/docs/orphan.md"; }
plant_markers()     { printf 'package app\n\n// Helper does a thing.\n// ADR-001 §3 — why.\nfunc Helper() {\n\t// DEFERRED-TEST: unregistered\n}\n' > "$FX/src/helper.go"; }
plant_bug_evidence(){ printf '| BUG-003 | P1 | another | def5678 | | |\n' >> "$FX/docs/tickets/bug-register.md"; }
plant_cond_skips()  { printf '\nfunc TestSetup(t *testing.T) {\n\tdb, err := open()\n\tif err != nil {\n\t\tt.Skip("no db")\n\t}\n\t_ = db\n}\n' >> "$FX/tests/app_test.go"; }
plant_citations()   { printf 'package app\n\nfunc Undocumented(x int) int {\n\treturn x * 2\n}\n' > "$FX/src/undocumented.go"; }
# The annotation must sit on the OFFENDING LINE, not above it — the gate reads one line at a time.
# This is the plant STRING for log-hygiene's own self-test, not a log call. Annotating rather than
# weakening the gate is the point: the exception stays visible and greppable, and the gate stays
# sharp enough to have caught this line in the first place (it did).
plant_log_hygiene() { printf '\n// Login logs the attempt.\n// ADR-001 §3 — why.\nfunc Login(password string) {\n\tlog.Printf("attempt with password=%%s", password)\n}\n' >> "$FX/src/app.go"; } # harness:allow-log self-test fixture

printf '%s══ harness self-test ══%s  every gate must FAIL on its own violation\n\n' "$B" "$Z"

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
