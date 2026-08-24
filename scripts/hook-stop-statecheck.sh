#!/usr/bin/env bash
# hook-stop-statecheck.sh — ADVISORY nudge for the keep-state-true rule at end of turn.
#
# WHY ADVISORY, AND WHY KEYED TO HEAD, NOT THE DIRTY TREE: dirty code mid-task is NORMAL — nagging
# every turn teaches everyone to ignore it (the disable-the-guard failure mode). Jobs end in
# COMMITS. So: fire only when HEAD contains code changes but touched none of the running docs, once
# per offending commit (stamped). The hit-log makes the rule's violation rate MEASURABLE; review it
# after two weeks before ever considering promotion to blocking.
#
# Wire on Stop (no matcher). SEMPARO_STOPCHECK_REF-style env override exists so the positive branch
# is TESTABLE against a known commit — a guard whose firing path was never watched is not a guard.
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$ROOT" || exit 0
# shellcheck disable=SC1091
[ -f harness.conf ] && . harness.conf
CODE_DIRS="${HARNESS_CODE_DIRS:-src}"
DOC_DIRS="${HARNESS_DOC_DIRS:-docs}"

payload="$(cat)"
SID="$(printf '%s' "$payload" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("session_id","nosession"))
except Exception: print("nosession")' 2>/dev/null)"
STAMP="${TMPDIR:-/tmp}/harness-stopcheck-${SID}.head"

REF="${HARNESS_STOPCHECK_REF:-HEAD}"
head="$(git rev-parse "$REF" 2>/dev/null)" || exit 0
[ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$head" ] && exit 0
printf '%s' "$head" > "$STAMP"

files="$(git show --name-only --format= "$REF" 2>/dev/null)"
code_re="$(printf '%s' "$CODE_DIRS" | tr ' ' '|')"
doc_re="$(printf '%s' "$DOC_DIRS" | tr ' ' '|')"
code=$(printf '%s\n' "$files" | grep -cE "^($code_re)/" || true)
docs=$(printf '%s\n' "$files" | grep -cE "^($doc_re)/" || true)

if [ "${code:-0}" -gt 0 ] && [ "${docs:-0}" -eq 0 ]; then
  mkdir -p .gate-logs 2>/dev/null || true
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) head=$(git rev-parse --short "$REF") code_files=$code session=${SID%"${SID#????????}"}" >> .gate-logs/stop-advisory.log
  python3 - <<PY
import json
print(json.dumps({"systemMessage":"state-check (advisory): HEAD changed $code code file(s) but no running doc. If this commit finished a job, the state docs move in the same breath — update them or note why no update is owed."}))
PY
fi
exit 0
