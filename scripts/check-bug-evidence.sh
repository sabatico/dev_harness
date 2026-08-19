#!/usr/bin/env bash
# check-bug-evidence.sh — a bug marked CLOSED must name its evidence.
#
# WHY: "fixed" is a claim. The only thing that makes it a result is a demonstration that the defect
# could be reproduced and now cannot. Without that, a closed bug is indistinguishable from a bug that
# MOVED — and a disappearing symptom is not a diagnosis.
#
# So a closed row must carry two things:
#   (a) a TEST reference   — a token containing "test" or "spec"
#   (b) an EVIDENCE phrase — mutation / reverted / reproduced / went red / verified red
#
# ── FORMAT-FLEXIBLE (two shapes, auto-detected) ──────────────────────────────
#
#   TABLE  — a "## Closed" section whose rows are `| ID | ... |` (this kit's template).
#            Give it a "Verified by (the test that went RED)" column.
#   SECTION— `### BUG-NNN — title` blocks carrying a status line.
#
# If neither shape is found the gate exits 3 (INCOMPLETE) rather than 0, because a register it cannot
# parse is a register it did not check. Adapt the patterns below to your own format if you use a third.
#
# HONEST LIMIT (gates.md G5): this proves the claim was made in a falsifiable FORM. It cannot prove the
# named test is the right one, or that it ever actually went red. Green means "stated", not "true".

GATE_NAME="bug-evidence"
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

harness_need_config
harness_need_var HARNESS_BUG_REGISTER "the bug register"

REG="$REPO_ROOT/$HARNESS_BUG_REGISTER"
[ -f "$REG" ] || gate_incomplete "bug register not found: $HARNESS_BUG_REGISTER"

gate_head

ID_RE='^\|[[:space:]]*[A-Z][A-Z]*-[0-9][0-9]*[[:space:]]*\|'
TEST_RE='[Tt]est|[Ss]pec|_test|\.test'
EVID_RE='[Mm]utation|[Rr]everted|[Rr]eproduc|went red|[Ww]ent RED|verified red|saw red|RED'

closed=0
checked=0
shape="none"

# ── shape 1: a "Closed" section with table rows ──────────────────────────────
closed_start="$(grep -nE '^#{1,3}[[:space:]].*[Cc]losed' "$REG" 2>/dev/null | head -1 | cut -d: -f1)"

if [ -n "$closed_start" ]; then
  shape="table"
  # End at the next heading of any level after the closed heading.
  rest_start=$((closed_start + 1))
  next_head="$(tail -n +"$rest_start" "$REG" | grep -nE '^#{1,3}[[:space:]]' | head -1 | cut -d: -f1)"
  if [ -n "$next_head" ]; then
    closed_end=$((closed_start + next_head - 1))
  else
    closed_end="$(wc -l < "$REG" | tr -d ' ')"
  fi

  while IFS= read -r numbered; do
    [ -n "$numbered" ] || continue
    lineno="${numbered%%:*}"
    row="${numbered#*:}"

    # Skip the header, the separator, and the placeholder row.
    case "$row" in
      *'---'*) continue ;;
      *'| — |'*|*'| - |'*) continue ;;
    esac
    printf '%s' "$row" | grep -qE "$ID_RE" || continue

    closed=$((closed + 1)); checked=$((checked + 1))
    id="$(printf '%s' "$row" | sed -E 's/^\|[[:space:]]*//; s/[[:space:]]*\|.*$//')"

    printf '%s' "$row" | grep -qE "$TEST_RE" || \
      gate_violation "$HARNESS_BUG_REGISTER" "$lineno" "$id closed with no test named (Verified-by column)"
    printf '%s' "$row" | grep -qE "$EVID_RE" || \
      gate_violation "$HARNESS_BUG_REGISTER" "$lineno" "$id closed with no reproduction evidence (mutation / reverted / went red)"
  done < <(sed -n "${closed_start},${closed_end}p" "$REG" | grep -nE '^\|' | awk -F: -v off="$((closed_start - 1))" '{ $1 = $1 + off; print $0 }' OFS=':')
fi

# ── shape 2: "### BUG-NNN" sections ──────────────────────────────────────────
if [ "$shape" = "none" ]; then
  sections="$(grep -cE '^###[[:space:]]+[A-Z]+-[0-9]+' "$REG" 2>/dev/null || echo 0)"
  if [ "$sections" -gt 0 ]; then
    shape="section"
    tmp="${TMPDIR:-/tmp}/harness-bugsec.$$"
    awk '
      /^###[[:space:]]+[A-Z]+-[0-9]+/ { if (id != "") print id "\t" start "\t" body; id=$0; start=NR; body=""; next }
      { gsub(/\t/," "); body = body " " $0 }
      END { if (id != "") print id "\t" start "\t" body }
    ' "$REG" > "$tmp"

    while IFS=$'\t' read -r heading lineno body; do
      [ -n "$heading" ] || continue
      checked=$((checked + 1))
      case "$body$heading" in
        *CLOSED*|*Closed*|*RESOLVED*|*Resolved*|*FIXED*|*Fixed*) ;;
        *) continue ;;
      esac
      closed=$((closed + 1))
      label="$(printf '%s' "$heading" | sed 's/^###[[:space:]]*//' | cut -c1-50)"
      printf '%s' "$body" | grep -qE "$TEST_RE" || \
        gate_violation "$HARNESS_BUG_REGISTER" "$lineno" "closed bug names no test: $label"
      printf '%s' "$body" | grep -qE "$EVID_RE" || \
        gate_violation "$HARNESS_BUG_REGISTER" "$lineno" "closed bug shows no reproduction evidence: $label"
    done < "$tmp"
    rm -f "$tmp"
  fi
fi

if [ "$shape" = "none" ]; then
  gate_incomplete "could not parse $HARNESS_BUG_REGISTER — expected a '## Closed' table or '### BUG-NNN' sections"
fi

[ "$closed" -eq 0 ] && gate_note "no closed bugs yet — nothing to verify (this is a real pass, not an empty scan: the register parsed as '$shape')"

gate_finish "$closed closed bug(s), $shape format"
