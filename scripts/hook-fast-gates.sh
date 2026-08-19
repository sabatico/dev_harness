#!/usr/bin/env bash
# hook-fast-gates.sh — run the sub-second gates AT THE MOMENT OF THE EDIT.
#
# ── WHY THE TIMING IS THE WHOLE POINT ─────────────────────────────────────────
#
# The gates were already correct and already ran — at push, as a long run at the end.
# So a wrong doc link would be written, THREE PARAGRAPHS OF REASONING BUILT ON IT,
# and the error would surface forty minutes later. The gate was right and still
# nearly useless, because it arrived after the cost was sunk.
#
# Same gates, same exit codes, fired on the write. That is the entire change, and it
# is worth more than any individual check in the suite.
#
# ── THE TWO TIERS, AND THE SPLIT IS DELIBERATE ────────────────────────────────
#
#   BLOCKING (docs) — a doc pointing at a file that does not exist is a FACT ERROR.
#     There is no legitimate in-progress state for it, and everything downstream
#     inherits a false premise. Fail loudly, now.
#
#   ADVISORY (code) — a half-written function is a legitimate state; the doc comment
#     often lands after the signature. Blocking here would interrupt every second
#     keystroke and teach the author to switch the hook off — which is the failure
#     mode this file exists to prevent. A control annoying enough to disable has a
#     real enforcement value of zero.
#
# Exit 0 = pass or advisory notice. Exit 2 = blocking failure, fed back to the model.
#
# ── ⛔ HOW NOT TO VERIFY THIS ─────────────────────────────────────────────────
#
# Piping a JSON payload at this script proves THE SCRIPT. It does not prove the hook
# is wired, loaded, or firing. Hook config is typically read at SESSION START, so a
# session already running when you installed this has no hook and NOTHING SAYS SO —
# an unprotected session looks exactly like a protected one.
#
# To verify a control, trigger it the way production triggers it: edit a real file
# through the agent and watch the block arrive. Anything else tests the check and
# calls it the system.

HERE="$(cd "$(dirname "$0")" && pwd)"

payload="$(cat)"

# The file path arrives in the hook payload. Try the common shapes, then fall back
# to any absolute-looking path in the blob.
file="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get("tool_input") or {}
for k in ("file_path", "path", "notebook_path"):
    v = ti.get(k) or d.get(k)
    if v:
        print(v); break
' 2>/dev/null)"

[ -n "$file" ] || exit 0
[ -e "$file" ] || exit 0

case "$file" in
  # ── BLOCKING: documentation ─────────────────────────────────────────────────
  *.md|*.mdx)
    out="$(bash "$HERE/check-doc-links.sh" "$file" 2>&1)"
    rc=$?
    if [ "$rc" -eq 1 ]; then
      printf 'BLOCKED — this doc points at a file that does not exist.\n\n%s\n\n' "$out"
      printf 'Look the path up (ls / grep) before writing anything that depends on it.\n'
      printf 'A path you did not see printed is a guess, and everything you build on it\n'
      printf 'inherits the error.\n'
      exit 2
    fi
    exit 0
    ;;

  # ── ADVISORY: source ────────────────────────────────────────────────────────
  *.go|*.ts|*.tsx|*.js|*.rs|*.py|*.java|*.rb)
    out="$(bash "$HERE/check-citations.sh" 2>&1 | grep -F "$(basename "$file")" | head -3)"
    [ -n "$out" ] && printf 'advisory (enforced at push, not now):\n%s\n' "$out"
    exit 0
    ;;
esac

exit 0
