#!/usr/bin/env bash
# librarian-presweep.sh — run librarian-sweep.sh on the terms in a /consulting-the-librarian brief, BEFORE the
# librarian starts. Injected by .claude/skills/consulting-the-librarian/SKILL.md (context: fork, agent: librarian).
# Generalised 2026-09-29 from a live project.
#
# WHY. The live project's first harness eval found the librarian's one systematic
# weakness: "all three probes self-judged the full sweep unnecessary and skipped
# librarian-sweep.sh's per-surface accounting" — an instruction competing with agent judgment loses.
# The countermeasure then was a stronger instruction; the eval itself listed the real fix as an open idea:
# `!`-inject the sweep so coverage stops depending on the agent. A forked skill runs this command
# before the prompt exists and pastes the output INTO THE LIBRARIAN'S window (not the caller's —
# code.claude.com/docs skills, "Run skills in a subagent"), so the per-surface floor is guaranteed.
#
# Input: the brief on STDIN (a quoted heredoc in the skill — the brief is never shell-parsed, so text
# like $(…) or backticks in it is inert). Terms extracted, in priority order:
#   1. an explicit line  TERMS: a | b | c   (the skill description asks the caller for one)
#   2. ids — any PREFIX-NNN ticket/decision id (ADR-012, BUG-7, DEC-3 …), "migration NNNN"
#   3. `backticked` identifiers/paths, and "short quoted phrases" (≤ 5 words)
# Each term is ERE-escaped (the sweep ORs them into one grep -E), deduped, capped at 12. The first term
# drives the sweep's git pickaxe, so ids/TERMS come first.
#
# ALWAYS exits 0: a failing injected command aborts the whole skill invocation, and a librarian that
# never starts is worse than one told "the pre-sweep found no terms — run step 1 yourself".
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
pf="$(mktemp "${TMPDIR:-/tmp}/presweep.XXXXXX")" || { echo "PRE-SWEEP: could not create a temp file — run step 1 yourself."; exit 0; }
cat > "$pf"
# Python reads the brief from a file and writes terms to a file: macOS ships bash 3.2, which mis-parses a
# heredoc nested inside $( ) or <( ) when the body holds a backtick (this regex does) — found 2026-09-29.
tf="$pf.terms"
python3 - "$pf" > "$tf" 2>/dev/null <<'PY'
import re, sys
b = open(sys.argv[1], encoding="utf-8", errors="replace").read()
out = []
# harness:allow-uncited — plumbing: dedupe case-insensitively and drop 1–2 char noise, so the ERE the
# sweep builds stays short and the first (most specific) term keeps the git-pickaxe slot.
def add(t):
    t = t.strip().strip(".,;:")
    if len(t) >= 3 and t.lower() not in (x.lower() for x in out):
        out.append(t)
for line in b.splitlines():
    m = re.match(r"\s*TERMS\s*:\s*(.+)$", line, re.I)
    if m:
        for t in re.split(r"\s*[|,]\s*", m.group(1)): add(t)
for m in re.finditer(r"\b[A-Z]{2,6}-\d+[a-z]?\b", b): add(m.group(0))
for m in re.finditer(r"\bmigration\s+(\d{4})\b", b, re.I): add(m.group(1))
for m in re.finditer(r"`([^`\n]{3,60})`", b): add(m.group(1))
for m in re.finditer(r'"([^"\n]{3,60})"', b):
    if len(m.group(1).split()) <= 5: add(m.group(1))
for t in out[:12]:
    print(re.sub(r"([.^$*+?()\[\]{}|\\])", r"\\\1", t))
PY
terms=()
while IFS= read -r t; do [ -n "$t" ] && terms+=("$t"); done < "$tf"
rm -f "$pf" "$tf"
if [ "${#terms[@]}" -eq 0 ]; then
  echo "PRE-SWEEP: no search terms could be extracted from the brief (no TERMS: line, ids, \`code\` or"
  echo "\"phrases\"). Derive aliases (step 0) and run librarian-sweep.sh yourself — the accounting is still owed."
  exit 0
fi
echo "PRE-SWEEP on the caller's terms (run before you started; ERE-escaped): ${terms[*]}"
bash "$HERE/librarian-sweep.sh" "${terms[@]}" 2>&1 || echo "PRE-SWEEP: librarian-sweep.sh exited non-zero — run it yourself."
exit 0
