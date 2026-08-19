#!/usr/bin/env bash
# check-bug-evidence.sh — a bug marked CLOSED must name its evidence.
#
# WHY: "fixed" is a claim. The only thing that makes it a result is a demonstration
# that the bug could be reproduced and now cannot. Without that, a closed bug means
# "someone changed some code and the symptom stopped appearing" — which is also what
# a bug that MOVED looks like. A disappearing symptom is not a diagnosis.
#
# The contract (see registers/bug-register.template.md):
#   Each bug is a `### BUG-NNN — title` section.
#   A closed one carries a status containing CLOSED / RESOLVED / FIXED,
#   and within the same section:
#     (a) a reference to a test  — a token containing "test" or "spec", and
#     (b) an evidence phrase     — mutation / reproduced / went red / verified red.
#
# It cannot check that the named test is the RIGHT test. Green means the claim was
# made in a falsifiable form, never that it is true.

GATE_NAME="bug-evidence"
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

harness_need_config
harness_need_var HARNESS_BUG_REGISTER "the bug register"

REG="$REPO_ROOT/$HARNESS_BUG_REGISTER"
[ -f "$REG" ] || gate_incomplete "bug register not found: $HARNESS_BUG_REGISTER"

gate_head

# Split into sections, then evaluate each closed one.
closed=0
total=0

awk '
  /^###[[:space:]]/ {
    if (id != "") print id "\t" start "\t" body
    id = $0; start = NR; body = ""
    next
  }
  { gsub(/\t/, " "); body = body " " $0 }
  END { if (id != "") print id "\t" start "\t" body }
' "$REG" > "$REPO_ROOT/.harness-bugsections.$$" 2>/dev/null

while IFS=$'\t' read -r heading lineno body; do
  [ -n "$heading" ] || continue
  total=$((total + 1))

  # Closed?
  case "$body$heading" in
    *CLOSED*|*Closed*|*RESOLVED*|*Resolved*|*FIXED*|*Fixed*) ;;
    *) continue ;;
  esac
  closed=$((closed + 1))

  has_test=0
  has_evidence=0
  case "$body" in *test*|*Test*|*spec*|*Spec*) has_test=1 ;; esac
  case "$body" in
    *mutation*|*Mutation*|*reproduced*|*Reproduced*|*"went red"*|*"Went red"*|*"verified red"*|*"saw red"*) has_evidence=1 ;;
  esac

  label="$(printf '%s' "$heading" | sed 's/^###[[:space:]]*//' | cut -c1-60)"

  if [ "$has_test" -eq 0 ]; then
    gate_violation "$HARNESS_BUG_REGISTER" "$lineno" "closed bug names no test: $label"
  fi
  if [ "$has_evidence" -eq 0 ]; then
    gate_violation "$HARNESS_BUG_REGISTER" "$lineno" "closed bug shows no reproduction evidence (mutation / reproduced / went red): $label"
  fi
done < "$REPO_ROOT/.harness-bugsections.$$"

rm -f "$REPO_ROOT/.harness-bugsections.$$"

[ "$total" -eq 0 ] && gate_incomplete "no '### BUG-...' sections found in $HARNESS_BUG_REGISTER — is the format right?"

gate_finish "$closed closed bug(s) of $total"
