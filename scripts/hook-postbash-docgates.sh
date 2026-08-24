#!/usr/bin/env bash
# hook-postbash-docgates.sh — close the fast-gates BYPASS: a doc written through Bash.
#
# WHY: the Write|Edit fast-gates hook cannot see files created by `cat > file` heredocs, `sed -i`,
# or generator scripts — and the source project's harness review was itself written that way and
# triggered nothing. The control assumed one write path; an agent harness has three.
#
# HOW: after every Bash call, ask git which docs are dirty (tracked AND untracked — a brand-new doc
# is exactly where invented paths are born). If that set's CONTENT differs from what we last gated,
# run the blocking doc gates. A digest stamp makes the common case cost one `git status`. The stamp
# is SESSION-SCOPED: a shared fixed path would let two sessions cancel each other's stamps.
#
# Wire on PostToolUse, matcher "Bash". Output contract: decision:block + reason on failure feeds
# the broken pointer straight back to the model so it is fixed NOW, before reasoning builds on it.
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT" || exit 0

payload="$(cat)"
SID="$(printf '%s' "$payload" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("session_id","nosession"))
except Exception: print("nosession")' 2>/dev/null)"
STAMP="${TMPDIR:-/tmp}/harness-docgate-${SID}.digest"

dirty_md="$( { git status --porcelain 2>/dev/null | awk '$0 ~ /\.md$/ {print $NF}'; } )"
[ -n "$dirty_md" ] || exit 0

digest="$(printf '%s\n' "$dirty_md" | while IFS= read -r f; do [ -f "$f" ] && shasum -a 256 "$f"; done | shasum -a 256 | cut -d' ' -f1)"
[ -f "$STAMP" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$digest" ] && exit 0

fail_out=""
for g in check-doc-links check-doc-paths; do
  [ -x "$HERE/$g.sh" ] || continue
  out="$(bash "$HERE/$g.sh" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] && fail_out="${fail_out}
── ${g} ──
$(printf '%s' "$out" | tail -12)"
done

if [ -n "$fail_out" ]; then
  python3 - "$fail_out" <<'PY'
import json,sys
print(json.dumps({
  "decision":"block",
  "reason":("A doc changed via Bash points at a file that DOES NOT EXIST (the Write|Edit hook cannot "
            "see Bash writes). Fix the path before building anything on it; look the real name up "
            "with ls, do not guess.\n"+sys.argv[1]),
  "hookSpecificOutput":{"hookEventName":"PostToolUse"},
}))
PY
  exit 2
fi
printf '%s' "$digest" > "$STAMP"
exit 0
