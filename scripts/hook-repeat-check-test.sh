#!/usr/bin/env bash
# hook-repeat-check-test.sh — known-answer matrix for hook-repeat-check.sh (the cheap stuck detector).
#
# Each row is ONE hook call with a known verdict: SPEAK (an additionalContext advisory) or SILENT.
# Rows are grouped into streaks, each on its own session id, so state never leaks between scenarios.
# Both halves are mandatory: the SPEAK rows prove the counter fires at the limit (and only on each
# limit step), the SILENT rows prove what must NOT count — a different call, an exempt polling tool,
# another session, another agent. A change that flips any row is a regression, either direction.
# Runs against a temp git repo (HARNESS_ROOT_OVERRIDE) and a temp TMPDIR (where the hook keeps its
# per-session state), so neither the real repo's log nor the real temp dir is touched.
#
# Cross-authored 2026-09-30 (not by the builder of the hook). Cases the hook currently gets WRONG are
# not rows; they went to the lead in the test author's report. Fast-tier gate.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/hook-repeat-check.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/rc-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P" "$T/tmp"; git -C "$P" init -q
printf 'HARNESS_LOG_DIR="%s"\n' "$T/logs" > "$P/harness.conf"
LOGF="$T/logs/repeat-check.log"
unset HARNESS_REPEAT_LIMIT HARNESS_REPEAT_EXEMPT
export HARNESS_ROOT_OVERRIDE="$P" TMPDIR="$T/tmp"
pass=0; fail=0; n=0

# payload <event> <sid> <agent|''> <tool> <raw tool_input JSON> [raw extra fields] — built as a raw
# string (not via json.dumps) so key order and spelling reach the hook exactly as written.
payload() {
  local ag=""; [ -n "$3" ] && ag="\"agent_id\":\"$3\","
  printf '{"hook_event_name":"%s","session_id":"%s",%s"tool_name":"%s","tool_input":%s%s}' "$1" "$2" "$ag" "$4" "$5" "${6:-}"
}

# c <want: SPEAK|SILENT> <label> <event> <sid> <agent> <tool> <input> [extra]
#   ROW_ENV: VAR=val for the hook; ROW_RE: a regex the advisory must also match. stderr must be empty
#   too (a crash trace is not "silent"), unless ROW_STDERR_OK=1.
c() {
  local want="$1" label="$2"; shift 2; n=$((n+1))
  local out rc err ok=1
  out="$(payload "$@" | env ${ROW_ENV:-} bash "$HOOK" 2>"$T/stderr")"; rc=$?
  err="$(cat "$T/stderr")"
  [ "$rc" -eq 0 ] || ok=0
  [ -z "$err" ] || [ "${ROW_STDERR_OK:-}" = 1 ] || { ok=0; out="$out [stderr: $err]"; }
  if [ "$want" = SILENT ]; then [ -z "$out" ] || ok=0
  else
    printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)["hookSpecificOutput"]
assert d["hookEventName"]==sys.argv[1] and "repeat-check (advisory)" in d["additionalContext"]' "$1" 2>/dev/null || ok=0
    [ -z "${ROW_RE:-}" ] || printf '%s' "$out" | grep -qE "$ROW_RE" || ok=0
  fi
  if [ "$ok" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  want=$want rc=$rc  $label"; echo "      out: ${out:-<silent>}"; fi
}
PU=PostToolUse; PF=PostToolUseFailure
X='{"command":"make test"}'; Y='{"command":"make lint"}'

# ── the limit: 2 silent, 3rd speaks, 4-5 silent, 6th speaks ───────────────────
c SILENT '1st identical call'   $PU s1 '' Bash "$X"
c SILENT '2nd identical call'   $PU s1 '' Bash "$X"
ROW_RE='3 identical Bash calls in a row' \
c SPEAK  '3rd identical call speaks' $PU s1 '' Bash "$X"
c SILENT '4th is silent (once per limit step)' $PU s1 '' Bash "$X"
c SILENT '5th is silent'        $PU s1 '' Bash "$X"
ROW_RE='6 identical Bash calls' \
c SPEAK  '6th speaks again'     $PU s1 '' Bash "$X"
c SILENT '7th is silent'        $PU s1 '' Bash "$X"

# ── a different call resets the streak ───────────────────────────────────────
c SILENT 'X'                    $PU s2 '' Bash "$X"
c SILENT 'X'                    $PU s2 '' Bash "$X"
c SILENT 'Y resets'             $PU s2 '' Bash "$Y"
c SILENT 'X after reset (1)'    $PU s2 '' Bash "$X"
c SILENT 'X after reset (2)'    $PU s2 '' Bash "$X"
c SPEAK  'X after reset (3) speaks' $PU s2 '' Bash "$X"
c SILENT 'same input, different tool, is a different call' $PU s2 '' Monitor2 "$X"
c SILENT 'back to Bash X: streak restarted at 1' $PU s2 '' Bash "$X"

# ── identical means identical JSON, not identical bytes ──────────────────────
c SILENT 'key order A'          $PU s3 '' Bash '{"command":"ls","description":"list","timeout":5}'
c SILENT 'key order B'          $PU s3 '' Bash '{"timeout":5,"description":"list","command":"ls"}'
c SPEAK  'key order C (whitespace too) = 3rd identical' $PU s3 '' Bash '{ "description" : "list" , "command":"ls","timeout" :5 }'
c SILENT 'nested order A'       $PU s3b '' Edit '{"file_path":"a","edits":[{"old":"x","new":"y"}]}'
c SILENT 'nested order B'       $PU s3b '' Edit '{"edits":[{"new":"y","old":"x"}],"file_path":"a"}'
c SPEAK  'nested order C (unicode escape = same char)' $PU s3b '' Edit '{"edits":[{"new":"y","old":"x"}],"file_path":"a"}'
c SILENT 'array ORDER does matter (a different call)' $PU s3b '' Edit '{"edits":[{"new":"y","old":"x"},{"new":"z","old":"w"}],"file_path":"a"}'
c SILENT 'same input, different tool_response, 1' $PU s3c '' Bash "$X" ',"tool_response":{"stdout":"1"}'
c SILENT 'same input, different tool_response, 2' $PU s3c '' Bash "$X" ',"tool_response":{"stdout":"2"}'
c SPEAK  'output differs, call is identical: still a repeat' $PU s3c '' Bash "$X" ',"tool_response":{"stdout":"3"}'

# ── failures are counted and named ───────────────────────────────────────────
c SILENT 'fail 1'               $PF s4 '' Bash "$X"
c SILENT 'fail 2'               $PF s4 '' Bash "$X"
ROW_RE='3 identical Bash calls in a row and it failed 3 of those times' \
c SPEAK  'fail 3 speaks, says 3 failures, on the failure event' $PF s4 '' Bash "$X"
c SILENT 'mixed: success'       $PU s4b '' Bash "$X"
c SILENT 'mixed: fail'          $PF s4b '' Bash "$X"
ROW_RE='failed 2 of those times' \
c SPEAK  'mixed: fail (3rd) says 2 failures' $PF s4b '' Bash "$X"
c SILENT 'interrupt 1'          $PF s4c '' Bash "$X" ',"is_interrupt":true'
c SILENT 'interrupt 2'          $PF s4c '' Bash "$X" ',"is_interrupt":true'
ROW_RE='in a row - same tool' \
c SPEAK  'an interrupt counts as a repeat but NOT as a failure' $PF s4c '' Bash "$X" ',"is_interrupt":true'
c SILENT 'success 1'            $PU s4d '' Bash "$X"
c SILENT 'success 2'            $PU s4d '' Bash "$X"
ROW_RE='calls in a row - same' \
c SPEAK  'all-success streak does not mention failures' $PU s4d '' Bash "$X"

# ── exempt polling tools never count, and never break a streak ───────────────
for i in 1 2 3 4 5 6; do c SILENT "BashOutput poll $i is exempt" $PU s5 '' BashOutput '{"bash_id":"b1"}'; done
for i in 1 2 3; do c SILENT "Monitor poll $i is exempt" $PU s5 '' Monitor '{"x":1}'; done
c SILENT 'X 1'                  $PU s5b '' Bash "$X"
c SILENT 'X 2'                  $PU s5b '' Bash "$X"
c SILENT 'an exempt poll in between' $PU s5b '' TaskOutput '{"id":"t"}'
c SPEAK  'X 3 still speaks: the exempt call did not reset the streak' $PU s5b '' Bash "$X"
ROW_ENV='HARNESS_REPEAT_EXEMPT=Read'
c SILENT 'custom exempt: Read 1' $PU s5c '' Read '{"file_path":"a"}'
c SILENT 'custom exempt: Read 2' $PU s5c '' Read '{"file_path":"a"}'
c SILENT 'custom exempt: Read 3' $PU s5c '' Read '{"file_path":"a"}'
unset ROW_ENV

# ── a Bash call's identity is its command (trimmed), not its label ───────────
c SILENT 'relabelled retry 1'   $PU s12 '' Bash '{"command":"make test","description":"run tests"}'
c SILENT 'relabelled retry 2: new description' $PU s12 '' Bash '{"command":"make test","description":"try again"}'
c SPEAK  'relabelled retry 3: new timeout + description, same command' $PU s12 '' Bash '{"command":"make test","description":"third","timeout":600000}'
c SILENT 'whitespace 1'         $PU s12b '' Bash '{"command":"make test"}'
c SILENT 'whitespace 2: trailing space' $PU s12b '' Bash '{"command":"make test "}'
c SPEAK  'whitespace 3: leading space + newline' $PU s12b '' Bash '{"command":"\n make test"}'
c SILENT 'background flag 1'    $PU s12c '' Bash '{"command":"make test","run_in_background":true}'
c SILENT 'background flag 2'    $PU s12c '' Bash '{"command":"make test"}'
c SPEAK  'background flag 3: the flag does not change the call' $PU s12c '' Bash '{"command":"make test","run_in_background":false}'
c SILENT 'inner space 1'        $PU s12d '' Bash '{"command":"make test"}'
c SILENT 'inner space 2'        $PU s12d '' Bash '{"command":"make test"}'
c SILENT 'a different command (inner double space) resets' $PU s12d '' Bash '{"command":"make  test"}'
c SILENT 'non-Bash: description-like field 1' $PU s12e '' Grep '{"pattern":"x","path":"a"}'
c SILENT 'non-Bash: description-like field 2' $PU s12e '' Grep '{"pattern":"x","path":"a"}'
c SILENT 'non-Bash: any input change is a different call' $PU s12e '' Grep '{"pattern":"x","path":"b"}'

# ── sessions and agents never share state ────────────────────────────────────
c SILENT 'session A 1'          $PU s6a '' Bash "$X"
c SILENT 'session A 2'          $PU s6a '' Bash "$X"
c SILENT 'session B 1 (does not continue A)' $PU s6b '' Bash "$X"
c SPEAK  'session A 3 (B did not reset A)' $PU s6a '' Bash "$X"
c SILENT 'session B 2'          $PU s6b '' Bash "$X"
c SPEAK  'session B 3'          $PU s6b '' Bash "$X"
c SILENT 'agent a1 1'           $PU s7 agent-1 Bash "$X"
c SILENT 'agent a2 1'           $PU s7 agent-2 Bash "$X"
c SILENT 'main 1'               $PU s7 '' Bash "$X"
c SILENT 'agent a1 2'           $PU s7 agent-1 Bash "$X"
c SILENT 'agent a2 2'           $PU s7 agent-2 Bash "$X"
c SPEAK  'agent a1 3 (interleaving did not reset it)' $PU s7 agent-1 Bash "$X"
c SPEAK  'agent a2 3'           $PU s7 agent-2 Bash "$X"
c SILENT 'main 2 (main has its own count)' $PU s7 '' Bash "$X"
c SILENT 'agent_type fallback 1' $PU s7b '' Bash "$X" ',"agent_type":"Explore"'
c SILENT 'main in same session 1' $PU s7b '' Bash "$X"
c SILENT 'agent_type fallback 2' $PU s7b '' Bash "$X" ',"agent_type":"Explore"'
c SPEAK  'agent_type fallback 3 (separate from main)' $PU s7b '' Bash "$X" ',"agent_type":"Explore"'
c SILENT 'hostile agent id 1'   $PU s7c '../../etc/x y' Bash "$X"
c SILENT 'hostile agent id 2'   $PU s7c '../../etc/x y' Bash "$X"
c SPEAK  'hostile agent id 3: sanitised into one state file' $PU s7c '../../etc/x y' Bash "$X"
if ls "$T/tmp"/harness-repeat-s7c-* >/dev/null 2>&1 && [ ! -e "$T/etc" ]; then pass=$((pass+1))
else fail=$((fail+1)); echo "FAIL  the agent id must be sanitised into a file name inside TMPDIR"; fi
# hostile session ids: sanitised into one state file inside TMPDIR, so the counter still works (it
# used to fail to write its state and never fire), with no shell noise on stderr
for hs in 'a/b' '..' '../../x' 'a b$(id)'; do
  for i in 1 2; do c SILENT "hostile session id '$hs' call $i" $PU "$hs" '' Bash "$X"; done
  c SPEAK "hostile session id '$hs' call 3 still speaks" $PU "$hs" '' Bash "$X"
done
if [ -z "$(find "$T/tmp" -mindepth 2 -name 'harness-repeat-*' 2>/dev/null)" ] && [ ! -e "$T/x-main" ] && [ ! -e "$T/harness-repeat-..-main" ]; then pass=$((pass+1))
else fail=$((fail+1)); echo "FAIL  a hostile session id escaped TMPDIR"; fi

# ── HARNESS_REPEAT_LIMIT ─────────────────────────────────────────────────────
ROW_ENV='HARNESS_REPEAT_LIMIT=2'
c SILENT 'limit 2: 1'           $PU s8 '' Bash "$X"
c SPEAK  'limit 2: 2 speaks'    $PU s8 '' Bash "$X"
c SILENT 'limit 2: 3'           $PU s8 '' Bash "$X"
c SPEAK  'limit 2: 4 speaks'    $PU s8 '' Bash "$X"
ROW_ENV='HARNESS_REPEAT_LIMIT=5'
for i in 1 2 3 4; do c SILENT "limit 5: $i" $PU s8b '' Bash "$X"; done
c SPEAK  'limit 5: 5 speaks'    $PU s8b '' Bash "$X"
ROW_ENV='HARNESS_REPEAT_LIMIT=1'
c SPEAK  'limit 1: every call speaks (1)' $PU s8c '' Bash "$X"
c SPEAK  'limit 1: every call speaks (2)' $PU s8c '' Bash "$X"
# A limit that is not a positive integer falls back to the default 3 (spec change 2026-09-30: 0 used to
# divide by zero and fire on EVERY call; -1 did the same; abc printed a shell error per call).
k=0
for bad in abc 0 -1 '' 1.5 07x; do
  k=$((k+1)); ROW_ENV="HARNESS_REPEAT_LIMIT=$bad"
  [ -z "$bad" ] && ROW_ENV='HARNESS_REPEAT_LIMIT='
  c SILENT "limit '$bad' falls back to 3: call 1" $PU "s8d$k" '' Bash "$X"
  c SILENT "limit '$bad' falls back to 3: call 2" $PU "s8d$k" '' Bash "$X"
  c SPEAK  "limit '$bad' falls back to 3: call 3 speaks" $PU "s8d$k" '' Bash "$X"
done
unset ROW_ENV
printf 'HARNESS_LOG_DIR="%s"\nHARNESS_REPEAT_LIMIT=2\n' "$T/logs" > "$P/harness.conf"
c SILENT 'limit from harness.conf: 1' $PU s8e '' Bash "$X"
c SPEAK  'limit from harness.conf: 2 speaks' $PU s8e '' Bash "$X"
printf 'HARNESS_LOG_DIR="%s"\n' "$T/logs" > "$P/harness.conf"

# ── broken input: silent, exit 0 ─────────────────────────────────────────────
raw() { # label stdin
  n=$((n+1)); local out rc
  out="$(printf '%s' "$2" | bash "$HOOK" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  $1 (rc=$rc)"; echo "      out: ${out:-<silent>}"; fi
}
for i in 1 2 3 4; do raw "garbage stdin ($i)" 'not json {{{'; done
for i in 1 2 3 4; do raw "empty stdin ($i)" ''; done
for i in 1 2 3 4; do raw "JSON without tool_name ($i)" '{"session_id":"s9","tool_input":{"command":"x"}}'; done
for i in 1 2 3; do raw "a JSON array ($i)" '[1,2,3]'; done
for i in 1 2 3; do raw "binary junk ($i)" "$(printf '\x00\xff\xfe\x01')"; done
# corrupt state file: the hook recovers instead of crashing
printf 'garbage line with words\n' > "$T/tmp/harness-repeat-s10-main"
c SILENT 'corrupt state: 1'     $PU s10 '' Bash "$X"
c SILENT 'corrupt state: 2'     $PU s10 '' Bash "$X"
c SPEAK  'corrupt state: 3 speaks' $PU s10 '' Bash "$X"
c SILENT 'tool_input absent = {} (1)' $PU s11 '' Glob 'null'
c SILENT 'tool_input absent = {} (2)' $PU s11 '' Glob '{}'
c SPEAK  'tool_input null and {} are the same call (3)' $PU s11 '' Glob 'null'

# ── the log: one line per advisory, counts only, never the input ─────────────
c SILENT 'log probe 1'          $PU logsess1 '' Bash '{"command":"echo LOGMARKER-q7"}'
c SILENT 'log probe 2'          $PU logsess1 '' Bash '{"command":"echo LOGMARKER-q7"}'
c SPEAK  'log probe 3'          $PU logsess1 '' Bash '{"command":"echo LOGMARKER-q7"}'
if [ "$(grep -c 'session=logsess1 ' "$LOGF")" -eq 1 ] \
   && grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z session=logsess1 agent=main tool=Bash repeats=3 failed=0$' "$LOGF" \
   && ! grep -q 'LOGMARKER' "$LOGF"; then pass=$((pass+1))
else fail=$((fail+1)); echo "FAIL  log: one line per advisory, counts only"; grep 'logsess1' "$LOGF" | sed 's/^/      /'; fi
if grep -qE 'session=s4 agent=main tool=Bash repeats=3 failed=3$' "$LOGF"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  log records the failure count"; fi
if [ "$(grep -c 'session=s1 ' "$LOGF")" -eq 2 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  the 7-call streak must log exactly 2 advisories"; fi
[ ! -d "$P/.harness-logs" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL  wrote to the default log dir instead of HARNESS_LOG_DIR"; }
# the hook leaves no payload temp files behind
if ls "$T/tmp"/rc-payload.* >/dev/null 2>&1; then fail=$((fail+1)); echo "FAIL  payload temp files left in TMPDIR"; else pass=$((pass+1)); fi

# ── KNOWN GAPS: documented, run, never counted as passes ─────────────────────
# A gap row asserts the CURRENT (wrong-by-design) behaviour. While the gap is open it prints GAP and
# counts in `gaps`, not in `pass`. If the hook starts detecting it, the row FAILS loudly so whoever
# closed the gap turns it into a real SPEAK row (strict-xfail: a gap cannot close silently).
gaps=0
gap() { # label sid then calls as "<input>" ...
  local label="$1" sid="$2" spoke=0 out; shift 2
  for inp in "$@"; do
    out="$(payload $PU "$sid" '' Bash "$inp" | bash "$HOOK" 2>/dev/null)"
    [ -n "$out" ] && spoke=1
  done
  if [ "$spoke" = 0 ]; then gaps=$((gaps+1)); echo "  GAP   $label (still undetected; by decision)"
  else fail=$((fail+1)); echo "FAIL  known gap now DETECTED — promote to a SPEAK row: $label"; fi
}
A='{"command":"make test"}'; B='{"command":"make lint"}'
gap 'alternating A B A B A B is not a streak' sgap1 "$A" "$B" "$A" "$B" "$A" "$B" "$A" "$B"

echo "repeat-check matrix: $pass pass, $fail fail, $gaps known gap(s) (NOT passes)"
[ "$fail" -eq 0 ]
