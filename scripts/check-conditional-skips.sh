#!/usr/bin/env bash
# check-conditional-skips.sh — no test may SKIP from an error branch.
#
# WHY THIS IS WORSE THAN IT SOUNDS:
#
#   res, err := setup()
#   if err != nil {
#       t.Skip("could not set up")     // <-- the bug
#   }
#
# The test runner prints `ok` whether this test verified the system or gave up on
# it. So the suite stays green precisely WHEN THE ENVIRONMENT IS BROKEN — the exact
# moment you most needed a red. A skip is a question never asked, and this pattern
# converts every infrastructure failure into a silent absence of coverage.
#
# A skip driven by a DELIBERATE precondition ("no GPU on this host") is legitimate.
# A skip driven by something going wrong is not. The distinction is the condition.
#
# HEURISTIC, and honestly so: it looks for a skip call whose nearby enclosing
# condition mentions an error. Suppress a verified-legitimate case with a trailing
#     # harness:allow-conditional-skip
# comment on the skip line, which makes the exception visible and greppable.

GATE_NAME="conditional-skips"
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

harness_need_config
harness_need_var HARNESS_CODE_DIRS "which directories hold your source"

gate_head

SKIP_RE='(\.Skip|\.Skipf|t\.SkipNow|test\.skip|it\.skip|describe\.skip|pytest\.skip|skipTest|self\.skipTest)'
ERR_RE='(err[[:space:]]*!=[[:space:]]*nil|err[[:space:]]*==[[:space:]]*nil|!ok\b|catch|except|rescue|\berr\b|\berror\b|Exception|panic|failed|Failed)'

scanned=0
skips=0

while IFS= read -r f; do
  case "$f" in
    *_test.*|*.test.*|*.spec.*|*test_*|*/tests/*|*/test/*|*/__tests__/*) ;;
    *) continue ;;
  esac
  scanned=$((scanned + 1))
  rel="${f#$REPO_ROOT/}"

  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    lineno="${hit%%:*}"
    text="${hit#*:}"
    skips=$((skips + 1))

    case "$text" in *harness:allow-conditional-skip*) continue ;; esac

    # Look back up to 4 lines for a condition mentioning an error.
    from=$((lineno - 4)); [ "$from" -lt 1 ] && from=1
    ctx="$(sed -n "${from},${lineno}p" "$f" 2>/dev/null)"

    if printf '%s' "$ctx" | grep -qE "$ERR_RE"; then
      gate_violation "$rel" "$lineno" "test skips from an error branch — a skip here hides a broken environment as a pass"
    fi
  done < <(grep -nE "$SKIP_RE" "$f" 2>/dev/null)

done < <(harness_code_files)

if [ "$scanned" -eq 0 ]; then
  gate_note "no test files matched under: $HARNESS_CODE_DIRS (checked *_test.* *.test.* *.spec.* tests/ __tests__/)"
  gate_note "if you DO have tests, your layout is not covered — fix the pattern rather than accepting this pass"
fi

gate_finish "$skips skip call(s) across $scanned test file(s)"
