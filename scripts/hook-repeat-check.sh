#!/usr/bin/env bash
# hook-repeat-check.sh — the cheap stuck detector: the SAME tool call (same tool, byte-identical input)
# N times in a row tells the model to stop and diagnose instead of trying again. Advisory, never blocks.
#
# WHY (2026-09-30): the harness-engineering source study (Barbaste et al. 2026, arXiv 2609.00006,
# Recommendation 18) — "do not over-engineer stuck detection, but do ship the cheap caps". Every
# minimal harness now has one (OpenCode: three identical calls raise a doom-loop ask; Hermes: hash the
# call signature, warn first). Here it serves the constitution's "a red must be reproduced before it is
# attributed / a disappearing symptom is not a diagnosis": re-running the identical failing command is
# hoping, not diagnosing. Advisory because a deliberate re-run (a flaky-test check) is legitimate.
#
# Wire on BOTH PostToolUse and PostToolUseFailure, no matcher (all tools): a Bash command that exits
# non-zero arrives on PostToolUseFailure, and failed repeats are the case that matters most.
# State is per session AND per agent (parallel subagents interleave their calls in one session) in
# ${TMPDIR}/harness-repeat-<session>-<agent>; hits are logged to $HARNESS_LOG_DIR/repeat-check.log.
# Knobs: HARNESS_REPEAT_LIMIT (default 3), HARNESS_REPEAT_EXEMPT (tools that legitimately poll).
# The python runs from a QUOTED heredoc over a temp file (ci/platform-layer.md P8, "Traps").
# Test: scripts/hook-repeat-check-test.sh (a fast-tier gate).
set -uo pipefail
ROOT="${HARNESS_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null)}" || exit 0
cd "$ROOT" || exit 0
[ -f harness.conf ] && . ./harness.conf
LIMIT="${HARNESS_REPEAT_LIMIT:-3}"
# A limit that is not a positive integer (0 divided by zero and fired on every call) falls back to 3.
case "$LIMIT" in ''|*[!0-9]*|0) LIMIT=3 ;; esac
EXEMPT="${HARNESS_REPEAT_EXEMPT:-BashOutput TaskOutput TaskGet TaskList ReadNotifications Monitor ScheduleWakeup}"
LOGDIR="${HARNESS_LOG_DIR:-.harness-logs}"

pf="$(mktemp "${TMPDIR:-/tmp}/rc-payload.XXXXXX")" || exit 0
cat > "$pf"
python3 - "$pf" "$EXEMPT" > "$pf.vars" 2>/dev/null <<'PY'
import hashlib, json, shlex, sys
try: d = json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
tool = d.get("tool_name", "")
if not tool or tool in sys.argv[2].split(): sys.exit(0)
ti = d.get("tool_input") or {}
# A Bash call is the same call whatever its description/timeout say, and whatever stray whitespace
# surrounds it - otherwise relabelling a retry defeats the counter (cross-author matrix, 2026-09-30).
ident = ti.get("command", "").strip() if tool == "Bash" and isinstance(ti, dict) else json.dumps(ti, sort_keys=True)
key = hashlib.sha256((tool + "\0" + ident).encode()).hexdigest()[:16]
failed = "1" if d.get("hook_event_name") == "PostToolUseFailure" and not d.get("is_interrupt") else "0"
agent = d.get("agent_id") or d.get("agent_type") or "main"
import re
for k, v in (("SID", re.sub(r"[^A-Za-z0-9_-]", "_", str(d.get("session_id", "nosession")))[:64]), ("AGENT", str(agent)), ("TOOL", tool),
             ("KEY", key), ("FAILED", failed), ("EVENT", d.get("hook_event_name", ""))):
    print(k + "=" + shlex.quote(v))
PY
vars="$(cat "$pf.vars" 2>/dev/null)"
rm -f "$pf" "$pf.vars"
eval "$vars" || exit 0
[ -n "${KEY:-}" ] || exit 0

STATE="${TMPDIR:-/tmp}/harness-repeat-${SID}-$(printf '%s' "$AGENT" | tr -c 'A-Za-z0-9_-' '_')"
{ read -r prev count fails 2>/dev/null < "$STATE"; } 2>/dev/null || { prev=""; count=0; fails=0; }
if [ "$prev" = "$KEY" ]; then count=$((count + 1)); fails=$((fails + FAILED)); else count=1; fails=$FAILED; fi
printf '%s %s %s\n' "$KEY" "$count" "$fails" > "$STATE"

# Speak at the limit and every LIMIT calls after it — once per streak step, never on every call.
[ "$count" -ge "$LIMIT" ] && [ $((count % LIMIT)) -eq 0 ] || exit 0
mkdir -p "$LOGDIR" 2>/dev/null && echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) session=${SID:0:8} agent=$AGENT tool=$TOOL repeats=$count failed=$fails" >> "$LOGDIR/repeat-check.log"
python3 - "$TOOL" "$count" "$fails" "$EVENT" <<'PY'
import json, sys
tool, n, fails, event = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
how = f"and it failed {fails} of those times " if fails else ""
print(json.dumps({"hookSpecificOutput": {"hookEventName": event or "PostToolUse", "additionalContext": (
  f"repeat-check (advisory): {n} identical {tool} calls in a row {how}- same tool, same input. "
  "Running it again unchanged will not tell you anything new. Stop and diagnose: read the actual error, "
  "form a hypothesis, change ONE thing, or report the blocker to the owner with the output.")}}))
PY
exit 0
