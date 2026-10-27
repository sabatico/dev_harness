#!/usr/bin/env bash
# heavy-run.sh — a FIRST-COME-FIRST-SERVED queue for heavy runs (full test suites, `run-all-gates.sh --all`, mutation
# batches) shared by every session and every worktree of one repository, with a set number of slots, a queue position report
# and a wait-time log.
#
# WHY (the lead of the first adopting project, 2026-10-24): 22 test jobs waited on one shared lock. A bare lock (lockf, flock)
# grants a freed lock to whichever waiter the kernel wakes, not to the one that came first, so one session waited 2 hours
# while later jobs went ahead, and the machine (8 cores) ran at a load of about 28. A wait nobody can see also reads as a hung
# session. The graph-engineering note (owner of that project, 2026-10-24) asks for a budget, monitoring and recovery per run:
# here the budget is the slot count, the monitoring is the position report and the wait log, the recovery is that a dead
# waiter's ticket is dropped. Design: docs/ci/session-resilience.md (S4).
#
# Usage: scripts/heavy-run.sh [--slots N] [--label TEXT] [--record] [--] <command> [args...]
#        scripts/heavy-run.sh --status [--tsv]      the queue now: who runs, who waits, in which order
#        scripts/heavy-run.sh --log [N]             the newest N rows of the wait-time log (default 20)
#   --slots N   how many heavy runs at once (1 to 8). Default: env HARNESS_HEAVY_SLOTS, else HARNESS_HEAVY_SLOTS in
#               harness.conf, else 1. Every session should use the same value, so set it in harness.conf, not per call.
#   --label     a short name for the queue view (default: the command)
#   --record    also keep the run's last raw lines in this worktree's session-state record (scripts/session-state.sh
#               gate); output then goes through `tee` (stdout and stderr merged).
# Config (env wins over harness.conf, which is READ for these names, never sourced):
#   HARNESS_HEAVY_SLOTS     the slot count above
#   HARNESS_HEAVY_LOCK_DIR  the queue folder. Default: <the repository's COMMON git dir>/harness-heavy, so every worktree of
#                           one repository shares one queue and nothing lands in the working tree; outside a git repository
#                           ${TMPDIR:-/tmp}/harness-heavy-<uid>. Make it absolute in harness.conf to share one queue between
#                           several repositories on one machine (they then also share the slots).
#   HARNESS_HEAVY_LOG       the wait-time log file (default <queue folder>/wait-log.tsv)
#   HARNESS_HEAVY_POLL_S (default 2) and HARNESS_HEAVY_HEARTBEAT_S (default 300) are tuning knobs for tests and operators.
# Exit: the command's own exit code · 1 usage error · 3 could not run (no queue folder, the queue lock not taken).
#
# HOW: each caller takes a numbered TICKET (a file in the queue folder, written under a short lock), then polls. It may
# start when fewer than N live tickets are ahead of it, so the order is the ticket order (FIFO). A ticket whose process is
# gone (same PID and start time no longer running) is dropped by the next poll, so a killed session never blocks the
# queue. At most N tickets are in state RUN, and a RUN ticket exists exactly while its wrapper (and so its command) lives, so
# the ticket file is the slot: there is no second lock to hold. Slot numbers (1..N) are for the view and the log.
# NESTING: inside a heavy run (HARNESS_HEAVY_RUN_ACTIVE set) the command runs at once, without the queue: waiting for a slot
# its own parent holds would never end.
# THE SHORT LOCK: taking a ticket or a slot is a few milliseconds of work done under a lock that is a SYMLINK whose target
# names its owner ("pid|process start"). Why not lockf or flock: lockf exists only on macOS and flock only on Linux, and the
# same code must behave the same on both. ln -s is atomic everywhere, and the owner's pid + start time lets a waiter see the
# holder died and take over. Residual: two waiters taking over the same dead lock at the same instant can race (microsecond
# window on a lock held for milliseconds).
# NO ps: where ps cannot read a process start time (a minimal container image), a ticket records "-" and its liveness is
# the pid alone, so a reused PID could keep a dead ticket alive until that PID ends; the stopping of a command's process tree
# also falls back to the command's own process.
# SIGNALS: a TERM or INT sent to this wrapper stops its command too, removes the ticket, and exits 143 / 130. The command runs
# as a background child that the wrapper waits for (bash runs a trap only between foreground commands, so a foreground child
# would have deferred it for ever); stdin stays the wrapper's stdin. Nothing is deleted except this queue's own ticket files
# (by their owner, or when their process is gone).
# Bash 3.2 compatible (stock macOS). Tests: scripts/heavy-run-test.sh (cross author).
set -uo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
# technical knob — seconds between queue polls; short enough that a free slot is taken at once, long enough to be idle.
POLL_S="${HARNESS_HEAVY_POLL_S:-2}"
# technical knob — a waiting run prints its position at least this often, so a long wait never looks like a hang.
HEARTBEAT_S="${HARNESS_HEAVY_HEARTBEAT_S:-300}"
# technical knob — the most slots accepted: one heavy run already uses several cores.
SLOTS_MAX=8
# technical knob — the longest wait for the short queue lock (taking a ticket or a slot is milliseconds of work); the
# env HARNESS_HEAVY_MUTEX_WAIT_S exists for the tests.
MUTEX_WAIT_S="${HARNESS_HEAVY_MUTEX_WAIT_S:-60}"
case "$MUTEX_WAIT_S" in ''|*[!0-9]*) MUTEX_WAIT_S=60 ;; esac

die() { echo "heavy-run: $1" >&2; exit "${2:-1}"; }
utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
fmt_s() { local s="$1"; if [ "$s" -lt 120 ]; then echo "${s}s"; elif [ "$s" -lt 7200 ]; then echo "$((s / 60))m $((s % 60))s"; else echo "$((s / 3600))h $((s % 3600 / 60))m"; fi; }
# pstart <pid> — the process start time, or "-" when ps cannot tell (the field stays non-empty: tickets are TAB-separated and
# read with a TAB in IFS, which would swallow an empty field)
pstart() { local s; s="$(ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//')"; echo "${s:--}"; }
# alive <pid> <start> — the ticket's process still runs (a reused PID has another start time; "-" = unknown, pid only)
alive() {
  local cur
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null || return 1
  [ "$2" = "-" ] && return 0
  cur="$(pstart "$1")"
  [ "$cur" = "-" ] || [ "$cur" = "$2" ]
}

# conf_val <NAME> — the value of NAME= in the repository's harness.conf, read with sed and never sourced (it is
# owner-owned configuration; sourcing would run whatever else is in it). Last assignment wins; quotes and a trailing comment cut.
conf_val() {
  local top conf
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  conf="$top/harness.conf"; [ -f "$conf" ] || return 0
  sed -n "s/^$1=[\"']\\{0,1\\}\\([^\"'#]*\\).*/\\1/p" "$conf" | tail -1 | sed 's/[[:space:]]*$//'
}
absolute() { case "$1" in /*) echo "$1" ;; *) echo "$PWD/$1" ;; esac; }

# The queue folder. The COMMON git dir (not the worktree's own) is what every worktree of one repository has in common.
Q="${HARNESS_HEAVY_LOCK_DIR:-}"
[ -n "$Q" ] || Q="$(conf_val HARNESS_HEAVY_LOCK_DIR)"
if [ -z "$Q" ]; then
  cdir="$(git rev-parse --git-common-dir 2>/dev/null)" && cdir="$(cd "$cdir" 2>/dev/null && pwd -P)" || cdir=""
  if [ -n "$cdir" ]; then Q="$cdir/harness-heavy"; else Q="${TMPDIR:-/tmp}/harness-heavy-$(id -u)"; fi
fi
Q="$(absolute "$Q")"
LOG="${HARNESS_HEAVY_LOG:-}"
[ -n "$LOG" ] || LOG="$(conf_val HARNESS_HEAVY_LOG)"
[ -n "$LOG" ] || LOG="$Q/wait-log.tsv"

# ── the short lock and the two queue steps that run under it ──────────────────────────────────────────────────────────
MYSTART="$(pstart $$)"
MUTEX="$Q/.mutex"
MUTEX_ME="$$|$MYSTART"
MUTEX_HELD=0
mutex_take() { # 0 taken · 1 not taken within MUTEX_WAIT_S
  local i=0 max=$((MUTEX_WAIT_S * 20)) owner
  while ! ln -s "$MUTEX_ME" "$MUTEX" 2>/dev/null; do
    owner="$(readlink "$MUTEX" 2>/dev/null)"
    if [ -n "$owner" ] && ! alive "${owner%%|*}" "${owner#*|}"; then rm -f "$MUTEX"; continue; fi   # the holder is gone
    [ "$i" -lt "$max" ] || return 1
    sleep 0.05; i=$((i + 1))
  done
  MUTEX_HELD=1
}
mutex_drop() { if [ "$(readlink "$MUTEX" 2>/dev/null)" = "$MUTEX_ME" ]; then rm -f "$MUTEX"; fi; MUTEX_HELD=0; }

# Ticket file t-<10-digit number>: pid, process start, state (wait|run), slot, queued epoch, folder, label (TAB-separated), and
# for a RUN ticket an 8th field `started` (the epoch the command started).
take_ticket() { # take_ticket <pid> <start> <cwd> <label> -> prints the ticket number
  local n
  mutex_take || return 1
  n="$(cat "$Q/next" 2>/dev/null)"; case "$n" in ''|*[!0-9]*) n=1 ;; esac
  n=$((10#$n))
  if printf '%s\t%s\twait\t-\t%s\t%s\t%s\n' "$1" "$2" "$(date +%s)" "$3" "$4" > "$Q/t-$(printf '%010d' "$n")" && echo $((n + 1)) > "$Q/next"; then
    mutex_drop; echo "$n"
  else
    mutex_drop; return 3
  fi
}
claim() { # claim <ticket> <slots> -> "RUN <slot>" or "WAIT <position> <live tickets> <running>" or "GONE"; drops dead tickets first
  local me="t-$(printf '%010d' "$((10#$1))")" slots="$2"
  local ahead=0 pos=0 total=0 running=0 used=" " t pid st state slot k q c l
  mutex_take || return 1
  if [ ! -f "$Q/$me" ]; then mutex_drop; echo "GONE"; return 0; fi
  for t in "$Q"/t-*; do
    [ -f "$t" ] || continue
    { IFS="$(printf '\t')" read -r pid st state slot _ < "$t"; } 2>/dev/null || continue   # the ticket may vanish after the glob
    if ! alive "$pid" "$st"; then rm -f "$t"; continue; fi
    total=$((total + 1))
    [ "$state" != run ] || { running=$((running + 1)); used="$used$slot "; }
    if [ "$(basename "$t")" = "$me" ]; then pos=$total; elif [ "$pos" -eq 0 ]; then ahead=$((ahead + 1)); fi
  done
  if [ "$ahead" -lt "$slots" ]; then
    k=1
    while [ "$k" -le "$slots" ]; do case "$used" in *" $k "*) k=$((k + 1)) ;; *) break ;; esac; done
    if [ "$k" -le "$slots" ]; then
      if ! { IFS="$(printf '\t')" read -r pid st _ _ q c l _ < "$Q/$me"; } 2>/dev/null; then mutex_drop; echo "GONE"; return 0; fi
      printf '%s\t%s\trun\t%s\t%s\t%s\t%s\t%s\n' "$pid" "$st" "$k" "$q" "$c" "$l" "$(date +%s)" > "$Q/$me.new" && mv -f "$Q/$me.new" "$Q/$me"
      mutex_drop; echo "RUN $k"; return 0
    fi
  fi
  mutex_drop; echo "WAIT $pos $total $running"
}

# ── the public commands ──────────────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$Q" 2>/dev/null && [ -w "$Q" ] || die "cannot use the queue folder $Q" 3

if [ "${1:-}" = "--status" ]; then
  tsv=0; [ "${2:-}" = "--tsv" ] && tsv=1
  now="$(date +%s)"; i=0
  [ "$tsv" -eq 1 ] || echo "heavy-run queue  folder=$Q"
  for t in "$Q"/t-*; do
    [ -f "$t" ] || continue
    { IFS="$(printf '\t')" read -r pid st state slot qd cwd label started < "$t"; } 2>/dev/null || continue
    alive "$pid" "$st" || continue
    i=$((i + 1)); num="$(basename "$t" | sed 's/^t-0*//')"
    # phase: wait · started (a RUN ticket with its start epoch) · running (a RUN ticket without one: cannot tell)
    phase="wait"; ran="-"; extra=""
    if [ "$state" = run ]; then
      case "$started" in
        ''|*[!0-9]*) phase="running" ;;
        *) phase="started"; ran="$((now - started))"; extra="  started, running $(fmt_s "$ran")" ;;
      esac
    fi
    if [ "$tsv" -eq 1 ]; then
      # columns: number state position slot age_s pid folder label phase seconds_run
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$num" "$state" "$i" "$slot" "$((now - qd))" "$pid" "$cwd" "$label" "$phase" "$ran"
    else
      printf '  #%s  %-4s %s  position %s  queued %s ago  pid %s  %s  %s%s\n' "$num" "$(echo "$state" | tr "[:lower:]" "[:upper:]")" \
        "$([ "$state" = run ] && echo "slot $slot" || echo "      ")" "$i" "$(fmt_s $((now - qd)))" "$pid" "$cwd" "$label" "$extra"
    fi
  done
  [ "$tsv" -eq 1 ] || [ "$i" -gt 0 ] || echo "  (empty)"
  exit 0
fi
if [ "${1:-}" = "--log" ]; then
  n="${2:-20}"; case "$n" in ''|*[!0-9]*) die "--log takes a number of rows" ;; esac
  [ -f "$LOG" ] || { echo "heavy-run: no wait-time log yet ($LOG)"; exit 0; }
  echo "queued_utc	waited_s	ran_s	exit	slots	slot	folder	label"
  tail -n "$n" "$LOG"; exit 0
fi

SLOTS="${HARNESS_HEAVY_SLOTS:-}"
# the conf value is digits only: anything else reads as unset (the default), not as an error
[ -n "$SLOTS" ] || SLOTS="$(conf_val HARNESS_HEAVY_SLOTS | sed -n 's/^\([0-9]*\).*/\1/p')"
LABEL="" RECORD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --slots) [ $# -ge 2 ] && [ -n "$2" ] || die "--slots needs a number (1 to $SLOTS_MAX), not an empty text"; SLOTS="$2"; shift 2 ;;
    --label) [ $# -ge 2 ] || die "--label needs a text"; LABEL="$2"; shift 2 ;;
    --record) RECORD=1; shift ;;
    --) shift; break ;;
    -h|--help) sed -n '2,/^# Bash 3.2/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option $1 (try --help)" ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || die "name the command to run (try --help)"
[ -n "$SLOTS" ] || SLOTS=1
case "$SLOTS" in [1-9]) ;; *) die "--slots must be 1 to $SLOTS_MAX (got '$SLOTS')" ;; esac
[ "$SLOTS" -le "$SLOTS_MAX" ] || die "--slots must be 1 to $SLOTS_MAX (got '$SLOTS')"
[ -n "$LABEL" ] || LABEL="$*"
LABEL="$(printf '%s' "$LABEL" | tr '\t\r\n' '   ' | cut -c1-120)"
CWD="$(pwd | tr '\t' ' ')"

# ── stopping on a signal ───────────────────────────────────────────────────────────────────────────────────────────────
CHILD=""
TFILE=""
# shellcheck disable=SC2329  # called from the trap strings and from on_signal below
descendants() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do descendants "$c"; echo "$c"; done; }  # deepest first
# shellcheck disable=SC2329  # called from the trap strings and from on_signal below
pid_running() { local st; kill -0 "$1" 2>/dev/null || return 1; st="$(ps -o stat= -p "$1" 2>/dev/null)"; case "$st" in Z*) return 1 ;; esac; return 0; }
# on_signal <exit code> — stop the command's whole process tree (TERM, then KILL after ~5 s), then leave; the EXIT trap removes the ticket
# shellcheck disable=SC2329  # called from the trap strings and from on_signal below
on_signal() {
  local pids p i any
  trap '' INT TERM
  if [ -n "$CHILD" ]; then
    pids="$(descendants "$CHILD") $CHILD"
    # shellcheck disable=SC2086  # $pids is a list of numeric process ids
    kill -TERM $pids 2>/dev/null
    i=0
    while [ "$i" -lt 50 ]; do
      any=0; for p in $pids; do if pid_running "$p"; then any=1; fi; done
      [ "$any" -eq 1 ] || break
      sleep 0.1; i=$((i + 1))
    done
    for p in $pids; do if pid_running "$p"; then kill -KILL "$p" 2>/dev/null; fi; done
  fi
  exit "$1"
}
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
# The files this run owns: its ticket (and the ticket's temp name) and, with --record, the capture file. Made in THIS shell
# (not in the background child that dies on a signal), and removed here on every way out, so a TERM leaves nothing in TMPDIR.
RECORD_OUT=""
# shellcheck disable=SC2329  # runs from the EXIT trap below
cleanup_files() {
  if [ -n "$TFILE" ]; then rm -f "$TFILE" "$TFILE.new"; fi
  if [ -n "$RECORD_OUT" ]; then rm -f "$RECORD_OUT"; fi
  mutex_drop   # a signal that arrived while this process held the short lock must not leave it for the next waiter
}
trap cleanup_files EXIT

# run_record <command...> — the command with its output kept (tee) and its last lines handed to the session-state record
run_record() {
  local rc
  HARNESS_HEAVY_RUN_ACTIVE=1 "$@" 2>&1 | tee "$RECORD_OUT"; rc=${PIPESTATUS[0]}
  tail -n 3 "$RECORD_OUT" | "$(dirname "$SELF")/session-state.sh" gate "$LABEL" --exit "$rc" >/dev/null 2>&1 \
    || echo "heavy-run: --record: no session-state record in this worktree (scripts/session-state.sh init first); lines not kept" >&2
  rm -f "$RECORD_OUT"   # (also removed by the EXIT trap, for the paths where this line is never reached)
  return "$rc"
}
# run_tracked <command...> -> the command's exit code. The command is a background child we wait for, so a signal is handled
# at once. Without --record the child IS the command's process (no wrapper function in between), so the signal handler's
# kill reaches it even where pgrep cannot list its descendants.
run_tracked() {
  local rc
  if [ "$RECORD" -eq 1 ]; then
    RECORD_OUT="$(mktemp "${TMPDIR:-/tmp}/heavy-run-out.XXXXXX")" || die "no temp file for --record" 3
    run_record "$@" 0<&0 &
  else
    HARNESS_HEAVY_RUN_ACTIVE=1 "$@" 0<&0 &
  fi
  CHILD=$!
  wait "$CHILD"; rc=$?
  CHILD=""
  return "$rc"
}

# Nested inside a heavy run: run at once (see NESTING above).
if [ -n "${HARNESS_HEAVY_RUN_ACTIVE:-}" ]; then
  echo "heavy-run: nested (inside heavy-run) — runs at once, no queue" >&2
  run_tracked "$@"; exit $?
fi

TICKET="$(take_ticket "$$" "$MYSTART" "$CWD" "$LABEL")" || die "could not take a queue ticket (the queue lock $MUTEX was not free for ${MUTEX_WAIT_S}s)" 3
case "$TICKET" in ''|*[!0-9]*) die "could not take a queue ticket (got '$TICKET')" 3 ;; esac
TFILE="$Q/t-$(printf '%010d' "$TICKET")"
QUEUED="$(date +%s)"; QUEUED_UTC="$(utc)"

last=""; last_beat="$QUEUED"
while :; do
  ans="$(claim "$TICKET" "$SLOTS")" || die "the queue lock $MUTEX was not free for ${MUTEX_WAIT_S}s" 3
  case "$ans" in
    RUN\ *) SLOT="${ans#RUN }"; break ;;
    GONE) die "this run's ticket was removed from the queue folder (by hand?) — start again" 3 ;;
    WAIT\ *)
      now="$(date +%s)"
      read -r _ pos total running <<EOF
$ans
EOF
      if [ "$ans" != "$last" ] || [ $((now - last_beat)) -ge "$HEARTBEAT_S" ]; then
        echo "heavy-run: waiting — ticket #$TICKET, position $pos of $total ($((pos - 1)) ahead, $running running, $SLOTS slot(s)), waited $(fmt_s $((now - QUEUED))): $LABEL" >&2
        last="$ans"; last_beat="$now"
      fi
      sleep "$POLL_S" & wait $! ;;   # a background sleep we wait for: a signal ends the poll at once
    *) die "unexpected queue answer: $ans" 3 ;;
  esac
done

STARTED="$(date +%s)"
echo "heavy-run: starting ticket #$TICKET in slot $SLOT after waiting $(fmt_s $((STARTED - QUEUED))): $LABEL" >&2
run_tracked "$@"; RC=$?
ENDED="$(date +%s)"
WAITED=$((STARTED - QUEUED))
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$QUEUED_UTC" "$WAITED" "$((ENDED - STARTED))" "$RC" "$SLOTS" "$SLOT" "$CWD" "$LABEL" >> "$LOG" 2>/dev/null \
  || echo "heavy-run: could not write the wait-time log $LOG" >&2
echo "heavy-run: done ticket #$TICKET — exit $RC, waited $(fmt_s "$WAITED"), ran $(fmt_s $((ENDED - STARTED)))" >&2
exit "$RC"
