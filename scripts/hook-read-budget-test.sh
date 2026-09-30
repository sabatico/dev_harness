#!/usr/bin/env bash
# hook-read-budget-test.sh — known-answer matrix for hook-read-budget.sh. Each row is a payload with a
# KNOWN verdict (what counts, how many bytes, what is ignored); a change that flips any row is a
# regression. Runs in a temp git repo with its own harness.conf. Fast-tier gate.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/hook-read-budget.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/rb-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P/docs/ai" "$P/src"; git -C "$P" init -q
printf 'HARNESS_CORPUS_DIRS="docs"\nHARNESS_LOG_DIR="%s"\n' "$T/logs" > "$P/harness.conf"
CORPUS="$P/docs/ai/big.md"; head -c 70000 /dev/zero | tr '\0' 'x' > "$CORPUS"
echo 'code' > "$P/src/x.go"
export TMPDIR="$T" HARNESS_ROOT_OVERRIDE="$P"
pass=0; fail=0; n=0
payload() { python3 -c '
import json,sys
tool,ti,tr,agent,sid=sys.argv[1:6]
d={"session_id":sid,"tool_name":tool,"tool_input":json.loads(ti)}
if tr!="null": d["tool_response"]=json.loads(tr)
if agent: d["agent_type"]=agent
print(json.dumps(d))' "$@"; }
row() { # label want-log-regex|NONE advisory(yes|no) tool ti tr [agent]
  local label="$1" want="$2" adv="$3"; shift 3; n=$((n+1)); local sid="s$n"
  local out; out="$(payload "$1" "$2" "$3" "${4:-}" "$sid" | bash "$HOOK")"
  local line; line="$(grep "session=${sid} " "$T/logs/read-budget.log" 2>/dev/null | tail -1)"; local ok=1
  if [ "$want" = NONE ]; then [ -z "$line" ] || ok=0; else printf '%s' "$line" | grep -qE "$want" || ok=0; fi
  if [ "$adv" = yes ]; then printf '%s' "$out" | grep -q additionalContext || ok=0; else [ -z "$out" ] || ok=0; fi
  if [ "$ok" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  $label | log: ${line:-<none>} | out: ${out:-<none>}"; fi
}
J() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }
big="$(head -c 40000 /dev/zero | tr '\0' 'y')"
row 'Read counts returned content, not file size' 'event=read bytes=138 ' no Read "{\"file_path\":\"$CORPUS\",\"limit\":3}" "{\"file\":{\"content\":$(J "$(head -c 138 /dev/zero | tr '\0' z)")}}"
row 'Read with unknown response falls back to size (crosses 60 KB)' 'event=read bytes=70000 ' yes Read "{\"file_path\":\"$CORPUS\"}" null
row 'Bash cat of a corpus path counts stdout'   'event=bash bytes=500 ' no Bash '{"command":"cat docs/ai/x.md"}' "{\"stdout\":$(J "$(head -c 500 /dev/zero | tr '\0' a)")}"
row 'Bash $VAR/docs path counts'                'event=bash bytes=10 ' no Bash '{"command":"grep -rn t $D/docs"}' '{"stdout":"0123456789"}'
row 'Bash absolute path under the root counts'  'event=bash bytes=3 '  no Bash "{\"command\":\"sed -n 1p $CORPUS\"}" '{"stdout":"abc"}'
row 'Bash past 30000 chars counts the 2 KB preview' 'event=bash bytes=2048 ' no Bash '{"command":"cat docs/a.md"}' "{\"stdout\":$(J "$big")}"
row 'librarian Agent = delegation'              'event=delegate via=agent:librarian' no Agent '{"subagent_type":"librarian"}' '{}'
row 'ask-librarian Skill = delegation'          'event=delegate via=skill:ask-librarian' no Skill '{"skill":"ask-librarian"}' '{}'
row 'code Read is not corpus'                   NONE no Read "{\"file_path\":\"$P/src/x.go\"}" '{"file":{"content":"code"}}'
row 'a docs URL is not a corpus path'           NONE no Bash '{"command":"curl -s https://example.com/docs/en/x"}' '{"stdout":"lots"}'
row 'subagent reads are exempt'                 NONE no Read "{\"file_path\":\"$CORPUS\"}" null librarian
row 'non-librarian subagent is no delegation'   NONE no Agent '{"subagent_type":"general-purpose"}' '{}'
echo "hook-read-budget matrix: $pass/$n pass"
[ "$fail" -eq 0 ]
