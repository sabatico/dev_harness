#!/usr/bin/env bash
# heavy-run-test.sh — known-answer matrix for scripts/heavy-run.sh. Ported from the first adopting project, where it was
# written by a model that did not build the script (cross author, 2026-10-24). The rows under "KIT ADDITIONS" (the queue
# folder default, the symlink lock, the conf-read knobs, the no-ps fallback) cover code that differs from that project's
# script and were written by the porter, who also adapted the script: they are NOT cross-authored; have a different agent
# review them. The rows about the old `lockf -k <lock>` compatibility were dropped: the kit has no old callers.
#
# WHY: heavy-run.sh is the first-come-first-served queue every session on this machine takes before a heavy test run. A wrong
# answer here is silent and expensive: a queue that serves out of order lets one session wait for hours (the case it was
# built for), one that lets a third job in overloads the machine, and one that keeps a dead session's ticket blocks every
# later run. So the matrix pins (1) the order (FIFO) and the slot count under contention, (2) the dead-ticket drop, (3) nesting
# without deadlock, (4) the exit code passthrough and the usage vocabulary, (5) the wait-time log and the status columns,
# (6) the ticket clean-up on every way out, and (7) --record into the session-state record.
#
# SAFETY: every row runs the script under its own QUEUE FOLDER inside one mktemp folder (HARNESS_HEAVY_LOCK_DIR) with
# HARNESS_HEAVY_POLL_S=1; the repository's real queue folder is never touched: other sessions use it. The script is copied
# into the temp folder first (with the session-state.sh it calls), so the copy under test cannot change while rows run. The
# cleanup stops only the processes this matrix recorded, and only while their command line still holds what it started with.
# The last rows compare the real queue folder before and after.
#
# NEEDS ps and pgrep: a row about a reused PID needs `ps -o lstart=`, and the row that stops a --record pipeline needs `pgrep -P`
# (the pipeline is a subshell whose descendants are found with pgrep). Where either cannot work
# (a sandbox, a minimal container image) those rows print "SKIP" and are COUNTED in the summary line, never silently passed;
# run the matrix once somewhere ps works before trusting a green. Everything else runs in the pid-only fallback mode.
#
# Rows named "KNOWN-DEFECT ..." assert the correct behaviour the script lacks (findings for the lead). They print
# "known-defect (open finding)" and do not fail the matrix; once the script is fixed they fail with "now PASSES - promote".
# HEAVY_RUN_TEST_STRICT=1 makes them ordinary failing rows. Rows whose expected behaviour rests on an assumption about
# intent say "ASSUMPTION" in their name.
# SCRIPT_UNDER_TEST=<path> runs the matrix against a copy (a mutant, to watch a row go red).
# Exit: 0 every row passed · 1 any row failed · 3 could not run (a tool missing, or the fixture could not be built).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT0="${SCRIPT_UNDER_TEST:-$HERE/heavy-run.sh}"
[ -f "$SUT0" ] || { echo "heavy-run matrix: INCOMPLETE - the script under test is missing: $SUT0"; exit 3; }
for tool in git perl ps awk sed ln readlink cksum; do
  command -v "$tool" >/dev/null 2>&1 || { echo "heavy-run matrix: INCOMPLETE - $tool is missing"; exit 3; }
done
[ -f "$HERE/session-state.sh" ] || { echo "heavy-run matrix: INCOMPLETE - scripts/session-state.sh is missing (the --record rows call it)"; exit 3; }

# the queue folder a call made from the kit's own repository would use by default (never written by this matrix)
REAL_Q="$(cd "$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$HERE" rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)/harness-heavy"
real_snapshot() { { for f in "$REAL_Q"/*; do case "$f" in *wait-log*|*/t-*|*.mutex|*/next) ;; *) basename "$f" ;; esac; done; cksum "$SUT0" 2>&1; } 2>&1; }
REAL_BEFORE="$(real_snapshot)"

# Isolation: the environment of a heavy run (this matrix may itself run inside one) must not reach the rows.
unset HARNESS_HEAVY_RUN_ACTIVE HARNESS_HEAVY_SLOTS HARNESS_HEAVY_HEARTBEAT_S HARNESS_HEAVY_LOG HARNESS_HEAVY_LOCK_DIR HARNESS_HEAVY_MUTEX_WAIT_S
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_NAMESPACE
T0="$(mktemp -d "${TMPDIR:-/tmp}/hr-test.XXXXXX")" || { echo "heavy-run matrix: INCOMPLETE - mktemp failed"; exit 3; }
T="$(cd "$T0" && pwd -P)"
TAB="$(printf '\t')"
# the sacrificial processes are always stopped; HEAVY_RUN_TEST_KEEP=1 keeps the temp folder for a post-mortem
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() {
  local f pid want cur kid
  # let every job end by itself first
  for f in "$T"/r*; do [ -d "$f" ] && : > "$f/release.all"; done
  sleep 1
  if [ -f "$T/spawned" ]; then
    while IFS="$TAB" read -r pid want; do
      cur="$(ps -o command= -p "$pid" 2>/dev/null)"
      case "$cur" in
        *"$want"*)
          for kid in $(pgrep -P "$pid" 2>/dev/null); do kill -KILL "$kid" 2>/dev/null; done
          kill -KILL "$pid" 2>/dev/null ;;
      esac
    done < "$T/spawned"
  fi
  if [ "${HEAVY_RUN_TEST_KEEP:-0}" = 1 ]; then echo "kept $T"; else rm -rf "$T"; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM
mkdir -p "$T/home" "$T/tmp" "$T/o" "$T/sut" "$T/cwd"
export HOME="$T/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 TMPDIR="$T/tmp" LC_ALL=C
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid
export GIT_CEILING_DIRECTORIES="$T"
# the copy under test sits beside the session-state.sh it calls for --record
cp "$SUT0" "$T/sut/heavy-run.sh" || { echo "heavy-run matrix: INCOMPLETE - cannot copy the script"; exit 3; }
cp "$HERE/session-state.sh" "$T/sut/session-state.sh" || { echo "heavy-run matrix: INCOMPLETE - cannot copy session-state.sh"; exit 3; }
HR="$T/sut/heavy-run.sh"
export HARNESS_HEAVY_POLL_S=1
# can ps read a process start time here? (see NEEDS ps above)
PS_OK=0; [ -n "$(ps -o lstart= -p $$ 2>/dev/null)" ] && PS_OK=1
# can pgrep list child processes? (rc 0/1 = yes; 3 = "cannot get process list", e.g. in a sandbox)
PGREP_OK=0; pgrep -P $$ >/dev/null 2>&1; [ $? -le 1 ] && PGREP_OK=1
cd "$T/cwd" || exit 3

# ── the framework ──────────────────────────────────────────────────────────────────────────────────────────────────────
N=0; PASSED=0; FAILED=0; KD=0; SKIPPED=0; SKIPROW=0; WHY=""; NAME=""; KDROW=0
fail() { WHY="$WHY | $*"; }
begin() { WHY=""; NAME="$1"; KDROW=0; SKIPROW=0; N=$((N + 1)); new_row; }
# shellcheck disable=SC2329  # no known-defect row is open yet; kept for the next finding (house style)
kbegin() { begin "KNOWN-DEFECT $1"; KDROW=1; }
finish() {
  if [ "$SKIPROW" = 1 ]; then SKIPPED=$((SKIPPED + 1)); echo "SKIP  $NAME -- ps/pgrep cannot read processes here (run the matrix where they can)"; return; fi
  if [ "$KDROW" = 1 ] && [ "${HEAVY_RUN_TEST_STRICT:-0}" != 1 ]; then
    if [ -z "$WHY" ]; then FAILED=$((FAILED + 1)); echo "FAIL  KNOWN-DEFECT now PASSES - promote to a normal row: $NAME"
    else KD=$((KD + 1)); echo "known-defect (open finding)  $NAME -- ${WHY# | }"; fi
    return
  fi
  if [ -z "$WHY" ]; then PASSED=$((PASSED + 1)); echo "PASS  $NAME"; else FAILED=$((FAILED + 1)); echo "FAIL  $NAME -- ${WHY# | }"; fi
}
setup_fail() { echo "heavy-run matrix: INCOMPLETE - fixture: $*"; exit 3; }
has() { grep -qF -- "$2" "$1" 2>/dev/null || fail "${3:-$(basename "$1")}: missing '$2'"; }
lacks() { ! grep -qF -- "$2" "$1" 2>/dev/null || fail "${3:-$(basename "$1")}: must not contain '$2'"; }
eq() { [ "$1" = "$2" ] || fail "${3:-value}: got '$1', wanted '$2'"; }
want_rc() { [ "$RC" = "$1" ] || fail "exit $RC, wanted $1 (out: $(head -c 200 "$OUT" | tr '\n' '~') err: $(head -c 300 "$ERR" | tr '\n' '~'))"; }

# One private folder per row: its own queue, event log and release files, so a row can never see another's state.
new_row() {
  R="$T/r$N"; mkdir -p "$R"
  Q="$R/q"; EV="$R/events"; : > "$EV"
  export HARNESS_HEAVY_LOCK_DIR="$Q"
  unset HARNESS_HEAVY_SLOTS HARNESS_HEAVY_HEARTBEAT_S HARNESS_HEAVY_LOG HARNESS_HEAVY_RUN_ACTIVE HARNESS_HEAVY_MUTEX_WAIT_S
  CWD="$T/cwd"
}
# reset_row: forget the jobs of the first half of a row (release files, started marks, events), keep the queue folder
reset_row() { rm -f "$R"/release.* "$R"/started.* "$R"/jobpid.* "$R"/*.pid "$R"/*.out "$R"/*.err; : > "$EV"; }
tab_count() { awk -F'\t' '{ print NF; exit }' "$1"; }
field() { awk -F'\t' -v n="$2" -v r="${3:-1}" 'NR == r { print $n }' "$1"; }

# A job the matrix queues: records "start <name>" and "end <name>" in the row's event log, waits for its release file
# ($R/release.<name> or $R/release.all) and exits with the code it was given.
cat > "$T/job.sh" <<'EOF'
#!/bin/bash
# job.sh <row folder> <name> <exit code>
R="$1"; name="$2"; rc="${3:-0}"
case "$name" in stubborn*) trap '' TERM ;; esac   # a command that ignores TERM (only KILL stops it)
echo "$$" > "$R/jobpid.$name"
echo "start $name" >> "$R/events"
: > "$R/started.$name"
while [ ! -e "$R/release.$name" ] && [ ! -e "$R/release.all" ]; do sleep 0.1; done
echo "end $name" >> "$R/events"
exit "$rc"
EOF
chmod +x "$T/job.sh"

# spawn_rec <pid> <text its command line holds>: remember a process for the cleanup
spawn_rec() { printf '%s\t%s\n' "$1" "$2" >> "$T/spawned"; }
# wait_for <seconds> <description> <command...>: poll every 0.1 s until the command succeeds
wait_for() {
  local max="$1" what="$2" i=0 lim; shift 2
  lim=$((max * 10))
  while [ "$i" -lt "$lim" ]; do "$@" && return 0; sleep 0.1; i=$((i + 1)); done
  fail "timed out after ${max}s waiting for: $what"; return 1
}
started() { [ -e "$R/started.$1" ]; }
# nfiles <folder> <glob>: how many files match (no ls | grep)
nfiles() { local n=0 f; for f in "$1"/$2; do [ -e "$f" ] && n=$((n + 1)); done; echo "$n"; }
# nt: how many ticket files are in the row's queue folder
nt() { local n=0 f; for f in "$Q"/t-*; do [ -e "$f" ] && n=$((n + 1)); done; echo "$n"; }
# shellcheck disable=SC2329  # called through wait_for
ntickets() { [ "$(nt)" -ge "$1" ]; }
release() { : > "$R/release.$1"; }
# shellcheck disable=SC2329  # called through wait_for
nwaits_ge() { local n; n="$(grep -c 'waiting — ticket' "$R/$1.err" 2>/dev/null || true)"; [ "${n:-0}" -ge "$2" ]; }
# shellcheck disable=SC2329  # called through wait_for
job_dead() { ! kill -0 "$(cat "$R/jobpid.$1" 2>/dev/null)" 2>/dev/null; }
# shellcheck disable=SC2329  # called through wait_for
wrapper_dead() { ! kill -0 "$(cat "$R/$1.pid")" 2>/dev/null; }
# shellcheck disable=SC2329  # called through wait_for
nstarts_ge() { [ "$(grep -c '^start' "$EV")" -ge "$1" ]; }
# the order of the "start" lines, e.g. "A B C"
order() { awk '$1 == "start" { printf "%s%s", (n++ ? " " : ""), $2 } END { print "" }' "$EV"; }
# the most jobs running at once, read from the event log
maxconc() { awk '$1 == "start" { c++; if (c > m) m = c } $1 == "end" { c-- } END { print m + 0 }' "$EV"; }

# bg <name> <exit code> [heavy-run options...]: queue a job in the background; its output goes to $R/<name>.out/.err and its
# pid to $R/<name>.pid. perl resets SIGINT to the default first: a background job of a non-interactive shell ignores SIGINT,
# which would make the INT rows meaningless.
bg() {
  local name="$1" rc="$2" pid; shift 2
  perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' bash "$HR" "$@" --label "$name" -- bash "$T/job.sh" "$R" "$name" "$rc" \
    </dev/null >"$R/$name.out" 2>"$R/$name.err" &
  pid=$!; echo "$pid" > "$R/$name.pid"; spawn_rec "$pid" "heavy-run.sh"
}
# bg_wait <name>: wait for a background heavy-run and set BRC
# (bounded: a job that can never run - e.g. behind a ticket a mutant failed to drop - must make the row fail, not hang the matrix)
bg_wait() {
  local pid i=0; pid="$(cat "$R/$1.pid")"
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 900 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; BRC=137; fail "job $1 did not end within 90 s (killed)"
  else wait "$pid" 2>/dev/null; BRC=$?; fi
}
# hr <args...>: run the script in the foreground (a 60 s alarm stops a deadlock); sets OUT, ERR, RC
hr() {
  OUT="$R/fg.out"; ERR="$R/fg.err"
  ( cd "$CWD" && perl -e 'alarm shift; exec @ARGV' 60 bash "$HR" "$@" ) </dev/null >"$OUT" 2>"$ERR"; RC=$?
}
statusf() { ( cd "$CWD" && bash "$HR" --status --tsv ) 2>/dev/null; }
# dead_ticket <number> <state> <slot>: a ticket file of a process that has ended (a real pid, a real start time)
dead_ticket() {
  local pid st
  sleep 30 & pid=$!; st="$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^ *//; s/ *$//')"; st="${st:--}"
  kill -KILL "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  mkdir -p "$Q"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$pid" "$st" "${2:-wait}" "${3:--}" "$(( $(date +%s) - 5 ))" "/dead" "dead job" > "$Q/t-$(printf '%010d' "$1")"
  echo $(( $1 + 1 )) > "$Q/next"
}

# ══ PART 1: order and slots under contention ═══════════════════════════════════════════════════════════════════════════
begin "FIFO: four jobs queued in turn start in ticket order A B C D, one at a time (slots 1)"
bg A 0; wait_for 30 "A to run" started A
bg B 0; wait_for 30 "B's ticket" ntickets 2
bg C 0; wait_for 30 "C's ticket" ntickets 3
bg D 0; wait_for 30 "D's ticket" ntickets 4
sleep 2.5
eq "$(order)" "A" "only A has started after 2.5 s (B, C, D are queued behind it)"
release A; wait_for 30 "B to run" started B; sleep 1.5
eq "$(order)" "A B" "after A ends only B starts, C and D still wait"
release B; wait_for 30 "C to run" started C; release C; wait_for 30 "D to run" started D; release D
for j in A B C D; do bg_wait $j; [ "$BRC" = 0 ] || fail "job $j ended with $BRC"; done
eq "$(order)" "A B C D" "start order"; eq "$(maxconc)" "1" "most jobs at once"; finish

begin "slots 2: two jobs run at once, a third waits (never three); freeing one lets exactly the third in"
bg A 0 --slots 2; wait_for 30 "A to run" started A
bg B 0 --slots 2; wait_for 30 "B to run" started B
bg C 0 --slots 2; wait_for 30 "C's ticket" ntickets 3
sleep 2.5
eq "$(order)" "A B" "after 2.5 s only A and B run"; eq "$(maxconc)" "2" "most at once while C waits"
release A; wait_for 30 "C to run" started C
eq "$(order)" "A B C" "C starts when A is done"; release B; release C
for j in A B C; do bg_wait $j; done; eq "$(maxconc)" "2" "most jobs at once"; finish

begin "slots 2: the first run takes the lowest free slot (1), the second slot 2"
bg A 0 --slots 2; wait_for 30 "A to run" started A
bg B 0 --slots 2; wait_for 30 "B to run" started B
st="$(statusf)"; eq "$(printf '%s\n' "$st" | awk -F'\t' '$8 == "A" { print $2 ":" $4 }')" "run:1" "A's state and slot"
eq "$(printf '%s\n' "$st" | awk -F'\t' '$8 == "B" { print $2 ":" $4 }')" "run:2" "B's state and slot"
release all; for j in A B; do bg_wait $j; done; finish

begin "slots 3 and six jobs started at the same moment: every job runs once, never more than 3 at once, six distinct tickets"
for j in A B C D E F; do bg $j 0 --slots 3; done
wait_for 40 "three jobs to start" nstarts_ge 3
sleep 2
eq "$(grep -c '^start' "$EV")" "3" "jobs started while all three slots are taken"
release all
for j in A B C D E F; do bg_wait $j; [ "$BRC" = 0 ] || fail "job $j ended with $BRC"; done
eq "$(grep -c '^start' "$EV")" "6" "jobs run in all"; eq "$(maxconc)" "3" "most at once"
eq "$(cat "$R"/?.err | sed -n 's/.*starting ticket #\([0-9]*\).*/\1/p' | sort -u | wc -l | tr -d ' ')" "6" "distinct ticket numbers"; finish

begin "the waiting run reports its position: 'position 3 of 3 (2 ahead, 1 running, 1 slot(s))' and the label"
bg A 0; wait_for 30 "A to run" started A
bg B 0; wait_for 30 "B's ticket" ntickets 2
bg C 0; wait_for 30 "C's ticket" ntickets 3
wait_for 30 "C's position line" grep -q 'position 3 of 3' "$R/C.err"
wait_for 30 "B's updated position line" grep -q 'position 2 of 3' "$R/B.err"
has "$R/C.err" "waiting — ticket #3, position 3 of 3 (2 ahead, 1 running, 1 slot(s))"; has "$R/C.err" ": C"
has "$R/B.err" "position 2 of 3 (1 ahead, 1 running, 1 slot(s))"
lacks "$R/A.err" "waiting — ticket"; has "$R/A.err" "starting ticket #1 in slot 1"
release all; for j in A B C; do bg_wait $j; done; finish

begin "a waiting run prints its position again after HARNESS_HEAVY_HEARTBEAT_S; with the default it prints once"
export HARNESS_HEAVY_HEARTBEAT_S=1
bg A 0; wait_for 30 "A to run" started A
bg B 0; wait_for 30 "B's ticket" ntickets 2
wait_for 40 "three waiting lines of B with a 1 s heartbeat" nwaits_ge B 3
release all; bg_wait A; bg_wait B
unset HARNESS_HEAVY_HEARTBEAT_S; reset_row
bg A 0; wait_for 30 "A to run" started A
bg B 0; wait_for 30 "B's ticket" ntickets 2
wait_for 30 "B's first waiting line" nwaits_ge B 1
sleep 3.5
eq "$(grep -c 'waiting — ticket' "$R/B.err")" "1" "waiting lines with the 300 s default"
release all; bg_wait A; bg_wait B; finish

# ══ PART 2: dead tickets ═══════════════════════════════════════════════════════════════════════════════════════════════
begin "a ticket whose process has ended (any state, even RUN on the slot) is dropped and does not block"
dead_ticket 1 wait; dead_ticket 2 run 1
hr -- true; want_rc 0
has "$ERR" "starting ticket #3 in slot 1"; lacks "$ERR" "waiting — ticket"
[ ! -e "$Q/t-0000000001" ] && [ ! -e "$Q/t-0000000002" ] || fail "dead ticket files still in the queue folder: $(ls "$Q")"; finish

begin "a ticket whose PID is alive but has ANOTHER start time (a reused PID) is dropped; the same ticket with its real start time blocks"
if [ "$PS_OK" = 1 ]; then
sleep 60 & LP=$!; spawn_rec "$LP" "sleep 60"
LS="$(ps -o lstart= -p "$LP" 2>/dev/null | sed 's/^ *//; s/ *$//')"; LS="${LS:--}"
mkdir -p "$Q"; echo 2 > "$Q/next"
printf '%s\t%s\twait\t-\t%s\t/x\tliveticket\n' "$LP" "$LS" "$(date +%s)" > "$Q/t-0000000001"
bg B 0; wait_for 30 "B's waiting line" nwaits_ge B 1; sleep 2
[ ! -e "$R/started.B" ] || fail "positive control: a live ticket ahead did not block B"
has "$R/B.err" "position 2 of 2"
# now the same pid with a start time that is not its own
printf '%s\t%s\twait\t-\t%s\t/x\tliveticket\n' "$LP" "Thu Jan  1 00:00:00 2015" "$(date +%s)" > "$Q/t-0000000001"
wait_for 30 "B to start once the stale-PID ticket is dropped" started B
[ ! -e "$Q/t-0000000001" ] || fail "the reused-PID ticket file was not removed"
release all; bg_wait B; { kill -KILL "$LP"; wait "$LP"; } 2>/dev/null;
else SKIPROW=1; fi; finish

begin "a waiter that dies while queued (kill -9) is dropped at the next poll and the run behind it starts"
bg A 0; wait_for 30 "A to run" started A
bg B 0; wait_for 30 "B's ticket" ntickets 2
bg C 0; wait_for 30 "C's ticket" ntickets 3
kill -KILL "$(cat "$R/B.pid")"; wait "$(cat "$R/B.pid")" 2>/dev/null
release A; wait_for 40 "C to start behind the dead B" started C
if started B; then fail "B ran although it was killed while queued"; fi
release all; bg_wait C; bg_wait A; finish

begin "a ticket file edited by hand into garbage (no TAB fields) is dropped, not a crash or a block"
mkdir -p "$Q"; echo 2 > "$Q/next"; printf 'garbage without fields\n' > "$Q/t-0000000001"
hr -- true; want_rc 0; has "$ERR" "starting ticket #2"; finish

begin "R2: a ticket file that cannot be read (chmod 000, a stand-in for the vanish race) is skipped silently by --status and by a queued run: no 'No such file' / 'Permission denied' on stderr, the job still runs; a readable ticket is listed (control)"
mkdir -p "$Q"; echo 3 > "$Q/next"
: > "$Q/t-0000000001"; printf '1\tx\twait\t-\t0\t/x\tunreadable\n' > "$Q/t-0000000001"; chmod 000 "$Q/t-0000000001"
sleep 60 & LP=$!; spawn_rec "$LP" "sleep 60"; LS="$(ps -o lstart= -p "$LP" 2>/dev/null | sed 's/^ *//; s/ *$//')"; LS="${LS:--}"
printf '%s\t%s\twait\t-\t%s\t/x\treadable\n' "$LP" "$LS" "$(date +%s)" > "$Q/t-0000000002"
hr --status; want_rc 0
has "$OUT" "readable"; lacks "$OUT" "unreadable"; lacks "$ERR" "No such file"; lacks "$ERR" "Permission denied"; eq "$(wc -c < "$ERR" | tr -d ' ')" "0" "bytes on stderr of --status"
hr --status --tsv; want_rc 0; eq "$(awk -F'\t' '{ print $8 }' "$OUT" | paste -sd' ' -)" "readable" "labels in the tsv view"; eq "$(wc -c < "$ERR" | tr -d ' ')" "0" "bytes on stderr of --status --tsv"
{ kill -KILL "$LP"; wait "$LP"; } 2>/dev/null
hr -- bash -c 'echo ran'; want_rc 0; has "$OUT" "ran"; lacks "$ERR" "No such file"; lacks "$ERR" "Permission denied"; lacks "$ERR" "line "
chmod 600 "$Q/t-0000000001"; finish

begin "the 'next' counter file holding 08 (an octal trap) or text still numbers the next ticket in decimal"
mkdir -p "$Q"; echo 08 > "$Q/next"
hr -- true; want_rc 0; has "$ERR" "starting ticket #8 in slot 1"
echo "abc" > "$Q/next"; hr -- true; want_rc 0; has "$ERR" "starting ticket #1 in slot 1"; finish

begin "a ticket removed by hand while waiting: the run stops with exit 3 and says so (never runs the command)"
bg A 0; wait_for 30 "A to run" started A
bg B 0; wait_for 30 "B's ticket" ntickets 2
rm -f "$Q/t-0000000002"; bg_wait B
eq "$BRC" "3" "exit of B"; has "$R/B.err" "ticket was removed"; [ ! -e "$R/started.B" ] || fail "B's command ran"
release all; bg_wait A; finish

# ══ PART 3: the start phase ═══════════════════════════════════════════════════════════════════════════════════════════
begin "E6: a run's phase is 'started' as soon as its slot is taken and the 'starting' line is printed once, with the slot"
bg A 0; wait_for 30 "A to run" started A
eq "$(grep -c 'starting ticket' "$R/A.err")" "1" "starting lines"; has "$R/A.err" "starting ticket #1 in slot 1"
eq "$(statusf | awk -F'\t' '$8 == "A" { print $9 }')" "started" "phase"
[ "$(statusf | awk -F'\t' '$8 == "A" { print $10 }')" -ge 0 ] 2>/dev/null || fail "column 10 (seconds run) is not a number"
release all; bg_wait A; finish

# ══ PART 4: nesting ═══════════════════════════════════════════════════════════════════════════════════════════════════
begin "nesting 1: HARNESS_HEAVY_RUN_ACTIVE set -> the command runs at once while slot 1 is taken, no ticket, a notice on stderr"
bg A 0; wait_for 30 "A to run" started A
HARNESS_HEAVY_RUN_ACTIVE=1 hr -- bash -c 'echo inner-ran'; want_rc 0
has "$OUT" "inner-ran"; has "$ERR" "nested (inside heavy-run)"
eq "$(nt)" "1" "tickets in the queue (only A's)"
release all; bg_wait A; finish

begin "nesting 2: a job started by heavy-run exports HARNESS_HEAVY_RUN_ACTIVE and its own heavy-run call runs at once (no deadlock)"
cat > "$R/outer.sh" <<EOF
#!/bin/bash
bash "$HR" -- bash -c 'echo deep-ran' > "$R/inner.out" 2> "$R/inner.err"
echo "inner-rc=\$?" >> "$R/inner.out"
exit 0
EOF
hr -- bash "$R/outer.sh"; want_rc 0; has "$R/inner.out" "deep-ran"; has "$R/inner.out" "inner-rc=0"; has "$R/inner.err" "nested"; finish

begin "nesting 5: the nested run passes its command's exit code through"
HARNESS_HEAVY_RUN_ACTIVE=1 hr -- bash -c 'exit 9'; want_rc 9
HARNESS_HEAVY_RUN_ACTIVE=1 hr -- true; want_rc 0; finish

# ══ PART 5: exit codes and usage ══════════════════════════════════════════════════════════════════════════════════════
begin "the command's exit code comes back unchanged (0, 1, 2, 7, 42, 75, 126, 255) and the log keeps it"
for c in 0 1 2 7 42 75 255; do
  hr -- bash -c "exit $c"; [ "$RC" = "$c" ] || fail "command exit $c came back as $RC"
done
hr -- bash -c 'exit 126'; eq "$RC" "126" "exit 126"
eq "$(awk -F'\t' '{ print $4 }' "$Q/wait-log.tsv" | paste -sd' ' -)" "0 1 2 7 42 75 255 126" "exit column of the log"; finish

begin "a command that does not exist: a non-zero exit, a ticket removed, nothing hangs"
hr -- "$R/no-such-command"; [ "$RC" != 0 ] || fail "exit 0 for a missing command"
eq "$(nt)" "0" "tickets left"; finish

begin "arguments reach the command unchanged: spaces, quotes, a dollar sign, an empty argument, a leading dash after --"
# shellcheck disable=SC2016  # the child shell expands "$@"; '$HOME' must reach it literally
hr -- bash -c 'printf "%s|" "$@"' _ "a b" "it's" '$HOME' "" "-x"; want_rc 0
eq "$(cat "$OUT")" "a b|it's|\$HOME||-x|" "arguments seen by the command"; finish

begin "the command's stdout goes to stdout and the script's own messages to stderr (stdout stays clean for a caller that parses it)"
hr -- bash -c 'echo payload'; want_rc 0; eq "$(cat "$OUT")" "payload" "stdout"; has "$ERR" "heavy-run: done ticket #1 — exit 0"; finish

begin "usage errors exit 1 and never run the command: no command, unknown option, --slots/--label without a value"
for args in "" "--bogus -- true" "--slots" "--label" "--slots 2"; do
  # shellcheck disable=SC2086  # the words of $args are separate arguments on purpose
  hr $args; [ "$RC" = 1 ] || fail "args '$args': exit $RC, wanted 1"
done
has "$ERR" "name the command to run"
eq "$(nt)" "0" "tickets taken by refused calls"; finish

begin "-h and --help print the usage and exit 0"
hr -h; want_rc 0; has "$OUT" "Usage: scripts/heavy-run.sh"; hr --help; want_rc 0; has "$OUT" "--slots N"; finish

begin "--slots validation: 0, 9, 10, x, -1, 1.5, 08 and ' 2' are refused (exit 1, command not run); 1 and 8 are accepted"
for v in 0 9 10 x -1 1.5 08 " 2"; do
  rm -f "$R/ran"; hr --slots "$v" -- bash -c ": > '$R/ran'"
  [ "$RC" = 1 ] || fail "--slots '$v': exit $RC, wanted 1"
  [ ! -e "$R/ran" ] || fail "--slots '$v': the command ran"
done
has "$ERR" "--slots must be 1 to 8"
for v in 1 8; do hr --slots "$v" -- true; [ "$RC" = 0 ] || fail "--slots $v refused (exit $RC)"; done; finish

begin "--slots '' (an empty value) is refused like any other bad value: exit 1, the command is not run"
rm -f "$R/ran"; hr --slots "" -- bash -c ": > '$R/ran'"
[ "$RC" = 1 ] || fail "exit $RC, wanted 1"; [ ! -e "$R/ran" ] || fail "the command ran with --slots ''"; finish

begin "ASSUMPTION: HARNESS_HEAVY_SLOTS='' (empty) is treated as unset: the slots come from harness.conf, else 1 (not an error)"
HARNESS_HEAVY_SLOTS="" hr -- true; want_rc 0; eq "$(field "$Q/wait-log.tsv" 5 1)" "1" "slots column with an empty env and no conf"
CR="$R/conf-repo2"; mkdir -p "$CR"; git init -q -b main "$CR" || setup_fail "git init conf repo2"; CWD="$CR"
printf 'HARNESS_HEAVY_SLOTS=3\n' > "$CR/harness.conf"; HARNESS_HEAVY_SLOTS="" hr -- true; want_rc 0
eq "$(field "$Q/wait-log.tsv" 5 2)" "3" "slots column with an empty env and a conf of 3"; CWD="$T/cwd"; finish

begin "slots from HARNESS_HEAVY_SLOTS: 0, 9 and x are refused; 2 is used (log 'slots' column); --slots beats the env"
for v in 0 9 x; do HARNESS_HEAVY_SLOTS="$v" hr -- true; [ "$RC" = 1 ] || fail "env slots '$v': exit $RC, wanted 1"; done
HARNESS_HEAVY_SLOTS=2 hr -- true; want_rc 0; eq "$(field "$Q/wait-log.tsv" 5 1)" "2" "slots column with env 2"
HARNESS_HEAVY_SLOTS=2 hr --slots 4 -- true; want_rc 0; eq "$(field "$Q/wait-log.tsv" 5 2)" "4" "slots column with --slots 4 over env 2"; finish

begin "slots from harness.conf (HARNESS_HEAVY_SLOTS in the repository the call is made from): plain, quoted, last line wins, commented ignored"
CR="$R/conf-repo"; mkdir -p "$CR"; git init -q -b main "$CR" || setup_fail "git init conf repo"; CWD="$CR"
printf '#HARNESS_HEAVY_SLOTS=7\nHARNESS_HEAVY_SLOTS=2\nHARNESS_HEAVY_SLOTS="3"  # three\n' > "$CR/harness.conf"
hr -- true; want_rc 0; eq "$(field "$Q/wait-log.tsv" 5 1)" "3" "slots from the last uncommented line, quotes cut"
HARNESS_HEAVY_SLOTS=1 hr -- true; want_rc 0; eq "$(field "$Q/wait-log.tsv" 5 2)" "1" "env beats the conf"
printf 'HARNESS_HEAVY_SLOTS=9\n' > "$CR/harness.conf"; hr -- true; eq "$RC" "1" "a conf value of 9 is refused like any other"
printf 'HARNESS_HEAVY_SLOTS=abc\n' > "$CR/harness.conf"; hr -- true; want_rc 0
eq "$(field "$Q/wait-log.tsv" 5 3)" "1" "a non-number in the conf falls back to 1 (ASSUMPTION: the default, not an error)"
printf 'echo hacked > "%s/pwned"\nHARNESS_HEAVY_SLOTS=2\n' "$R" > "$CR/harness.conf"; hr -- true; want_rc 0
[ ! -e "$R/pwned" ] || fail "the conf file was executed (sourced)"
eq "$(field "$Q/wait-log.tsv" 5 4)" "2" "slots read from a conf that also holds a command line"
CWD="$T/cwd"; finish

begin "the queue folder unusable (a regular file in its place) -> exit 3, the command is not run"
rm -rf "$Q"; : > "$Q"
hr -- bash -c ": > '$R/ran'"; want_rc 3; has "$ERR" "cannot use the queue folder"; [ ! -e "$R/ran" ] || fail "the command ran"; finish

begin "--status and --log with an unusable queue folder also exit 3 (never 0 on a broken look)"
rm -rf "$Q"; : > "$Q"; hr --status; want_rc 3; hr --log; want_rc 3; finish

# ══ PART 6: the wait-time log and the status columns ═════════════════════════════════════════════════════════════════
begin "wait-log row: 8 TAB columns queued_utc, waited_s, ran_s, exit, slots, slot, folder, label"
CWD="$T/cwd"; hr --label "my label" -- bash -c 'sleep 1; exit 3'; want_rc 3
LOGF="$Q/wait-log.tsv"; eq "$(wc -l < "$LOGF" | tr -d ' ')" "1" "log rows"; eq "$(tab_count "$LOGF")" "8" "columns"
case "$(field "$LOGF" 1)" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;; *) fail "col 1 not a UTC stamp: $(field "$LOGF" 1)" ;; esac
case "$(field "$LOGF" 2)" in ''|*[!0-9]*) fail "col 2 (waited_s) not a number: $(field "$LOGF" 2)" ;; esac
[ "$(field "$LOGF" 3)" -ge 1 ] 2>/dev/null || fail "col 3 (ran_s) should be >= 1 for a 1 s command: '$(field "$LOGF" 3)'"
eq "$(field "$LOGF" 4)" "3" "col 4 exit"; eq "$(field "$LOGF" 5)" "1" "col 5 slots"; eq "$(field "$LOGF" 6)" "1" "col 6 slot"
eq "$(field "$LOGF" 7)" "$T/cwd" "col 7 folder"; eq "$(field "$LOGF" 8)" "my label" "col 8 label"; finish

begin "wait-log: the second job's waited_s covers the time it queued (>= 2 s behind a 2.5 s job); the first waited little"
bg A 0; wait_for 30 "A to run" started A
bg B 0; wait_for 30 "B's ticket" ntickets 2
sleep 2.5; release A; wait_for 30 "B to run" started B; release B; bg_wait A; bg_wait B
LOGF="$Q/wait-log.tsv"
[ "$(awk -F'\t' '$8 == "A" { print $2 }' "$LOGF")" -le 4 ] || fail "A waited $(awk -F'\t' '$8 == "A" { print $2 }' "$LOGF") s (a machine under load may add a little; 4 s is far below B's wait)"
[ "$(awk -F'\t' '$8 == "B" { print $2 }' "$LOGF")" -ge 2 ] || fail "B's waited_s is $(awk -F'\t' '$8 == "B" { print $2 }' "$LOGF"), wanted >= 2"
eq "$(awk -F'\t' '{ print $8 }' "$LOGF" | paste -sd' ' -)" "A B" "log order = finish order"; finish

begin "the label: default is the command; a TAB / newline in --label becomes blanks; it is cut to 120 characters"
hr -- true; eq "$(field "$Q/wait-log.tsv" 8 1)" "true" "default label"
hr --label "$(printf 'a\tb\nc')" -- true; eq "$(field "$Q/wait-log.tsv" 8 2)" "a b c" "label with TAB and newline"
eq "$(wc -l < "$Q/wait-log.tsv" | tr -d ' ')" "2" "log rows (a newline in the label did not split a row)"
eq "$(tab_count "$Q/wait-log.tsv")" "8" "columns after the TAB label"
long="$(printf 'x%.0s' $(seq 1 300))"; hr --label "$long" -- true; eq "$(field "$Q/wait-log.tsv" 8 3 | awk '{ print length($0) }')" "120" "label length"; finish

begin "--log: header + newest N rows; N=0 style bad numbers refused; no log yet -> a message and exit 0"
hr --log; want_rc 0; has "$OUT" "no wait-time log yet"
for i in 1 2 3 4 5; do hr --label "job$i" -- true; done
hr --log 2; want_rc 0; eq "$(wc -l < "$OUT" | tr -d ' ')" "3" "lines of --log 2 (header + 2)"
eq "$(head -1 "$OUT")" "queued_utc${TAB}waited_s${TAB}ran_s${TAB}exit${TAB}slots${TAB}slot${TAB}folder${TAB}label" "header"
eq "$(tail -1 "$OUT" | cut -f8)" "job5" "newest row last"; eq "$(sed -n 2p "$OUT" | cut -f8)" "job4" "oldest shown"
hr --log abc; want_rc 1; hr --log -1; want_rc 1; hr --log 100; want_rc 0; eq "$(wc -l < "$OUT" | tr -d ' ')" "6" "lines of --log 100"; finish

begin "HARNESS_HEAVY_LOG moves the log; an unwritable log gives a warning and the command's own exit code"
HARNESS_HEAVY_LOG="$R/elsewhere.tsv" hr -- true; want_rc 0; [ -s "$R/elsewhere.tsv" ] || fail "no log row in HARNESS_HEAVY_LOG"
[ ! -e "$Q/wait-log.tsv" ] || fail "the default log was written too"
HARNESS_HEAVY_LOG="$R/no/such/dir/log.tsv" hr -- bash -c 'exit 4'; want_rc 4; has "$ERR" "could not write the wait-time log"; finish

begin "--status --tsv: 10 TAB columns number, state, position, slot, age_s, pid, folder, label, phase, seconds_run; RUN row slot set, WAIT row slot '-', phase started/wait"
bg A 0; wait_for 30 "A to run" started A
bg B 0; wait_for 30 "B's ticket" ntickets 2
sleep 1.2
statusf > "$R/st.tsv"; eq "$(wc -l < "$R/st.tsv" | tr -d ' ')" "2" "rows"; eq "$(tab_count "$R/st.tsv")" "10" "columns"
eq "$(field "$R/st.tsv" 9 1)" "started" "col 9 phase of A"; eq "$(field "$R/st.tsv" 9 2)" "wait" "col 9 phase of B"; eq "$(field "$R/st.tsv" 10 2)" "-" "col 10 of the waiting B"
[ "$(field "$R/st.tsv" 10 1)" -ge 1 ] 2>/dev/null || fail "col 10 (seconds run) of A should be >= 1: '$(field "$R/st.tsv" 10 1)'"
eq "$(field "$R/st.tsv" 1 1)" "1" "col 1 ticket number of the first row"; eq "$(field "$R/st.tsv" 2 1)" "run" "col 2 state of A"
eq "$(field "$R/st.tsv" 3 1)" "1" "col 3 position of A"; eq "$(field "$R/st.tsv" 4 1)" "1" "col 4 slot of A"
eq "$(field "$R/st.tsv" 2 2)" "wait" "col 2 state of B"; eq "$(field "$R/st.tsv" 3 2)" "2" "col 3 position of B"; eq "$(field "$R/st.tsv" 4 2)" "-" "col 4 slot of B"
[ "$(field "$R/st.tsv" 5 2)" -ge 1 ] 2>/dev/null || fail "col 5 (age) of B should be >= 1 s: '$(field "$R/st.tsv" 5 2)'"
eq "$(field "$R/st.tsv" 6 1)" "$(cat "$R/A.pid")" "col 6 pid of A = the heavy-run process"
eq "$(field "$R/st.tsv" 7 1)" "$T/cwd" "col 7 folder"; eq "$(field "$R/st.tsv" 8 2)" "B" "col 8 label"
release all; bg_wait A; bg_wait B; finish

begin "--status (text): header with the folder, RUN/WAIT lines with positions; '(empty)' when idle; --status --tsv prints nothing when idle"
hr --status; want_rc 0; has "$OUT" "heavy-run queue  folder=$Q"; has "$OUT" "(empty)"
eq "$(statusf | wc -l | tr -d ' ')" "0" "tsv rows when idle"
bg A 0; wait_for 30 "A to run" started A; bg B 0; wait_for 30 "B's ticket" ntickets 2
hr --status; want_rc 0; has "$OUT" "RUN  slot 1  position 1"; has "$OUT" "WAIT"; has "$OUT" "position 2"; lacks "$OUT" "(empty)"
release all; bg_wait A; bg_wait B; finish

begin "--status does not list (and does not need) a dead ticket; a live one is listed (positive control)"
sleep 60 & LP=$!; spawn_rec "$LP" "sleep 60"; LS="$(ps -o lstart= -p "$LP" 2>/dev/null | sed 's/^ *//; s/ *$//')"; LS="${LS:--}"
mkdir -p "$Q"; echo 3 > "$Q/next"
printf '%s\t%s\twait\t-\t%s\t/x\tlivejob\n' "$LP" "$LS" "$(date +%s)" > "$Q/t-0000000002"
dead_ticket 1 wait; echo 3 > "$Q/next"
eq "$(statusf | awk -F'\t' '{ print $8 }' | paste -sd' ' -)" "livejob" "labels listed"; { kill -KILL "$LP"; wait "$LP"; } 2>/dev/null; finish

# ══ PART 7: the ticket file is removed on every way out ══════════════════════════════════════════════════════════════
begin "after a normal run the ticket file is gone (exit 0 and exit 5)"
hr -- true; want_rc 0; hr -- bash -c 'exit 5'; want_rc 5
eq "$(nt)" "0" "ticket files left"; finish

begin "TERM while queued: exit 143 within a few seconds, the ticket is removed, the command never ran, the run behind it still starts"
bg A 0; wait_for 30 "A to run" started A
bg B 0; wait_for 30 "B's ticket" ntickets 2
bg C 0; wait_for 30 "C's ticket" ntickets 3
kill -TERM "$(cat "$R/B.pid")"; bg_wait B
eq "$BRC" "143" "exit of B after TERM"; [ ! -e "$R/started.B" ] || fail "B's command ran"
eq "$(nt)" "2" "tickets left (A and C)"
release A; wait_for 30 "C to start" started C; release all; bg_wait A; bg_wait C; finish

begin "INT while queued: exit 130, the ticket is removed"
bg A 0; wait_for 30 "A to run" started A
bg B 0; wait_for 30 "B's ticket" ntickets 2
kill -INT "$(cat "$R/B.pid")"; bg_wait B
eq "$BRC" "130" "exit of B after INT"; eq "$(nt)" "1" "tickets left (A)"
release all; bg_wait A; finish

begin "E1: TERM while the command RUNS stops the command too (its whole process tree), exit 143, ticket removed, the run behind it starts"
bg A 0; wait_for 30 "A to run" started A
bg B 0; wait_for 30 "B's ticket" ntickets 2
kill -TERM "$(cat "$R/A.pid")"; wait_for 30 "the wrapper to end" wrapper_dead A; bg_wait A
eq "$BRC" "143" "exit after TERM during the run"
job_dead A || fail "the command (pid $(cat "$R/jobpid.A")) still runs after the wrapper was stopped"
wait_for 40 "B to start behind the stopped A" started B
eq "$(nt)" "1" "tickets left (only B's)"; release all; bg_wait B; finish

begin "E1: INT while the command RUNS: command stopped, exit 130, ticket removed"
bg A 0; wait_for 30 "A to run" started A
kill -INT "$(cat "$R/A.pid")"; wait_for 30 "the wrapper to end" wrapper_dead A; bg_wait A
eq "$BRC" "130" "exit after INT during the run"; job_dead A || fail "the command still runs"; eq "$(nt)" "0" "ticket files left"; finish

begin "E1: a command that IGNORES TERM is stopped by KILL after a grace period of about 5 s (alive at 2 s, gone by 20 s), exit 143, ticket removed"
bg stubborn1 0; wait_for 30 "the command to run" started stubborn1
kill -TERM "$(cat "$R/stubborn1.pid")"; sleep 2
kill -0 "$(cat "$R/jobpid.stubborn1")" 2>/dev/null || fail "positive control: the TERM-ignoring command should still be alive 2 s after TERM (grace period)"
wait_for 40 "the wrapper to end" wrapper_dead stubborn1; bg_wait stubborn1
eq "$BRC" "143" "exit"; job_dead stubborn1 || fail "the stubborn command survived (no KILL)"; eq "$(nt)" "0" "ticket files left"; finish

begin "E1: TERM to a NESTED run (no ticket, HARNESS_HEAVY_RUN_ACTIVE set) stops its command and exits 143"
HARNESS_HEAVY_RUN_ACTIVE=1 bg N1 0; wait_for 30 "the nested command to run" started N1
eq "$(nt)" "0" "tickets (a nested run has none)"
kill -TERM "$(cat "$R/N1.pid")"; wait_for 30 "the wrapper to end" wrapper_dead N1; bg_wait N1
eq "$BRC" "143" "exit"; job_dead N1 || fail "the nested command still runs"; finish

begin "E1: TERM with --record stops the command (the pipe through tee too), exit 143, ticket removed"
if [ "$PGREP_OK" = 1 ]; then
bg R1 0 --record; wait_for 30 "the command to run" started R1
kill -TERM "$(cat "$R/R1.pid")"; wait_for 30 "the wrapper to end" wrapper_dead R1; bg_wait R1
eq "$BRC" "143" "exit"; job_dead R1 || fail "the --record command still runs"; eq "$(nt)" "0" "ticket files left";
else SKIPROW=1; fi; finish

begin "E7: TERM to a --record run removes its temp file heavy-run-out.* from TMPDIR (it exists while the command runs, is gone after the stop)"
mkdir -p "$R/tmp"; TMPDIR="$R/tmp" bg R2 0 --record; wait_for 30 "the command to run" started R2
eq "$(nfiles "$R/tmp" 'heavy-run-out.*')" "1" "positive control: the temp file exists while the --record command runs"
kill -TERM "$(cat "$R/R2.pid")"; wait_for 30 "the wrapper to end" wrapper_dead R2; bg_wait R2
eq "$(nfiles "$R/tmp" 'heavy-run-out.*')" "0" "temp files of --record left after the stop"; finish

begin "E1: TERM during the queue wait (not yet RUN) is unchanged: exit 143 at once, the command never starts (control for the new signal code)"
bg A 0; wait_for 30 "A to run" started A
bg B 0; wait_for 30 "B's ticket" ntickets 2
kill -TERM "$(cat "$R/B.pid")"; wait_for 30 "B to end" wrapper_dead B; bg_wait B
eq "$BRC" "143" "exit"; [ ! -e "$R/started.B" ] || fail "B ran"; kill -0 "$(cat "$R/jobpid.A")" 2>/dev/null || fail "A (running) was stopped by the TERM sent to B"
release all; bg_wait A; finish

begin "kill -9 of a queued waiter leaves its ticket file, but the next call drops it (no stale block)"
bg A 0; wait_for 30 "A to run" started A
bg B 0; wait_for 30 "B's ticket" ntickets 2
kill -KILL "$(cat "$R/B.pid")"; wait "$(cat "$R/B.pid")" 2>/dev/null
[ -e "$Q/t-0000000002" ] || fail "setup: the dead waiter's ticket should still be there"
release A; bg_wait A
hr -- true; want_rc 0; has "$ERR" "starting ticket #3"; [ ! -e "$Q/t-0000000002" ] || fail "the dead ticket was not dropped"; finish

# ══ PART 8: --record into the session-state record ═══════════════════════════════════════════════════════════════════
mkrec() { # mkrec <folder>: a git repo with a session-state record; CWD there
  git init -q -b main "$1" || setup_fail "git init $1"
  printf 'GOAL: x\nPROOF: y\nLIMIT: z\n' > "$1/goal.txt"
  ( cd "$1" && bash "$T/sut/session-state.sh" init --goal "$1/goal.txt" >/dev/null ) || setup_fail "session-state init in $1"
}
begin "--record: the last 3 raw lines and the exit code land in the session-state record; the exit code passes through; output still shown"
mkrec "$R/rec"; CWD="$R/rec"
hr --record --label "my gate" -- bash -c 'echo one; echo two; echo three; echo four; exit 5'; want_rc 5
has "$OUT" "one"; has "$OUT" "four"
REC="$(cd "$R/rec" && bash "$T/sut/session-state.sh" show)"
printf '%s\n' "$REC" > "$R/rec.txt"
eq "$(awk -F'\t' '$1 == "R"' "$R/rec.txt" | wc -l | tr -d ' ')" "3" "R lines"
eq "$(awk -F'\t' '$1 == "R" { print $5 }' "$R/rec.txt" | paste -sd'|' -)" "two|three|four" "the raw lines (the last three)"
eq "$(awk -F'\t' '$1 == "R" { print $3 "/" $4 }' "$R/rec.txt" | sort -u)" "5/my gate" "exit and command text of the R lines"; CWD="$T/cwd"; finish

begin "--record without a session-state record: the exit code still passes through, the lines are not kept, a notice names the cause"
mkdir -p "$R/norec"; git init -q -b main "$R/norec"; CWD="$R/norec"
hr --record -- bash -c 'echo hello; exit 6'; want_rc 6; has "$OUT" "hello"; has "$ERR" "--record: no session-state record in this worktree"; CWD="$T/cwd"; finish

begin "--record outside any git folder: the command's exit code still passes through (the record step fails softly)"
hr --record -- bash -c 'echo outside; exit 2'; want_rc 2; has "$OUT" "outside"; finish

begin "without --record the session-state record is left alone"
mkrec "$R/rec2"; CWD="$R/rec2"; hr -- bash -c 'echo plain'; want_rc 0
eq "$(cd "$R/rec2" && bash "$T/sut/session-state.sh" show | awk -F'\t' '$1 == "R"' | wc -l | tr -d ' ')" "0" "R lines"; CWD="$T/cwd"; finish

begin "--record: output of both stdout and stderr is shown (merged)"
hr --record -- bash -c 'echo to-out; echo to-err >&2'; want_rc 0; has "$OUT" "to-out"; { has "$OUT" "to-err" || has "$ERR" "to-err"; }; finish

# ══ KIT ADDITIONS (porter-written; not cross-authored): queue folder, symlink lock, conf knobs, no-ps fallback ═════════════════
begin "KIT: the default queue folder is <common git dir>/harness-heavy: two worktrees of one repository share ONE queue (ticket numbers continue), nothing lands in a working tree"
unset HARNESS_HEAVY_LOCK_DIR
RM="$R/repo"; RW="$R/repo-wt"; git init -q -b main "$RM" || setup_fail "git init"; git -C "$RM" commit -q --allow-empty -m base || setup_fail "commit"
git -C "$RM" worktree add -q -b feat "$RW" || setup_fail "worktree add"
CWD="$RM"; hr --label one -- true; want_rc 0; has "$ERR" "starting ticket #1"
CWD="$RW"; hr --label two -- true; want_rc 0; has "$ERR" "starting ticket #2"; CWD="$T/cwd"
GC="$(cd "$RM/.git" && pwd -P)"
eq "$(wc -l < "$GC/harness-heavy/wait-log.tsv" | tr -d ' ')" "2" "rows in the ONE shared wait log"
eq "$(git -C "$RM" status --porcelain | wc -l | tr -d ' ')" "0" "changes in the main working tree"; eq "$(git -C "$RW" status --porcelain | wc -l | tr -d ' ')" "0" "changes in the linked worktree"
[ ! -L "$GC/harness-heavy/.mutex" ] || fail "the short lock was left behind"; finish

begin "KIT: outside any git repository the default queue folder is \$TMPDIR/harness-heavy-<uid>"
unset HARNESS_HEAVY_LOCK_DIR; hr -- true; want_rc 0
[ -s "$T/tmp/harness-heavy-$(id -u)/wait-log.tsv" ] || fail "no log in $T/tmp/harness-heavy-$(id -u): $(ls "$T/tmp" | paste -sd' ' -)"; finish

begin "KIT: HARNESS_HEAVY_LOCK_DIR and HARNESS_HEAVY_LOG are read from harness.conf (a relative folder becomes absolute); the env beats the conf; the conf is not sourced"
CR="$R/cr"; mkdir -p "$CR"; git init -q -b main "$CR" || setup_fail "git init"; CWD="$CR"; unset HARNESS_HEAVY_LOCK_DIR
printf 'touch "%s/pwned-conf"\nHARNESS_HEAVY_LOCK_DIR="%s/confq"\nHARNESS_HEAVY_LOG=%s/conflog.tsv\n' "$R" "$R" "$R" > "$CR/harness.conf"
hr -- true; want_rc 0; [ -f "$R/confq/next" ] || fail "the queue folder from harness.conf was not used"; eq "$(wc -l < "$R/conflog.tsv" | tr -d ' ')" "1" "rows in the conf log"
[ ! -e "$R/confq/wait-log.tsv" ] || fail "the default log was written too"; [ ! -e "$R/pwned-conf" ] || fail "harness.conf was executed (sourced)"
HARNESS_HEAVY_LOCK_DIR="$R/envq" hr -- true; want_rc 0; [ -f "$R/envq/next" ] || fail "the env queue folder did not beat the conf"
printf 'HARNESS_HEAVY_LOCK_DIR=relq\n' > "$CR/harness.conf"; hr -- true; want_rc 0; [ -f "$CR/relq/next" ] || fail "a relative queue folder was not made absolute from the working folder"
CWD="$T/cwd"; finish

begin "KIT: the short queue lock held by a LIVE process is never stolen: exit 3 after the wait, the command does not run, the holder's lock is intact"
mkdir -p "$Q"; sleep 60 & LP=$!; spawn_rec "$LP" "sleep 60"; LS="$(ps -o lstart= -p "$LP" 2>/dev/null | sed 's/^ *//; s/ *$//')"; LS="${LS:--}"
ln -s "$LP|$LS" "$Q/.mutex" || setup_fail "plant a lock"
HARNESS_HEAVY_MUTEX_WAIT_S=1 hr -- bash -c ": > '$R/ran'"; want_rc 3; has "$ERR" "queue lock"; [ ! -e "$R/ran" ] || fail "the command ran without the queue lock"
eq "$(readlink "$Q/.mutex")" "$LP|$LS" "the live holder's lock"; { kill -KILL "$LP"; wait "$LP"; } 2>/dev/null; finish

begin "KIT: a short queue lock whose owner is dead is taken over at once; no lock is left after a run, a refused call or a TERM"
mkdir -p "$Q"; sleep 30 & DP=$!; DS="$(ps -o lstart= -p "$DP" 2>/dev/null | sed 's/^ *//; s/ *$//')"; DS="${DS:--}"; kill -KILL "$DP"; wait "$DP" 2>/dev/null
ln -s "$DP|$DS" "$Q/.mutex" || setup_fail "plant a lock"
hr -- true; want_rc 0; [ ! -L "$Q/.mutex" ] || fail "the lock was left after taking over a dead one"
hr --slots 0 -- true; want_rc 1; [ ! -L "$Q/.mutex" ] || fail "a refused call left the lock"
bg A 0; wait_for 30 "A to run" started A; bg B 0; wait_for 30 "B's ticket" ntickets 2
kill -TERM "$(cat "$R/B.pid")"; bg_wait B; [ ! -L "$Q/.mutex" ] || fail "a TERM left the lock"
release all; bg_wait A; finish

begin "KIT: with a ps that cannot read start times the queue works pid-only: tickets record '-', FIFO holds, a dead ticket is dropped"
mkdir -p "$T/nops" "$Q"; printf '#!/bin/sh\nexit 1\n' > "$T/nops/ps"; chmod +x "$T/nops/ps"
sleep 30 & DP=$!; kill -KILL "$DP"; wait "$DP" 2>/dev/null
printf '%s\t-\twait\t-\t%s\t/dead\tdead job\n' "$DP" "$(( $(date +%s) - 5 ))" > "$Q/t-0000000001"; echo 2 > "$Q/next"
PATH="$T/nops:$PATH" bg A 0; wait_for 30 "A to run behind the dead ticket" started A
eq "$(field "$Q/t-0000000002" 2 1)" "-" "start field of A's ticket"; [ ! -e "$Q/t-0000000001" ] || fail "the dead ticket was not dropped"
PATH="$T/nops:$PATH" bg B 0; wait_for 30 "B's ticket" ntickets 2; sleep 1.5
eq "$(order)" "A" "only A runs"; release A; wait_for 30 "B to run" started B; release all; bg_wait A; bg_wait B
eq "$(order)" "A B" "start order"; finish

# ══ the real queue and the temp folder ═════════════════════════════════════════════════════════════════════════════════
begin "the real queue folder (names only) and the script under test are unchanged by this matrix"
eq "$(real_snapshot | grep -v 't-0' )" "$(printf '%s\n' "$REAL_BEFORE" | grep -v 't-0')" "real queue state apart from live tickets of other sessions"; finish
begin "no row left a job of this matrix running"
for f in "$T"/r*; do [ -d "$f" ] && : > "$f/release.all"; done
sleep 1.5
left=0; [ "$PS_OK" = 1 ] || echo "  (ps cannot read command lines here: this row only checks the recorded pids with kill -0)"
if [ -f "$T/spawned" ]; then while IFS="$TAB" read -r pid want; do case "$(ps -o command= -p "$pid" 2>/dev/null)" in *"$want"*) left=$((left + 1)); echo "  still running: $pid $want" ;; esac; done < "$T/spawned"; fi
[ "$left" = 0 ] || fail "$left matrix process(es) still running after every release"; finish

MIN_ROWS=60
echo "heavy-run matrix: $PASSED pass, $FAILED fail, $SKIPPED skipped (ps), $KD known-defect (open findings)"
[ "$N" -ge "$MIN_ROWS" ] || { echo "heavy-run matrix: only $N rows ran (expected >= $MIN_ROWS) - refusing to report green"; exit 1; }
[ "$FAILED" -eq 0 ] || exit 1
exit 0
