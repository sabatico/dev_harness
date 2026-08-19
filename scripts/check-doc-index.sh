#!/usr/bin/env bash
# check-doc-index.sh — every living doc must be registered in the index.
#
# WHY: undocumented docs are how a project ends up with four files that each claim
# to be the current truth. The index is not bureaucracy; it is the list of things
# that have an owner and an update trigger. A doc nobody registered is a doc nobody
# will ever update, and it will still be read.
#
# The gate is deliberately dumb: it checks that each doc's path appears SOMEWHERE in
# the index file. It cannot check that the index entry is accurate — no script can —
# so a green here means "declared", never "correct".

GATE_NAME="doc-index"
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

harness_need_config
harness_need_var HARNESS_DOC_DIRS  "which directories hold your docs"
harness_need_var HARNESS_DOC_INDEX "the index every doc registers in"

INDEX="$REPO_ROOT/$HARNESS_DOC_INDEX"
[ -f "$INDEX" ] || gate_incomplete "index not found: $HARNESS_DOC_INDEX"

gate_head

n=0
while IFS= read -r doc; do
  rel="${doc#$REPO_ROOT/}"
  # The index itself never needs to register itself.
  [ "$rel" = "$HARNESS_DOC_INDEX" ] && continue
  n=$((n + 1))
  base="$(basename "$doc")"
  # Accept either the full relative path or the bare filename.
  if grep -qF "$rel" "$INDEX" 2>/dev/null; then continue; fi
  if grep -qF "$base" "$INDEX" 2>/dev/null; then continue; fi
  gate_violation "$rel" "-" "not registered in $HARNESS_DOC_INDEX"
done < <(harness_doc_files)

[ "$n" -eq 0 ] && gate_incomplete "no docs found under: $HARNESS_DOC_DIRS"

gate_finish "$n doc(s) against $HARNESS_DOC_INDEX"
