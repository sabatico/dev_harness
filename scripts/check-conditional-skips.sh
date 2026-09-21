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
# ⚠ The annotation must sit on the SAME LINE as the offending call — the gate reads line by line,
# so a comment on the line above is silently ignored. (This tripped its own author.)

GATE_NAME="conditional-skips"
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

harness_need_config
harness_need_stack
harness_need_var HARNESS_CODE_DIRS "which directories hold your source"

gate_head

# WHAT A SKIP AND AN ERROR LOOK LIKE ARE LANGUAGE FACTS, not properties of this gate — they come
# from the stack pack (stacks/<HARNESS_STACK>.conf). The generic union matches many runners loosely;
# a pack matches yours exactly. This matters more here than in most gates: an over-broad ERR_RE
# turns legitimate precondition skips into noise, and a gate that cries wolf gets muted — after
# which the actual failure it exists to catch (a broken environment printing `ok`) returns silently.
SKIP_RE="$HARNESS_SKIP_RE"
ERR_RE="$HARNESS_ERROR_RE"

scanned=0
skips=0

while IFS= read -r f; do
  # This gate SELECTS test files; every other gate excludes them. Same question,
  # so it must be the same answer — it now comes from lib/common.sh. (The pattern
  # that used to live here had `*test_*` unanchored, which also matched a source
  # file called `latest_events.py`; the shared predicate anchors it to `*/test_*`.)
  harness_is_test_file "$f" || continue
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

# Scanning nothing is never a PASS (gates.md G1), and the two ways of scanning nothing are
# different facts that deserve different answers.
if [ "$scanned" -eq 0 ]; then
  harness_code_dirs_exist || gate_incomplete "no source directories exist yet: $HARNESS_CODE_DIRS"
  gate_not_applicable "no test files matched under: $HARNESS_CODE_DIRS (HARNESS_TEST_GLOBS = $HARNESS_TEST_GLOBS, stack '$HARNESS_STACK') — if you DO have tests, your globs are wrong and need fixing, not accepting"
fi

gate_finish "$skips skip call(s) across $scanned test file(s)"
