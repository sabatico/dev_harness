#!/usr/bin/env bash
# check-doc-links.sh — every markdown link in a doc must resolve on disk.
#
# WHY: a doc pointing at a file that does not exist is a FACT ERROR, not a typo.
# Everything written downstream of it inherits a false premise. In practice this is
# the single highest-yield gate in the whole harness, because the most common defect
# in agent-written documentation is a confidently invented filename — one that reads
# exactly like a real one, because recall and reading feel identical from the inside.
#
# This gate is BLOCKING and runs on every write (see hook-fast-gates.sh). Two seconds
# at write time beats forty minutes of reasoning built on a dead pointer.

GATE_NAME="doc-links"
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

harness_need_config
harness_need_var HARNESS_DOC_DIRS "which directories hold your docs"

gate_head

scanned=0
targets=0

# Optionally restrict to specific files (used by the write-time hook).
if [ "$#" -gt 0 ]; then
  file_list() { printf '%s\n' "$@"; }
  set -- "$@"
else
  file_list() { harness_doc_files; }
fi

while IFS= read -r doc; do
  [ -f "$doc" ] || continue
  case "$doc" in *.md) ;; *) continue ;; esac
  scanned=$((scanned + 1))
  docdir="$(dirname "$doc")"

  # Pull [text](target) links. -o gives one per line; strip to the target.
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    target="${link#*](}"
    target="${target%)}"

    # Skip anything that is not a filesystem path.
    case "$target" in
      http://*|https://*|mailto:*|tel:*|"#"*|"<"*) continue ;;
      "") continue ;;
    esac

    # Drop a trailing #anchor and any title text after a space.
    target="${target%%#*}"
    target="${target%% *}"
    [ -n "$target" ] || continue

    # Resolve: absolute-from-repo-root if it starts with /, else relative to the doc.
    case "$target" in
      /*) resolved="$REPO_ROOT$target" ;;
      *)  resolved="$docdir/$target" ;;
    esac

    targets=$((targets + 1))
    if [ ! -e "$resolved" ]; then
      rel="${doc#$REPO_ROOT/}"
      lineno="$(grep -n -F "]($target" "$doc" 2>/dev/null | head -1 | cut -d: -f1)"
      gate_violation "$rel" "${lineno:--}" "link target does not exist: $target"
    fi
  done < <(grep -o '\][(][^)]*[)]' "$doc" 2>/dev/null)

done < <(file_list "$@")

if [ "$scanned" -eq 0 ]; then
  gate_incomplete "no markdown files found under: $HARNESS_DOC_DIRS"
fi

gate_finish "$targets link target(s) across $scanned doc(s)"
