#!/usr/bin/env bash
# manifest.sh — the honest-reporting library. Source it from any multi-stage job.
#
# ── THE PROBLEM THIS SOLVES, STATED PLAINLY ───────────────────────────────────
#
# A scanner pointed at the wrong address reports zero findings.
# A test suite that skipped every case prints `ok`.
# A stage that crashed before starting produces an empty, clean-looking report.
#
# In all three the output is INDISTINGUISHABLE from a genuinely clean result, and
# it is indistinguishable in the reassuring direction. This is not a hypothetical:
# a nightly security run once scored PASS for days on scanners that were pointed at
# their own loopback address and never touched the application.
#
# You cannot fix this by reading the findings more carefully. The findings are
# correct — there really were zero. The missing information is whether anything was
# ever LOOKED AT, and only the job itself can record that.
#
# ── THE PATTERN ───────────────────────────────────────────────────────────────
#
#   1. Every stage calls record() with what it ACTUALLY did.
#   2. The manifest — not the tool output — is the run's record of truth.
#   3. The run ends in a VERDICT: COMPLETE or INCOMPLETE.
#   4. INCOMPLETE means a stage never reached its target. It is NOT a clean bill of
#      health no matter how few findings it produced, and the report must say so
#      FIRST, before any findings.
#
# ── USAGE ─────────────────────────────────────────────────────────────────────
#
#   . "$HARNESS_DIR/scripts/lib/manifest.sh"
#   manifest_init "$REPORT_DIR"
#
#   run_scanner_a > "$REPORT_DIR/a.txt" 2>&1
#   record scanner-a "$(status_from_exit $?)" "scanned 412 files" a.txt
#
#   record scanner-b unreachable "target refused connection — NOTHING was scanned" b.txt
#
#   manifest_verdict     # prints the table + verdict, exits 0 COMPLETE / 3 INCOMPLETE
#
# ── STATUS VOCABULARY ─────────────────────────────────────────────────────────
#
#   ok           the stage ran against a real target and found nothing wrong
#   findings     the stage ran against a real target and found something to triage
#   unreachable  the stage ran but never reached its target  → INCOMPLETE
#   error        the stage broke                             → INCOMPLETE
#   skipped      honestly not applicable, or a missing tool  → NOT a pass; named in the report
#
# `skipped` deliberately does NOT force INCOMPLETE — some stages are legitimately
# N/A (a TLS check against a plain-HTTP target). But it is never counted as a pass,
# and manifest_verdict lists every skip so the report must account for it.

MANIFEST_DIR=""
MANIFEST_FILE=""

manifest_init() {
  MANIFEST_DIR="$1"
  mkdir -p "$MANIFEST_DIR"
  MANIFEST_FILE="$MANIFEST_DIR/RUN-MANIFEST.tsv"
  printf 'stage\tstatus\tdetail\tevidence\n' > "$MANIFEST_FILE"
}

# Map an exit code to a status using the harness vocabulary (see lib/common.sh).
status_from_exit() {
  case "$1" in
    0) printf 'ok' ;;
    1) printf 'findings' ;;
    3) printf 'error' ;;
    4) printf 'skipped' ;;
    *) printf 'error' ;;
  esac
}

record() {
  # record <stage> <status> <detail> [evidence-file]
  [ -n "$MANIFEST_FILE" ] || { echo "manifest_init was never called" >&2; return 1; }
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${3:-}" "${4:--}" >> "$MANIFEST_FILE"
}

# Guard against the subtlest failure of all: a stage block that calls record() ZERO
# times. Its absence is invisible, and the verdict silently becomes a constant.
# Declare up front what MUST appear, and the verdict fails if any is missing.
MANIFEST_EXPECTED=""
manifest_expect() { MANIFEST_EXPECTED="$MANIFEST_EXPECTED $*"; }

manifest_verdict() {
  local bad=0 skipped=0 missing=0 st stage want

  printf '\n──── run manifest (%s) ────\n' "$MANIFEST_FILE"
  awk -F'\t' 'NR>1 { printf "  %-26s %-12s %s\n", $1, $2, $3 }' "$MANIFEST_FILE"

  # Any stage that never reached its target?
  while IFS=$'\t' read -r stage st _detail _ev; do
    case "$st" in
      unreachable|error) bad=$((bad + 1)) ;;
      skipped)           skipped=$((skipped + 1)) ;;
    esac
  done < <(tail -n +2 "$MANIFEST_FILE")

  # Any EXPECTED stage that never recorded anything at all?
  for want in $MANIFEST_EXPECTED; do
    if ! awk -F'\t' -v w="$want" 'NR>1 && $1==w {found=1} END{exit !found}' "$MANIFEST_FILE"; then
      printf '  %-26s %-12s %s\n' "$want" "MISSING" "declared but never recorded a result"
      missing=$((missing + 1))
    fi
  done

  printf '\n'
  if [ "$bad" -gt 0 ] || [ "$missing" -gt 0 ]; then
    printf 'VERDICT: INCOMPLETE — %d stage(s) never reached a real target.\n' "$((bad + missing))"
    printf 'This is NOT a clean result. Report the gap BEFORE any findings, and do\n'
    printf 'not describe this run as clean or green.\n'
    return 3
  fi

  if [ "$skipped" -gt 0 ]; then
    printf 'VERDICT: COMPLETE — every expected stage reached a real target.\n'
    printf 'NOTE: %d stage(s) skipped. A skip is an honest non-result, not a pass —\n' "$skipped"
    printf 'name what went uncovered in the report.\n'
    return 0
  fi

  printf 'VERDICT: COMPLETE — every expected stage reached a real target.\n'
  return 0
}
