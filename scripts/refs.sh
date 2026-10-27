#!/usr/bin/env bash
# refs.sh — "what points at X, and what does X point at?" for a known ID or file. Step one for anything you can name.
#
# Usage: scripts/refs.sh [--all] [--cap N] [--section N] [--rebuild] TARGET
#        scripts/refs.sh [--rebuild] --dangling
#   TARGET: an ID (ADR-012, "ADR 12", BUG-321, SEC-001, USER-001, TBD-001, W3), a repo file path
#           (no ./ = repo-relative; ./x and ../x = relative to the folder you stand in; an absolute path works),
#           or a test name cited in a bug-register row (TestFoo)
#   --section N  only decision citations that name part N ("ADR-002 §4", "§4 of ADR-002", "ADR-015 rule 1")  harness:allow-old-citation shows the citation forms, not a claim
#   --dangling   IDs that are cited but never defined, grouped by kind (+ ids defined more than once)
#   exit 0 = references found · 1 = none (the number of files scanned is printed) · 2 = usage error / crash
#
# WHY (owner of the first adopting project: "Do we not need some graph implementation to improve retrieval?"; the
# ruling: a generated reference index over the exact IDs the repo already writes, not a graph database or embeddings).
# CLAUDE.md says to read "everything that POINTS AT" a decision before changing it; find.sh does that one text term at a
# time and misses "ADR-12", "ADR 12" and "§3 of ADR-001". Use refs.sh when you KNOW the ID or path; use find.sh when you
# only have words. The index is built on demand (a few seconds for the whole repo), cached in the gitignored
# `.refs-cache/` keyed on every file's path, size and mtime (a changed file rebuilds it), and never committed — add
# `.refs-cache/` to .gitignore. The only thing this script deletes is stale `index-*.json` files inside that cache
# folder, which it rebuilds itself. Design, edge kinds and limits: the header of scripts/refs-index.py.
# Exit codes follow scripts/find.sh (0/1/2), not the gate vocabulary: this is a lookup, not a gate.
#
# Config: these harness.conf assignments are READ with sed, never sourced (a lookup must not execute config; same as
# find.sh). An environment variable already set wins, so a test can vary a knob without a config file. Unset knobs
# take the installed-project default.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "refs.sh: python3 is required (LOOKUP FAILED — NOT 'no references')" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "refs.sh: git is required (LOOKUP FAILED — NOT 'no references')" >&2; exit 2; }
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "refs.sh: not inside a git repo (LOOKUP FAILED — NOT 'no references')" >&2; exit 2; }
[ -f "$here/refs-index.py" ] || { echo "refs.sh: $here/refs-index.py is missing (LOOKUP FAILED — NOT 'no references')" >&2; exit 2; }

# conf_knob NAME DEFAULT → exports NAME: the environment's value if set, else harness.conf's last assignment, else DEFAULT.
conf_knob() {
  local name="$1" def="$2" val
  if [ -n "${!name+x}" ]; then val="${!name}"
  elif [ -f "$root/harness.conf" ] && grep -qE "^[[:space:]]*(export[[:space:]]+)?$name=" "$root/harness.conf"; then
    val="$(sed -n "s/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}$name=[\"']\{0,1\}\([^\"'#]*\).*/\2/p" "$root/harness.conf" | tail -1)"
  else val="$def"; fi
  export "$name=$val"
}
conf_knob HARNESS_DOC_DIRS "docs"
conf_knob HARNESS_DECISION_DIR "docs/adr"
conf_knob HARNESS_DECISION_PREFIX "ADR"
conf_knob HARNESS_BUG_PREFIX "BUG"
conf_knob HARNESS_BUG_REGISTER ""
conf_knob HARNESS_REFS_IDS "USER DEC FEAT DOC BIZ SEC TBD"

# -I: isolated mode, so a stray json.py or re.py in the current directory is never imported.
exec python3 -I "$here/refs-index.py" --root "$root" "$@"
