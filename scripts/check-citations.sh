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
harness_need_var HARNESS_CODE_EXTS       "which file extensions are source"
harness_need_var HARNESS_DECISION_PREFIX "the decision-record prefix, e.g. ADR"

MODE="changed"
case "${1:-}" in
  --all)     MODE="all" ;;
  --measure) MODE="measure" ;;
esac

gate_head

# What a declaration, a comment and a test file LOOK LIKE are properties of your language, not of
# this gate — they come from the stack pack (stacks/<HARNESS_STACK>.conf, overridable in
# harness.conf). With the generic union you get a loose match that misses receiver methods and
# arrow functions; that looseness is why adopting a pack is a first-act job, not a nicety.
DECL_RE="$HARNESS_DECL_RE"
STRIP_RE="$HARNESS_DECL_STRIP_RE"
# ⚠ EXPORTED, and read in awk via ENVIRON rather than -v: `awk -v re='\*'` performs escape
# processing on the value, so the backslash is eaten and awk sees a bare `*` — "illegal primary in
# regular expression". It fails loudly here, but the same trap silently empties a pattern in
# gates that tolerate a bad regex.
COMMENT_RE="$HARNESS_COMMENT_RE"
export COMMENT_RE
CITE_RE="${HARNESS_DECISION_PREFIX}-[0-9]+"

target_files() {
  if [ "$MODE" = "changed" ]; then
    # Filter by BOTH directory and extension. --all mode goes through
    # harness_code_files, which honours HARNESS_CODE_EXTS; changed mode used to
    # filter on directory alone, so the two modes disagreed about what counts as
    # source and `--all` was the more accurate of the two. A gate whose scope
    # depends on which flag you passed is a gate nobody can reason about.
    harness_changed_files | sort -u | while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      [ -f "$REPO_ROOT/$rel" ] || continue
      in_dir=1
      for d in $HARNESS_CODE_DIRS; do
        case "$rel" in "$d"/*) in_dir=0; break ;; esac
      done
      [ "$in_dir" -eq 0 ] || continue
      for e in $HARNESS_CODE_EXTS; do
        case "$rel" in *."$e") printf '%s\n' "$REPO_ROOT/$rel"; break ;; esac
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
exempted=0

while IFS= read -r f; do
  [ -f "$f" ] || continue
  # Test files and vendored/generated code are not ours to cite. Both questions
  # are answered ONCE, in lib/common.sh — three gates used to answer them
  # separately and disagreed, which is how a Python repo ended up with every test
  # function reported as an uncited declaration.
  harness_is_test_file "$f" && continue
  harness_is_vendored  "$f" && continue
  rel="${f#$REPO_ROOT/}"

  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    lineno="${hit%%:*}"
    decl="${hit#*:}"
    total=$((total + 1))

    fname="$(printf '%s' "$decl" | sed -E "$STRIP_RE" | sed -E 's/[^A-Za-z0-9_$].*$//')"

    # ── find the function's doc block ─────────────────────────────────────────
    # WHERE it lives is a language fact, not a gate fact. C-family puts a comment block ABOVE the
    # declaration; Python-family puts a docstring on the line AFTER it. HARNESS_DOC_BELOW (stack
    # pack) picks the direction, HARNESS_COMMENT_RE says what a comment line looks like. Hardcoding
    # "above" made this gate report every Python function as undocumented — uniform, confident, and
    # wrong, which is how a gate gets muted in week one instead of fixed.
    if [ "${HARNESS_DOC_BELOW:-0}" -eq 1 ]; then
      # Downward: the first non-blank line after the declaration must be a doc line; take the
      # contiguous run from there. A multi-line signature reads as "no doc" — conservative in the
      # loud direction, which is the right way for a gate to be wrong.
      to=$((lineno + 12))
      # A doc block below a declaration comes in two shapes and BOTH must work, or the gate is
      # wrong for half the projects that set DOC_BELOW:
      #   · a delimited block   — `"""…` spanning lines, blank lines included, to its closing mark
      #   · a contiguous run    — `#` comment lines, one after another
      # Stopping at the first blank line (the obvious implementation) truncates a docstring to its
      # summary line, so a citation on line 3 of the docstring reads as absent. That is a false
      # POSITIVE, which costs more than a miss: it trains people to mute the gate.
      block="$(sed -n "$((lineno + 1)),${to}p" "$f" 2>/dev/null | awk '
        BEGIN { re = ENVIRON["COMMENT_RE"] }
        {
          l = $0; sub(/^[[:space:]]+/, "", l)
          if (!started) {
            if (l == "") next
            if (l !~ re) exit
            started = 1
            if (match(l, /^[rfbu]*"""/))            delim = "\"\"\""
            else if (match(l, /^[rfbu]*\047\047\047/)) delim = "\047\047\047"
            print
            if (delim != "") {
              rest = substr(l, RSTART + RLENGTH)
              if (index(rest, delim) > 0) exit      # opened and closed on one line
              indoc = 1
            }
            next
          }
          if (indoc) { print; if (index($0, delim) > 0) exit; next }
          if (l ~ re) { print; next }
          exit
        }')"
    else
      from=$((lineno - 12)); [ "$from" -lt 1 ] && from=1
      above="$(sed -n "${from},$((lineno - 1))p" "$f" 2>/dev/null)"
      # Keep only the contiguous comment run immediately preceding the declaration.
      block="$(printf '%s\n' "$above" | awk '
        BEGIN { re = ENVIRON["COMMENT_RE"] }
        { lines[NR] = $0 }
        END {
          for (i = NR; i >= 1; i--) {
            l = lines[i]
            sub(/^[[:space:]]+/, "", l)
            if (l ~ re || (l ~ /^$/ && started)) { out = l "\n" out; started = 1 }
            else if (l == "") { break }
            else break
          }
          printf "%s", out
        }')"
    fi

    # An inline, REASONED exemption, mirroring `harness:allow-log`. It exists for
    # code that is in a source file but is not ours to govern — a vendor analytics
    # snippet inline in a template, say. The alternative people reach for is
    # inventing a decision-record reference that does not govern the code, which
    # is worse than a gap: it is a false pointer, and this gate's own honest limit
    # is that it cannot tell a real citation from a plausible one.
    # Accept the annotation on the declaration line itself OR in the comment block
    # above it. Same-line is how `harness:allow-log` already works, and it is the
    # only form that reaches a declaration with no contiguous comment run above it
    # — e.g. a vendor snippet wedged between two statements inside a <script>.
    if printf '%s\n%s' "$decl" "$block" | grep -q "harness:allow-uncited"; then
      exempted=$((exempted + 1))
      continue
    fi

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
      gate_violation "$rel" "$lineno" "$fname() has no doc comment — say WHY it exists and cite its ${HARNESS_DECISION_PREFIX}, or annotate 'harness:allow-uncited <reason>'"
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
  printf '  exempted:         %d\n' "$exempted"
  printf '\n  Measure BEFORE you enforce. A rule with no baseline is a wish.\n'
  exit 0
fi

if [ "$total" -eq 0 ]; then
  gate_note "no changed source files with function declarations — nothing to check"
fi

gate_finish "$total function(s) in changed files"
