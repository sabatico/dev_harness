#!/usr/bin/env bash
# hook-pretooluse-guard.sh — stop the un-undoable BEFORE it runs. The only control in the harness
# that fires before damage instead of after it.
#
# WHY: every gate fires after the fact — post-write, pre-push, nightly. Right for correctness,
# exactly wrong for destruction. The source project's history includes an infra destroy that wiped a
# whole baseline and a `git add -A` that swept another session's four in-flight files. PreToolUse is
# the one surface where "stop" precedes "done". (ci/platform-layer.md P2 has the full doctrine.)
#
# DESIGN RULES:
#   · DENY only what is (a) destructive or (b) forbidden by a standing owner rule, and put WHY plus
#     the sanctioned alternative in the reason — the model reads the reason and self-corrects.
#   · Never deny broadly. A guard that false-positives gets disabled, and then it is worse than
#     absent.
#   · Anything unmatched: exit 0 silently, no decision. Permissions still govern.
#
# ⚠ EVERY DESTRUCTIVE-COMMAND REGEX IS ANCHORED TO COMMAND POSITION (line start, or after ; & | ` or
# an opening paren). Learned live, minutes after the source project's guard hot-reloaded: its first
# real deny was the commit SHIPPING it — the commit MESSAGE named the forbidden commands. Its second
# was its own bug-fix heredoc. A guard reading the whole command string sees its own vocabulary
# quoted in messages, echoes and heredocs; with the anchor, a quoted mention can never match, only
# an actual invocation can. COROLLARY: content that legitimately contains guard vocabulary at line
# starts (e.g. this file) is written through the agent's Write/Edit tools, whose branch checks
# paths, not content. Keep hook-pretooluse-guard-test.sh green after ANY edit here.
#
# Wire in .claude/settings.json: PreToolUse, matcher "Bash|Write|Edit" (see dot-claude/).
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# The control-floor override is read from the LAUNCH environment, BEFORE harness.conf is sourced: a
# value the agent could write mid-session (harness.conf, an exported shell var in its Bash tool — which
# never reaches this process) must not be able to lift the floor. Owner sets it when starting claude.
ALLOW_CONTROL="${HARNESS_ALLOW_CONTROL_EDITS:-}"
GUARD_LOG_OVERRIDE="${HARNESS_GUARD_LOG:-}"   # test matrices point this at a temp file
# shellcheck disable=SC1091
[ -f "$ROOT/harness.conf" ] && . "$ROOT/harness.conf"
LOGDIR="${HARNESS_LOG_DIR:-.harness-logs}"
case "$LOGDIR" in /*) ;; *) LOGDIR="$ROOT/$LOGDIR" ;; esac
GUARD_LOG="${GUARD_LOG_OVERRIDE:-$LOGDIR/guard.log}"
PROTECTED_DBS="${HARNESS_PROTECTED_DBS:-}"
ARCHIVED="${HARNESS_ARCHIVED_PATHS:-}"
GENERATED="${HARNESS_GENERATED_PATHS:-}"

# deny() emits the decision WITHOUT python3, because the one case that must never fail silently is
# python3 being absent. Reasons are therefore constrained to JSON-safe plain text: no double quotes,
# no backslashes, no newlines. (Keep that true of every reason string below.)
deny() {
  # Every deny is LOGGED (rule, tool, session - never the command text, which can carry a secret), so
  # "how often does the guard fire, and on what" is a number: the same two-week review the advisories get.
  mkdir -p "$(dirname "$GUARD_LOG")" 2>/dev/null && printf '%s session=%s tool=%s rule=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "${SID:-?}" "${TOOL:-?}" "${RULE:-cannot-run}" >> "$GUARD_LOG" 2>/dev/null
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s %s"}}\n' "$1" \
    "(If you were WRITING ABOUT this command rather than running it, the guard cannot tell prose from execution: a markdown code span and a shell command substitution use the same backtick. Name the flag in plain words instead of quoting the command, rather than disabling the hook.)"
  exit 0
}

# ⛔ FAIL CLOSED. This is the only control in the harness that fires BEFORE damage, and its payload
# parser is python3. If python3 is missing or the payload will not parse, the guard cannot judge —
# and a guard that cannot judge must not wave the command through. Silent-allow is precisely the
# "reports the reassuring answer over an empty scan" failure this kit exists to unlearn (gates.md
# G1), and it is invisible: the SessionStart banner still prints, so the session LOOKS protected.
#
# So: deny, and name the two sanctioned exits in the reason. This is a broken-install state, not a
# recurring false positive — it fires once, the owner fixes it or removes the hook ON PURPOSE, and
# either way the hole stops being invisible. hook-session-start.sh reports the same fact in the
# banner so the cause is visible before the first deny lands.
command -v python3 >/dev/null 2>&1 || deny \
  "GUARD CANNOT RUN: python3 is not on PATH, so the destructive-action guard cannot parse this tool call and is denying rather than allowing blind. Fix the install (python3 is a harness prerequisite) or, if you accept an unguarded session, remove the PreToolUse hook from .claude/settings.json so the gap is recorded rather than silent."

payload="$(cat)"
eval "$(printf '%s' "$payload" | python3 -c '
import json,sys,shlex
d=json.load(sys.stdin)
ti=d.get("tool_input") or {}
print("TOOL="+shlex.quote(d.get("tool_name","")))
print("CMD="+shlex.quote(ti.get("command","")))
print("FP="+shlex.quote(ti.get("file_path","")))
import re
print("SID="+shlex.quote(re.sub(r"[^A-Za-z0-9-]","",str(d.get("session_id","?")))[:8] or "?"))
' 2>/dev/null)" || true

[ -n "${TOOL:-}" ] || deny \
  "GUARD CANNOT RUN: the tool payload did not parse, so the destructive-action guard could not judge this call and is denying rather than allowing blind. Re-run the command; if it repeats, the hook payload shape has changed and scripts/hook-pretooluse-guard.sh needs updating (its known-answer matrix is scripts/hook-pretooluse-guard-test.sh)."
CMD="${CMD:-}"
FP="${FP:-}"

# WRITING ABOUT A DANGEROUS COMMAND TRIPS THIS, and that is deliberate.
# The splitter counts a backtick as a command separator, because in shell it is
# one - a backtick-quoted string substitutes and executes. A markdown code span uses
# the same character, so a sentence documenting the force-push form is, to this
# guard, indistinguishable from running it. The tempting fix is to skip heredoc
# bodies; that is a real bypass, because an interpreter fed a heredoc runs whatever
# is inside one. So the guard stays strict and the deny messages tell you to rephrase
# instead - name the flag in plain words rather than quoting the command.
#
# THE JUDGE IS scripts/guard-check.py (2026-09-30): it splits the command into the simple commands it
# runs, strips wrappers (sudo, env, command, VAR=val, bash -c, eval), reads flags as sets, and judges
# each target. Regexes over the raw string let 14 of 14 probed disguises through (its header has the
# list). This file keeps the payload plumbing, the fail-closed contract, the protected-DB SQL check,
# the archived/generated paths, the reasons, and the deny log.
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/guard-check.py" ] || deny \
  "GUARD CANNOT RUN: scripts/guard-check.py is missing, so the destructive-action guard cannot judge this call and is denying rather than allowing blind. Restore the file from the harness kit."
RULE="$(printf '%s' "$payload" | python3 "$HERE/guard-check.py" "$ROOT" "$ALLOW_CONTROL" "${HARNESS_CONTROL_PATHS:-}" "${HARNESS_BASE_REF:-}" 2>/dev/null)" || RULE=ERROR
case "$RULE" in
  "") ;;
  ERROR) deny "GUARD CANNOT RUN: the command judge (scripts/guard-check.py) failed on this call, so the guard is denying rather than allowing blind. Re-run; if it repeats, add the command to scripts/hook-pretooluse-guard-test.sh and fix the judge." ;;
  infra-destroy) deny "BLOCKED (standing rule): infra destroy is never run without explicit owner approval in chat. Use a targeted toggle (apply -var enable_X=false). If the owner has approved a destroy IN THIS CONVERSATION, ask them to run it themselves or restate it for the record." ;;
  rm-recursive) deny "BLOCKED (standing rule): recursive delete of a home, repo-root, system or .git path needs explicit owner approval. Delete specific files by name, move them to a temp dir, or explain the blast radius in chat and get a yes first." ;;
  find-delete) deny "BLOCKED (standing rule): find with -delete or -exec rm over a home, repo-root or system path and no name filter is a recursive delete by another spelling. Add a -name or -path filter, list first with -print, or get an owner yes for the blast radius." ;;
  broad-add) deny "BLOCKED (shared-checkout rule): a broad git add (all, dot, colon-slash) swept another session's in-flight files once. Stage by explicit path: git add <file> <file>." ;;
  checkout-discard) deny "BLOCKED (shared-checkout rule): checkout or restore over a path (or the whole tree, or forced) destroys ALL uncommitted work in it, not just your change. Look first (git diff <path>), revert the specific hunk, or stash. Unstage-only restore (the staged flag alone) is allowed." ;;
  reset-hard) deny "BLOCKED (shared-checkout rule): a hard reset throws away every uncommitted change in the tree, including other sessions' work. Use git stash, or git reset --keep (refuses when it would lose local changes), or put the situation to the owner." ;;
  git-clean) deny "BLOCKED (shared-checkout rule): a forced git clean deletes every untracked file, including another session's new files. List first with the dry-run flag, then delete specific files by name." ;;
  branch-force-delete) deny "BLOCKED: force-deleting a branch can drop commits that exist nowhere else. Use the lowercase delete flag (it refuses unless merged), or put the situation to the owner." ;;
  stash-clear) deny "BLOCKED: clearing the stash discards every stashed change at once. Drop the one entry you mean by name (stash@{N}) after looking at it." ;;
  force-push) deny "BLOCKED: force-push (a force flag or a plus-prefixed refspec) rewrites shared history. If history must move, stop and put the situation to the owner." ;;
  push-delete) deny "BLOCKED: deleting the shared main branch on the remote (a delete flag or a colon refspec) removes it for everyone. Delete feature branches by name; put anything touching main to the owner." ;;
  control-edit) deny "BLOCKED (control floor): this edits the harness's own enforcement - the hook wiring in .claude/settings*.json, a scripts/hook-* or judge script, or harness.conf. An agent never switches off its own guard. Tell the owner what change you want and why; they make it by hand, or relaunch the session with HARNESS_ALLOW_CONTROL_EDITS=1 for a harness-maintenance session." ;;
  *) deny "GUARD CANNOT RUN: the judge returned an unknown rule (${RULE//[^a-z-]/}), so the guard is denying rather than allowing blind. Add a reason for it in scripts/hook-pretooluse-guard.sh." ;;
esac

case "$TOOL" in
  Bash)
    C="$CMD"
    # Destructive SQL against protected DBs (clones named <db>_* stay allowed — the
    # verification-clone pattern: clone, test, drop the CLONE).
    if [ -n "$PROTECTED_DBS" ] && printf '%s' "$C" | grep -qE '(psql|mysql|pg_dump|pg_restore|docker[^|;&]*(postgres|mysql))'; then
      for db in $PROTECTED_DBS; do
        if printf '%s' "$C" | grep -qiE "(DROP[[:space:]]+DATABASE[[:space:]]+${db}\b|DROP[[:space:]]+SCHEMA[[:space:]]+public)" \
           || { printf '%s' "$C" | grep -qiE '\bTRUNCATE\b' && printf '%s' "$C" | grep -qE "(-d[[:space:]]*${db}\b|dbname=${db}\b|/${db}\b)" && ! printf '%s' "$C" | grep -qE "${db}_[a-z0-9_]+"; }; then
          RULE=protected-db; deny "BLOCKED: destructive SQL against protected DB '${db}' (HARNESS_PROTECTED_DBS). Use a clone (CREATE DATABASE x TEMPLATE ${db}), work on the clone, drop the CLONE."
        fi
      done
    fi
    ;;
  Write|Edit)
    F="$FP"
    for g in $ARCHIVED; do
      case "$F" in *$g*) RULE=archived-path; deny "BLOCKED: '$g' is ARCHIVED — history, never updated. Find the live document (the archive's banner names it)." ;; esac
    done
    for pair in $GENERATED; do
      g="${pair%%=*}"; cmd="${pair#*=}"
      case "$F" in *$g*) RULE=generated-path; deny "BLOCKED: '$g' is GENERATED — never hand-edit. Regenerate: ${cmd}." ;; esac
    done
    ;;
esac
exit 0
