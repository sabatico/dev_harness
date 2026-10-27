#!/usr/bin/env bash
# scripts/check-the-work.sh — the "check the work" step every sub-session runs at its end, BEFORE it commits: the
# configured second opinion reads the work against the goal the lead set, the sub-session judges each finding (fixed /
# rejected with a reason / deferred to a named home), and the judged review is logged in <HARNESS_AGENT_DIR>/reviews.jsonl
# in the same commit.
#
# WHY: a sub-session's "done" used to reach the lead unchecked, and a bug hunt found P0 defects in work that was "done".
# The owner of the first adopting project asked for a goal set by the lead at the start of every sub-session and a
# check-the-work step at its end, before the commit, by a reviewer other than the builder; the sub-session then analyses
# the findings and improves the work. The goal is a GOAL block in the brief (GOAL / PROOF / LIMIT), NOT Claude Code's
# built-in /goal: its judge is a small fast model, and the kit's model floor bans such models from the dev process.
#
# The reviewer is the CONFIGURED second opinion (scripts/second-opinion.sh; harness.conf HARNESS_SECOND_OPINION):
#   external  an outside reviewer answered (exit 0 of second-opinion.sh): its answer is stored and printed. Keeping
#             secrets out of what is sent is the WRAPPER's job (CLAUDE.md: never send secrets to an outside model);
#   local     no outside answer (exit 3): the sub-session spawns the local reviewer agent with the prompt file this
#             script wrote, then records its answer (`record`); labelled "same-family review";
#   off       (exit 4) a self-review, labelled as such.
#
# Usage (from the sub-session's worktree; state lives in the worktree's git dir, never in the tree):
#   scripts/check-the-work.sh run    --goal <file> [--summary <file>] [--base <ref>] [--vote] [--lead-ok "<words>"]
#         builds the review prompt (the GOAL block, the sub-session's own summary of what it did and claims, the change
#         list and the diff) and asks the reviewer. ROUND 1 shows the diff of committed + staged + unstaged work since the
#         merge base with the base ref; ROUND 2 and later show only the change since the tree the previous round's
#         reviewer saw, plus that round's findings and judgements (so a judged finding is not raised again), plus the full
#         diff of the files the previous round's reviewer did not see (cut for size) that still differ from the merge base.
#         BASE REF: --base <ref>, else CHECK_THE_WORK_BASE, else the kit's HARNESS_BASE_REF (default origin/main) and, if
#         that does not resolve, its local branch name (main) — the first that is a commit; the chosen ref is printed on
#         stderr. WHY the fallback: a sub-session branches off the lead's local branch, which an offline checkout may be
#         the only copy of.
#         Exit 0 = an answer is stored and printed; 3 = no usable outside answer (none, empty, or without the VERDICT
#         line): follow the printed instruction (local reviewer agent, then `record`); 4 = mode off (self-review, then
#         `record`); 2 = usage, nothing changed since the last round, or the brief is too big even after the diff was
#         cut (split the work); 1 = ROUND CAP: CHECK_THE_WORK_MAX_ROUNDS (default 3) judged rounds are logged for this
#         branch — stop and ask the lead; only the lead's yes, quoted with --lead-ok, opens one more round; 5 = vote
#         mode only: the pre-send secret scan refused the prompt, nothing was sent; 6 = vote mode only: no scan command
#         is configured (HARNESS_REVIEW_SCAN), so nothing was sent (fail closed).
#   scripts/check-the-work.sh record --answer <file> --reviewer <name>
#         stores an answer that came from the local agent or a self-review (mode local/off). It stays bound to the tree
#         `run` prepared the prompt from (what the reviewer saw); a later edit shows as changed_after_review at `judge`.
#         In a vote round it is the local agent's VOTE: stored beside the outside votes, then the votes are tallied.
#   scripts/check-the-work.sh tally
#         vote mode: counts the votes stored so far (e.g. when the local agent cannot run) into the answer to judge.
#   scripts/check-the-work.sh judge  --judgement <file>
#         the sub-session's analysis: one line per finding id of the answer, `F<n>: FIXED <how>`, `F<n>: REJECTED <why>`
#         or `F<n>: DEFERRED <where it is recorded>`; when the reviewer's GOAL verdict is not MET, also
#         `GOAL: FIXED <the proof now shown>` or `GOAL: REJECTED <why>`. Refuses a judgement that misses one or uses
#         another word. TAGS: a finding tagged `nit` needs no judgement (it is logged under "nits") — but a P0 or P1 can
#         never be a nit, whatever the line says (scripts/lib/review_tally.py); a finding tagged `pre-existing` goes to the
#         bug register, not to this change: it is REJECTED <why it is not real>, or FIXED/DEFERRED with the register row id
#         (<HARNESS_BUG_PREFIX>-nnn or SEC-nnn) in the reason, and that row must exist in a register file
#         (CHECK_THE_WORK_REGISTERS). An untagged finding counts as important.
#         Appends the judged review to <HARNESS_AGENT_DIR>/reviews.jsonl; commit that file WITH the work.
#   scripts/check-the-work.sh verify [--branch <name>] [--base <ref>]   (base: --base, CHECK_THE_WORK_BASE, HARNESS_BASE_REF)
#         for the lead at integration (before the merge): exit 0 when the branch's commits since the merge base with
#         the base ref add a judged review row for that branch; 1 when none (the step was skipped), or when a row of a
#         round above the cap (the LEAD's CHECK_THE_WORK_MAX_ROUNDS, default 3) has no lead_ok; 3 when it cannot tell
#         (including a missing ENFORCING hook, below).
# Reviewer answer format asked for (scripts/lib/review-prompt-header.txt): a `VERDICT:` line, a `GOAL:` line (MET / NOT MET
# / CANNOT TELL), and one line per finding starting `F1`, `F2`, ... with a severity and a tag. Findings are read by
# scripts/lib/review_tally.py only (the judge and the vote read the same way).
#
# VOTE MODE (`run --vote`, or CHECK_THE_WORK_VOTE=on, or HARNESS_REVIEW_VOTE=on in harness.conf; OFF by default because each
# round then makes several outside calls the owner must approve): the outside voters (HARNESS_REVIEW_VOTERS =
# "name=command ...", empty by default) answer in parallel after ONE pre-send secret scan of the prompt (the command
# HARNESS_REVIEW_SCAN, which reads the prompt on stdin: exit 0 = clean, 5 = refused, anything else = could not run); the local
# reviewer agent is the last voter (`record`). A finding is kept only when 2 voters name the same place
# (scripts/lib/review_tally.py); the others are logged as UNCONFIRMED and need no judgement. With one voter only there
# is no vote: every finding is kept and the row says vote_quorum false. WHY no default scan: a vote sends the prompt to
# outside commands, and "no scanner configured" must never read as "nothing secret in it" — so vote on without a scan
# command refuses to send (exit 6).
#
# Env: CHECK_THE_WORK_DIFF_KB (default 110) — the diff part of the prompt; above it, files are cut whole and named, so
#   the reviewer knows what it did not see (an outside wrapper may refuse a brief over its own size limit).
#   CHECK_THE_WORK_MAX_ROUNDS (default 3, 1 to 99) · CHECK_THE_WORK_VOTE (on|off) · CHECK_THE_WORK_VOTERS (overrides
#   HARNESS_REVIEW_VOTERS; a relative command runs from the checkout root; a command is one word: no arguments, no spaces
#   in its path) · CHECK_THE_WORK_LOCAL_VOTER (default <HARNESS_LOCAL_REVIEWER, red-team>-local) ·
#   CHECK_THE_WORK_VOTE_WINDOW (default 15 lines) · CHECK_THE_WORK_SCAN (overrides HARNESS_REVIEW_SCAN) ·
#   CHECK_THE_WORK_BASE (the base ref) · CHECK_THE_WORK_REGISTERS (default the bug register, its archive and the security
#   register: HARNESS_BUG_REGISTER, HARNESS_BUG_ARCHIVE, HARNESS_SEC_REGISTER) · CHECK_THE_WORK_LIB (default the lib folder
#   next to this script) · CHECK_THE_WORK_HOOKS (the hook folder below; default check-the-work.d next to this script) ·
#   CHECK_THE_WORK_REVIEW_LOGS (the review logs left out of the reviewed tree, the change list and the diff: REVIEW_LOGS
#   below; default reviews.jsonl and criterion.jsonl in HARNESS_AGENT_DIR, default docs/agents) ·
#   CHECK_THE_WORK_SECOND_OPINION (the reviewer command; default scripts/second-opinion.sh; the tests use it).
#   CHECK_THE_WORK_LAST (optional) — space-separated path globs shown last, after the tests, with the data files
#   (archive/ fixtures/ fixture/ testdata/ runs/ folders, *.answer.md, *.jsonl) and the machine-written lists (sbom/*,
#   package-lock.json, packages.lock.json, *.lockfile, go.sum): files a reviewer learns least from, cut first.
#
# HOOK POINT (WHY: other checks — a FINAL-report contract check, a success-criterion guard — plug in as their own scripts
# and add no lines here). Each EXECUTABLE `*.sh` in the folder CHECK_THE_WORK_HOOKS (default check-the-work.d beside this
# script) runs in name order as `<hook> <stage>`, from the checkout root, with the env
# CTW_STAGE (judge | verify), CTW_ROOT (the checkout), CTW_STATE (the state folder: goal.md, answer.md, prompt.md ...,
# an ABSOLUTE path), CTW_BRANCH, CTW_LOG (the review log, an ABSOLUTE path), CTW_JUDGEMENT (the judgement file; empty at verify) and CTW_BASE (the base this step resolved; empty when none). No folder, or no
# executable `*.sh` in it, means nothing runs and nothing is said — EXCEPT the two enforcing hooks (EXPECTED_HOOKS) in
# the default folder of the checkout: missing or not executable there exits 3. Stage `judge`: the hooks run AFTER the judgement
# passed every check and BEFORE the row is written, so a hook that stops leaves the log untouched. Stage `verify`: they
# run after "verify OK" was printed (a branch that already failed is not asked again). A hook's exit: 0 or 4 = go on;
# 3 = it could not run, the step stops; any other non-zero = it stopped the step; a stop makes this script exit 1 and
# says which hook. All hooks are skipped while CTW_SELFPROOF_RUNNING is set: the self-proof's inner verify runs must
# not depend on whatever hooks happen to sit in a checkout.
# Tests: scripts/check-the-work-test.sh (cross-author). Design: docs/ci/review-step.md.
set -uo pipefail

# This script and its lib folder as ABSOLUTE paths, taken before the cd below: a relative $0 would name nothing after it.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
LIB="${CHECK_THE_WORK_LIB:-$(dirname "$SELF")/lib}"
ROOT="${CHECK_THE_WORK_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}" || ROOT=""
[ -n "$ROOT" ] || { echo "check-the-work: not inside a git work tree" >&2; exit 3; }
cd "$ROOT" || exit 3
# The project's knobs (HARNESS_AGENT_DIR, HARNESS_BUG_REGISTER, HARNESS_REVIEW_*, HARNESS_BASE_REF ...), read the way
# scripts/second-opinion.sh reads them. harness.conf only assigns HARNESS_* names, so it cannot clobber this script's variables.
# shellcheck disable=SC1091
[ -f ./harness.conf ] && . ./harness.conf
GITDIR="$(git rev-parse --git-dir)"
STATE="$GITDIR/check-the-work"
AGENT_DIR="${HARNESS_AGENT_DIR:-docs/agents}"
LOG="$AGENT_DIR/reviews.jsonl"
LOCAL_AGENT="${HARNESS_LOCAL_REVIEWER:-red-team}"
BUG_PREFIX="${HARNESS_BUG_PREFIX:-BUG}"
case "$BUG_PREFIX" in [A-Za-z]*) case "$BUG_PREFIX" in *[!A-Za-z0-9_]*) BUG_PREFIX="" ;; esac ;; *) BUG_PREFIX="" ;; esac
[ -n "$BUG_PREFIX" ] || { echo "check-the-work: HARNESS_BUG_PREFIX must be letters, digits or _, starting with a letter" >&2; exit 3; }
# The register row-id prefixes a pre-existing finding may name (space-separated): the bug prefix and SEC.
ID_PREFIXES="$BUG_PREFIX SEC"
# The review logs: every file this step (or one of its hooks) writes AFTER a review, left out of the reviewed tree, the
# prompt's change list and the diff. WHY (from the first adopting project): a log written after the review would make every judged review
# read as changed_after_review, and earlier log rows would reach the reviewer in the prompt. LOG (what `judge` appends to
# and `verify` reads) must be in the list; criterion.jsonl is written by the hook
# check-the-work.d/10-success-criterion.sh and committed with the work. Space-separated, repo-relative, no spaces in a name.
# CHECK_THE_WORK_REVIEW_LOGS overrides it (tests).
REVIEW_LOGS="${CHECK_THE_WORK_REVIEW_LOGS:-$AGENT_DIR/reviews.jsonl $AGENT_DIR/criterion.jsonl}"
# The same list as git pathspec excludes (bash 3.2: no mapfile; "${LOG_EXCLUDES[@]+...}" is safe when the list is empty).
LOG_EXCLUDES=()
for _log in $REVIEW_LOGS; do LOG_EXCLUDES+=(":!$_log"); done
unset _log
SECOND_OPINION="${CHECK_THE_WORK_SECOND_OPINION:-scripts/second-opinion.sh}"
# The enforcing hooks (names in the default hook folder) whose absence run_hooks reports instead of skipping.
EXPECTED_HOOKS="10-success-criterion.sh 20-report-contract.sh"

die() { echo "check-the-work: $1" >&2; exit "${2:-2}"; }
# Names as they are: with core.quotepath on, git prints a non-ASCII name as "\303\251.txt" in quotes, which matches no
# file, so that file was neither shown nor named as cut (cross-author finding 2026-10-18).
gitn() { git -c core.quotepath=false "$@"; }
branch_name() { git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "detached-$(git rev-parse --short HEAD)"; }

# run_hooks <stage> <branch> <judgement file or empty> — the HOOK POINT of the header. Exits 1 itself when a hook stops
# the step, so a caller cannot forget to check. WHY the exit text names the hook and the stage: a stop is read by a
# sub-session that did not write the hook and has only this line to go on.
# Stdin is /dev/null: a hook that reads stdin would otherwise hang judge/verify when it is run from a terminal.
run_hooks() {
  [ -z "${CTW_SELFPROOF_RUNNING:-}" ] || return 0
  local dir h name rc abs_state
  case "$STATE" in /*) abs_state="$STATE" ;; *) abs_state="$ROOT/$STATE" ;; esac
  dir="${CHECK_THE_WORK_HOOKS:-$(dirname "$SELF")/check-the-work.d}"
  # The two enforcing hooks must not stop running without a sign. With the DEFAULT folder
  # (no CHECK_THE_WORK_HOOKS: an override is the caller's own choice, and the matrix uses it), when the folder is the
  # checkout's own scripts/check-the-work.d OR holds at least one expected hook, every expected hook must be there and
  # executable, or the step exits 3 (could not run) and says which. A folder that holds none of them and is not the
  # checkout's own (a copy of this script elsewhere) is still "no hooks, nothing said". LIMIT: a script copy outside the
  # checkout whose folder lost ALL expected hooks reads as that copy case; CTW_SELFPROOF_RUNNING and CHECK_THE_WORK_HOOKS
  # are env switches of the caller, as before.
  if [ -z "${CHECK_THE_WORK_HOOKS:-}" ]; then
    local armed=0 miss="" e sd rr
    # Compared as PHYSICAL paths (check-the-work F1 2026-10-26): SELF is a logical path, ROOT comes from git; a symlinked
    # checkout path must not make the same folder read as another one.
    sd="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd -P)"; rr="$(cd "$ROOT" 2>/dev/null && pwd -P)"
    [ -z "$sd" ] || [ "$sd" != "$rr/scripts" ] || armed=1
    for e in $EXPECTED_HOOKS; do [ ! -e "$dir/$e" ] || armed=1; done
    if [ "$armed" -eq 1 ]; then
      for e in $EXPECTED_HOOKS; do { [ -f "$dir/$e" ] && [ -x "$dir/$e" ]; } || miss="$miss $e"; done
      if [ -n "$miss" ]; then
        echo "check-the-work: the enforcing hook(s)$miss are missing or not executable in $dir — the $1 step cannot run (exit 3)" >&2
        exit 3
      fi
    fi
  fi
  [ -d "$dir" ] || return 0
  for h in "$dir"/*.sh; do
    { [ -f "$h" ] && [ -x "$h" ]; } || continue
    name="$(basename "$h")"
    # STATE and LOG as ABSOLUTE paths (cross-author finding 2026-10-24: in a normal checkout STATE is ".git/check-the-work",
    # and a hook that changes directory lost both).
    # CTW_BASE: the base this step resolved (empty when it resolved none), so a hook never guesses "main" on a master repo.
    CTW_STAGE="$1" CTW_ROOT="$ROOT" CTW_STATE="$abs_state" CTW_BRANCH="$2" CTW_LOG="$ROOT/$LOG" CTW_JUDGEMENT="$3" CTW_BASE="${base:-}" "$h" "$1" </dev/null
    rc=$?
    case "$rc" in
      0|4) ;;
      3) echo "check-the-work: hook $name could not run (exit 3) — the $1 step stops here" >&2; exit 1 ;;
      *) echo "check-the-work: hook $name stopped the $1 step (exit $rc) — read its messages above" >&2; exit 1 ;;
    esac
  done
  return 0
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
goal="" summary="" base="" answer="" reviewer="" judgement="" vbranch="" vote_flag=0 lead_ok=""
while [ $# -gt 0 ]; do
  case "$1" in
    --vote) vote_flag=1; shift ;;
    --lead-ok) lead_ok="${2-}"; shift 2 || die "--lead-ok needs the lead's words, quoted" ;;
    --goal) goal="${2-}"; shift 2 || die "--goal needs a file" ;;
    --summary) summary="${2-}"; shift 2 || die "--summary needs a file" ;;
    --base) base="${2-}"; shift 2 || die "--base needs a ref" ;;
    --answer) answer="${2-}"; shift 2 || die "--answer needs a file" ;;
    --reviewer) reviewer="${2-}"; shift 2 || die "--reviewer needs a name" ;;
    --judgement) judgement="${2-}"; shift 2 || die "--judgement needs a file" ;;
    --branch) vbranch="${2-}"; shift 2 || die "--branch needs a branch name" ;;
    *) die "unknown argument: $1 (see the header of scripts/check-the-work.sh)" ;;
  esac
done

# resolve_base: --base wins, then CHECK_THE_WORK_BASE, else the first of HARNESS_BASE_REF and its local branch name (the part
# after the first "/", so origin/main also tries main) that is a commit. The choice is said on stderr, never silent.
resolve_base() {
  [ -z "$base" ] || return 0
  local want c
  if [ -n "${CHECK_THE_WORK_BASE:-}" ]; then base="$CHECK_THE_WORK_BASE"; return 0; fi
  want="${HARNESS_BASE_REF:-origin/main}"
  for c in "$want" "${want#*/}"; do
    if git rev-parse --verify --quiet "$c^{commit}" >/dev/null 2>&1; then
      base="$c"; echo "check-the-work: base ref = $base (derived from HARNESS_BASE_REF=$want; --base or CHECK_THE_WORK_BASE overrides)" >&2; return 0
    fi
  done
  base="$want"   # merge_base names it in its error
}
merge_base() {
  git rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "base '$base' is not a commit" 2
  git merge-base "$base" HEAD 2>/dev/null || die "no merge base between '$base' and HEAD" 2
}

# The tree as it will be committed if everything now in the work tree is added: so the review is bound to the exact
# content it read (a temporary index; the real index is never touched).
work_tree_id() {
  local idx; idx="$(mktemp "${TMPDIR:-/tmp}/ctw-index.XXXXXX")"
  cp "$GITDIR/index" "$idx" 2>/dev/null || :
  GIT_INDEX_FILE="$idx" git add -A -- . ${LOG_EXCLUDES[@]+"${LOG_EXCLUDES[@]}"} >/dev/null 2>&1
  GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null
  rm -f "$idx"
}

# The diff of one file for this round. ROUND 1 (DIFF_TO empty): the merge base against the work tree, plus an untracked
# file in full. ROUND 2+: the tree the previous reviewer saw against the tree now (both trees hold untracked files too).
diff_of() {
  if [ -n "$DIFF_TO" ]; then gitn diff "$DIFF_FROM" "$DIFF_TO" -- "$1"; return; fi
  gitn diff "$DIFF_FROM" -- "$1"; [ -f "$1" ] && ! git ls-files --error-unmatch -- "$1" >/dev/null 2>&1 && gitn diff --no-index /dev/null "$1"
}
changed_files() {
  if [ -n "$DIFF_TO" ]; then gitn diff --name-only "$DIFF_FROM" "$DIFF_TO" -- . ${LOG_EXCLUDES[@]+"${LOG_EXCLUDES[@]}"}; return; fi
  gitn diff --name-only "$DIFF_FROM" -- . ${LOG_EXCLUDES[@]+"${LOG_EXCLUDES[@]}"}; gitn ls-files --others --exclude-standard -- . ${LOG_EXCLUDES[@]+"${LOG_EXCLUDES[@]}"}
}

# file_class <path>: the order class of one changed path in the review brief — 0 implementation, 1 test, 2 data and
# machine-written files. ONE classifier for the whole pipeline (order_files below calls it).
# WHY (check-the-work F1 2026-10-24, merged with a later run where a lockfile did the same): the size budget is spent in this order
# and the rest is cut, so what matters most goes first. On its first run a long test file used the whole budget and the
# script under review was cut (found by the first adversary review). On another run a 55 KB package-lock.json,
# sorted first by name, cut the code under review. On the second run of this script, data files (an eval archive,
# answers, logs) came BEFORE the implementation, because the sort ran in the user's locale and put
# "scripts/tool/archive/..." ahead of "scripts/tool.py". A reviewer learns least from class 2.
# Class 2 is: a path with an archive/, fixtures/, fixture/, testdata/ or runs/ folder anywhere in it, or a name ending
# .answer.md or .jsonl (checked FIRST, so a fixture inside tests/ is data); the machine-written package lists (sbom/*,
# package-lock.json, packages.lock.json, *.lockfile, go.sum); and any path matching a glob in CHECK_THE_WORK_LAST
# (shell patterns on the repo-relative path). Class 1, a "test file": a name with -test. / _test. / Test. / Tests. in it
# or a path under a test/, tests/ or Tests/ folder.
file_class() {
  local p="$1" g
  case "$p" in
    archive/*|*/archive/*|fixtures/*|*/fixtures/*|fixture/*|*/fixture/*|testdata/*|*/testdata/*|runs/*|*/runs/*|*.answer.md|*.jsonl) echo 2; return ;;
    sbom/*|*package-lock.json|*packages.lock.json|*.lockfile|go.sum) echo 2; return ;;
  esac
  for g in ${CHECK_THE_WORK_LAST:-}; do
    # shellcheck disable=SC2254  # $g is a glob on purpose (CHECK_THE_WORK_LAST holds patterns)
    case "$p" in $g) echo 2; return ;; esac
  done
  case "$p" in
    tests/*|test/*|Tests/*|*/tests/*|*/test/*|*/Tests/*|*-test.*|*_test.*|*Test.*|*Tests.*) echo 1 ;;
    *) echo 0 ;;
  esac
}
# order_files: the changed file names on stdin -> the order they are shown in (file_class, then the byte order), unique,
# one per line. LC_ALL=C on EVERY sort here, so the order is the same on every machine.
# WHY `set -f` in the command substitution: file_class walks CHECK_THE_WORK_LAST unquoted, so a glob such as `gen/*`
# was expanded against the current folder's files instead of matched as a pattern. The substitution is a subshell, so
# globbing stays on for the rest of the script, and file_class's body stays byte-identical to the success-criterion
# hook's copy (10-success-criterion.sh sets -f itself; its matrix compares the two bodies).
order_files() {
  LC_ALL=C sort -u \
    | while IFS= read -r p; do printf '%s\t%s\n' "$(set -f; file_class "$p")" "$p"; done \
    | LC_ALL=C sort -s -t "$(printf '\t')" -k1,1 | cut -f2-
}
# The diff of one file since the merge base (the round-1 form of diff_of), whatever this round's DIFF_FROM / DIFF_TO.
# with_base <command...>: runs the command as round 1 would (DIFF_FROM = the merge base, DIFF_TO empty), then puts this
# round's values back. Not a subshell on purpose: the globals are plain variables of this script.
with_base() {
  local keep_from="$DIFF_FROM" keep_to="$DIFF_TO" rc
  DIFF_FROM="$mb"; DIFF_TO=""
  "$@"; rc=$?
  DIFF_FROM="$keep_from"; DIFF_TO="$keep_to"
  return "$rc"
}
full_diff_of() { with_base diff_of "$1"; }

# build_prompt <out> [<earlier-rounds file>]: the shared reviewer instructions (scripts/lib/review-prompt-header.txt,
# the one text every reviewer gets), the goal, the summary, the change list and the diff
# of this round (DIFF_FROM / DIFF_TO, set by `run`).
build_prompt() {
  local out="$1" earlier="${2:-}" kb="${CHECK_THE_WORK_DIFF_KB:-110}" budget used=0 f size cut=()
  case "$kb" in ''|*[!0-9]*) die "CHECK_THE_WORK_DIFF_KB must be a whole number (got '$kb')" ;; esac
  budget=$(( 10#$kb * 1024 ))
  {
    cat "$LIB/review-prompt-header.txt"
    echo "----------------------------------------------------------------------------------------------------"
    echo "## The goal the lead set (GOAL block of the brief)"; cat "$goal"; echo
    if [ -n "$summary" ]; then echo "## The sub-session's own summary and claims"; cat "$summary"; echo; fi
    if [ -n "$earlier" ] && [ -s "$earlier" ]; then
      if [ -n "$DIFF_TO" ]; then echo "## Review round $ROUND: ONLY the change since the tree the round-$((ROUND - 1)) reviewer saw"
      else echo "## Review round $ROUND (the whole work again: the tree of round $((ROUND - 1)) is not in this repository)"; fi
      echo "Earlier rounds reviewed the rest of the work; their findings were judged as below. Do not raise a judged"
      echo "finding again unless the change below makes it wrong again (then say which one, and why)."
      cat "$earlier"; echo
    fi
    if [ -n "$DIFF_TO" ]; then
      echo "## Change list since round $((ROUND - 1)) (tree $(printf '%.10s' "$DIFF_FROM"))"
      echo "(The review logs this step and its hooks write to are left out on purpose: they hold earlier reviews, not this work.)"
      gitn diff --stat "$DIFF_FROM" "$DIFF_TO" -- . ${LOG_EXCLUDES[@]+"${LOG_EXCLUDES[@]}"}
    else
      echo "## Change list since $(git rev-parse --short "$DIFF_FROM") (committed, staged and not yet committed)"
      echo "(The review logs this step and its hooks write to are left out on purpose: they hold earlier reviews, not this work.)"
      gitn diff --stat "$DIFF_FROM" -- . ${LOG_EXCLUDES[@]+"${LOG_EXCLUDES[@]}"}
      gitn ls-files --others --exclude-standard -- . ${LOG_EXCLUDES[@]+"${LOG_EXCLUDES[@]}"} | sed 's/^/new, untracked: /'
    fi
    echo
    echo "## The diff"
  } >"$out"
  # The files carried over from the previous round (fix 5): in a delta round, the files the previous reviewer never saw
  # (that row's not_shown_to_reviewer, handed over by earlier_rounds in $STATE/carried.txt) that still differ from the
  # merge base. They are shown in full AFTER the delta diff (below), so the delta loop leaves them out: their full diff
  # holds the delta too. carried_nl is the same list as one newline-joined string for the membership test.
  local carried=() carried_nl="" mb_base="${mb:-}"
  if [ -n "$DIFF_TO" ] && [ -n "$mb_base" ] && [ -s "$STATE/carried.txt" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      carried+=("$f"); carried_nl="$carried_nl$f"$'\n'
    done < <( with_base changed_files | order_files | grep -Fx -f "$STATE/carried.txt" )
  fi
  # The review logs (REVIEW_LOGS) are never sent, tracked or not (an untracked first log would carry earlier answers to the reviewer).
  # Order: order_files (implementation, then tests, then data and machine-written files: file_class).
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case $'\n'"$carried_nl" in *$'\n'"$f"$'\n'*) continue ;; esac
    size="$(diff_of "$f" 2>/dev/null | wc -c | tr -d ' ')"
    if [ $((used + size)) -gt "$budget" ]; then cut+=("$f"); continue; fi
    diff_of "$f" >>"$out" 2>/dev/null
    used=$((used + size))
  done < <( changed_files | order_files )
  if [ "${#carried[@]}" -gt 0 ]; then
    # lead finding 2026-10-24: a file cut for size in round N was never read, and the next rounds showed only the change
    # since the tree round N saw, so it stayed unseen for ever. The size budget is the same one (used carries on); a
    # file that does not fit is cut again and named again in NOT SHOWN below.
    { echo; echo "## Carried over: files the round-$((ROUND - 1)) reviewer did not see (cut for size)"
      echo "(Their FULL diff since the merge base: an earlier round could not show them. Later rounds show only the change since the previous round.)"; } >>"$out"
    # The files that changed in THIS round, as a newline-joined string for the membership test below.
    local round_nl="" dsize
    while IFS= read -r f; do [ -n "$f" ] && round_nl="$round_nl$f"$'\n'; done < <( changed_files )
    for f in "${carried[@]}"; do
      size="$(full_diff_of "$f" 2>/dev/null | wc -c | tr -d ' ')"
      if [ $((used + size)) -gt "$budget" ]; then
        # check-the-work round 2 F2 2026-10-24: a carried file that also changed in this round is skipped in the delta
        # loop above (its full diff holds the delta), so cutting the full diff whole lost this round's small change
        # even when that change alone fits. Show the delta instead, with a note, and keep the file in the cut list so
        # not_shown_to_reviewer still names it and the next round carries it again (its earlier part is still unseen).
        case $'\n'"$round_nl" in
          *$'\n'"$f"$'\n'*)
            dsize="$(diff_of "$f" 2>/dev/null | wc -c | tr -d ' ')"
            if [ "$dsize" -gt 0 ] && [ $((used + dsize)) -le "$budget" ]; then
              echo "(only this round's change of $f is shown; its earlier diff was cut for size)" >>"$out"
              diff_of "$f" >>"$out" 2>/dev/null
              used=$((used + dsize))
            fi ;;
        esac
        cut+=("$f"); continue
      fi
      full_diff_of "$f" >>"$out" 2>/dev/null
      used=$((used + size))
    done
  fi
  if [ "${#cut[@]}" -gt 0 ]; then
    { echo; echo "## NOT SHOWN (cut to keep the brief under the reviewer's size limit; say in UNSEEN that you did not see them)"; printf '%s\n' "${cut[@]}"; } >>"$out"
  fi
  # ${cut[@]+...}: bash 3.2 (stock macOS) calls an empty array unbound under set -u.
  printf '%s\n' ${cut[@]+"${cut[@]}"} >"$STATE/cut.txt"
}

# earlier_rounds <merge base> <branch>: the rows of THIS branch added to the review log since the merge base (the work
# tree's log, so a judged row not yet committed counts too). Prints "<count>\t<the tree the last one reviewed>" and
# writes the earlier findings and their judgements to $STATE/earlier.md for the next round's prompt, and the previous
# row's not_shown_to_reviewer list to $STATE/carried.txt (one name per line; empty when none) for its "carried over" part.
# WHY from the log and not a counter in the state folder: the log is what the lead reads and `verify` checks, so the
# round count cannot drift from the record (a counter could be deleted with the state folder and reset the cap).
earlier_rounds() {
  { git show "$1:$LOG" 2>/dev/null || :; } >"$STATE/log-at-base"
  CTW_BRANCH="$2" CTW_BASELOG="$STATE/log-at-base" CTW_LOG="$LOG" CTW_OUT="$STATE/earlier.md" CTW_CARRY="$STATE/carried.txt" python3 -I -c '
import json, os
base = set(open(os.environ["CTW_BASELOG"], encoding="utf-8", errors="replace").read().splitlines())
rows = []
if os.path.exists(os.environ["CTW_LOG"]):
    for line in open(os.environ["CTW_LOG"], encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if not line.strip() or line in base:
            continue
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if isinstance(r, dict) and r.get("branch") == os.environ["CTW_BRANCH"]:
            rows.append(r)
with open(os.environ["CTW_OUT"], "w", encoding="utf-8") as f:
    for n, r in enumerate(rows, 1):
        f.write("Round %d (%s): verdict %s; goal: %s\n" % (n, r.get("reviewer"), r.get("verdict"), str(r.get("goal_verdict"))[:160]))
        judged = r.get("judged") if isinstance(r.get("judged"), dict) else {}
        for i in (r.get("findings") or []) + (r.get("nits") or []):
            d = judged.get(i) if isinstance(judged.get(i), dict) else {}
            f.write("  %s: %s %s\n" % (i, d.get("decision", "(nit, not judged)"), str(d.get("reason", ""))[:200]))
# The files the reviewer of the LAST round did not see, for build_prompt (lead finding 2026-10-24: they stayed unseen for ever).
ns = rows[-1].get("not_shown_to_reviewer") if rows else None
with open(os.environ["CTW_CARRY"], "w", encoding="utf-8") as f:
    for p in (ns if isinstance(ns, list) else []):
        if isinstance(p, str) and p.strip() and "\n" not in p:
            f.write(p + "\n")
tree = str(rows[-1].get("reviewed_tree") or "") if rows else ""
print("%d\t%s" % (len(rows), tree))
'
}

save_state() { # save_state <key> <value>
  printf '%s' "$2" >"$STATE/$1"
}
state() { cat "$STATE/$1" 2>/dev/null; }

# ── SELF-PROOF of the one detector here, `verify` (a gate added without a self-proof is a gate nobody has seen fail) ──────
# WHY: `verify` is the lead's merge check, and its detector (a COMPLETE judged row for the branch, added since the merge
# base) can rot: a renamed log path, a branch match or a complete() rule that drifts would answer "verify OK" for a
# branch that skipped the step, or FAIL for every branch (scripts rule 1; docs/ci/gates.md G1/G7). So before it judges
# a real branch, and on a run with no command (how a gate self-proof runner can call every check script), it runs
# THIS script's own `verify` on a throwaway repository with known answers: a branch that added a complete judged row
# MUST pass, a branch whose row has an unjudged finding MUST fail, a branch with no row MUST fail, and a branch whose pre-existing finding was FIXED without a register row id MUST fail (2026-10-24), and so MUST a complete row of a round above the cap that carries no lead_ok (check-the-work F4 2026-10-24). A wrong answer
# means a real verdict would prove nothing: exit 3. The repository is made fresh under mktemp (never the real tree);
# only that folder is removed. CTW_SELFPROOF_RUNNING stops the inner runs from proving themselves again.
self_proof() {
  [ -n "${CTW_SELFPROOF_RUNNING:-}" ] && return 0
  command -v python3 >/dev/null 2>&1 || { echo "self-proof: BROKEN — python3 is missing, so verify cannot run" >&2; exit 3; }
  local pin d bad="" o_good o_bad o_none o_pre o_cap rc_good rc_bad rc_none rc_pre rc_cap
  # The inner runs read their own (fixture) root, so the log folder and id prefix they must use are handed over in the env.
  pin="HARNESS_AGENT_DIR=$(dirname "$LOG") HARNESS_BUG_PREFIX=$BUG_PREFIX"
  d="$(mktemp -d "${TMPDIR:-/tmp}/ctw-proof.XXXXXX")" || { echo "check-the-work: INCOMPLETE — no temp folder for the self-proof" >&2; exit 3; }
  pg() { git -C "$d" -c user.name=ctw-proof -c user.email=ctw-proof@invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
  {
    pg init -q && pg symbolic-ref HEAD refs/heads/main && mkdir -p "$d/$(dirname "$LOG")" && : > "$d/$LOG" \
      && pg add -A && pg commit -q -m base \
      && pg checkout -q -b proof-good \
      && printf '%s\n' '{"branch": "proof-good", "reviewer": "proof", "label": "self-proof", "verdict": "FINDINGS", "goal_verdict": "MET", "findings": ["F1"], "judged": {"F1": {"decision": "FIXED", "reason": "a known-answer fixture"}}}' >> "$d/$LOG" \
      && pg commit -q -am good \
      && pg checkout -q -b proof-bad main \
      && printf '%s\n' '{"branch": "proof-bad", "reviewer": "proof", "label": "self-proof", "verdict": "FINDINGS", "goal_verdict": "MET", "findings": ["F1"], "judged": {}}' >> "$d/$LOG" \
      && pg commit -q -am bad \
      && pg checkout -q -b proof-none main && echo work > "$d/work.txt" && pg add work.txt && pg commit -q -m none \
      && pg checkout -q -b proof-pre main \
      && printf '%s\n' '{"branch": "proof-pre", "reviewer": "proof", "label": "self-proof", "verdict": "FINDINGS", "goal_verdict": "MET", "findings": ["F1"], "tags": {"F1": "pre-existing"}, "judged": {"F1": {"decision": "FIXED", "reason": "fixed it here, no register row"}}}' >> "$d/$LOG" \
      && pg commit -q -am pre \
      && pg checkout -q -b proof-cap main \
      && printf '%s\n' '{"branch": "proof-cap", "reviewer": "proof", "label": "self-proof", "verdict": "FINDINGS", "goal_verdict": "MET", "findings": ["F1"], "judged": {"F1": {"decision": "FIXED", "reason": "a complete row, but round 4 with no lead_ok"}}, "round": 4, "lead_ok": null}' >> "$d/$LOG" \
      && pg commit -q -am cap
  } >/dev/null 2>&1 || bad=" the fixture repository could not be built;"
  if [ -z "$bad" ]; then
    o_good="$(env $pin CTW_SELFPROOF_RUNNING=1 CHECK_THE_WORK_ROOT="$d" bash "$SELF" verify --branch proof-good --base main 2>&1)"; rc_good=$?
    o_bad="$(env $pin CTW_SELFPROOF_RUNNING=1 CHECK_THE_WORK_ROOT="$d" bash "$SELF" verify --branch proof-bad --base main 2>&1)"; rc_bad=$?
    o_none="$(env $pin CTW_SELFPROOF_RUNNING=1 CHECK_THE_WORK_ROOT="$d" bash "$SELF" verify --branch proof-none --base main 2>&1)"; rc_none=$?
    o_pre="$(env $pin CTW_SELFPROOF_RUNNING=1 CHECK_THE_WORK_ROOT="$d" bash "$SELF" verify --branch proof-pre --base main 2>&1)"; rc_pre=$?
    # CHECK_THE_WORK_MAX_ROUNDS=3 pinned: the fixture's round 4 must be over the cap whatever the caller's environment says.
    o_cap="$(env $pin CHECK_THE_WORK_MAX_ROUNDS=3 CTW_SELFPROOF_RUNNING=1 CHECK_THE_WORK_ROOT="$d" bash "$SELF" verify --branch proof-cap --base main 2>&1)"; rc_cap=$?
    { [ "$rc_good" = 0 ] && printf '%s' "$o_good" | grep -qF "verify OK"; } || bad="$bad a complete judged row was not passed (exit $rc_good);"
    { [ "$rc_bad" = 1 ] && printf '%s' "$o_bad" | grep -qF "none is a judged review of branch proof-bad"; } || bad="$bad a row with an unjudged finding was not failed (exit $rc_bad);"
    { [ "$rc_none" = 1 ] && printf '%s' "$o_none" | grep -qF "the check-the-work step was skipped"; } || bad="$bad a branch with no row was not failed (exit $rc_none);"
    { [ "$rc_pre" = 1 ] && printf '%s' "$o_pre" | grep -qF "none is a judged review of branch proof-pre"; } || bad="$bad a pre-existing finding fixed without a register row was not failed (exit $rc_pre);"
    { [ "$rc_cap" = 1 ] && printf '%s' "$o_cap" | grep -qF "no lead_ok: the round cap was passed without the lead"; } || bad="$bad a round past the cap without the lead's ok was not failed (exit $rc_cap);"
  fi
  rm -rf -- "$d"
  if [ -n "$bad" ]; then
    printf '%s\n' "${o_good:-}" "${o_bad:-}" "${o_none:-}" "${o_pre:-}" "${o_cap:-}" | sed 's/^/    /' >&2
    echo "self-proof: BROKEN —$bad the verify detector is not trustworthy, so a verdict on a real branch would prove nothing" >&2
    exit 3
  fi
  echo "self-proof: OK (verify run on 5 fixture branches: a complete judged row passes; an unjudged finding, a missing row, an unrouted pre-existing finding and a round past the cap without the lead's ok fail)"
}

# vote_mode: on by `run --vote`, CHECK_THE_WORK_VOTE=on, or HARNESS_REVIEW_VOTE=on in harness.conf; OFF otherwise,
# because each voting round makes several outside calls and the owner approves that spend first.
vote_mode() {
  local v="${CHECK_THE_WORK_VOTE:-}"
  [ "$vote_flag" = 1 ] && return 0
  [ -n "$v" ] || v="${HARNESS_REVIEW_VOTE:-}"   # harness.conf was read at the top; the env switch above wins over it
  case "$v" in
    on|1) return 0 ;;
    ''|off|0) return 1 ;;
    *) echo "check-the-work: the vote setting '$v' is not on or off — the vote stays OFF" >&2; return 1 ;;
  esac
}

# run_votes: the outside voters of a vote round, in parallel, after ONE pre-send secret scan of the prompt here (a voter
# command may scan again itself: never send secrets to an outside model). Exit 5 = the scan refused, nothing was sent;
# 6 = no scan command is configured, nothing was sent; 3 = the scan could not run, nothing was sent, or (the normal end)
# the local voter is next.
run_votes() {
  local voters scan entry name c rc f n_ok=0 ok="" model asked=""
  voters="${CHECK_THE_WORK_VOTERS:-${HARNESS_REVIEW_VOTERS:-}}"
  scan="${CHECK_THE_WORK_SCAN:-${HARNESS_REVIEW_SCAN:-}}"
  # FAIL CLOSED: a vote sends the prompt (the diff of the work) to outside commands. With no scan command there is nothing
  # that could notice a secret in it, and "nothing configured" must not read as "nothing found" — so nothing is sent.
  [ -n "$scan" ] || die "REFUSED — vote mode needs a pre-send secret scan: set HARNESS_REVIEW_SCAN (a command that reads the prompt on stdin: exit 0 clean, 5 refused); NOTHING was sent to any voter" 6
  mkdir -p "$STATE/votes" || die "cannot create $STATE/votes" 3
  rc=0
  bash -c "$scan" <"$STATE/prompt.md" >/dev/null 2>"$STATE/votes/scan.err" || rc=$?
  if [ "$rc" -eq 5 ]; then sed 's/^/  scan: /' "$STATE/votes/scan.err" >&2; die "REFUSED — the prompt holds something secret-shaped; NOTHING was sent to any voter" 5; fi
  [ "$rc" -eq 0 ] || { sed 's/^/  scan: /' "$STATE/votes/scan.err" >&2; die "the pre-send secret scan could not run (exit $rc); NOTHING was sent" 3; }
  set -f  # a voter entry such as * must stay a word, never a file list
  for entry in $voters; do
    name="${entry%%=*}"; c="${entry#*=}"
    case "$name" in ''|*[!A-Za-z0-9._-]*) echo "check-the-work: voter '$entry' is malformed (want name=command) — not asked" >&2; continue ;; esac
    [ "$name" != "$entry" ] && [ -n "$c" ] || { echo "check-the-work: voter '$entry' is malformed (want name=command) — not asked" >&2; continue; }
    # A name is asked ONCE (cross-author finding 2026-10-24: a repeat ran twice in parallel into the same votes/<name>.*
    # files and wrote over the first run's answer).
    case " $asked " in *" $name "*) echo "check-the-work: voter '$name' is listed twice — asked once" >&2; continue ;; esac
    asked="$asked $name"
    # A relative voter command is "$ROOT/<cmd>". WHY no lookup of the main checkout here: a voter wrapper that needs a key
    # which lives only there finds it itself; this script runs the command from the checkout being reviewed.
    case "$c" in /*) ;; *) c="$ROOT/$c" ;; esac
    [ -x "$c" ] || { echo "check-the-work: voter $name is missing ($c) — not asked" >&2; continue; }
    ( "$c" <"$STATE/prompt.md" >"$STATE/votes/$name.out" 2>"$STATE/votes/$name.err"; echo $? >"$STATE/votes/$name.rc" ) &
  done
  set +f
  wait
  for f in "$STATE"/votes/*.rc; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .rc)"; rc="$(cat "$f")"
    if [ "$rc" = 0 ] && grep -q '^VERDICT:' "$STATE/votes/$name.out"; then
      mv "$STATE/votes/$name.out" "$STATE/votes/$name.md"
      # The model the provider SERVED (its "[usage] model=" line), so the row names what really answered.
      model="$(sed -n 's/.*\[usage\] model=\([^ ]*\).*/\1/p' "$STATE/votes/$name.err" | tail -1)"
      [ -z "$model" ] || printf '%s' "$model" >"$STATE/votes/$name.model"
      n_ok=$((n_ok + 1)); ok="$ok $name"
    else
      echo "check-the-work: voter $name gave no vote (exit $rc$([ "$rc" = 0 ] && echo ', no VERDICT line')); its last messages:" >&2
      tail -n 5 "$STATE/votes/$name.err" 2>/dev/null | sed 's/^/  | /' >&2
      rm -f "$STATE/votes/$name.out"
    fi
  done
  echo "check-the-work: VOTE round $ROUND ($scope): $n_ok outside vote(s) stored:${ok:- none}."
  echo "  The local voter is next (same family, the last vote):"
  echo "  1. spawn the $LOCAL_AGENT agent with the prompt file: $STATE/prompt.md"
  echo "  2. save its answer to a file, then: scripts/check-the-work.sh record --answer <file> --reviewer ${CHECK_THE_WORK_LOCAL_VOTER:-$LOCAL_AGENT-local}"
  echo "  (the votes are counted then; if the local agent cannot run: scripts/check-the-work.sh tally)"
  return 3
}

# do_tally: count the stored votes (scripts/lib/review_tally.py) into the answer the sub-session judges.
do_tally() {
  local win="${CHECK_THE_WORK_VOTE_WINDOW:-15}" f names="" args=()
  case "$win" in ''|*[!0-9]*) die "CHECK_THE_WORK_VOTE_WINDOW must be a whole number of lines (got '$win')" ;; esac
  for f in "$STATE"/votes/*.md; do
    [ -f "$f" ] || continue
    args+=("$(basename "$f" .md)=$f"); names="$names+$(basename "$f" .md)"
  done
  [ "${#args[@]}" -gt 0 ] || die "no vote is stored for this round — run again, or record the local agent's answer" 2
  python3 -I "$LIB/review_tally.py" tally --window "$((10#$win))" --meta "$STATE/vote.json" "${args[@]}" >"$STATE/answer.md" \
    || { rm -f "$STATE/answer.md"; die "the vote count failed; nothing to judge" 3; }
  save_state reviewer "vote:${names#+}"
  if [ "${#args[@]}" -ge 2 ]; then save_state label vote; else save_state label vote-no-quorum; fi
  cat "$STATE/answer.md"
  echo
  [ "${#args[@]}" -ge 2 ] || echo "check-the-work: only ONE vote — no vote was possible, so every finding is kept (logged as vote_quorum false)"
  echo "check-the-work: judge every F-line (a U-line or a nit needs none), fix what is real, then:"
  echo "  scripts/check-the-work.sh judge --judgement <file>   (one line per finding: F<n>: FIXED|REJECTED|DEFERRED <reason>)"
}

case "$cmd" in
  run)
    [ -n "$goal" ] && [ -s "$goal" ] || die "run needs --goal <file> with the GOAL block of the brief (every sub-session has a goal)"
    [ -z "$summary" ] || [ -s "$summary" ] || die "--summary file is missing or empty: $summary"
    grep -q '^GOAL:' "$goal" || die "the goal file has no 'GOAL:' line (the brief's GOAL block: GOAL, PROOF, LIMIT)"
    # The review row is matched by BRANCH name (verify, the lead's merge check); a detached HEAD has none that survives
    # the next commit, so its review could never be verified (cross-author finding 2026-10-18).
    git symbolic-ref --quiet HEAD >/dev/null 2>&1 || die "detached HEAD: check out the sub-session's branch first (the review is matched by branch name)" 3
    command -v python3 >/dev/null 2>&1 || die "python3 is missing — install it (a harness prerequisite); nothing was asked" 3
    [ -f "$LIB/review-prompt-header.txt" ] && [ -f "$LIB/review_tally.py" ] || die "the shared review files are missing in $LIB (a harness defect); nothing was asked" 3
    max="${CHECK_THE_WORK_MAX_ROUNDS:-3}"
    case "$max" in ''|*[!0-9]*) die "CHECK_THE_WORK_MAX_ROUNDS must be a whole number 1 to 99 (got '$max')" ;; esac
    { [ "${#max}" -le 2 ] && [ "$((10#$max))" -ge 1 ]; } || die "CHECK_THE_WORK_MAX_ROUNDS must be 1 to 99 (got '$max')"
    max=$((10#$max))
    case "$lead_ok" in *[![:space:]]*|'') ;; *) die "--lead-ok needs the lead's words, not blanks" ;; esac
    mkdir -p "$STATE" || die "cannot create $STATE" 3
    rm -rf "$STATE"/answer.md "$STATE"/reviewer "$STATE"/label "$STATE"/votes "$STATE"/vote "$STATE"/vote.json "$STATE"/lead_ok
    resolve_base
    mb="$(merge_base)" || exit 2
    info="$(earlier_rounds "$mb" "$(branch_name)")" || die "could not read the review log $LOG; nothing was asked" 3
    prior="${info%%$'\t'*}"; prev_tree="${info#*$'\t'}"
    ROUND=$((prior + 1))
    # ROUND CAP (work that needs many review rounds is a sign the goal or the
    # approach is wrong, and more rounds of the same reviewer add noise, not proof). Past the cap the sub-session stops
    # and asks the lead; the lead's yes is quoted into the row, so each extra round is a recorded decision.
    if [ "$ROUND" -gt "$max" ]; then
      if [ -z "$lead_ok" ]; then
        echo "check-the-work: ROUND CAP — $prior judged review round(s) are logged for $(branch_name); the cap is $max. Nothing was asked."
        echo "  Stop here and ask the lead: send the open findings and what you changed since round $prior."
        echo "  Only when the lead says go on: run again with --lead-ok \"<the lead's words, quoted>\" (it is logged in the row)."
        exit 1
      fi
      save_state lead_ok "$lead_ok"
    fi
    DIFF_FROM="$mb" DIFF_TO="" scope="since-merge-base" now_tree="$(work_tree_id)"
    if [ "$ROUND" -gt 1 ]; then
      if [ -n "$prev_tree" ] && [ "$(git cat-file -t "$prev_tree" 2>/dev/null)" = tree ]; then
        [ "$prev_tree" != "$now_tree" ] || die "nothing changed since review round $prior (the same tree): there is nothing new to review — judge or commit"
        DIFF_FROM="$prev_tree" DIFF_TO="$now_tree" scope="since-round-$prior"
      else
        echo "check-the-work: the tree round $prior reviewed is not in this repository; round $ROUND shows the whole work again" >&2
      fi
    fi
    build_prompt "$STATE/prompt.md" "$([ "$ROUND" -gt 1 ] && echo "$STATE/earlier.md")"
    cp "$goal" "$STATE/goal.md"
    save_state base "$mb"; save_state tree "$now_tree"; save_state branch "$(branch_name)"
    save_state round "$ROUND"; save_state scope "$scope"
    if vote_mode; then
      save_state vote 1
      run_votes
      exit $?
    fi
    # The reviewer of a worktree is the configured second opinion, called as is. WHY no worktree rule here: a key file may
    # live only in the MAIN checkout, and scripts/second-opinion.sh hands such a call over itself (when
    # scripts/lib/main-checkout.sh is installed). An earlier copy of that rule here was redundant, and it asked git without
    # unsetting GIT_DIR, so inside a git hook it could have named the wrong repository.
    "$SECOND_OPINION" <"$STATE/prompt.md" >"$STATE/answer.out" 2>"$STATE/answer.err"; rc=$?
    case "$rc" in
      0)
        # An empty answer, or one without the asked VERDICT line, is no review (record refuses the same text): the
        # sub-session falls back to the local reviewer exactly as when no outside model answered (cross-author finding).
        if ! grep -q '^VERDICT:' "$STATE/answer.out"; then
          echo "check-the-work: the outside reviewer answered WITHOUT a 'VERDICT:' line (empty or not in the asked shape) — not stored."
          echo "  Use the local $LOCAL_AGENT agent with the prompt file: $STATE/prompt.md"
          echo "  then: scripts/check-the-work.sh record --answer <file> --reviewer $LOCAL_AGENT-local"
          rm -f "$STATE/answer.out"
          exit 3
        fi
        mv "$STATE/answer.out" "$STATE/answer.md"
        # every "answered by X" line of the chain (the provider inside a chain, then the chain itself)
        who="$(grep -o 'answered by [^ ]*' "$STATE/answer.err" | sed 's/answered by //' | awk '!seen[$0]++' | paste -sd/ -)"
        save_state reviewer "${who:-external}"; save_state label "cross-family"
        cat "$STATE/answer.md"
        echo
        echo "check-the-work: round $ROUND ($scope), answered by ${who:-external} (cross-family). Judge every F-line (a nit needs none), fix what is real, then:"
        echo "  scripts/check-the-work.sh judge --judgement <file>   (one line per finding: F<n>: FIXED|REJECTED|DEFERRED <reason>)"
        exit 0 ;;
      3)
        echo "check-the-work: NO OUTSIDE ANSWER — use the local $LOCAL_AGENT agent (a same-family review, label it so):"
        echo "  1. spawn the $LOCAL_AGENT agent with the prompt file: $STATE/prompt.md"
        echo "  2. save its answer to a file, then: scripts/check-the-work.sh record --answer <file> --reviewer $LOCAL_AGENT-local"
        sed 's/^/  reviewer chain: /' "$STATE/answer.err" | tail -5
        exit 3 ;;
      4)
        echo "check-the-work: second opinion is OFF (harness.conf) — write a self-review in the asked shape from $STATE/prompt.md,"
        echo "  then: scripts/check-the-work.sh record --answer <file> --reviewer self   (it is logged as a SELF-review)"
        exit 4 ;;
      *)
        sed 's/^/  reviewer chain: /' "$STATE/answer.err" | tail -8 >&2
        die "the reviewer chain failed (exit $rc); nothing is recorded — read the lines above (exit 2 = brief too big: lower CHECK_THE_WORK_DIFF_KB or split the work)" 2 ;;
    esac ;;
  record)
    [ -s "$STATE/prompt.md" ] || die "no prompt prepared — run 'check-the-work.sh run --goal <file>' first" 2
    [ -n "$answer" ] && [ -s "$answer" ] || die "record needs --answer <file> (the reviewer's answer, not empty)"
    case "$reviewer" in ''|*[!A-Za-z0-9._-]*) die "record needs --reviewer <name> (letters, digits, . _ -)" ;; esac
    grep -q '^VERDICT:' "$answer" || die "the answer has no 'VERDICT:' line — ask the reviewer again in the shape the prompt asks for"
    if [ "$(state vote)" = 1 ]; then
      # A vote round: this answer is one more VOTE (the local agent's), never the answer of record on its own.
      [ ! -f "$STATE/votes/$reviewer.md" ] || die "a vote of '$reviewer' is already stored for this round — use another name, or run again"
      mkdir -p "$STATE/votes" || die "cannot create $STATE/votes" 3
      cp "$answer" "$STATE/votes/$reviewer.md"
      echo "check-the-work: vote of $reviewer recorded; counting the votes"
      do_tally; exit $?
    fi
    cp "$answer" "$STATE/answer.md"; save_state reviewer "$reviewer"
    if [ "$reviewer" = self ]; then save_state label self-review; else save_state label same-family; fi
    echo "check-the-work: answer of $reviewer recorded ($(state label)); judge it next (check-the-work.sh judge --judgement <file>)" ;;
  tally)
    [ "$(state vote)" = 1 ] || die "tally counts the votes of a vote round — this round is not one (run --vote)" 2
    do_tally; exit $? ;;
  judge)
    command -v python3 >/dev/null 2>&1 || die "python3 is missing — install it (a harness prerequisite); nothing was judged" 3
    [ -s "$STATE/answer.md" ] || die "no reviewer answer stored — run 'check-the-work.sh run' (and 'record' for a local review) first" 2
    [ -n "$judgement" ] && [ -s "$judgement" ] || die "judge needs --judgement <file> (one line per finding id)"
    [ -f "$LIB/review_tally.py" ] || die "the shared answer reader $LIB/review_tally.py is missing (a harness defect); nothing was judged" 3
    # The registers a pre-existing finding is routed to (a row id there is the proof it was registered).
    bugreg="${HARNESS_BUG_REGISTER:-docs/registers/bug-register.md}"
    regs="${CHECK_THE_WORK_REGISTERS:-$bugreg ${HARNESS_BUG_ARCHIVE:-${bugreg%.md}-archive.md} ${HARNESS_SEC_REGISTER:-docs/tickets/security.md}}"
    # The judgement is read and checked TWICE by the same code: a dry pass (CTW_DRY=1, exits 0 right after the last check,
    # before any row is built), then the hooks, then the real pass that writes the row. WHY not one pass: a hook must see
    # only a judgement that already passed, and the log must stay untouched when a hook stops the step.
    judge_py() {
    CTW_DRY="$1" CTW_STATE="$STATE" CTW_JUDGEMENT="$judgement" CTW_LOG="$LOG" CTW_HEAD="$(git rev-parse HEAD)" CTW_LIB="$LIB" \
      CTW_REGISTERS="$regs" CTW_NOW_TREE="$now_tree" CTW_ID_PREFIXES="$ID_PREFIXES" python3 -I - <<'PY'
import json, os, re, sys, datetime
sys.path.insert(0, os.environ["CTW_LIB"])
sys.dont_write_bytecode = True  # no __pycache__ folder left in scripts/lib by the import below
import review_tally
PFX = os.environ["CTW_ID_PREFIXES"].split()
ID_RE = re.compile(r"\b(?:" + "|".join(re.escape(x) for x in PFX) + r")-\d+\b")
ID_HINT = " or ".join(x + "-nnn" for x in PFX)
st = os.environ["CTW_STATE"]
read = lambda n: open(os.path.join(st, n), encoding="utf-8", errors="replace").read() if os.path.exists(os.path.join(st, n)) else ""
answer = read("answer.md")
# The finding ids, as scripts/lib/review_tally.py reads them (the reviewer scorer reads the same way): a line that starts
# F<n>; after "===== ALSO-ASKED OPINION: <name>" the ids get the prefix "<name>:" so two answers that
# both start at F1 are judged one by one. A U-line of a vote (one voter only) is not a finding to judge.
parsed = review_tally.parse(answer)
tags = {f["id"]: f["tag"] for f in parsed}
# A nit needs no judgement (it breaks nothing; judging noise only trains people to skim); an untagged
# finding is judged like an important one, so leaving the tag out never lets a defect skip its judgement.
nits = [f["id"] for f in parsed if f["tag"] == "nit"]
ids = [f["id"] for f in parsed if f["tag"] != "nit"]
verdict = (re.search(r"^VERDICT:\s*(\S+)", answer, re.M) or [None, "?"])[1]
goal_line = (re.search(r"^GOAL:\s*(.+)$", answer, re.M) or [None, "?"])[1].strip()
judged, bad, goal_answer = {}, [], None
for line in open(os.environ["CTW_JUDGEMENT"], encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line:
        continue
    g = re.match(r"^GOAL\s*:\s*(FIXED|REJECTED)\s+(\S.*)$", line)
    if g:
        goal_answer = {"decision": g.group(1), "reason": g.group(2)}
        continue
    m = re.match(r"^((?:[A-Za-z0-9._-]+:)?F\d+)\s*:\s*(FIXED|REJECTED|DEFERRED)\s+(\S.*)$", line)
    if not m:
        bad.append(line)
        continue
    judged[m.group(1)] = {"decision": m.group(2), "reason": m.group(3)}
missing = [i for i in ids if i not in judged]
extra = [i for i in judged if i not in ids and i not in nits]
# A PRE-EXISTING finding belongs to the bug register, not to this change (it is routed, not judged here): REJECTED <why it is
# not real>, or FIXED/DEFERRED naming its register row (<prefix>-nnn or SEC-nnn), and that row must exist in a register file.
routed, unrouted = {}, []
reg_text = None
for i in ids:
    if tags.get(i) != "pre-existing" or i not in judged or judged[i]["decision"] == "REJECTED":
        continue
    ref = ID_RE.search(judged[i]["reason"])
    if not ref:
        unrouted.append(i + ": is pre-existing — name its register row (" + ID_HINT + ") in the reason, or REJECTED <why it is not real>")
        continue
    if reg_text is None:
        files = [p for p in os.environ["CTW_REGISTERS"].split() if os.path.isfile(p)]
        if not files:
            print("check-the-work: no register file to check the row id against (" + os.environ["CTW_REGISTERS"] + ") — nothing judged", file=sys.stderr)
            sys.exit(3)
        reg_text = "\n".join(open(p, encoding="utf-8", errors="replace").read() for p in files)
    if not re.search(r"\|\s*" + re.escape(ref.group(0)) + r"\s*\|", reg_text):
        unrouted.append(i + ": " + ref.group(0) + " is not a row of the registers (" + os.environ["CTW_REGISTERS"] + ") — file the row first")
        continue
    routed[i] = ref.group(0)
# A goal the reviewer did not see met is answered too: FIXED <the proof now shown> or REJECTED <why the reviewer is wrong>.
goal_open = not goal_line.upper().startswith("MET")
if bad or missing or extra or unrouted or (goal_open and goal_answer is None):
    if goal_open and goal_answer is None: print("check-the-work: the reviewer's goal verdict is '" + goal_line + "': add a line 'GOAL: FIXED <the proof now shown>' or 'GOAL: REJECTED <why>'", file=sys.stderr)
    if bad: print("check-the-work: judgement lines not in the form 'F<n>: FIXED|REJECTED|DEFERRED <reason>':", *bad, sep="\n  ", file=sys.stderr)
    if missing: print("check-the-work: findings not judged: " + ", ".join(missing), file=sys.stderr)
    if extra: print("check-the-work: judged ids the answer does not have: " + ", ".join(extra), file=sys.stderr)
    if unrouted: print("check-the-work: pre-existing findings not routed to the bug register:", *unrouted, sep="\n  ", file=sys.stderr)
    sys.exit(1)
if verdict.upper() == "FINDINGS" and not parsed:
    print("check-the-work: the answer says FINDINGS but has no F-lines — ask the reviewer again in the asked shape", file=sys.stderr)
    sys.exit(1)
if os.environ.get("CTW_DRY") == "1":
    sys.exit(0)  # the dry pass: everything above is the validation; nothing below may run before the hooks
cut = [l for l in read("cut.txt").splitlines() if l]
row = {
    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "branch": read("branch"), "base": read("base"), "head_at_judgement": os.environ["CTW_HEAD"],
    "reviewed_tree": read("tree"), "tree_at_judgement": os.environ["CTW_NOW_TREE"],
    "changed_after_review": read("tree") != os.environ["CTW_NOW_TREE"],
    "reviewer": read("reviewer"), "label": read("label"),
    "verdict": verdict, "goal_verdict": goal_line, "goal": read("goal.md").strip(),
    "goal_judged": goal_answer, "findings": ids, "judged": judged, "not_shown_to_reviewer": cut,
    "answer": answer.strip(),
    # The round (cap 3), what the reviewer saw, the tags, the nits, the register routing.
    "round": int(read("round") or 1), "diff_scope": read("scope") or "since-merge-base",
    "lead_ok": read("lead_ok") or None, "tags": tags, "nits": nits, "routed": routed,
}
if read("vote") == "1":
    meta = json.loads(read("vote.json") or "{}")
    vdir = os.path.join(st, "votes")
    row["vote"] = meta
    row["vote_quorum"] = meta.get("quorum", 1) >= 2
    row["votes"] = {n[:-3]: open(os.path.join(vdir, n), encoding="utf-8", errors="replace").read().strip()
                    for n in sorted(os.listdir(vdir)) if n.endswith(".md")} if os.path.isdir(vdir) else {}
    row["vote_models"] = {n[:-6]: open(os.path.join(vdir, n), encoding="utf-8", errors="replace").read().strip()
                          for n in sorted(os.listdir(vdir)) if n.endswith(".model")} if os.path.isdir(vdir) else {}
try:
    log = os.environ["CTW_LOG"]
    os.makedirs(os.path.dirname(log) or ".", exist_ok=True)
    # A log whose last row lost its newline (a hand edit) would glue the new row onto it: one corrupt line.
    lead = ""
    if os.path.exists(log) and os.path.getsize(log) > 0:
        with open(log, "rb") as f:
            f.seek(-1, os.SEEK_END)
            lead = "" if f.read(1) == b"\n" else "\n"
    with open(log, "a", encoding="utf-8") as f:
        f.write(lead + json.dumps(row, ensure_ascii=False) + "\n")
except OSError as e:
    print("check-the-work: could not write the review log: %s — nothing logged" % e.__class__.__name__, file=sys.stderr)
    sys.exit(3)
counts = {d: sum(1 for i in ids if judged[i]["decision"] == d) for d in ("FIXED", "REJECTED", "DEFERRED")}
print(f"check-the-work: logged in {os.environ['CTW_LOG']} — {row['reviewer']} ({row['label']}), verdict {verdict}, "
      f"round {row['round']} ({row['diff_scope']}), goal: {goal_line}; {len(ids)} finding(s): {counts['FIXED']} fixed, "
      f"{counts['REJECTED']} rejected, {counts['DEFERRED']} deferred; {len(nits)} nit(s); {len(routed)} routed to the register"
      + (f"; {len(row['vote'].get('unconfirmed', []))} unconfirmed (one voter)" if "vote" in row else "")
      + ("; the work changed after the review (fixes) — say so in the report" if row["changed_after_review"] else "")
      + (f"; {len(cut)} file(s) were NOT shown to the reviewer" if cut else ""))
print("check-the-work: commit " + os.environ["CTW_LOG"] + " together with the work.")
PY
    }
    now_tree="$(work_tree_id)"
    judge_py 1 || exit $?
    run_hooks judge "$(branch_name)" "$judgement"
    judge_py 0 || exit $?
    ;;
  verify)
    command -v python3 >/dev/null 2>&1 || die "python3 is missing — cannot tell" 3
    self_proof
    # The cap `verify` holds a branch to is the LEAD's (this environment), never the one the sub-session ran with.
    vmax="${CHECK_THE_WORK_MAX_ROUNDS:-3}"
    case "$vmax" in ''|*[!0-9]*) die "CHECK_THE_WORK_MAX_ROUNDS must be a whole number 1 to 99 (got '$vmax')" 3 ;; esac
    { [ "${#vmax}" -le 2 ] && [ "$((10#$vmax))" -ge 1 ]; } || die "CHECK_THE_WORK_MAX_ROUNDS must be 1 to 99 (got '$vmax')" 3
    vmax=$((10#$vmax))
    if [ -z "$vbranch" ] && ! git symbolic-ref --quiet HEAD >/dev/null 2>&1; then
      die "detached HEAD: pass --branch <name> of the branch the review was run on" 3
    fi
    br="${vbranch:-$(branch_name)}"
    tip="$br"; [ -n "$vbranch" ] || tip=HEAD
    git rev-parse --verify --quiet "$tip^{commit}" >/dev/null || die "branch '$br' is not a commit here" 3
    resolve_base
    mb="$(git merge-base "$base" "$tip" 2>/dev/null)" || die "no merge base between '$base' and '$br'" 3
    added="$(git diff "$mb" "$tip" -- "$LOG" 2>/dev/null | sed -n 's/^+{/{/p')"
    if [ -z "$added" ]; then
      echo "check-the-work: verify FAIL — no review row added to $LOG on $br since $(git rev-parse --short "$mb"): the check-the-work step was skipped" >&2
      exit 1
    fi
    printf '%s\n' "$added" | CTW_BRANCH="$br" CTW_MAXR="$vmax" CTW_ID_PREFIXES="$ID_PREFIXES" python3 -I -c '
import json, os, re, sys
ID_RE = re.compile(r"\b(?:" + "|".join(re.escape(x) for x in os.environ["CTW_ID_PREFIXES"].split()) + r")-\d+\b")
rows = []
for line in sys.stdin:
    try: rows.append(json.loads(line))
    except ValueError: pass
# A row counts only when it is COMPLETE, as judge writes it: every finding judged with a known word and a reason, a
# FINDINGS verdict with findings, and a goal not seen MET answered (found by an adversary review: a hand-written
# row with judged {} passed). It proves the step ran in full, not that the judgement is honest (the lead reads it).
def has_text(x):  # harness:allow-uncited embedded verify helper; WHY lives in the script header (ci/review-step.md)
    # A reason is TEXT: null, 0 or [] passed as "None", "0", "[]" through str() (cross-author finding 2026-10-18).
    return isinstance(x, str) and bool(x.strip())
def complete(r):  # harness:allow-uncited embedded verify helper; WHY lives in the script header (ci/review-step.md)
    j, f = r.get("judged"), r.get("findings")
    if not isinstance(j, dict) or not isinstance(f, list):
        return False
    for i in f:
        d = j.get(i)
        if not isinstance(d, dict) or d.get("decision") not in ("FIXED", "REJECTED", "DEFERRED") or not has_text(d.get("reason")):
            return False
    if str(r.get("verdict", "")).upper() == "FINDINGS" and not f and not r.get("nits"):
        return False
    # A finding tagged pre-existing that is not REJECTED names its register row.
    tags = r.get("tags") if isinstance(r.get("tags"), dict) else {}
    for i in f:
        if tags.get(i) == "pre-existing" and j[i].get("decision") != "REJECTED" and not ID_RE.search(j[i].get("reason")):
            return False
    if not str(r.get("goal_verdict", "")).strip().upper().startswith("MET"):
        g = r.get("goal_judged")
        if not isinstance(g, dict) or g.get("decision") not in ("FIXED", "REJECTED") or not has_text(g.get("reason")):
            return False
    return True
# check-the-work F4 2026-10-24: a sub-session can raise CHECK_THE_WORK_MAX_ROUNDS in its own run and then pass the cap
# alone; run writes lead_ok only past the cap it was given. So verify holds every row of the branch to ITS cap (the
# environment of the lead): a row of a round above it must carry text in lead_ok. A row with no "round" (an older row) is not judged.
cap = int(os.environ["CTW_MAXR"])
def round_of(r):  # harness:allow-uncited embedded verify helper; WHY lives in the script header (ci/review-step.md)
    n = r.get("round")
    if isinstance(n, bool): return None
    if isinstance(n, str) and n.strip().isdigit(): n = int(n.strip())
    return n if isinstance(n, int) else None
for r in rows:
    n = round_of(r)
    if r.get("branch") == os.environ["CTW_BRANCH"] and n is not None and n > cap and not has_text(r.get("lead_ok")):
        print("check-the-work: verify FAIL — a review row of round %d on branch %s has no lead_ok: the round cap was passed without the lead (the cap is %d)" % (n, os.environ["CTW_BRANCH"], cap), file=sys.stderr); sys.exit(1)
mine = [r for r in rows if r.get("branch") == os.environ["CTW_BRANCH"] and complete(r)]
if not mine:
    print("check-the-work: verify FAIL — review rows were added, but none is a judged review of branch " + os.environ["CTW_BRANCH"] + " (complete: every finding judged with a reason, a goal not seen MET answered)", file=sys.stderr); sys.exit(1)
r = mine[-1]
print("check-the-work: verify OK — %s (%s), verdict %s, goal: %s; %d finding(s) judged%s" % (r.get("reviewer"), r.get("label"), r.get("verdict"),
      r.get("goal_verdict"), len(r.get("findings", [])), "; changed after the review" if r.get("changed_after_review") else ""))
' || exit $?
    run_hooks verify "$br" ""
    ;;
  "")
    # No command: the way a gate self-proof runner calls a check script. Prove the detector, then the usage (exit 2).
    self_proof
    die "usage: check-the-work.sh run --goal <file> [--summary <file>] [--base <ref>] [--vote] [--lead-ok <the lead's words>] | record --answer <file> --reviewer <name> | judge --judgement <file> | tally | verify [--branch <name>] [--base <ref>]" ;;
  *)
    die "usage: check-the-work.sh run --goal <file> [--summary <file>] [--base <ref>] [--vote] [--lead-ok <the lead's words>] | record --answer <file> --reviewer <name> | judge --judgement <file> | tally | verify [--branch <name>] [--base <ref>]" ;;
esac
