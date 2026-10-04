#!/usr/bin/env bash
# hook-session-start.sh — inject VERIFIED project state at session start, and PROVE hooks loaded.
#
# WHY (two findings, ci/platform-layer.md P1):
#   1. A mandated cold-start reading list grows until nobody affords it (the source project's
#      reached ~70k tokens — 35% of a context window before any work). Most of what a session needs
#      is a page of hard facts, and hand-typed facts rot. So: derive the facts by script, inject
#      ~a page.
#   2. THE BANNER IS A LIVENESS PROOF. Hook config loads at session start; a session running
#      without hooks is otherwise indistinguishable from a protected one (the source project's
#      fast-gates hook shipped from a session that never once ran it, and two dead links sailed
#      through). This banner appearing IS the proof the hooks loaded. No banner ⇒ no hooks ⇒ run
#      gates by hand. Put that contract in your CLAUDE.md.
#
# Wire on SessionStart with matcher "startup|resume|clear|compact" — `compact` is deliberate:
# after auto-compaction the session re-receives current DERIVED state instead of trusting the
# summary's paraphrase of it.
#
# Output contract: plain text on stdout + exit 0 ⇒ added to the model's context. Keep it under a
# page; it is paid EVERY session. Everything printed is DERIVED (git, the registers, the receipt),
# never asserted — if a line is wrong, a source of record is wrong.
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$ROOT" || exit 0
# shellcheck disable=SC1091
[ -f harness.conf ] && . harness.conf

# The watchdog's output goes to /dev/null: killing its subshell leaves the `sleep` alive, and a sleep that
# still holds this hook's stdout made Claude Code wait out BOTH 8-second timers — 16 s on every session
# start against a 20 s hook timeout (found by the v1.3 cross-author matrix, 2026-10-03).
bounded() { ( "$@" ) & local p=$!; ( sleep 8; kill -9 "$p" 2>/dev/null ) >/dev/null 2>&1 & local k=$!; wait "$p" 2>/dev/null; local rc=$?; kill -9 "$k" 2>/dev/null; return $rc; }

# Which SessionStart fired (startup|resume|clear|compact) — from the payload, never guessed.
payload=""; [ -t 0 ] || payload="$(cat)"
source_evt="$(printf '%s' "$payload" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("source",""))
except Exception: print("")' 2>/dev/null)"

echo "⚡ SESSION BRIEF (scripts/hook-session-start.sh — hooks ARE loaded this session; if you never saw this banner, they are NOT: run the gates by hand)"
# AFTER COMPACTION: every fact read before this point now survives only as the summary's paraphrase,
# and a paraphrase of a quote reads exactly like knowledge — this is where "answers from memory" are
# made. Said at the one moment it is certainly true. (Generalised 2026-09-29 from a live project.)
if [ "$source_evt" = "compact" ]; then
  echo
  echo "── ⚠ CONTEXT WAS JUST COMPACTED ──"
  echo "  Everything before this point is a SUMMARY. File paths, numbers, and what a decision record says"
  echo "  are UNVERIFIED until looked up again this session. Re-read, or /consulting-the-librarian, before asserting one."
fi
echo

# The banner proves the hooks LOADED. It must not also imply they can RUN: this script needs only
# git, while the guard and both doc-gate hooks shell out to python3, and hook-postbash-docgates
# needs shasum. A missing prerequisite would otherwise leave a session that banners "protected"
# while the controls behind it are inert — the liveness proof lying in the reassuring direction.
missing=""
for t in python3 shasum; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
if [ -n "$missing" ]; then
  echo "⛔ MISSING HARNESS PREREQUISITE(S):$missing"
  echo "   The banner proves hooks loaded, NOT that they work. Without python3 the destructive-action"
  echo "   guard DENIES every Bash/Write/Edit (fail-closed, by design) and the write-time doc gates"
  echo "   are inert. Install the tool(s), or remove the affected hooks from .claude/settings.json so"
  echo "   the gap is a recorded decision instead of a silent one."
  echo
fi
# The control floor (guard-check.py): edits to the hook wiring, hook scripts and harness.conf are denied
# unless the owner LAUNCHED this session with HARNESS_ALLOW_CONTROL_EDITS=1. A lifted floor must be
# visible, or a maintenance session's permission quietly becomes every session's.
if [ "${HARNESS_ALLOW_CONTROL_EDITS:-}" = "1" ]; then
  echo "⚠ CONTROL FLOOR LIFTED for this session (HARNESS_ALLOW_CONTROL_EDITS=1): the agent may edit the"
  echo "  hook wiring, the hook scripts and harness.conf. Meant for harness maintenance only — start the"
  echo "  next ordinary session without it."
  echo
fi
[ -f "$(dirname "$0")/guard-check.py" ] || { echo "⛔ scripts/guard-check.py is MISSING: the guard will deny every Bash/Write/Edit (fail-closed). Restore it from the kit."; echo; }
echo "── git ──"
bounded git log --oneline -5 2>/dev/null | sed 's/^/  /'
dirty="$(bounded git status --porcelain 2>/dev/null)"
if [ -n "$dirty" ]; then
  echo "  DIRTY TREE: $(printf '%s\n' "$dirty" | grep -c .) path(s) — another session may be mid-work (scoped adds, separate trees):"
  printf '%s\n' "$dirty" | head -6 | sed 's/^/    /'
else
  echo "  tree clean"
fi
echo
if [ -f .gate-receipt ]; then
  echo "── gate receipt (pre-push proof) ──"
  sed 's/^/  /' .gate-receipt
  echo "  Validity = tree hash match at push; any edit since invalidates it."
  echo
fi
if [ -n "${HARNESS_BUG_REGISTER:-}" ] && [ -f "${HARNESS_BUG_REGISTER}" ]; then
  echo "── open P0/P1 (${HARNESS_BUG_REGISTER}, derived) ──"
  # ⚠ THESE PATTERNS MUST MATCH YOUR REGISTER'S ACTUAL VOCABULARY. The status match is deliberately
  # broad (☐ / open / OPEN / **OPEN** / ▶ / in progress) because the failure mode is silent: a
  # filter that matches nothing prints "none open at P0/P1" over a live P0, which reads as good
  # news. If you re-shape the register, plant a P0 row and confirm it appears HERE before trusting
  # this line — the same G7 ritual the gates get. (Found exactly this way: the original filter
  # required "**OPEN" and the shipped template writes "☐ open".)
  # SECTION-SCOPED, not whole-file: the Closed table carries the same `| ID | Sev |` shape, so a
  # whole-file grep would resurrect every historical P0 as if it were live — the brief's loudest
  # line, permanently wrong. Read only from an "Open" heading to the next heading.
  p01="$(awk '
      /^#{1,3}[[:space:]].*[Oo]pen/ { inopen=1; next }
      /^#{1,3}[[:space:]]/          { inopen=0 }
      inopen && /^\|[[:space:]]*(BUG|SEC)-[0-9]+/ && /\|[[:space:]]*\**P[01]\**[[:space:]]*\|/ { print }
    ' "$HARNESS_BUG_REGISTER" 2>/dev/null || true)"
  if [ -n "$p01" ]; then printf '%s\n' "$p01" | cut -c1-160 | sed 's/^/  /'; else echo "  none open at P0/P1"; fi
  echo
fi
ONB=""
for c in ${HARNESS_ONBOARDING:-} docs/ONBOARDING.md ONBOARDING.md; do [ -f "$c" ] && ONB="$c" && break; done
if [ -n "$ONB" ]; then
  # v1.3: "read ONBOARDING first" was an instruction, and an outside benchmark found only a small
  # minority of sessions opened it first and well under half opened it at all. So its current state is
  # INJECTED: the status and decided-vs-open sections, bounded, then what happens next. Headings are
  # matched by meaning (status / decided / next), not by number, so a renumbered template still works;
  # HARNESS_ONBOARDING (harness.conf) wins over the default locations. HTML comments — template
  # guidance, often multi-line, sometimes opened mid-line — are never injected, and lines are cut by
  # CHARACTER, not byte (a byte cut split accented letters into invalid UTF-8 in the model's context).
  # A section that cannot be found is SAID, never printed as nothing.
  # (The python reads its arguments only; no backticks in this body - macOS bash 3.2 trap, P8.)
  onb_section() { python3 - "$ONB" "$1" "$2" <<'PY' 2>/dev/null
import re, sys
path, pattern, limit = sys.argv[1], sys.argv[2], int(sys.argv[3])
text = open(path, encoding="utf-8", errors="replace").read()
text = re.sub(r"<!--.*?(-->|\Z)", "", text, flags=re.S)      # every comment, wherever it opens
out, inside = [], False
for line in text.splitlines():
    if line.startswith("## "):
        if inside:
            break
        inside = re.search(pattern, line, re.I) is not None
        continue
    if inside and line.strip():
        out.append("  " + line[:200])
print("\n".join(out[:limit]))
PY
  }
  st="$(onb_section 'status' 10)"
  dv="$(onb_section 'decided' 10)"
  nx="$(onb_section 'next' 8)"
  if [ -n "$st$dv" ]; then
    echo "── current state ($ONB — injected, so you start from it; open the file for detail) ──"
    if [ -n "$st" ]; then printf '%s\n' "$st"; else echo "  ⚠ no section headed 'status' (or only comments in it) — status could NOT be injected; read the file."; fi
    if [ -n "$dv" ]; then echo "  · decided vs open:"; printf '%s\n' "$dv"; else echo "  ⚠ no section headed 'decided' (or only comments in it) — decided-vs-open could NOT be injected; read the file."; fi
  else
    echo "⚠ $ONB has no section headed 'status' or 'decided' — the current state could NOT be injected; read the file."
  fi
  echo
  echo "── what happens next ($ONB, first lines of the next-steps section) ──"
  if [ -n "$nx" ]; then printf '%s\n' "$nx"; else echo "  ⚠ no section headed 'next' — read the file."; fi
  echo
fi
echo "This brief is DERIVED state, not a substitute for reading what your task touches. Look things up with scripts/find.sh (whole repo); broad questions → the librarian (/consulting-the-librarian)."
exit 0
