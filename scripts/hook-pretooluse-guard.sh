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

payload="$(cat)"
eval "$(printf '%s' "$payload" | python3 -c '
import json,sys,shlex
d=json.load(sys.stdin)
ti=d.get("tool_input") or {}
print("TOOL="+shlex.quote(d.get("tool_name","")))
print("CMD="+shlex.quote(ti.get("command","")))
print("FP="+shlex.quote(ti.get("file_path","")))
' 2>/dev/null)" || exit 0

deny() {
  python3 - "$1" <<'PY'
import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":sys.argv[1]}}))
PY
  exit 0
}

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
