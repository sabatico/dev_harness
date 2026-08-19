#!/usr/bin/env bash
# check-citations.sh — a function you TOUCHED must cite the decision that governs it.
#
# WHY: behaviour and the reasons for it drift apart silently, and every expensive
# defect comes from that gap — a check narrowed away from the rule it implements, a
# comment claiming a guarantee the code never provided. Binding them makes the drift
# visible at the only moment anyone is looking: when the code changes.
#
# The citation must name the SECTION, not just the record number, so the next reader
# lands on the argument rather than the index.
#
# ── COMMENTS SAY WHY, NOT WHAT ────────────────────────────────────────────────
# The code already says what. The next reader is another agent with no memory of the
# session that wrote this, and WHY is the only thing they cannot recover from the
# source. A comment restating the signature is worse than none — it costs a line and
# teaches the reader that comments here are noise.
#
# RATCHETED against HARNESS_BASE_REF: only functions in files you CHANGED are
# checked, so this can land on a large existing codebase without a migration.
#
# HONEST LIMIT: no script can judge whether the cited record is RELEVANT. Green here
# means a pointer exists, never that it is the right one.
#
#   scripts/check-citations.sh              # enforce on changed files
#   scripts/check-citations.sh --all        # audit the whole tree (reporting only)
#   scripts/check-citations.sh --measure    # print the adoption rate, fail nothing

GATE_NAME="citations"
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

harness_need_config
harness_need_var HARNESS_CODE_DIRS       "which directories hold your source"
harness_need_var HARNESS_DECISION_PREFIX "the decision-record prefix, e.g. ADR"

MODE="changed"
case "${1:-}" in
  --all)     MODE="all" ;;
  --measure) MODE="measure" ;;
esac

gate_head

# Declaration shapes across the common languages. Deliberately conservative: a
# missed declaration is a quiet gap, a false one is noise that gets the gate muted.
DECL_RE='^[[:space:]]*(export[[:space:]]+)?(pub[[:space:]]+)?(async[[:space:]]+)?(func|def|fn|function)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*'
CITE_RE="${HARNESS_DECISION_PREFIX}-[0-9]+"

target_files() {
  if [ "$MODE" = "changed" ]; then
    harness_changed_files | sort -u | while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      [ -f "$REPO_ROOT/$rel" ] || continue
      for d in $HARNESS_CODE_DIRS; do
        case "$rel" in "$d"/*) printf '%s\n' "$REPO_ROOT/$rel"; break ;; esac
      done
    done
  else
    harness_code_files
  fi
}

total=0
cited=0
commented=0
bare=0

while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in
    *_test.*|*.test.*|*.spec.*|*/vendor/*|*/node_modules/*|*.pb.go|*_generated.*|*.gen.*) continue ;;
  esac
  rel="${f#$REPO_ROOT/}"

  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    lineno="${hit%%:*}"
    decl="${hit#*:}"
    total=$((total + 1))

    fname="$(printf '%s' "$decl" | sed -E 's/^[[:space:]]*(export[[:space:]]+)?(pub[[:space:]]+)?(async[[:space:]]+)?(func|def|fn|function)[[:space:]]+//' | sed -E 's/[^A-Za-z0-9_].*$//')"

    # The comment block directly above: walk up while lines look like comments.
    from=$((lineno - 12)); [ "$from" -lt 1 ] && from=1
    above="$(sed -n "${from},$((lineno - 1))p" "$f" 2>/dev/null)"
    # Keep only the contiguous comment run immediately preceding the declaration.
    block="$(printf '%s\n' "$above" | awk '
      { lines[NR] = $0 }
      END {
        for (i = NR; i >= 1; i--) {
          l = lines[i]
          sub(/^[[:space:]]+/, "", l)
          if (l ~ /^(\/\/|#|\*|\/\*|--|"""|'"'''"')/ || l ~ /^$/ && started) { out = l "\n" out; started = 1 }
          else if (l == "") { break }
          else break
        }
        printf "%s", out
      }')"

    if [ -n "$block" ]; then
      commented=$((commented + 1))
      if printf '%s' "$block" | grep -qE "$CITE_RE"; then
        cited=$((cited + 1))
        continue
      fi
      [ "$MODE" = "measure" ] && continue
      [ "$MODE" = "all" ] && continue
      gate_violation "$rel" "$lineno" "$fname() is documented but cites no ${HARNESS_DECISION_PREFIX}-NNN §section"
    else
      bare=$((bare + 1))
      [ "$MODE" = "measure" ] && continue
      [ "$MODE" = "all" ] && continue
      gate_violation "$rel" "$lineno" "$fname() has no doc comment — say WHY it exists and cite its ${HARNESS_DECISION_PREFIX}"
    fi
  done < <(grep -nE "$DECL_RE" "$f" 2>/dev/null)

done < <(target_files)

if [ "$MODE" = "measure" ] || [ "$MODE" = "all" ]; then
  if [ "$total" -eq 0 ]; then
    gate_incomplete "no function declarations matched under: $HARNESS_CODE_DIRS"
  fi
  pc() { [ "$2" -eq 0 ] && { echo 0; return; }; echo $(( $1 * 100 / $2 )); }
  printf '  functions:        %d\n' "$total"
  printf '  cite a decision:  %d (%d%%)\n' "$cited"     "$(pc "$cited" "$total")"
  printf '  commented, no ref:%d (%d%%)\n' "$((commented - cited))" "$(pc "$((commented - cited))" "$total")"
  printf '  no comment:       %d (%d%%)\n' "$bare"      "$(pc "$bare" "$total")"
  printf '\n  Measure BEFORE you enforce. A rule with no baseline is a wish.\n'
  exit 0
fi

if [ "$total" -eq 0 ]; then
  gate_note "no changed source files with function declarations — nothing to check"
fi

gate_finish "$total function(s) in changed files"
