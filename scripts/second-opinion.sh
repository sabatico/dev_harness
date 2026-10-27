#!/usr/bin/env bash
# second-opinion.sh — get an INDEPENDENT review (design debate, adversarial read, cross-author tests)
# from whichever reviewer this project has configured — and never fail the run because one is missing.
#
# WHY: the harness asks for a second, independent pair of eyes in several places (a different
# model/agent writes the tests, a second reviewer reads the diff, an adversary attacks the design).
# The source project wired those to specific outside APIs. A kit that hard-codes vendors breaks the
# moment it is copied somewhere without those keys — so the reviewer is CONFIGURED, per project:
#
#   HARNESS_SECOND_OPINION = external | local | off        (harness.conf; default: local)
#     external  try each entry of HARNESS_EXTERNAL_REVIEWERS in order; the first that answers wins.
#               Each entry is  name=command  — the command reads the prompt on stdin and prints the
#               answer on stdout (a small wrapper around any provider's CLI or HTTP API). Keys live in
#               the environment / a gitignored .env, referenced by the WRAPPER; never in this kit.
#     local     no outside model: the caller spawns the LOCAL reviewer subagent
#               (HARNESS_LOCAL_REVIEWER, default "red-team" — dot-claude/agents/red-team.md). Honest
#               caveat: a reviewer from the same model family shares its blind spots, so this is a
#               weaker check than a different family — label it as such — but far better than none.
#     off       no second opinion; the caller does a checklist self-review and SAYS it was self-review.
#
#   HARNESS_ALSO_ASK = "name=command [arg ...] name@SECONDS=command [arg ...] ..."   (harness.conf; default: empty;
#                                                                                       only in mode external)
#     Reviewers asked IN ADDITION to the ones above, never instead of them (an extra independent view: the owner of the
#     first adopting project wanted a fast, cheap model next to the main one). Each is started at once, in parallel with
#     the chain, and its answer is printed AFTER the chain's answer in a block that names it. It never becomes "the"
#     answer, never changes the exit code, and its failure is only said on stderr. Example:
#       HARNESS_ALSO_ASK="fast=scripts/models/fast.sh"
#     Entries and arguments: the value is split on blanks; a word that begins with a NAME and "=" (NAME = a letter or
#     digit, then letters, digits, ".", "_", "-", optionally "@SECONDS") starts a new entry, and every other word is one
#     more argument of the entry before it. So "fl=scripts/x.sh --model y other=scripts/z.sh" is two entries. Limits: an
#     argument that itself looks like word=value must be written --word=value (it would start an entry); there is no
#     quoting; each word reaches the program exactly as written (no shell reads it again: no globbing, no $ expansion).
#     Time limit: every extra runs in its own process group and is stopped (TERM, then KILL 5 s later, the whole group)
#     after "@SECONDS" of its own entry, else HARNESS_ALSO_ASK_LIMIT_S (default 900 s: above a wrapper's own limit, so its
#     own limit fires first). A stopped extra is "timed out" on stderr (exit 124) and the chain's answer is not held up
#     past the limit. The limit needs python3; without it the extras are not asked.
#     When none of the primary reviewers answered (exit 3), an extra that did answer is still printed, labelled; the caller
#     still uses the local reviewer for the review of record, because an extra is not a replacement for the chain.
#
#   HARNESS_KEY_FILE (harness.conf; default .env): the file that holds the reviewers' keys. Only used to decide the
#     worktree hand-over below (scripts/lib/main-checkout.sh); this script never reads it.
#
# Exit codes (callers branch on these; none of them is a harness failure):
#   0  an external reviewer answered — the answer is on stdout; stderr names WHO answered (record it)
#   3  no external answer (mode local, or every external reviewer failed/was missing) — stdout carries
#      the instruction to use the local reviewer; the run continues
#   4  mode off
#   2  usage error
# When a reviewer fails, its last stderr lines are printed ("second-opinion: | ...") and a reviewer exit 2 is called
# "brief too big, split it" — the reason must reach the caller, not only the word "failed".
# Usage: scripts/second-opinion.sh < prompt.txt        (test: scripts/second-opinion-test.sh)
set -uo pipefail
# WHY the env -u: a git hook exports GIT_DIR (and GIT_WORK_TREE), and git would then name the hook's repository instead
# of the folder this was called in (the same rule as lib/main-checkout.sh).
ROOT="${HARNESS_ROOT_OVERRIDE:-$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# KEY-HANDLING CODE (review it): called in a git worktree that has no key file (HARNESS_KEY_FILE, default .env) while
# the main checkout has one, the whole call goes to the main checkout's OWN copy of this script (its keys, its
# harness.conf, its scripts), so worktree code never handles a key. The rule is scripts/lib/main-checkout.sh; the
# hand-over sets HARNESS_ROOT_OVERRIDE, which also stops a second hand-over. Only paths are printed, never a value.
if [ -f "$(dirname "$0")/lib/main-checkout.sh" ]; then
  # shellcheck source=scripts/lib/main-checkout.sh
  . "$(dirname "$0")/lib/main-checkout.sh"
  if main_root="$(main_checkout_for "$ROOT" scripts/second-opinion.sh)"; then
    echo "second-opinion: this worktree has no key file; the main checkout's own script takes the call ($main_root)" >&2
    exec env HARNESS_ROOT_OVERRIDE="$main_root" "$main_root/scripts/second-opinion.sh" "$@"
  fi
else
  echo "second-opinion: note — $(dirname "$0")/lib/main-checkout.sh is missing, so a worktree call is not handed to the main checkout" >&2
fi
cd "$ROOT" || exit 2
[ -f harness.conf ] && . ./harness.conf
MODE="${HARNESS_SECOND_OPINION:-local}"
LOCAL_AGENT="${HARNESS_LOCAL_REVIEWER:-red-team}"
[ -t 0 ] && { echo "usage: second-opinion.sh < prompt.txt" >&2; exit 2; }
prompt="$(mktemp "${TMPDIR:-/tmp}/so-prompt.XXXXXX")"; cat > "$prompt"
ALSO_DIR="$prompt.also"
# The extras' runners are stopped on every exit (each stops its own process group), so none outlives this script.
# shellcheck disable=SC2046  # jobs -p prints one PID per line; each must be its own argument to kill
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$prompt" "$prompt.out" "$prompt.err" "$ALSO_DIR"' EXIT

# ── the extra opinions (HARNESS_ALSO_ASK) ──
# start_also: launch every entry in the background, so the wait is the slower of (chain, extra), not their sum.
# print_also: after the primary result, print each answer that came, in the order registered, under a header naming it.
# Both are no-ops unless the mode is external and the list is not empty. A command runs exactly as a primary one does
# (bash -c, the prompt on stdin), so the same wrapper rules apply: it scans before it sends and prints no secret.
ALSO_NAMES=""
# WHY a python3 runner and not bash: macOS has no `timeout` and no `setsid`, and a bash `kill` of the wrapper would
# leave its curl running. The runner starts the command in a NEW session (its own process group), waits at most LIMIT
# seconds, then stops the whole group (TERM, then KILL after 5 s); a group member left behind after a normal exit is
# stopped too, so an extra never outlives this script. TERM or INT to the runner (Ctrl-C, the EXIT trap) stops the group.
# The runner IS the background job (no bash subshell around it), so the EXIT trap's kill reaches it; it writes its own
# exit code to RCFILE on every path.
# Usage: python3 -I -c "$ALSO_RUNNER" LIMIT RCFILE PROGRAM [ARG ...]
ALSO_RUNNER='
import os, signal, subprocess, sys, time
limit, rcfile, argv = int(sys.argv[1]), sys.argv[2], sys.argv[3:]
def done(rc):  # harness:allow-uncited python helper of the extra-reviewer runner (WHY: the comment block above ALSO_RUNNER)
    with open(rcfile, "w") as f:
        f.write("%d\n" % rc)
    sys.exit(rc)
try:
    p = subprocess.Popen(argv, start_new_session=True)
except OSError as e:
    sys.stderr.write("could not start: %s\n" % type(e).__name__)
    done(127)
def stop(sig):  # harness:allow-uncited python helper of the extra-reviewer runner (WHY: the comment block above ALSO_RUNNER)
    try:
        os.killpg(p.pid, sig)
    except (ProcessLookupError, PermissionError):
        pass
def alive():  # harness:allow-uncited python helper of the extra-reviewer runner (WHY: the comment block above ALSO_RUNNER)
    try:
        os.killpg(p.pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False
def stop_group():  # harness:allow-uncited python helper of the extra-reviewer runner (WHY: the comment block above ALSO_RUNNER)
    # TERM to the whole group; whatever is still there 5 s later (it ignored TERM) gets KILL. A member that outlived
    # its leader got only TERM before.
    stop(signal.SIGTERM)
    for _ in range(50):
        if not alive():
            return
        time.sleep(0.1)
    stop(signal.SIGKILL)
def on_signal(signum, _frame):  # harness:allow-uncited python helper of the extra-reviewer runner (WHY: the comment block above ALSO_RUNNER)
    stop_group()
    done(128 + signum)
signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)
try:
    rc = p.wait(timeout=limit)
except subprocess.TimeoutExpired:
    stop_group()
    p.wait()
    sys.stderr.write("timed out after %d s: stopped (its whole process group)\n" % limit)
    done(124)
stop_group()
done(rc if rc >= 0 else 128 - rc)
'
# also_limit_default: HARNESS_ALSO_ASK_LIMIT_S when it is 1 to 5 digits above 0, else 900 (a bad value is said once).
also_limit_default() {
  local v="${HARNESS_ALSO_ASK_LIMIT_S:-}"
  case "$v" in
    '') echo 900 ;;
    *[!0-9]*) echo "second-opinion: HARNESS_ALSO_ASK_LIMIT_S '$v' is not a whole number of seconds — 900 is used" >&2; echo 900 ;;
    *) if [ "${#v}" -gt 5 ] || [ "$((10#$v))" -le 0 ]; then
         echo "second-opinion: HARNESS_ALSO_ASK_LIMIT_S '$v' is not 1 to 99999 seconds — 900 is used" >&2; echo 900
       else echo "$((10#$v))"; fi ;;
  esac
}
# launch_also <name[@SECONDS]> <command> [arg ...]: check one parsed entry and start it in the background.
launch_also() {
  local head="$1" name limit
  shift
  local cmd="${1:-}"
  name="${head%%@*}"; limit="$ALSO_LIMIT"
  if [ "$name" != "$head" ]; then
    limit="${head#*@}"
    case "$limit" in
      ''|*[!0-9]*) echo "second-opinion: extra reviewer '$head' has a bad time limit (want name@SECONDS=command) — not asked" >&2; return 0 ;;
    esac
    if [ "${#limit}" -gt 5 ] || [ "$((10#$limit))" -le 0 ]; then
      echo "second-opinion: extra reviewer '$head' has a time limit outside 1 to 99999 s — not asked" >&2; return 0
    fi
    limit="$((10#$limit))"
  fi
  if [ -z "$name" ] || [ -z "$cmd" ]; then echo "second-opinion: extra reviewer '$head=$cmd' is malformed (want name=command) — not asked" >&2; return 0; fi
  if ! command -v "$cmd" >/dev/null 2>&1 && [ ! -x "$cmd" ]; then echo "second-opinion: extra reviewer $name is missing ($cmd) — not asked" >&2; return 0; fi
  ALSO_I=$((ALSO_I + 1))
  ALSO_NAMES="$ALSO_NAMES $ALSO_I:$name"
  python3 -I -c "$ALSO_RUNNER" "$limit" "$ALSO_DIR/$ALSO_I.rc" "$@" < "$prompt" > "$ALSO_DIR/$ALSO_I.out" 2> "$ALSO_DIR/$ALSO_I.err" &
}
# start_also: parse HARNESS_ALSO_ASK into entries (see the header) and launch each, so the wait is the slower of (chain,
# extra), not their sum. print_also: after the primary result, print each answer that came, in the order registered,
# under a header naming it. Both are no-ops unless the mode is external and the list is not empty. The prompt reaches an
# extra on stdin, as it reaches a primary one, so the same wrapper rules apply: it scans before it sends and prints no
# secret. WHY an extra runs as a word list and not through bash -c (as the primary ones do): its words were split once
# here, and a second shell reading would expand a * or a $ in an argument (found on a smoke run).
start_also() {
  local word head="" have=0
  local words=()
  [ -n "${HARNESS_ALSO_ASK:-}" ] || return 0
  command -v python3 >/dev/null 2>&1 || { echo "second-opinion: python3 is not installed, so no time limit can be kept — the extra reviewers were not asked" >&2; return 0; }
  mkdir -p "$ALSO_DIR" || { echo "second-opinion: could not create the scratch folder for the extra reviewers — they were not asked" >&2; return 0; }
  ALSO_LIMIT="$(also_limit_default)"; ALSO_I=0
  set -f  # a word such as * must stay a word, never a file list
  for word in $HARNESS_ALSO_ASK; do
    if [[ "$word" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(@[^=]*)?= ]] || [ "${word#=}" != "$word" ]; then
      [ "$have" -eq 0 ] || launch_also "$head" ${words[@]+"${words[@]}"}
      head="${word%%=*}"; words=(); [ -z "${word#*=}" ] || words=("${word#*=}"); have=1
    elif [ "$have" -eq 1 ]; then
      words+=("$word")
    else
      echo "second-opinion: extra reviewer '$word' is malformed (want name=command) — not asked" >&2
    fi
  done
  set +f
  [ "$have" -eq 0 ] || launch_also "$head" ${words[@]+"${words[@]}"}
}
print_also() {
  local item i name rc
  [ -n "$ALSO_NAMES" ] || return 0
  wait
  for item in $ALSO_NAMES; do
    i="${item%%:*}"; name="${item#*:}"
    rc="$(cat "$ALSO_DIR/$i.rc" 2>/dev/null || echo "?")"
    if [ "$rc" = "0" ] && [ -s "$ALSO_DIR/$i.out" ] && grep -q '[^[:space:]]' "$ALSO_DIR/$i.out"; then
      printf '\n===== ALSO-ASKED OPINION: %s (an independent extra view, asked next to the reviewers above; not their replacement) =====\n' "$name"
      cat "$ALSO_DIR/$i.out"
      echo "second-opinion: also asked $name: answered" >&2
    else
      if [ "$rc" = "124" ]; then echo "second-opinion: also asked $name: timed out (exit 124); its last messages:" >&2
      else echo "second-opinion: also asked $name: failed (exit $rc); its last messages:" >&2; fi
      tail -n 6 "$ALSO_DIR/$i.err" 2>/dev/null | sed 's/^/second-opinion: | /' >&2
      continue
    fi
    sed 's/^/second-opinion: | /' "$ALSO_DIR/$i.err" >&2
  done
}

use_local() {
  print_also
  echo "SECOND-OPINION: no external reviewer answered ($1)."
  echo "Use the LOCAL reviewer: spawn the '$LOCAL_AGENT' subagent with this same prompt, and label its"
  echo "findings \"same-family review\" (weaker than a different model family; stronger than none)."
  echo "second-opinion: answered by NONE — fall back to local '$LOCAL_AGENT' ($1)" >&2
  exit 3
}

case "$MODE" in
  off)   echo "SECOND-OPINION: off (harness.conf). Do a checklist self-review and say it was self-review."
         echo "second-opinion: off" >&2; exit 4 ;;
  local) use_local "mode local" ;;
  external) ;;
  *) echo "second-opinion.sh: HARNESS_SECOND_OPINION must be external|local|off (got '$MODE')" >&2; exit 2 ;;
esac

start_also
[ -n "${HARNESS_EXTERNAL_REVIEWERS:-}" ] || use_local "mode external but HARNESS_EXTERNAL_REVIEWERS is empty"
tried=()
for entry in $HARNESS_EXTERNAL_REVIEWERS; do
  name="${entry%%=*}"; cmd="${entry#*=}"
  if [ "$name" = "$entry" ] || [ -z "$cmd" ]; then tried+=("$entry:malformed"); continue; fi
  if ! command -v "${cmd%% *}" >/dev/null 2>&1 && [ ! -x "${cmd%% *}" ]; then tried+=("$name:missing"); continue; fi
  # The wrapper's stderr names the exact model that answered (provider, model, ...). It used to go to /dev/null, so a
  # review could not record WHO reviewed — the reviewing-code-quality skill requires that record. Wrappers never print
  # secrets to stderr.
  rc=0; bash -c "$cmd" < "$prompt" > "$prompt.out" 2> "$prompt.err" || rc=$?
  if [ "$rc" -eq 0 ] && [ -s "$prompt.out" ] && grep -q '[^[:space:]]' "$prompt.out"; then
    cat "$prompt.out"
    echo "second-opinion: answered by $name${tried:+ (after: ${tried[*]})}" >&2
    sed 's/^/second-opinion: | /' "$prompt.err" >&2
    print_also
    exit 0
  fi
  # The failure reason must reach the user too: the wrapper's own stderr says "brief too big - split it" (exit 2),
  # "REFUSED" on a secret (exit 5) or a timeout, and it was dropped here, so the caller saw only "every external
  # reviewer failed". The last lines are enough. Wrappers print rule NAMES and key NAMES, never a secret value.
  echo "second-opinion: $name failed (exit $rc); its last messages:" >&2
  tail -n 6 "$prompt.err" 2>/dev/null | sed 's/^/second-opinion: | /' >&2
  [ "$rc" -ne 2 ] || echo "second-opinion: $name exit 2 = brief too big, split it (or the reviewer could not start: read the messages above); nothing was sent" >&2
  tried+=("$name:failed")
done
use_local "every external reviewer failed or is missing: ${tried[*]}"
