#!/usr/bin/env bash
# librarian-sweep.sh — sweep EVERY knowledge surface for a topic; every surface accounts for itself
# with a NUMBER, so "no hits" is provably different from "never looked".
#
# WHY: surface selection left to the searching agent's per-question judgment is a remembered
# checklist, and remembered checklists measure ~30% compliance. This makes the checklist
# MECHANICAL: one invocation, all surfaces, per-surface hit counts. The self-proof philosophy
# applied to retrieval:
#   · a surface with hits prints them (capped; deep-read from there);
#   · a surface with ZERO hits prints 0 — searched, empty, and that is now EVIDENCE;
#   · a surface whose FILES cannot be enumerated prints ⚠ ABSENT — "I could not look" reported as
#     "no hits" is the lie every gate in this harness exists to unlearn.
#
# Terms are OR'd ALIASES — the same subject lives under different names on different surfaces
# (doc phrase vs code identifier vs ticket id). Derive aliases FIRST, sweep once with all of them.
# The first sweep of the source project found its two sibling repos had been invisible to every
# previous search, and its doc-phrase/code-alias split had produced a false "unbuilt" verdict.
#
# Usage:  scripts/librarian-sweep.sh <term> [alias ...]     (case-insensitive extended regex OR)
#         SWEEP_CAP=20 …                                    (hits shown per surface; default 8)
#
# v1.3 (an outside benchmark of v1–v1.2): the named surfaces were the WHOLE sweep, so a decision kept
# anywhere else — a notes/ folder, a data file, a CSV of rulings — was invisible while the footer said
# "0 = searched and empty", and the librarian runs that succeeded did so only by stepping outside the
# sweep. Now a last surface, "everything else", greps every repo file (tracked + untracked, .gitignore
# respected) that no named surface enumerated, and names the folders its hits came from; every cap
# says TRUNCATED; the history pickaxe runs for every term, not only the first.
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
[ -f harness.conf ] && . harness.conf

[ $# -ge 1 ] || { echo "usage: librarian-sweep.sh <term> [alias ...]" >&2; exit 2; }
RX="$(printf '%s|' "$@")"; RX="${RX%|}"
CAP="${SWEEP_CAP:-8}"
COVERED="$(mktemp "${TMPDIR:-/tmp}/sweep-covered.XXXXXX")" || COVERED=/dev/null
trap 'rm -f "$COVERED" "$COVERED.rest"' EXIT

total_hits=0; absent=0; LAST_HITS=""
sweep() { # label, then an enumeration command
  local label="$1"; shift
  # Noise filter from HARNESS_EXCLUDE_GLOBS, not a baked-in list: a sweep that reports hits from
  # vendored code wastes the librarian's window, and one that prunes the WRONG directories reports
  # a confident 0 on a surface it never looked at.
  local files ex; ex="$(printf '%s' "${HARNESS_EXCLUDE_GLOBS:-}" | sed 's/[*]//g; s/  */|/g; s/^|//; s/|$//')"
  files="$(eval "$*" 2>/dev/null | grep -vE "\.git/${ex:+|$ex}" || true)"
  # Remember what the named surfaces enumerated, so the catch-all surface searches only the rest.
  [ -n "$files" ] && printf '%s\n' "$files" | sed 's|^\./||' >> "$COVERED"
  if [ -z "$files" ]; then
    printf '  ⚠ %-34s ABSENT — enumerated 0 files (path missing or filter ate everything)\n' "$label"
    absent=$((absent+1)); return
  fi
  local hits n
  hits="$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -niE -e "$RX" /dev/null 2>/dev/null | grep -v 'Binary file' || true)"
  n=$(printf '%s' "$hits" | grep -c . || true)
  total_hits=$((total_hits+n))
  printf '  %-36s %4d hit(s) in %d file(s)\n' "$label" "$n" "$(printf '%s\n' "$files" | grep -c .)"
  [ "$n" -gt 0 ] && printf '%s\n' "$hits" | head -"$CAP" | awk '{ if (length($0) > 200) $0 = substr($0, 1, 200) " …[cut]"; print "      " $0 }'
  [ "$n" -gt "$CAP" ] && echo "      … and $((n-CAP)) more — TRUNCATED (SWEEP_CAP=$CAP); read the files or raise the cap"
  LAST_HITS="$hits"
}

echo "══ LIBRARIAN SWEEP: /$RX/ (case-insensitive) ══"
echo "Every surface accounts for itself. 0 = searched and empty. ⚠ ABSENT = could not look — say so."
echo
echo "── decisions & docs ──"
[ -n "${HARNESS_DECISION_DIR:-}" ] && sweep "decision records" "find ${HARNESS_DECISION_DIR} -name '*.md'"
for d in ${HARNESS_DOC_DIRS:-docs}; do sweep "docs: $d/" "find $d -name '*.md'"; done
sweep "root docs (CLAUDE/README/etc)" "ls ./*.md"
echo "── contracts & constraints (ground truth for quantities) ──"
# WHAT a schema or an API contract looks like is a stack fact — HARNESS_SCHEMA_GLOBS and
# HARNESS_CONTRACT_GLOBS (stack pack / harness.conf). Hardcoding *.sql meant a project whose ground
# truth was a .prisma or .graphql file got a confident "0 hits" on the surface that holds its
# quantities — the exact surface the librarian exists to consult.
name_expr() { local first=1 g; for g in $1; do [ $first -eq 1 ] && printf -- "-name '%s'" "$g" || printf -- " -o -name '%s'" "$g"; first=0; done; }
sweep "migrations / schema"           "find . -path ./node_modules -prune -o \\( $(name_expr "${HARNESS_SCHEMA_GLOBS:-*.sql}") \\) -print"
sweep "API contracts"                 "find . -path ./node_modules -prune -o \\( $(name_expr "${HARNESS_CONTRACT_GLOBS:-openapi.* *.proto}") \\) -print"
echo "── code (comments carry the WHY) ──"
for d in ${HARNESS_CODE_DIRS:-src}; do
  sweep "code: $d/"        "find $d -type f \\( $(printf -- "-name '*.%s' -o " ${HARNESS_CODE_EXTS:-go ts tsx js rs py} | sed 's/ -o $//') \\)"
done
sweep "scripts/ (harness WHYs)"       "ls scripts/*.sh"
echo "── harness config ──"
sweep ".claude rules/skills/agents"   "find .claude/rules .claude/skills .claude/agents -name '*.md'"
echo "── siblings (outside this repo, inside this product) ──"
for sib in ${HARNESS_SIBLING_REPOS:-}; do
  if [ -d "../$sib" ]; then sweep "sibling: $sib" "find ../$sib -type f \\( -name '*.md' -o $(name_expr "$(for e in ${HARNESS_CODE_EXTS:-md}; do printf '*.%s ' "$e"; done)") \\)"
  else printf '  ⚠ %-34s ABSENT — ../%s not checked out on this machine\n' "sibling: $sib" "$sib"; absent=$((absent+1)); fi
done
echo "── everything else in the repo (no named surface above enumerated these files) ──"
if git rev-parse --git-dir >/dev/null 2>&1; then
  # -z: git quotes a name holding a quote, tab or backslash even with quotePath=false, and grep then
  # opens a path that does not exist — a silent miss. NFC on both sides: macOS find prints decomposed
  # accents and git composed ones, so one file read as two (counted twice). Names with a newline are
  # still not supported by this newline-separated sweep (scripts/find.sh handles them).
  # nfc [z]: one name per output line, NFC-normalised; "z" = the input is NUL-separated.
  nfc() { python3 -c 'import sys,unicodedata
sep = "\0" if sys.argv[1:] == ["z"] else "\n"
for l in sys.stdin.read().split(sep):
    l and print(unicodedata.normalize("NFC", l))' "$@"; }
  git -c core.quotePath=false ls-files -z --cached --others --exclude-standard | nfc z | sort -u > "$COVERED.rest.all"
  nfc < "$COVERED" | sort -u | comm -23 "$COVERED.rest.all" - > "$COVERED.rest"; rm -f "$COVERED.rest.all"
  if [ -s "$COVERED.rest" ]; then
    LAST_HITS=""
    sweep "everything else" "cat '$COVERED.rest'"
    if [ -n "$LAST_HITS" ]; then
      echo "      hits by folder (decisions live in notes, data files and archives too — read them):"
      printf '%s\n' "$LAST_HITS" | cut -d: -f1 | awk -F/ '{ print (NF > 1 ? $1 "/" : "(repo root)") }' | sort | uniq -c | sort -rn | sed 's/^/        /'
    fi
  else
    printf '  %-36s %4d file(s) left — the named surfaces covered the whole repo\n' "everything else" 0
  fi
else
  printf '  ⚠ %-34s ABSENT — not a git repo, so the rest of the tree could not be enumerated\n' "everything else"; absent=$((absent+1))
fi
echo "── git history (commit messages carry reasoning found nowhere else) ──"
for t in "$@"; do
  n=$(git log --oneline -i --grep="$t" 2>/dev/null | wc -l | tr -d ' ')
  printf '  %-36s %4d commit(s)\n' "log --grep '$t'" "$n"
  [ "$n" -gt 0 ] && git log --oneline -i --grep="$t" | head -6 | sed 's/^/      /'
done
for t in "$@"; do
  p=$(git log -S"$t" --oneline 2>/dev/null | head -8)
  printf '  %-36s %s\n' "pickaxe -S '$t' (bounded, newest 8)" "$( [ -n "$p" ] && echo "" || echo "0 commits")"
  [ -n "$p" ] && printf '%s\n' "$p" | sed 's/^/      /'
done
echo
echo "────────────────────────────────────────────────────────"
echo "TOTAL: $total_hits hit(s) · ⚠ ABSENT surfaces: $absent"
echo "Librarian: paste this accounting into your answer. A 0 above is EVIDENCE of absence on that"
echo "surface; an ABSENT row must appear in NOT SEARCHED verbatim."
