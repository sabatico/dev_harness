#!/usr/bin/env bash
# session-state.sh — the small resumable state file every sub-session keeps, updated at each step, so a FRESH session can
# continue the work when this one dies (scripts/resume-brief.sh turns the file into a brief).
#
# WHY (the lead of the first adopting project, 2026-10-24, after a weekly usage limit killed three sub-sessions at once):
# each lost its in-flight context — the goal, what was done, the last test lines and the open questions lived only in the
# dead session's conversation, so the lead re-briefed them from memory. The MASS study (arXiv 2610.12176) found that a
# recovery step works when it re-calls the failed agent with its failure trace and a NARROWED scope; that needs a record of
# where the work stood. Design: docs/ci/session-resilience.md (S1).
#
# WHERE: one file in the worktree's OWN git folder (`git rev-parse --absolute-git-dir`/session-state.txt). It is never
# committed, never shows as an uncommitted change (so a worktree-status listing does not read it as dirty work), and lives
# as long as the worktree does, also after the session that wrote it has died.
#
# Usage (from inside the sub-session's worktree, or with -C <worktree> first):
#   init --goal <file> [--session NAME]   start the record (the GOAL block of the brief: needs a 'GOAL:' line). On an
#                                         existing record it adds an ATTEMPT line (a resume) and keeps the FIRST goal;
#                                         a different goal file is refused unless --replace-goal (then a goal-change
#                                         line is kept, which scripts/check-the-work.sh shows the lead).
#   init --resume [--session NAME]        a resumed session (scripts/resume-brief.sh): adds the ATTEMPT line, keeps the
#                                         goal as recorded; refused when there is no record yet.
#   step add <text>                       a checklist step, not done; prints its number
#   step doing|done|todo <n> [note]       move a step (done = its proof was seen; put the proof in the note)
#   gate <command text> [--exit N]        the RAW last lines of a gate or test run, read from stdin (the last 3 kept per
#                                         run, the newest 30 lines overall), e.g.  ... 2>&1 | tail -3 | session-state.sh
#                                         gate "your test command" --exit "${PIPESTATUS[0]}"
#   question <text> · answer <n> <text>   an open question, and its answer
#   note <text>                           where you are, a decision taken, what to do next
#   show · path                           print the record · print its path
# Exit: 0 done · 1 usage error or a refused change (no GOAL line, a different goal, a step that does not exist) ·
#       3 could not run (not in a git worktree, no record to update, the lock not taken within the wait).
#
# Format (one record per line, TAB-separated; text fields have tabs and line breaks turned into blanks):
#   #harness-session-state 1
#   A <attempt> <utc> <session>           one per init: attempt 1 = the first session, 2 = the first resume ...
#   G <goal line>                         the GOAL block as first given (GC <utc> <old first line> = a replaced goal)
#   S <n> <todo|doing|done> <utc> <text> <note>
#   R <utc> <exit> <command> <raw line>
#   Q <n> <open|answered> <utc> <text> <answer>
#   N <utc> <text>
# Env: HARNESS_STATE_LOCK_WAIT_S (default 30) — the longest wait for the record's lock.
# Bash 3.2 compatible (stock macOS). Tests: scripts/resume-brief-test.sh (cross author).
set -uo pipefail

# technical knob — how many raw gate lines the record keeps (the newest); a brief needs the last runs, not a log.
KEEP_GATE_LINES=30
# technical knob — raw lines kept per gate run (the summary lines are the last ones a runner prints).
KEEP_PER_RUN=3
# technical knob — the longest wait for the record's lock; two writers in one worktree are rare and brief.
LOCK_WAIT_S="${HARNESS_STATE_LOCK_WAIT_S:-30}"
case "$LOCK_WAIT_S" in ''|*[!0-9]*) LOCK_WAIT_S=30 ;; esac

die() { echo "session-state: $1" >&2; exit "${2:-1}"; }
clean() { printf '%s' "$1" | tr '\t\r\n' '   ' | tr -d '\000-\010\013\014\016-\037'; }
# has_text <text> — real text: not empty and not only blanks / control characters (clean() already turns tabs and line breaks
# into blanks, so "   " would otherwise be stored as a step, note or question with nothing in it)
has_text() { [ -n "$(clean "$1" | tr -d '[:space:]')" ]; }
utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

WT=""
if [ "${1:-}" = "-C" ]; then [ $# -ge 2 ] || die "-C needs a worktree folder"; WT="$2"; shift 2; fi
g() { if [ -n "$WT" ]; then env -u GIT_DIR -u GIT_WORK_TREE git -C "$WT" "$@"; else env -u GIT_DIR -u GIT_WORK_TREE git "$@"; fi; }
GD="$(g rev-parse --absolute-git-dir 2>/dev/null)" || die "not inside a git worktree${WT:+: $WT}" 3
F="$GD/session-state.txt"

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  path) echo "$F"; exit 0 ;;
  show) [ -f "$F" ] || die "no state record yet ($F): run 'session-state.sh init --goal <file>'" 3; cat "$F"; exit 0 ;;
  init|step|gate|question|answer|note) ;;
  ""|-h|--help) sed -n '2,/^# Bash 3.2/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "unknown command: $cmd (see the header of scripts/session-state.sh)" ;;
esac

# A gate's stdin is read BEFORE the lock: a long pipe must not hold the lock while it runs.
GATE_LINES=""
if [ "$cmd" = gate ] && [ $# -ge 1 ]; then
  GATE_LINES="$(sed '/^[[:space:]]*$/d' | tail -n "$KEEP_PER_RUN")"
fi

# Every change runs under one lock on the record, and writes a new file that replaces the old one in one step (mv), so a
# session that dies mid-write leaves the old record whole, never half a file.
#
# The lock is a SYMLINK whose target names its owner ("pid|process start"). Why not lockf or flock: lockf exists only on
# macOS and flock only on Linux, and a kit that must behave the same on both would be tested on one of them. ln -s is atomic
# on every filesystem and every OS with the same code, and the owner's pid + start time lets a waiter see that the holder
# died (a session killed mid-write) and take the lock over, which a plain mkdir lock cannot do. Residual: two waiters that
# take over the same dead lock at the same instant can race; the window is a few microseconds on a lock held for
# milliseconds, and the loser's write is still an atomic mv of a complete file.
LOCK="$GD/session-state.lock"
pstart() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'; }
ME="$$|$(pstart $$)"
HAVE_LOCK=0
lock_take() { # lock_take <seconds> — 0 taken, 1 not taken in time
  local i=0 max=$(($1 * 20)) owner pid st
  while ! ln -s "$ME" "$LOCK" 2>/dev/null; do
    owner="$(readlink "$LOCK" 2>/dev/null)"
    if [ -n "$owner" ]; then
      pid="${owner%%|*}"; st="${owner#*|}"
      if ! { kill -0 "$pid" 2>/dev/null && [ "$(pstart "$pid")" = "$st" ]; }; then rm -f "$LOCK"; continue; fi   # the holder is gone
    fi
    [ "$i" -lt "$max" ] || return 1
    sleep 0.05; i=$((i + 1))
  done
  HAVE_LOCK=1
}
lock_drop() { if [ "$HAVE_LOCK" -eq 1 ] && [ "$(readlink "$LOCK" 2>/dev/null)" = "$ME" ]; then rm -f "$LOCK"; fi; HAVE_LOCK=0; }

NEW="$(mktemp "$GD/session-state.new.XXXXXX")" || die "cannot write in $GD" 3
trap 'rm -f "$NEW"; lock_drop' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
lock_take "$LOCK_WAIT_S" || die "the record is locked by another writer for more than ${LOCK_WAIT_S}s ($LOCK)" 3

commit() { mv -f "$NEW" "$F" || die "cannot replace $F" 3; }
need_record() { [ -f "$F" ] || die "no state record yet: run 'scripts/session-state.sh init --goal <file>' first" 3; }
next_no() { awk -F'\t' -v k="$1" '$1 == k && $2 + 0 > m { m = $2 + 0 } END { print m + 1 }' "$F"; }

case "$cmd" in
  init)
    goal="" session="" replace=0 resume=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --resume) resume=1; shift ;;
        --goal) [ $# -ge 2 ] || die "--goal needs a file"; goal="$2"; shift 2 ;;
        --session) [ $# -ge 2 ] || die "--session needs a name"; session="$2"; shift 2 ;;
        --replace-goal) replace=1; shift ;;
        *) die "init: unknown argument $1" ;;
      esac
    done
    [ -n "$session" ] || session="$(basename "$(g rev-parse --show-toplevel 2>/dev/null)")"
    if [ "$resume" -eq 1 ]; then
      [ -z "$goal" ] || die "init: --resume keeps the recorded goal; do not pass --goal with it"
      need_record
      attempt="$(next_no A)"
      { cat "$F"; printf 'A\t%s\t%s\t%s\n' "$attempt" "$(utc)" "$(clean "$session")"; } > "$NEW"
      commit; echo "session-state: attempt $attempt (a resume) recorded in $F"; exit 0
    fi
    [ -n "$goal" ] && [ -s "$goal" ] || die "init needs --goal <file> with the brief's GOAL block"
    grep -q '^GOAL:' "$goal" || die "the goal file has no 'GOAL:' line (the brief's GOAL block: GOAL, PROOF, LIMIT)"
    goal_lines() { while IFS= read -r l || [ -n "$l" ]; do printf 'G\t%s\n' "$(clean "$l")"; done < "$goal"; }
    if [ ! -f "$F" ]; then
      { echo "#harness-session-state 1"; printf 'A\t1\t%s\t%s\n' "$(utc)" "$(clean "$session")"; goal_lines; } > "$NEW"
      commit; echo "session-state: started $F (attempt 1)"; exit 0
    fi
    attempt="$(next_no A)"
    same=1
    if [ "$(awk -F'\t' '$1 == "G"' "$F")" != "$(goal_lines)" ]; then same=0; fi
    if [ "$same" -eq 0 ] && [ "$replace" -eq 0 ]; then
      die "the goal file differs from the goal this record started with; keep the first goal, or pass --replace-goal when the LEAD changed it (the change is shown to the lead)"
    fi
    # readers select records by their first field, so the order after the header line does not matter
    {
      awk -F'\t' '$1 != "G"' "$F"
      if [ "$same" -eq 0 ]; then
        printf 'GC\t%s\t%s\n' "$(utc)" "$(awk -F'\t' '$1 == "G" { print $2; exit }' "$F")"
        goal_lines
      else
        awk -F'\t' '$1 == "G"' "$F"
      fi
      printf 'A\t%s\t%s\t%s\n' "$attempt" "$(utc)" "$(clean "$session")"
    } > "$NEW"
    commit
    echo "session-state: attempt $attempt recorded in $F$([ "$same" -eq 0 ] && echo ' (goal REPLACED — the lead sees it)')" ;;
  step)
    need_record
    sub="${1:-}"; [ $# -gt 0 ] && shift
    case "$sub" in
      add)
        if [ $# -lt 1 ] || ! has_text "$*"; then die "step add needs a text"; fi
        n="$(next_no S)"
        { cat "$F"; printf 'S\t%s\ttodo\t%s\t%s\t\n' "$n" "$(utc)" "$(clean "$*")"; } > "$NEW"
        commit; echo "$n" ;;
      todo|doing|done)
        n="${1:-}"; case "$n" in ''|*[!0-9]*) die "step $sub needs a step number" ;; esac
        shift; note="$(clean "${*:-}")"
        awk -F'\t' -v n="$n" '$1 == "S" && $2 == n { f = 1 } END { exit f ? 0 : 1 }' "$F" || die "no step $n in the record"
        # The note goes in through the environment, not `awk -v`: -v expands backslash escapes, so a note with
        # C:\new\tmp got a real newline and split the record row. ENVIRON is taken as is.
        SS_NOTE="$note" awk -F'\t' -v OFS='\t' -v n="$n" -v s="$sub" -v t="$(utc)" '
          $1 == "S" && $2 == n { $3 = s; $4 = t; if (ENVIRON["SS_NOTE"] != "") $6 = ENVIRON["SS_NOTE"] }
          { print }' "$F" > "$NEW"
        commit; echo "session-state: step $n is $sub" ;;
      *) die "step needs add, todo, doing or done" ;;
    esac ;;
  gate)
    need_record
    [ $# -ge 1 ] || die "gate needs the command text"
    gcmd="$(clean "$1")"; shift; ex="?"
    while [ $# -gt 0 ]; do
      case "$1" in
        --exit) [ $# -ge 2 ] || die "--exit needs a number"; ex="$2"; shift 2 ;;
        *) die "gate: unknown argument $1" ;;
      esac
    done
    case "$ex" in '?'|[0-9]|[0-9][0-9]|[0-9][0-9][0-9]) ;; *) die "--exit must be a number from 0 to 999" ;; esac
    t="$(utc)"
    lines="$GATE_LINES"
    [ -n "$lines" ] || lines="(no output)"
    {
      awk -F'\t' '$1 != "R"' "$F"
      { awk -F'\t' '$1 == "R"' "$F"
        printf '%s\n' "$lines" | while IFS= read -r l; do printf 'R\t%s\t%s\t%s\t%s\n' "$t" "$ex" "$gcmd" "$(clean "$l")"; done
      } | tail -n "$KEEP_GATE_LINES"
    } > "$NEW"
    commit; echo "session-state: gate lines of '$gcmd' (exit $ex) recorded" ;;
  question)
    need_record
    if [ $# -lt 1 ] || ! has_text "$*"; then die "question needs a text"; fi
    n="$(next_no Q)"
    { cat "$F"; printf 'Q\t%s\topen\t%s\t%s\t\n' "$n" "$(utc)" "$(clean "$*")"; } > "$NEW"
    commit; echo "$n" ;;
  answer)
    need_record
    n="${1:-}"; case "$n" in ''|*[!0-9]*) die "answer needs a question number" ;; esac
    shift; if [ $# -lt 1 ] || ! has_text "$*"; then die "answer needs a text"; fi
    awk -F'\t' -v n="$n" '$1 == "Q" && $2 == n { f = 1 } END { exit f ? 0 : 1 }' "$F" || die "no question $n in the record"
    # The answer text goes in through the environment, not `awk -v` (backslash escapes; see step done above).
    SS_ANSWER="$(clean "$*")" awk -F'\t' -v OFS='\t' -v n="$n" -v t="$(utc)" '$1 == "Q" && $2 == n { $3 = "answered"; $4 = t; $6 = ENVIRON["SS_ANSWER"] } { print }' "$F" > "$NEW"
    commit; echo "session-state: question $n answered" ;;
  note)
    need_record
    if [ $# -lt 1 ] || ! has_text "$*"; then die "note needs a text"; fi
    { cat "$F"; printf 'N\t%s\t%s\n' "$(utc)" "$(clean "$*")"; } > "$NEW"
    commit; echo "session-state: note recorded" ;;
esac
exit 0
