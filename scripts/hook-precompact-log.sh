#!/usr/bin/env bash
# hook-precompact-log.sh — make compaction OBSERVABLE. Compaction is literally the "the AI lost
# context" event; unlogged, a wrong decision made after one is indistinguishable from a wrong
# decision made with full context. One line per event, append-only, concurrent-session safe.
# The RE-INJECTION half is hook-session-start.sh, whose matcher includes `compact`.
# Wire on PreCompact (matcher "" = both manual and auto).
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$ROOT" || exit 0
payload="$(cat)"
info="$(printf '%s' "$payload" | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin); print(d.get("session_id","?")[:8], d.get("trigger") or d.get("matcher") or "?")
except Exception: print("? ?")' 2>/dev/null)"
dirty=$(git status --porcelain 2>/dev/null | grep -c . || echo 0)
mkdir -p .gate-logs 2>/dev/null || true
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) session=${info%% *} trigger=${info##* } dirty_paths=${dirty} head=$(git rev-parse --short HEAD 2>/dev/null)" >> .gate-logs/compaction.log
exit 0
