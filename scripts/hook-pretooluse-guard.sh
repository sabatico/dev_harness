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
# shellcheck disable=SC1091
[ -f "$ROOT/harness.conf" ] && . "$ROOT/harness.conf"
PROTECTED_DBS="${HARNESS_PROTECTED_DBS:-}"
ARCHIVED="${HARNESS_ARCHIVED_PATHS:-}"
GENERATED="${HARNESS_GENERATED_PATHS:-}"

# deny() emits the decision WITHOUT python3, because the one case that must never fail silently is
# python3 being absent. Reasons are therefore constrained to JSON-safe plain text: no double quotes,
# no backslashes, no newlines. (Keep that true of every reason string below.)
deny() {
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
' 2>/dev/null)" || true

[ -n "${TOOL:-}" ] || deny \
  "GUARD CANNOT RUN: the tool payload did not parse, so the destructive-action guard could not judge this call and is denying rather than allowing blind. Re-run the command; if it repeats, the hook payload shape has changed and scripts/hook-pretooluse-guard.sh needs updating (its known-answer matrix is scripts/hook-pretooluse-guard-test.sh)."
CMD="${CMD:-}"
FP="${FP:-}"

# WRITING ABOUT A DANGEROUS COMMAND TRIPS THIS, and that is deliberate.
# The anchor below counts a backtick as a command separator, because in shell it is
# one - a backtick-quoted string substitutes and executes. A markdown code span uses
# the same character, so a sentence documenting the force-push form is, to this
# guard, indistinguishable from running it. The tempting fix is to skip heredoc
# bodies; that is a real bypass, because an interpreter fed a heredoc runs whatever
# is inside one. So the guard stays strict and the deny messages tell you to rephrase
# instead - name the flag in plain words rather than quoting the command. A guard
# that errs toward blocking prose is worth far more than one that can be slipped past
# by wrapping the command in a heredoc.
#
# Command-position prefix: start of line, or after a separator that can begin a new command.
ANCH='(^|[;&|`]|\(\s*|&&|\|\|)[[:space:]]*'

case "$TOOL" in
  Bash)
    C="$CMD"
    # Infra destroy: never without explicit owner approval in chat. Targeted toggle, never destroy.
    if printf '%s' "$C" | grep -qE "${ANCH}(terraform|tofu|pulumi)[[:space:]]+(destroy|apply[[:space:]]+[^|]*-destroy)"; then
      deny "BLOCKED (standing rule): infra destroy is never run without explicit owner approval in chat. Use a targeted toggle (apply -var enable_X=false). If the owner has approved a destroy IN THIS CONVERSATION, ask them to run it themselves or restate it for the record."
    fi
    # rm -rf against repo or home paths (temp dirs, node_modules, build output stay allowed).
    if printf '%s' "$C" | grep -qE "${ANCH}(sudo[[:space:]]+)?rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|--recursive[[:space:]]+--force)" \
       && printf '%s' "$C" | grep -qE '(\.git\b|~/|/Users/[a-z]+/(Documents|Desktop|Library)|/home/[a-z]+/)' \
       && ! printf '%s' "$C" | grep -qE '(node_modules|/tmp/|/private/tmp|scratchpad|target/|dist/|build/)'; then
      deny "BLOCKED (standing rule): rm -rf against repo or home paths needs explicit owner approval. Delete specific files by name, move them to a temp dir, or explain the blast radius in chat and get a yes first."
    fi
    # Scoped adds only: a broad add sweeps other sessions' in-flight files.
    if printf '%s' "$C" | grep -qE "${ANCH}git[[:space:]]+add[[:space:]]+(-A\b|--all\b|\.[[:space:]]*$|\.[[:space:]])"; then
      deny "BLOCKED (shared-checkout rule): git add -A/--all/. swept another session's in-flight files once. Stage by explicit path: git add <file> <file>."
    fi
    # Uncommitted work is not recoverable. checkout --/restore revert everything since last commit.
    if printf '%s' "$C" | grep -qE "${ANCH}git[[:space:]]+(checkout[[:space:]]+[^-][^;|&]*--[[:space:]]|checkout[[:space:]]+--[[:space:]]|restore[[:space:]])" \
       && ! printf '%s' "$C" | grep -qE 'git[[:space:]]+restore[[:space:]]+--staged'; then
      deny "BLOCKED (shared-checkout rule): git checkout --/git restore on a path destroys ALL uncommitted work in it, not just your change. Look first (git diff <path>), revert the specific hunk, or stash. git restore --staged (unstage-only) is allowed."
    fi
    if printf '%s' "$C" | grep -qE "${ANCH}git[[:space:]]+push[[:space:]]+[^|;&]*(--force\b|-f\b)"; then
      deny "BLOCKED: force-push rewrites shared history. If history must move, stop and put the situation to the owner."
    fi
    # Destructive SQL against protected DBs (clones named <db>_* stay allowed — the
    # verification-clone pattern: clone, test, drop the CLONE).
    if [ -n "$PROTECTED_DBS" ] && printf '%s' "$C" | grep -qE '(psql|mysql|pg_dump|pg_restore|docker[^|;&]*(postgres|mysql))'; then
      for db in $PROTECTED_DBS; do
        if printf '%s' "$C" | grep -qiE "(DROP[[:space:]]+DATABASE[[:space:]]+${db}\b|DROP[[:space:]]+SCHEMA[[:space:]]+public)" \
           || { printf '%s' "$C" | grep -qiE '\bTRUNCATE\b' && printf '%s' "$C" | grep -qE "(-d[[:space:]]*${db}\b|dbname=${db}\b|/${db}\b)" && ! printf '%s' "$C" | grep -qE "${db}_[a-z0-9_]+"; }; then
          deny "BLOCKED: destructive SQL against protected DB '${db}' (HARNESS_PROTECTED_DBS). Use a clone (CREATE DATABASE x TEMPLATE ${db}), work on the clone, drop the CLONE."
        fi
      done
    fi
    ;;
  Write|Edit)
    F="$FP"
    for g in $ARCHIVED; do
      case "$F" in *$g*) deny "BLOCKED: '$g' is ARCHIVED — history, never updated. Find the live document (the archive's banner names it)." ;; esac
    done
    for pair in $GENERATED; do
      g="${pair%%=*}"; cmd="${pair#*=}"
      case "$F" in *$g*) deny "BLOCKED: '$g' is GENERATED — never hand-edit. Regenerate: ${cmd}." ;; esac
    done
    ;;
esac
exit 0
