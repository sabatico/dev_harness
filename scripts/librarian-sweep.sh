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
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
[ -f harness.conf ] && . harness.conf

[ $# -ge 1 ] || { echo "usage: librarian-sweep.sh <term> [alias ...]" >&2; exit 2; }
RX="$(printf '%s|' "$@")"; RX="${RX%|}"
CAP="${SWEEP_CAP:-8}"

total_hits=0; absent=0
sweep() { # label, then an enumeration command
  local label="$1"; shift
  local files; files="$(eval "$*" 2>/dev/null | grep -vE 'node_modules|/target/|/dist/|\.git/' || true)"
  if [ -z "$files" ]; then
    printf '  ⚠ %-34s ABSENT — enumerated 0 files (path missing or filter ate everything)\n' "$label"
    absent=$((absent+1)); return
  fi
  local hits n
  hits="$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -niE "$RX" /dev/null 2>/dev/null | grep -v 'Binary file' || true)"
  n=$(printf '%s' "$hits" | grep -c . || true)
  total_hits=$((total_hits+n))
  printf '  %-36s %4d hit(s) in %d file(s)\n' "$label" "$n" "$(printf '%s\n' "$files" | grep -c .)"
  [ "$n" -gt 0 ] && printf '%s\n' "$hits" | cut -c1-200 | head -"$CAP" | sed 's/^/      /'
  [ "$n" -gt "$CAP" ] && echo "      … and $((n-CAP)) more"
}

echo "══ LIBRARIAN SWEEP: /$RX/ (case-insensitive) ══"
echo "Every surface accounts for itself. 0 = searched and empty. ⚠ ABSENT = could not look — say so."
echo
echo "── decisions & docs ──"
[ -n "${HARNESS_DECISION_DIR:-}" ] && sweep "decision records" "find ${HARNESS_DECISION_DIR} -name '*.md'"
for d in ${HARNESS_DOC_DIRS:-docs}; do sweep "docs: $d/" "find $d -name '*.md'"; done
sweep "root docs (CLAUDE/README/etc)" "ls ./*.md"
echo "── contracts & constraints (ground truth for quantities) ──"
sweep "migrations / schema"           "find . -path ./node_modules -prune -o -name '*.sql' -print"
sweep "API contracts (openapi/proto)" "find . -path ./node_modules -prune -o \\( -name 'openapi.*' -o -name '*.proto' \\) -print"
echo "── code (comments carry the WHY) ──"
for d in ${HARNESS_CODE_DIRS:-src}; do
  sweep "code: $d/"        "find $d -type f \\( $(printf -- "-name '*.%s' -o " ${HARNESS_CODE_EXTS:-go ts tsx js rs py} | sed 's/ -o $//') \\)"
done
sweep "scripts/ (harness WHYs)"       "ls scripts/*.sh"
echo "── harness config ──"
sweep ".claude rules/skills/agents"   "find .claude/rules .claude/skills .claude/agents -name '*.md'"
echo "── siblings (outside this repo, inside this product) ──"
for sib in ${HARNESS_SIBLING_REPOS:-}; do
  if [ -d "../$sib" ]; then sweep "sibling: $sib" "find ../$sib -type f \\( -name '*.md' -o -name '*.kt' -o -name '*.swift' -o -name '*.ts' \\)"
  else printf '  ⚠ %-34s ABSENT — ../%s not checked out on this machine\n' "sibling: $sib" "$sib"; absent=$((absent+1)); fi
done
echo "── git history (commit messages carry reasoning found nowhere else) ──"
for t in "$@"; do
  n=$(git log --oneline -i --grep="$t" 2>/dev/null | wc -l | tr -d ' ')
  printf '  %-36s %4d commit(s)\n' "log --grep '$t'" "$n"
  [ "$n" -gt 0 ] && git log --oneline -i --grep="$t" | head -6 | sed 's/^/      /'
done
p=$(git log -S"$1" --oneline 2>/dev/null | head -8)
printf '  %-36s %s\n' "pickaxe -S '$1' (bounded, newest 8)" "$( [ -n "$p" ] && echo "" || echo "0 commits")"
[ -n "$p" ] && printf '%s\n' "$p" | sed 's/^/      /'
echo
echo "────────────────────────────────────────────────────────"
echo "TOTAL: $total_hits hit(s) · ⚠ ABSENT surfaces: $absent"
echo "Librarian: paste this accounting into your answer. A 0 above is EVIDENCE of absence on that"
echo "surface; an ABSENT row must appear in NOT SEARCHED verbatim."
