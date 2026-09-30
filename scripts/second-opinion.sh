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
# Exit codes (callers branch on these; none of them is a harness failure):
#   0  an external reviewer answered — the answer is on stdout; stderr names WHO answered (record it)
#   3  no external answer (mode local, or every external reviewer failed/was missing) — stdout carries
#      the instruction to use the local reviewer; the run continues
#   4  mode off
#   2  usage error
# Usage: scripts/second-opinion.sh < prompt.txt        (test: scripts/second-opinion-test.sh)
set -uo pipefail
ROOT="${HARNESS_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 2
[ -f harness.conf ] && . ./harness.conf
MODE="${HARNESS_SECOND_OPINION:-local}"
LOCAL_AGENT="${HARNESS_LOCAL_REVIEWER:-red-team}"
[ -t 0 ] && { echo "usage: second-opinion.sh < prompt.txt" >&2; exit 2; }
prompt="$(mktemp "${TMPDIR:-/tmp}/so-prompt.XXXXXX")"; cat > "$prompt"
trap 'rm -f "$prompt" "$prompt.out"' EXIT

use_local() {
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

[ -n "${HARNESS_EXTERNAL_REVIEWERS:-}" ] || use_local "mode external but HARNESS_EXTERNAL_REVIEWERS is empty"
tried=()
for entry in $HARNESS_EXTERNAL_REVIEWERS; do
  name="${entry%%=*}"; cmd="${entry#*=}"
  if [ "$name" = "$entry" ] || [ -z "$cmd" ]; then tried+=("$entry:malformed"); continue; fi
  if ! command -v "${cmd%% *}" >/dev/null 2>&1 && [ ! -x "${cmd%% *}" ]; then tried+=("$name:missing"); continue; fi
  if bash -c "$cmd" < "$prompt" > "$prompt.out" 2>/dev/null && [ -s "$prompt.out" ] && grep -q '[^[:space:]]' "$prompt.out"; then
    cat "$prompt.out"
    echo "second-opinion: answered by $name${tried:+ (after: ${tried[*]})}" >&2
    exit 0
  fi
  tried+=("$name:failed")
done
use_local "every external reviewer failed or is missing: ${tried[*]}"
