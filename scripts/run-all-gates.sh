#!/usr/bin/env bash
# run-all-gates.sh — THE LOCAL CI. Run before every push.
#
# WHY IT IS LOCAL: hosted CI is optional; this is not. A gate that only runs on a
# service you might not be paying for, on a branch you might not have pushed, is a
# gate you cannot rely on at the moment you need it. "All gates green" should mean
# something you can run right now, offline, in seconds.
#
# ── TIERS ─────────────────────────────────────────────────────────────────────
#   (default)    the drift + hygiene gates          — seconds, ALWAYS run these
#   --full       + your test and coverage commands  — minutes
#   --lint       + your linter
#   --all        everything
#
# ── TWO RULES THAT MAKE THE OUTPUT TRUSTWORTHY ────────────────────────────────
#
# 1. A SKIPPED GATE IS NOT A PASS. Every gate that could not run is listed loudly at
#    the end, and the run reports INCOMPLETE. The whole point of the harness is that
#    "nothing was checked" must never render as "nothing was wrong".
#
# 2. EVERY GATE'S OUTPUT IS CAPTURED to its own file. This exists because a real
#    failure was once reported and then could never be diagnosed: the only copy of
#    the output had gone through a `| tail -4` and was gone. A gate whose failure
#    cannot be read can only be believed or ignored — and "ignored" is how a genuine
#    red gets waved through as "that flaky one again".

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE_NAME="run-all-gates"
. "$HERE/lib/common.sh"
. "$HERE/lib/manifest.sh"

WANT_FULL=0; WANT_LINT=0
for a in "$@"; do
  case "$a" in
    --full) WANT_FULL=1 ;;
    --lint) WANT_LINT=1 ;;
    --all)  WANT_FULL=1; WANT_LINT=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
  esac
done

OUT_DIR="${TMPDIR:-/tmp}/harness-gates-$$"
mkdir -p "$OUT_DIR"
manifest_init "$OUT_DIR"

printf '%s══ local gates ══%s  output: %s\n\n' "$C_B" "$C_0" "$OUT_DIR"

run_gate() {
  # run_gate <name> <script> [args...]
  local name="$1"; shift
  local script="$1"; shift
  local log="$OUT_DIR/$name.log"

  if [ ! -x "$script" ] && [ ! -f "$script" ]; then
    record "$name" skipped "gate script not found: $script" "$name.log"
    printf '  %-22s %sSKIP%s  script missing\n' "$name" "$C_YEL" "$C_0"
    return
  fi

  bash "$script" "$@" > "$log" 2>&1
  local rc=$?

  case "$rc" in
    0) printf '  %-22s %sPASS%s\n' "$name" "$C_GRN" "$C_0"
       record "$name" ok "$(tail -1 "$log" | sed 's/^[[:space:]]*//')" "$name.log" ;;
    3) printf '  %-22s %sINCOMPLETE%s  %s\n' "$name" "$C_YEL" "$C_0" "$(grep -m1 INCOMPLETE "$log" | sed 's/.*INCOMPLETE//;s/^[[:space:]]*//')"
       record "$name" error "could not run — see $name.log" "$name.log" ;;
    *) printf '  %-22s %sFAIL%s\n' "$name" "$C_RED" "$C_0"
       sed 's/^/      /' "$log" | grep -E 'FAIL|violation' | head -12
       record "$name" findings "$(grep -c 'FAIL' "$log" | tr -d ' ') violation(s) — see $name.log" "$name.log" ;;
  esac
}

run_cmd() {
  # run_cmd <name> <command-string>
  local name="$1" cmd="$2"
  local log="$OUT_DIR/$name.log"
  if [ -z "$cmd" ]; then
    printf '  %-22s %sNOT RUN%s  (not configured in harness.conf)\n' "$name" "$C_YEL" "$C_0"
    record "$name" skipped "no command configured — this is a GAP, not a pass" "-"
    return
  fi
  ( cd "$REPO_ROOT" && eval "$cmd" ) > "$log" 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '  %-22s %sPASS%s\n' "$name" "$C_GRN" "$C_0"
    record "$name" ok "exit 0" "$name.log"
  else
    printf '  %-22s %sFAIL%s  (exit %d)\n' "$name" "$C_RED" "$C_0" "$rc"
    tail -15 "$log" | sed 's/^/      /'
    record "$name" findings "exit $rc — see $name.log" "$name.log"
  fi
}

# ── fast tier ─────────────────────────────────────────────────────────────────
printf '%sfast tier%s\n' "$C_B" "$C_0"
manifest_expect doc-links doc-paths doc-index markers bug-evidence conditional-skips citations log-hygiene

run_gate doc-links         "$HERE/check-doc-links.sh"
run_gate doc-paths         "$HERE/check-doc-paths.sh"
run_gate doc-index         "$HERE/check-doc-index.sh"
run_gate markers           "$HERE/check-markers.sh"
run_gate bug-evidence      "$HERE/check-bug-evidence.sh"
run_gate conditional-skips "$HERE/check-conditional-skips.sh"
run_gate citations         "$HERE/check-citations.sh"
run_gate log-hygiene       "$HERE/check-log-hygiene.sh"

# ── suites ────────────────────────────────────────────────────────────────────
if [ "$WANT_FULL" -eq 1 ]; then
  printf '\n%ssuites%s\n' "$C_B" "$C_0"
  manifest_expect tests coverage
  run_cmd tests    "$HARNESS_TEST_CMD"
  run_cmd coverage "$HARNESS_COVERAGE_CMD"
else
  printf '\n  %-22s %sNOT RUN%s  (pass --full)\n' "tests" "$C_DIM" "$C_0"
fi

if [ "$WANT_LINT" -eq 1 ]; then
  printf '\n%slint%s\n' "$C_B" "$C_0"
  manifest_expect lint
  run_cmd lint "$HARNESS_LINT_CMD"
fi

# ── verdict ───────────────────────────────────────────────────────────────────
manifest_verdict
verdict_rc=$?

fails="$(awk -F'\t' 'NR>1 && $2=="findings"' "$MANIFEST_FILE" | wc -l | tr -d ' ')"

printf '\nfull output: %s\n' "$OUT_DIR"

if [ "$verdict_rc" -ne 0 ]; then
  printf '%sDo not push.%s A gate could not run, so this run proves less than it appears to.\n' "$C_YEL" "$C_0"
  exit 3
fi
if [ "$fails" -gt 0 ]; then
  printf '%sDo not push.%s %s gate(s) found violations.\n' "$C_RED" "$C_0" "$fails"
  exit 1
fi
printf '%sAll gates green.%s\n' "$C_GRN" "$C_0"
exit 0
