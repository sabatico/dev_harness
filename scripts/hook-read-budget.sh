#!/usr/bin/env bash
# hook-read-budget.sh — the librarian tripwire: is retrieval actually being DELEGATED?
#
# HONEST DESIGN NOTE (the answer to "is delegation guaranteed?"): it cannot be a hard gate.
# Targeted corpus reads are MANDATORY elsewhere (read the decision record a function cites before
# changing it), so a hook that denies doc reads would fight the rules the harness enforces —
# "this read should have been delegated" is a judgment call no script can decide. What IS
# mechanically decidable is VOLUME: a session that has pulled tens of KB of corpus into its own
# window is doing the librarian's job itself, whatever its intentions. So: count corpus bytes the
# MAIN session Reads directly, fire ONE advisory per threshold crossed, and LOG hits — the
# delegation rate becomes a measurement instead of a feeling.
#
# Wire on PostToolUse, matcher "Read". Subagents are exempt: reading the corpus is their job.
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$ROOT" || exit 0
# shellcheck disable=SC1091
[ -f harness.conf ] && . harness.conf
CORPUS="${HARNESS_CORPUS_DIRS:-docs}"
STEP="${HARNESS_READ_BUDGET_BYTES:-61440}"

payload="$(cat)"
eval "$(printf '%s' "$payload" | python3 -c '
import json,sys,shlex
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
ti=d.get("tool_input") or {}
print("SID="+shlex.quote(d.get("session_id","nosession")))
print("FP="+shlex.quote(ti.get("file_path","")))
print("AGENT="+shlex.quote(d.get("agent_type","")))
' 2>/dev/null)" || exit 0

[ -n "${FP:-}" ] || exit 0
[ -z "${AGENT:-}" ] || exit 0   # inside a subagent: exempt

hit=0
for d in $CORPUS; do case "$FP" in */$d/*) hit=1 ;; esac; done
[ "$hit" = 1 ] || exit 0
[ -f "$FP" ] || exit 0

STATE="${TMPDIR:-/tmp}/harness-readbudget-${SID}.count"
sz=$(stat -f%z "$FP" 2>/dev/null || stat -c%s "$FP" 2>/dev/null || echo 0)
total=$(( $(cat "$STATE" 2>/dev/null || echo 0) + sz ))
printf '%s' "$total" > "$STATE"

prev=$(( (total - sz) / STEP )); now=$(( total / STEP ))
if [ "$now" -gt "$prev" ]; then
  mkdir -p .gate-logs 2>/dev/null || true
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) corpus_bytes=$total last=$FP" >> .gate-logs/read-budget.log
  python3 - "$total" <<'PY'
import json, sys
kb = int(sys.argv[1]) // 1024
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": (
  f"read-budget (advisory): this session has read ~{kb} KB of corpus directly into its own context. "
  "Targeted reads required by the code-decision binding are correct — but if you are SEARCHING or "
  "SURVEYING (\"what does the repo say about X\"), that is the librarian agent's job: it returns "
  "verbatim quotes with file:line from its own context window. Delegate the next sweep.")}}))
PY
fi
exit 0
