#!/usr/bin/env bash
# check-doc-paths.sh — every BARE backticked file path in a doc must exist.
#
# WHY THIS IS SEPARATE FROM check-doc-links: the link checker only ever sees
# markdown links. A path written in running prose as `src/thing/handler.go` is
# completely unguarded by it — and prose is exactly where agents cite paths most
# often. This gap was proven real by planting a fake path in prose and watching the
# whole suite stay green.
#
# RATCHETED. Existing misses are frozen in a baseline so the rule can be adopted on
# a repo that already has hundreds; only NEW ones fail.
#
#   scripts/check-doc-paths.sh --write-baseline   # freeze today's state
#   scripts/check-doc-paths.sh                    # enforce from here

GATE_NAME="doc-paths"
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

harness_need_config
harness_need_var HARNESS_DOC_DIRS "which directories hold your docs"

MODE="check"
[ "${1:-}" = "--write-baseline" ] && MODE="baseline"

gate_head

# A backticked token counts as a path claim when it contains a slash AND either has
# a file extension or ends in a slash. That deliberately excludes prose like
# `and/or`, command fragments, and URLs-without-scheme.
looks_like_path() {
  case "$1" in
    # Not a path claim at all.
    *" "*|*"("*|*")"*|http*|*"://"*) return 1 ;;
    # A PLACEHOLDER, not a real path: `/tmp/<name>.log`, `path/to/<thing>`. Flagging these
    # trains authors to stop backticking examples, which costs more than it catches.
    *"<"*|*">"*|*"«"*|*"»"*|*'${'*) return 1 ;;
    # A GLOB describes a set, not a file: `docs/sops/skill-*.md`.
    *"*"*|*"?"*|*"["*) return 1 ;;
    # An ABSOLUTE path is a claim about the machine, not about this repo. `/etc/hosts` and
    # `/tmp/gates.log` are legitimate prose and unresolvable here by design.
    /*) return 1 ;;
    */) return 0 ;;
    */*.*) return 0 ;;
    *) return 1 ;;
  esac
}

emit_claims() {
  while IFS= read -r doc; do
    [ -f "$doc" ] || continue
    rel="${doc#$REPO_ROOT/}"
    while IFS= read -r tok; do
      tok="${tok#\`}"; tok="${tok%\`}"
      [ -n "$tok" ] || continue
      looks_like_path "$tok" || continue
      printf '%s\t%s\n' "$rel" "$tok"
    done < <(grep -o '`[^`]*`' "$doc" 2>/dev/null)
  done < <(harness_doc_files)
}

# A path claim resolves if EITHER reading is true: relative to the repo root, or relative to
# the doc that wrote it. Docs legitimately use both, and a gate that only knows one flags
# correct prose — which is how a gate gets muted.
path_resolves() {
  # path_resolves <doc-rel-path> <token>
  local docdir; docdir="$(dirname "$REPO_ROOT/$1")"
  case "$2" in
    /*) [ -e "$REPO_ROOT$2" ] && return 0 ;;
    *)  [ -e "$REPO_ROOT/$2" ] && return 0
        [ -e "$docdir/$2" ]    && return 0 ;;
  esac
  return 1
}

if [ "$MODE" = "baseline" ]; then
  emit_claims | while IFS=$'\t' read -r rel tok; do
    path_resolves "$rel" "$tok" || printf '%s\t%s\n' "$rel" "$tok"
  done | harness_baseline_write "doc-paths"
  exit 0
fi

checked=0
while IFS=$'\t' read -r rel tok; do
  checked=$((checked + 1))
  path_resolves "$rel" "$tok" && continue
  harness_baseline_has "doc-paths" "$rel	$tok" && continue
  lineno="$(grep -n -F "\`$tok\`" "$REPO_ROOT/$rel" 2>/dev/null | head -1 | cut -d: -f1)"
  gate_violation "$rel" "${lineno:--}" "backticked path does not exist: $tok"
done < <(emit_claims)

if [ "$checked" -eq 0 ]; then
  gate_note "no backticked paths found — nothing to verify"
fi

gate_finish "$checked backticked path claim(s)"
