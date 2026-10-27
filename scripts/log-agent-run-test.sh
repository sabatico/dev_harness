#!/usr/bin/env bash
# log-agent-run-test.sh — known-answer matrix for scripts/log-agent-run.py, the one door a row enters the agent run log
# (HARNESS_AGENT_DIR/runs.jsonl) through: the happy path, every refusal (each with a sibling that passes when the same
# shape is valid), time sources, the interrupted outcomes, machine-problem (infra) rows, corrections, hostile free text,
# the log file itself (location, last line without a newline, missing folder, lock, dry run).
# Usage: scripts/log-agent-run-test.sh [path/to/log-agent-run.py]     (default: log-agent-run.py next to this file; a mutant
#        copy can be passed to watch a row go red)       Exit: 0 every row passes · 1 a row failed · 2 cannot run.
#
# WHY (CLAUDE.md "a guard test proves nothing until you have watched it fail"): the log is append-only and read by people
# deciding which model to trust with what, so one bad row (a model name that drifted, minutes that were never measured, a
# task that hides text with a direction character) is silent for as long as the log lives. Ported from the first adopting
# project's agent-board matrix, written by a different author than the builder of the helper (the cross-author rule); the
# rows that tested its dashboard gate, the legacy-line cut-over, or its page rendering were dropped when the helper was
# generalised (nothing of that exists here). Every refusing row asserts that the log is byte-identical afterwards.
# Each case runs in a throwaway git repo under a mktemp dir; the real log is never touched. The model table is set through
# the knobs (invented names, so no vendor is a requirement); the row for "any model accepted when the table is empty" is
# not in the source matrix and is listed as a gap in the report that came with this port.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LRPY="${1:-$HERE/log-agent-run.py}"
[ -f "$LRPY" ] || { echo "log-agent-run-test: $LRPY not found" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "log-agent-run-test: python3 is required" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "log-agent-run-test: git is required" >&2; exit 2; }
T="$(mktemp -d "${TMPDIR:-/tmp}/log-agent-run-test.XXXXXX")" || { echo "log-agent-run-test: no temp dir" >&2; exit 2; }
T="$(cd "$T" && pwd -P)"
trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
# hermetic: a knob exported by the caller's shell must not change what the rows mean
unset HARNESS_AGENT_DIR HARNESS_RUNLOG HARNESS_RUNLOG_ROLES HARNESS_RUNLOG_WAVE_RE
export HARNESS_RUNLOG_MODELS="model-b:fam-x model-a:fam-x fable-x:fam-x model-c:fam-y"
export HARNESS_RUNLOG_MODEL_ALIASES="ma=model-a mb=model-b mc=model-c"
GF_T="$T/repo"; GF_PASS=0; GF_FAIL=0; GF_RC=0; GF_OUT=""; GF_WHY=""; GF_RUN_ENV=""
mkdir -p "$GF_T/scripts" && cd "$GF_T" && git init -q . || exit 2
cp "$LRPY" "$GF_T/scripts/log-agent-run.py"
# shellcheck disable=SC2016  # expanded later on purpose (by the wrapper at run time)
printf '#!/usr/bin/env bash\nexec python3 -I "$(dirname "$0")/log-agent-run.py" "$@"\n' > "$GF_T/scripts/lr.sh"
LOG=docs/agents/runs.jsonl
LOGF="$GF_T/$LOG"
LEG=20                                     # the length of the filler log used where a row needs "a log that already has rows"
FILL="$T/filler.jsonl"; : > "$FILL"
for _i in $(seq 1 "$LEG"); do printf '%s\n' '{"date":"2026-10-11","family":"fam-x","model":"model-a","kind":"run","role":"lead","task":"filler","session":"s0","branch":"b0","wave":"H1","outcome":"ok","minutes":1}' >> "$FILL"; done
NEWL=$((LEG + 1))
REAL_LOG="$HERE/../docs/agents/runs.jsonl"; [ -e "$HERE/../running-files/agents/runs.jsonl" ] && REAL_LOG="$HERE/../running-files/agents/runs.jsonl"
REAL_LOG_SUM="$(cksum < "$REAL_LOG" 2>/dev/null)"
gf_reset() { rm -rf "$GF_T/docs" "$GF_T/elsewhere.jsonl" "$GF_T/no"; }
# gf_run_sync NAME ARGS...: run scripts/NAME in the fixture; GF_OUT = stdout+stderr, GF_RC = exit code
gf_run_sync() { local n="$1"; shift; if [ -n "$GF_RUN_ENV" ]; then GF_OUT="$(cd "$GF_T" && env "$GF_RUN_ENV" bash "scripts/$n" "$@" 2>&1)"; else GF_OUT="$(cd "$GF_T" && bash "scripts/$n" "$@" 2>&1)"; fi; GF_RC=$?; }
# _gf_check WANT FRAGMENT...: exit code (or "non-zero") and fragments of GF_OUT; "!x" = x must NOT be there. Sets GF_WHY.
_gf_check() {
  local want="$1" f; shift; GF_WHY=""
  if [ "$want" = non-zero ]; then [ "$GF_RC" != 0 ] || GF_WHY="exit 0, wanted non-zero"
  elif [ "$GF_RC" != "$want" ]; then GF_WHY="exit $GF_RC, wanted $want"; fi
  for f in "$@"; do
    case "$f" in
      '!'*) if printf '%s' "$GF_OUT" | grep -qF -- "${f#!}"; then GF_WHY="${GF_WHY:+$GF_WHY; }found '${f#!}'"; fi ;;
      *) printf '%s' "$GF_OUT" | grep -qF -- "$f" || GF_WHY="${GF_WHY:+$GF_WHY; }missing '$f'" ;;
    esac
  done
  [ -z "$GF_WHY" ]
}
gf_check() { if (cd "$GF_T" && eval "$2") >/dev/null 2>&1; then GF_PASS=$((GF_PASS + 1)); else GF_FAIL=$((GF_FAIL + 1)); echo "FAIL  $1"; fi; }
gf_expect() { local label="$1" want="$2"; shift 2; if _gf_check "$want" "$@"; then GF_PASS=$((GF_PASS + 1)); else GF_FAIL=$((GF_FAIL + 1)); echo "FAIL  $label  ($GF_WHY)"; fi; }
GF_BASH=bash
# ═══ scripts/log-agent-run.py: the one door a new row comes through ═══════════════════════════════════════════════════════
# The helper runs in the fixture (ROOT = $GF_T), so its default log is the fixture's docs/agents/runs.jsonl, never the real one.
# lr <name=value | -name>... [-- raw args...] : a valid call by default (builder, minutes 4); name=value overrides a default,
# -name drops it. lrx judges the LAST lr call: exit code, fragments, and - for a refusal - that the log is byte-identical.
LR_NAMES="model role task outcome session branch wave minutes"
lrdef() { case "$1" in model) echo model-a ;; role) echo builder ;; task) echo t ;; outcome) echo ok ;; session) echo s1 ;; branch) echo b1 ;; wave) echo H1 ;; minutes) echo 4 ;; esac; }
LOGF="$GF_T/$LOG"
lr() {
  LR_A=(); local n a v drop raw=0
  for n in $LR_NAMES; do
    v="$(lrdef "$n")"; drop=0
    for a in "$@"; do
      [ "$a" = "--" ] && break
      case "$a" in "-$n") drop=1 ;; "$n="*) v="${a#*=}" ;; esac
    done
    [ "$drop" = 1 ] || LR_A+=("--$n" "$v")
  done
  for a in "$@"; do if [ "$raw" = 1 ]; then LR_A+=("$a"); elif [ "$a" = "--" ]; then raw=1; fi; done
  LR_PRE="$(cat "$LOGF" 2>/dev/null; echo x)"
  gf_run_sync lr.sh "${LR_A[@]}"
  LR_POST="$(cat "$LOGF" 2>/dev/null; echo x)"
}
# lrx <label> <rc | nz> <fragment | !forbidden>... : rc 1 / 3 / nz (any non-zero) rows also require the log to be unchanged
lrx() {
  local label="$1" want="$2" why=""; shift 2
  if [ "$want" = nz ]; then if [ "$GF_RC" != 0 ]; then want="$GF_RC"; else want="non-zero"; fi; fi
  _gf_check "$want" "!Traceback" "$@" || why="$GF_WHY"
  if [ "$want" != 0 ] && [ "$LR_PRE" != "$LR_POST" ]; then why="${why:+$why; }the refused call CHANGED the log"; fi
  if [ -z "$why" ]; then GF_PASS=$((GF_PASS + 1)); else GF_FAIL=$((GF_FAIL + 1)); echo "FAIL  $label  ($why)"; printf '%s\n' "$GF_OUT" | tail -4 | sed 's/^/        | /'; fi
}
# lrlog: the Nth line of the fixture log, read back as JSON keys: lrlog <line> '<python expr over r>'
lrlog() { python3 -I -c 'import json,sys
r = json.loads(open(sys.argv[1], encoding="utf-8").read().splitlines()[int(sys.argv[2]) - 1])
print(json.dumps(eval(sys.argv[3]), ensure_ascii=False, separators=(",", ":")))' "$LOGF" "$1" "$2"; }
lrlogeq() { local got; got="$(lrlog "$2" "$3" 2>&1)"; if [ "$got" = "$4" ]; then GF_PASS=$((GF_PASS + 1)); else GF_FAIL=$((GF_FAIL + 1)); echo "FAIL  $1  (got $got, wanted $4)"; fi; }
fresh() { gf_reset; mkdir -p "$GF_T/docs/agents"; }                       # an empty fixture with no log
fresh596() { fresh; head -n "${1:-$LEG}" "$FILL" > "$LOGF"; }              # a log of that many filler lines (LEG = every new row is past the legacy part)
TODAY="$(date +%F)"

# ── the happy path and the normalisation of the model ───────────────────────────────────────────────────────────────────
fresh; lr
lrx "helper: a complete call appends line 1, exit 0, and prints the row" 0 "appended as line 1 of docs/agents/runs.jsonl" '"logged_by": "scripts/log-agent-run.py"'
lrlogeq "helper: the row holds the exact fields: date today, family from the model table, model, kind run, role, task, outcome, session, branch, wave, minutes 4.0, restarts 0" 1 '[r["date"],r["family"],r["model"],r["kind"],r["role"],r["task"],r["outcome"],r["session"],r["branch"],r["wave"],r["minutes"],r["restarts"],r["logged_by"]]' "[\"$TODAY\",\"fam-x\",\"model-a\",\"run\",\"builder\",\"t\",\"ok\",\"s1\",\"b1\",\"H1\",4.0,0,\"scripts/log-agent-run.py\"]"
fresh; lr model=ma
lrx "helper: the alias 'ma' is logged as 'model-a' and says so" 0 "note: model 'ma' logged as 'model-a' (lower-cased, or HARNESS_RUNLOG_MODEL_ALIASES)"
lrlogeq "helper: ... the stored model is canonical and the family follows it" 1 '[r["model"],r["family"]]' '["model-a","fam-x"]'
fresh; lr model=mc
lrlogeq "helper: alias 'mc' -> model-c, family fam-y" 1 '[r["model"],r["family"]]' '["model-c","fam-y"]'
fresh; lr "model=  Model-B "
lrlogeq "helper: a padded, mixed-case canonical model is normalised to 'model-b'" 1 '[r["model"],r["family"]]' '["model-b","fam-x"]'
fresh; lr model=model-a
lrx "helper sibling (T2): a canonical model prints no alias note" 0 "!logged as"
fresh; lr model=gpt-9
lrx "helper: an unknown model is refused, lists the known ones, nothing written" 1 "REFUSED: --model 'gpt-9' is not a known model" "model-a" "nothing was written"
fresh; lr model=model-b+model-a
lrx "helper: a two-model value is refused (log one row per model)" 1 "names several models; log one row per model"
fresh; lr model=""
lrx "helper: an empty model is refused" 1 "REFUSED"
fresh; lr role=wizard
lrx "helper: an unknown role is refused and the known roles are listed" 1 "REFUSED: --role 'wizard' is not one of" "builder"
fresh; lr "role= Builder "
lrlogeq "helper: a padded, capitalised role is normalised" 1 'r["role"]' '"builder"'
fresh; lr outcome=done
lrx "helper: an unknown outcome is refused" 1 "REFUSED: --outcome must be one of"
fresh; lr outcome=OK
lrlogeq "helper: outcome 'OK' is normalised to 'ok'" 1 'r["outcome"]' '"ok"'
fresh; lr -- --kind other
lrx "helper: an unknown kind is refused" 1 "REFUSED: --kind must be one of"
fresh; lr -- --fault theirs --failure-reason x
lrx "helper: an unknown fault is refused (the row detector says which are valid)" 1 "fault must be one of"
fresh; lr outcome=timeout -- --fault " OURS " --failure-reason "stuck before send"
lrx "helper: a failed run with a reason and a padded upper-case fault is accepted" 0 "appended as line 1"
lrlogeq "helper: ... the fault is stored normalised ('ours'), the reason kept" 1 '[r["outcome"],r["fault"],r["failure_reason"]]' '["timeout","ours","stuck before send"]'
fresh; lr outcome=timeout
lrx "helper: a failed outcome without --failure-reason is refused" 1 "outcome 'timeout' needs --failure-reason"
fresh; lr outcome=timeout -- --failure-reason "   "
lrx "helper: a failure reason of spaces only is refused (not accepted as a reason)" nz "REFUSED"
fresh; lr outcome=too-large -- --failure-reason "brief 383 KB"
lrx "helper sibling (T2): every failed outcome is fine WITH a reason" 0 "appended as line 1"

# ── session / branch / wave: the same formats as the gate, normalised by trimming ───────────────────────────────────────
for s in Sign sign_in -sign "" "sign in"; do fresh; lr "session=$s"; lrx "helper: session \"$s\" is refused with the format" 1 "REFUSED:"; done
fresh; lr "session=$(printf 'a%.0s' $(seq 1 49))"
lrx "helper: a 49-character session is refused" 1 "REFUSED: --session"
fresh; lr "session=$(printf 'a%.0s' $(seq 1 48))"
lrx "helper sibling (T2): a 48-character session is accepted" 0 "appended as line 1"
fresh; lr "session=  sign-in "
lrlogeq "helper: a padded session is trimmed in the log" 1 'r["session"]' '"sign-in"'
fresh; lr "session=$(printf 'abc\n')"
lrlogeq "helper: a trailing newline on the session is trimmed away (the stored name has none)" 1 'r["session"]' '"abc"'
for b in "a..b" "a b" "-x" "/x" ""; do fresh; lr "branch=$b"; lrx "helper: branch \"$b\" is refused" 1 "REFUSED:"; done
fresh; lr "branch=$(printf 'b%.0s' $(seq 1 201))"
lrx "helper: a 201-character branch is refused" 1 "REFUSED: --branch"
fresh; lr branch=dev_clone/wave8-export-1a2b3c
lrx "helper sibling (T2): a real branch name is accepted" 0 "appended as line 1"
for w in h63 H63ab wave8 None NONE none1 - "" H12345 63; do fresh; lr "wave=$w"; lrx "helper: wave \"$w\" is refused" 1 "REFUSED: --wave"; done
for w in H63 H63a H1 none; do fresh; lr "wave=$w"; lrx "helper: wave $w is accepted" 0 "appended as line 1"; done
fresh; lr "wave= none "
lrlogeq "helper: ' none ' is TRIMMED to 'none' (the helper normalises; the gate refuses the raw padded value - see the gate rows)" 1 'r["wave"]' '"none"'
fresh; lr wave=none role=lead
fresh; lr -session
lrx "helper: a missing --session is a refusal (exit 1), never argparse's exit 2" 1 "REFUSED: the following arguments are required: --session"
fresh; lr -branch -wave
lrx "helper: missing --branch and --wave are both named" 1 "--branch, --wave"
fresh; lr -- --no-such-flag
lrx "helper: an unknown flag is exit 1 'REFUSED', not argparse's 2" 1 "REFUSED"
fresh; lr -- --minutes abc
lrx "helper: a non-number --minutes is exit 1" 1 "REFUSED"

# ── time: usage block, explicit numbers, or a stated reason - exactly one source ────────────────────────────────────────
U1='<usage><subagent_tokens>412000</subagent_tokens><tool_uses>88</tool_uses><duration_ms>2712000</duration_ms></usage>'
fresh; lr -minutes -- --usage "$U1"
lrx "helper: a usage block is converted: 412000 tokens, 88 tool uses, 45.2 minutes" 0 "appended as line 1"
lrlogeq "helper: ... stored as tokens 412000, tool_uses 88, minutes 45.2 and the source names the notification" 1 '[r["tokens"],r["tool_uses"],r["minutes"],r["source"]]' '[412000,88,45.2,"harness task notification usage block"]'
U2='<usage><subagent_tokens>8000</subagent_tokens><tool_uses>2</tool_uses><duration_ms>30000</duration_ms></usage>'
fresh; lr -minutes -- --usage "$U1" --usage "$U2"
lrlogeq "helper: two --usage blocks (a resumed agent) are SUMMED: 420000 tokens, 90 tool uses, 45.7 minutes, source says 2 runs" 1 '[r["tokens"],r["tool_uses"],r["minutes"],r["source"]]' '[420000,90,45.7,"harness task notification usage blocks summed over 2 runs"]'
for miss in subagent_tokens tool_uses duration_ms; do
  fresh; lr -minutes -- --usage "$(printf '%s' "$U1" | sed "s#<$miss>[0-9]*</$miss>##")"
  lrx "helper: a usage block without <$miss> is refused and names the tag (found 0)" 1 "a --usage block needs exactly one <$miss>N</$miss> (found 0)"
  fresh; lr -minutes -- --usage "$(printf '%s' "$U1" | sed "s#<$miss>\([0-9]*\)</$miss>#<$miss>\1</$miss><$miss>5</$miss>#")"
  lrx "helper: a usage block with <$miss> given twice is refused (found 2)" 1 "a --usage block needs exactly one <$miss>N</$miss> (found 2)"
  for bad in abc -5 1.5 ""; do
    fresh; lr -minutes -- --usage "$(printf '%s' "$U1" | sed "s#<$miss>[0-9]*</$miss>#<$miss>$bad</$miss>#")"
    lrx "helper: <$miss>$bad</$miss> (not a whole non-negative number) is refused" 1 "a --usage block needs exactly one <$miss>N</$miss> (found 0)"
  done
done
fresh; lr -minutes -- --usage "$U1" --usage "$(printf '%s' "$U2" | sed 's#<tool_uses>2</tool_uses>##')"
lrx "helper: the SECOND of two blocks being incomplete refuses the whole call (nothing half-summed)" 1 "needs exactly one <tool_uses>N</tool_uses>"
fresh; lr -- --usage "$U1"
lrx "helper: --usage together with --minutes is refused ('give the time once')" 1 "give the time once: --usage and --minutes were both given"
fresh; lr -minutes -- --usage "$U1" --duration-ms 5000
lrx "helper: --usage together with --duration-ms is refused" 1 "give the time once"
fresh; lr -- --duration-ms 5000
lrx "helper: --minutes together with --duration-ms is refused" 1 "give the time once: --minutes and --duration-ms"
fresh; lr -- --not-timed "ran in the main checkout"
lrx "helper: --minutes together with --not-timed is refused" 1 "give the time once: --minutes and --not-timed"
fresh; lr -minutes -- --usage "$U1" --tokens 5
lrx "helper: --tokens together with --usage is refused (they come from the block)" 1 "--tokens / --tool-uses come from the --usage block"
fresh; lr -minutes -- --usage "$U1" --tool-uses 5
lrx "helper: --tool-uses together with --usage is refused" 1 "come from the --usage block"
for m in nan NaN inf -inf Infinity -1 -0.5 1e400 100000; do fresh; lr "minutes=$m"; lrx "helper: --minutes $m is refused (finite, 0 or more, below 100000)" 1 "REFUSED:"; done
fresh; lr minutes=99999.5
lrx "helper sibling (T2): --minutes 99999.5 is accepted (below the cap)" 0 "appended as line 1"
fresh; lr -minutes -- --duration-ms -5
lrx "helper: --duration-ms -5 is refused" 1 "REFUSED: --duration-ms must be 0 or more"
fresh; lr -minutes -- --duration-ms 90000 --tokens 10 --tool-uses 3
lrlogeq "helper: --duration-ms 90000 is 1.5 minutes; --tokens and --tool-uses are stored" 1 '[r["minutes"],r["tokens"],r["tool_uses"]]' '[1.5,10,3]'
fresh; lr minutes=2.3456
lrlogeq "helper: minutes are rounded to 2 decimals (2.3456 -> 2.35)" 1 'r["minutes"]' '2.35'
fresh; lr -minutes -- --tokens -3
lrx "helper: --tokens -3 is refused" 1 "REFUSED: --tokens must be 0 or more"
fresh; lr -- --tokens 1.5
lrx "helper: --tokens 1.5 is refused" 1 "REFUSED"
fresh; lr -minutes -- --not-timed "the call ran in the main checkout"
lrlogeq "helper: --not-timed stores minutes null and the reason in source as 'minutes not timed: <why>'" 1 '[r["minutes"],r["source"]]' '[null,"minutes not timed: the call ran in the main checkout"]'
fresh596; lr -minutes -- --not-timed "the call ran in the main checkout"
lrx "helper+gate: a builder run past line $LEG with --not-timed is accepted" 0 "appended as line $NEWL"
fresh; lr -minutes
lrx "helper: NO time source at all is refused for any role (the row detector wants minutes or a reason)" 1 "needs 'minutes'"
fresh; lr -minutes role=lead
lrx "helper: ... also for a lead run" 1 "needs 'minutes'"
fresh; lr -minutes -- --not-timed "$(printf 'x%.0s' $(seq 1 301))"
lrx "helper: a --not-timed reason over 300 characters is refused" 1 "REFUSED: --not-timed is 301 characters; at most 300"
fresh; lr -minutes -- --not-timed "$(printf 'one\ntwo')"
lrx "helper: a --not-timed reason with a newline is refused" 1 "REFUSED: --not-timed must be one line"
fresh; lr -minutes -- --not-timed "   "
lrx "helper: a --not-timed of spaces only is refused" 1 "REFUSED: --not-timed is empty"

# ── the new-row rule through the helper (the log has LEG lines, so the next row is line NEWL) and the legacy boundary ─────
fresh596 "$LEG"; lr minutes=0
lrx "helper+gate: a builder run with minutes 0 on line $NEWL is refused with the gate's own wording (no drift)" 1 "line $NEWL: a builder run needs minutes > 0"
fresh596 "$LEG"; lr role=lead minutes=0
lrx "helper sibling (T2): a lead run with minutes 0 on line $NEWL is accepted (not a timed role)" 0 "appended as line $NEWL"
# parity: what the helper accepts the gate accepts, and what it refuses the gate refuses the same way
fresh596 "$LEG"; lr minutes=4.2 -- --dry-run
HROW="$(printf '%s\n' "$GF_OUT" | sed -n '/^{/p' | head -1)"
fresh596 "$LEG"; lr minutes=4.2 model=mc -- --dry-run
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
gf_check "parity: the helper never prints an alias as the model (it would fail the gate on line $NEWL)" 'case "$GF_OUT" in *"\"model\": \"model-c\""*) true ;; *) false ;; esac'

# ── findings / accepted / rejected / corrections ────────────────────────────────────────────────────────────────────────
for role in tester reviewer test-author hunter; do
  fresh; lr role=$role
  lrx "helper: a $role run without --findings is refused ('0 is a number')" 1 "REFUSED: a $role run needs --findings (0 is a number)"
  fresh; lr role=$role -- --findings 0
  lrx "helper sibling (T2): a $role run with --findings 0 is accepted" 0 "appended as line 1"
done
fresh; lr role=builder
lrx "helper sibling (T2): a builder run needs no --findings" 0 "appended as line 1"
fresh; lr role=tester -- --findings 2 --accepted 2 --rejected 1
lrx "helper: accepted + rejected above findings is refused" 1 "REFUSED: --accepted + --rejected is more than --findings"
fresh; lr role=tester -- --findings 3 --accepted 2 --rejected 1
lrx "helper sibling (T2): accepted + rejected equal to findings is accepted" 0 "appended as line 1"
fresh; lr -- --accepted 1
lrx "helper: --accepted without --findings (a builder run) is refused" 1 "is more than --findings"
fresh; lr role=tester -- --findings -1
lrx "helper: --findings -1 is refused" 1 "REFUSED: --findings must be 0 or more"
fresh; lr role=tester -- --findings 2 --accepted -1
lrx "helper: --accepted -1 is refused" 1 "REFUSED: --accepted must be 0 or more"
fresh; lr role=tester -- --findings x
lrx "helper: --findings x is refused as exit 1" 1 "REFUSED"
fresh; lr role=lead -- --kind judgement
lrx "helper: a judgement row without findings, accepted and rejected is refused" 1 "a judgement row needs --findings, --accepted and --rejected"
fresh; lr role=lead -- --kind judgement --findings 3 --accepted 1
lrx "helper: a judgement row missing --rejected is refused" 1 "a judgement row needs --findings, --accepted and --rejected"
fresh; lr role=lead -- --kind judgement --findings 3 --accepted 2 --rejected 1
lrx "helper sibling (T2): a complete judgement row is accepted" 0 "appended as line 1"
lrlogeq "helper: ... and is stored as kind judgement with the counts" 1 '[r["kind"],r["findings"],r["accepted"],r["rejected"]]' '["judgement",3,2,1]'
fresh; lr role=lead -- --kind correction
lrx "helper: a correction row without --corrections is refused" 1 "a correction row needs --corrections N"
fresh; lr role=lead -- --kind correction --corrections 0
lrx "helper: a correction row with --corrections 0 is refused (0 corrections is not a correction)" 1 "a correction row needs --corrections N"
fresh; lr role=lead -- --kind correction --corrections 2
lrx "helper sibling (T2): a correction row with --corrections 2 is accepted" 0 "appended as line 1"
fresh; lr role=lead -- --kind correction --corrections -2
lrx "helper: --corrections -2 is refused" 1 "REFUSED"
fresh; lr -- --restarts -1
lrx "helper: --restarts -1 is refused" 1 "REFUSED: --restarts must be 0 or more"
fresh; lr -- --restarts 2
lrlogeq "helper: --restarts 2 is stored" 1 'r["restarts"]' '2'

# ── the date ────────────────────────────────────────────────────────────────────────────────────────────────────────────
for dt in 2099-01-01 2026-13-01 2026-02-30 26-10-19 2026-10-19x 20261019 "2026/10/19" abc; do
  fresh; lr -- --date "$dt"
  case "$dt" in 2099-01-01) lrx "helper: a future date ($dt) is refused" 1 "is in the future" ;; *) lrx "helper: a badly shaped date ($dt) is refused" 1 "REFUSED: --date" ;; esac
done
fresh; lr -- --date 2026-10-12
lrlogeq "helper sibling (T2): a past date is stored as given" 1 'r["date"]' '"2026-10-12"'
fresh; lr -- --date " $TODAY "
lrlogeq "helper: a padded date is trimmed" 1 'r["date"]' "\"$TODAY\""

# ── the free-text fields: task, failure reason, source (hostile input) ─────────────────────────────────────────
fresh; lr "task=$(printf 'line one\nline two')"
lrx "helper: a task with a newline is refused ('one line')" 1 "REFUSED: --task must be one line"
fresh; lr "task=$(printf 'a\rb')"
lrx "helper: a task with a carriage return is refused" 1 "REFUSED: --task must be one line"
fresh; lr "task=   "
lrx "helper: a task of spaces only is refused" 1 "REFUSED: --task is empty"
fresh; lr "task=$(printf '\033[31mred')"
lrx "helper: a task with an ESC (terminal control) is refused" 1 "holds a control character"
fresh; lr "task=$(printf 'x\177y')"
lrx "helper: a task with DEL is refused" 1 "holds a control character"
fresh; lr "task=$(printf 'x\001y')"
lrx "helper: a task with a SOH control byte is refused" 1 "holds a control character"
fresh; lr "task=$(printf 'x%.0s' $(seq 1 601))"
lrx "helper: a 601-character task is refused" 1 "REFUSED: --task is 601 characters; at most 600"
fresh; lr "task=$(printf 'x%.0s' $(seq 1 600))"
lrx "helper sibling (T2): a 600-character task is accepted" 0 "appended as line 1"
fresh; lr "task=   padded    with   gaps  "
lrlogeq "helper: a task is trimmed and its inner runs of spaces collapse to one" 1 'r["task"]' '"padded with gaps"'
fresh; lr "task=$(printf 'tab\there')"
lrlogeq "helper: a TAB inside a task becomes one space (whitespace is normalised)" 1 'r["task"]' '"tab here"'
fresh
# shellcheck disable=SC1111  # the unicode quotes are test data (the page text under test)
lr "task=ünïcode — dash “quotes” 日本語"
lrlogeq "helper: accents, dashes and CJK are kept as written (ensure_ascii off)" 1 'r["task"]' '"ünïcode — dash “quotes” 日本語"'
fresh
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
lr 'task=a | b `c` "d" \e </script><img src=x onerror=1> $(touch /nonexistent/x) ; --x'
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
lrlogeq "helper: pipes, backticks, quotes, backslashes, HTML and shell text are stored verbatim (data, never interpreted)" 1 'r["task"]' '"a | b `c` \"d\" \\e </script><img src=x onerror=1> $(touch /nonexistent/x) ; --x"'
# A page-data block must never hold an opening <script or <!-- : after "<!--" a "<script" makes the HTML parser treat the
# block's own closing tag as inner text, the rest of the page becomes data, and the board renders EMPTY (checked in a real
# browser on 2026-10-19: 0 charts, 0 log rows). The gate's script check also misreads a plain "<script>" in a task.
fresh; lr 'task=<script>x'
fresh; lr 'task=<!--<script>x'
fresh; lr -- --failure-reason "$(printf 'a\nb')"
lrx "helper: a --failure-reason with a newline is refused (even on an ok run)" nz "must be one line"
fresh; lr outcome=error -- --failure-reason "$(printf 'x%.0s' $(seq 1 601))"
lrx "helper: a 601-character failure reason is refused" 1 "REFUSED: --failure-reason is 601 characters"
fresh; lr -- --source "$(printf 'a\nb')"
lrx "helper: a --source with a newline is refused" 1 "REFUSED: --source must be one line"
fresh; lr -- --source "  from the log  "
lrlogeq "helper: --source is trimmed and stored" 1 'r["source"]' '"from the log"'
# whatever happens, no control character may reach the log (refused, or normalised to a space)
for pat in 033 001 007 010 013 014 034 037 177; do
  fresh; lr "task=x$(printf '%b' "\\0${pat}")y"
  if [ "$GF_RC" = 0 ]; then
    lrlogeq "helper invariant: task with octal byte $pat is either refused or stored with NO control character" 1 'any(ord(c) < 32 or ord(c) == 127 for c in r["task"])' 'false'
  else
    lrx "helper invariant: task with octal byte $pat is refused and the log is untouched" nz "REFUSED"
  fi
done
# nastier: characters that are not ASCII controls but hide or reorder text in a terminal and a board. Lead ruling 2026-10-19: refuse Cf (format,
# bidi), Cc, Zl, Zp, Co and Cn characters in free text.
fresh; lr "task=$(printf 'safe \342\200\256txet neddih')"
lrx "helper (lead ruling): a task with U+202E (right-to-left override) is refused" 1 "REFUSED:" "nothing was written"
fresh; lr "task=$(printf 'a\342\200\213b')"
lrx "helper (lead ruling): a task with U+200B (zero-width space) is refused" 1 "REFUSED:" "nothing was written"
for cp in $'\342\201\246:U+2066 (bidi isolate)' $'\357\273\277:U+FEFF (byte order mark)' $'\302\255:U+00AD (soft hyphen)' $'\356\200\200:U+E000 (private use)' $'\342\200\252:U+202A (left-to-right embedding)'; do
  fresh; lr "task=a${cp%%:*}b"
  lrx "helper (lead ruling): a task with ${cp#*:} is refused and the log is untouched" 1 "REFUSED:" "nothing was written"
done
fresh; lr -- --failure-reason "a$(printf '\342\200\256')b" outcome=error
lrx "helper (lead ruling): the same refusal holds for --failure-reason" 1 "REFUSED:"
fresh; lr -- --source "a$(printf '\342\200\213')b"
lrx "helper (lead ruling): ... and for --source" 1 "REFUSED:"
fresh; lr -- --not-timed "a$(printf '\342\200\256')b" -minutes
lrx "helper (lead ruling): ... and for --not-timed" 1 "REFUSED:"
for cp in $'\302\205:U+0085 (next line)' $'\342\200\250:U+2028 (line separator)' $'\342\200\251:U+2029 (paragraph separator)'; do
  fresh; lr "task=a${cp%%:*}b"
  lrx "helper: a task with ${cp#*:} is whitespace to Python, so it is normalised to ONE plain space (like a TAB), never stored as such" 0 "appended as line 1"
  lrlogeq "helper: ... the stored task is exactly 'a b'" 1 'r["task"]' '"a b"'
done
fresh; lr "task=Grüße — café ñ 日本語 ✓ 🙂"
lrx "helper sibling (T2): letters, accents, dashes, CJK, a check mark and an emoji are still accepted" 0 "appended as line 1"
fresh; lr "task=$(printf 'x\205y')"
lrx "helper (lead ruling): a task with an invalid UTF-8 byte is REFUSED (exit 1, bad input), never a traceback, a crash or a half-written line" 1 "REFUSED:" "not valid UTF-8" "nothing was written"

# ── the log file: location, last line, folder, locking, dry run, bytecode ──────────────────────────────────────────────
fresh; lr -- --dry-run
lrx "helper: --dry-run prints the row and 'valid as line 1' and exits 0" 0 "dry run: valid as line 1" "nothing was written"
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
gf_check "helper: --dry-run created no log file" '[ ! -e "$LOGF" ]'
fresh596 3; lr -- --dry-run
lrx "helper: --dry-run on a 3-line log says line 4" 0 "dry run: valid as line 4"
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
gf_check "helper: ... and the 3-line log is byte-identical (nothing written)" '[ "$LR_PRE" = "$LR_POST" ]'
fresh596 3; lr
lrx "helper: a real call on a 3-line log appends as line 4" 0 "appended as line 4"
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
gf_check "helper: ... the log now has 4 lines and the first 3 are untouched" '[ "$(wc -l < "$LOGF" | tr -d " ")" = 4 ] && [ "$(head -n 3 "$LOGF")" = "$(head -n 3 "$FILL")" ]'
fresh; printf '{"date":"2026-10-11","family":"fam-x","model":"model-a","kind":"run","role":"lead","task":"no newline","outcome":"ok","minutes":1}' > "$LOGF"; lr
lrx "helper: a log whose last line has NO newline: the new row lands on line 2, not glued to line 1" 0 "appended as line 2"
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
gf_check "helper: ... the log has 2 whole JSON lines and the first is intact" '[ "$(wc -l < "$LOGF" | tr -d " ")" = 2 ] && python3 -I -c "import json,sys
ls = open(sys.argv[1]).read().split(chr(10))
assert json.loads(ls[0])[\"task\"] == \"no newline\" and json.loads(ls[1])[\"task\"] == \"t\" and ls[2] == \"\"" "$LOGF"'
fresh; : > "$LOGF"; lr
lrx "helper: an empty log file: the row lands on line 1" 0 "appended as line 1"
# shellcheck disable=SC2154  # LR_PRE is set by lr
fresh; : > "$GF_T/elsewhere.jsonl"; GF_RUN_ENV="HARNESS_RUNLOG=$GF_T/elsewhere.jsonl"; lr
lrx "helper: HARNESS_RUNLOG selects the log (the default is the repo's log)" 0 "appended as line 1 of"
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
gf_check "helper: ... the row went to that file and not to the default log" '[ -s "$GF_T/elsewhere.jsonl" ] && [ ! -s "$LOGF" ]'
GF_RUN_ENV=""
fresh; lr -- --log "$GF_T/no/such/folder/runs.jsonl"
lrx "helper: a missing log FOLDER is exit 3 INCOMPLETE ('could not run'), not 0 and not a traceback" 3 "INCOMPLETE: the log folder" "does not exist"
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
gf_check "helper: ... and the folder was not created" '[ ! -e "$GF_T/no" ]'
fresh; mkdir -p "$GF_T/docs/agents/adir"; lr -- --log "$GF_T/docs/agents/adir"
lrx "helper: a log path that is a directory is exit 3 with a one-line reason, nothing written" 3 "INCOMPLETE: log-agent-run.py crashed" "nothing was written"
if [ "$(id -u)" != 0 ]; then
  fresh596 3; chmod 444 "$LOGF"; lr
  lrx "helper: a read-only log is a clean refusal / could-not-run, never a half write" nz "nothing was written"
  chmod 644 "$LOGF"
fi
# two helpers at once (the lock): 8 background calls with a big task each; every row must land whole, once
fresh596 "$LEG"; LOCKPIDS=""
for i in 1 2 3 4 5 6 7 8; do
  ( cd "$GF_T" && "$GF_BASH" scripts/lr.sh --model model-a --role lead --task "race $i $(printf 'z%.0s' $(seq 1 500))" --outcome ok --session s1 --branch b1 --wave H1 --minutes 1 > "$GF_T.res.race.$i" 2>&1 ) &
  LOCKPIDS="$LOCKPIDS $!"
done
for p in $LOCKPIDS; do wait "$p"; done
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
gf_check "lock: 8 helpers appending at once leave LEG+8 lines, all valid JSON, 8 distinct race tasks, none cut or glued" '[ "$(wc -l < "$LOGF" | tr -d " ")" = "$((LEG + 8))" ] && python3 -I -c "import json,sys
leg = int(sys.argv[2])
ls = open(sys.argv[1], encoding=\"utf-8\").read().split(chr(10))
assert ls[-1] == \"\" and len(ls) == leg + 9
rows = [json.loads(l) for l in ls[leg:leg + 8]]
assert sorted(r[\"task\"].split()[1] for r in rows) == [str(i) for i in range(1, 9)]" "$LOGF" "$LEG"'
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
gf_check "lock: ... and each of the 8 helpers reported success" '[ "$(cat "$GF_T".res.race.* | grep -c "^appended as line")" = 8 ]'
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
gf_check "bytecode: the helper left no __pycache__ in the fixture's scripts folder (it imports agent-board.py)" '[ ! -e "$GF_T/scripts/__pycache__" ]'
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
gf_check "bytecode: ... nor in the real scripts folder" '[ ! -e "$HERE/__pycache__" ]'
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
gf_check "isolation: the real docs/agents/runs.jsonl was not touched by any row of this section" '[ "$(cksum < "$REAL_LOG")" = "$REAL_LOG_SUM" ]'

# ── extra hostile input for the helper's fields (proposed by the cross author; each is also a T2 pair) ───────────────────
fresh; lr 'task=x","role":"lead","outcome":"error'
lrlogeq "helper: a task that tries to inject JSON fields (\"role\", \"outcome\") stays ONE string; role and outcome keep their values" 1 '[r["role"],r["outcome"],r["task"]]' '["builder","ok","x\",\"role\":\"lead\",\"outcome\":\"error"]'
fresh
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
lr 'task=%s {0} {task} \n %(x)d ${HOME} {{}}'
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check, python or the fixture
lrlogeq "helper: format-string and variable-looking text is stored as written (nothing is expanded)" 1 'r["task"]' '"%s {0} {task} \\n %(x)d ${HOME} {{}}"'
fresh; lr -task -- "--task=-leading dash"
lrlogeq "helper: a task that starts with a dash is kept when given as --task=VALUE" 1 'r["task"]' '"-leading dash"'
fresh; lr "session=$(printf 's\321\226gn')"
lrx "helper: a session spelled with a Cyrillic look-alike letter is refused (ASCII only)" 1 "REFUSED:"
fresh; lr -- --date "２０２６-10-19"
lrx "helper: a date written with full-width digits is refused" 1 "REFUSED: --date"
fresh; lr -- --source "$(printf 'x%.0s' $(seq 1 601))"
lrx "helper: a 601-character --source is refused" 1 "REFUSED: --source is 601 characters; at most 600"
fresh; lr -- --source "from the notification of 2026-10-19 | task 7"
lrlogeq "helper sibling (T2): a normal --source with a pipe is stored" 1 'r["source"]' '"from the notification of 2026-10-19 | task 7"'
# line numbers agree between the helper and the gate when the log holds a blank line (the gate counts raw lines)



# ── scripts/log-agent-run.py: --kind infra, and the interrupted outcomes ─────────────────────────────────────────────────
LI_NAMES="what minutes cause affected session branch wave"
lidef() { case "$1" in what) echo "Docker hung" ;; minutes) echo 60 ;; cause) echo "docker info hung" ;; affected) echo "the push gate run" ;; session) echo lead ;; branch) echo main ;; wave) echo H62 ;; esac; }
li() { # like lr: a valid --kind infra call by default; name=value overrides, -name drops; raw arguments after --
  LR_A=(--kind infra); local n a v drop raw=0
  for n in $LI_NAMES; do
    v="$(lidef "$n")"; drop=0
    for a in "$@"; do
      [ "$a" = "--" ] && break
      case "$a" in "-$n") drop=1 ;; "$n="*) v="${a#*=}" ;; esac
    done
    [ "$drop" = 1 ] || LR_A+=("--$n" "$v")
  done
  for a in "$@"; do if [ "$raw" = 1 ]; then LR_A+=("$a"); elif [ "$a" = "--" ]; then raw=1; fi; done
  LR_PRE="$(cat "$LOGF" 2>/dev/null; echo x)"
  gf_run_sync lr.sh "${LR_A[@]}"
  LR_POST="$(cat "$LOGF" 2>/dev/null; echo x)"
}
fresh; li
lrx "helper infra: a complete call appends line 1, exit 0, prints the row" 0 "appended as line 1 of docs/agents/runs.jsonl" '"kind": "infra"' '"logged_by": "scripts/log-agent-run.py"'
lrlogeq "helper infra: the stored row has exactly these keys, no model, family, task or outcome" 1 'sorted(r)' '["affected","branch","cause","date","kind","logged_by","minutes","session","source","wave","what"]'
lrlogeq "helper infra: ... with the values as given (minutes a float 60.0, source null)" 1 '[r["kind"],r["what"],r["minutes"],r["cause"],r["affected"],r["session"],r["branch"],r["wave"],r["source"],r["date"]]' "[\"infra\",\"Docker hung\",60.0,\"docker info hung\",\"the push gate run\",\"lead\",\"main\",\"H62\",null,\"$TODAY\"]"
fresh; li -- --source "  lead's own record  "
lrlogeq "helper infra: --source is trimmed and stored" 1 'r["source"]' '"lead'"'"'s own record"'
fresh; li "what=  Docker    hung  "
lrlogeq "helper infra: 'what' is trimmed and its inner spaces collapse to one" 1 'r["what"]' '"Docker hung"'
fresh596 "$LEG"; li
lrx "helper infra: past the legacy part of the log the row needs no model, session lookup or minutes rule beyond its own: appended as line $NEWL" 0 "appended as line $NEWL"
# every run-only option is refused, one by one, with the option named and the log untouched
for pair in "--model:model-a" "--role:builder" "--task:t" "--outcome:ok" "--not-timed:why" "--tokens:5" "--tool-uses:2" "--findings:0" "--accepted:0" "--rejected:0" "--corrections:0" "--restarts:0" "--failure-reason:x" "--fault:model" "--usage:$U1" "--model:"; do
  opt="${pair%%:*}"; val="${pair#*:}"
  fresh; li -- "$opt" "$val"
  lrx "helper infra: $opt is refused for --kind infra (a machine problem names no model and no run), the log untouched" 1 "REFUSED: a machine-problem row (--kind infra) names no model and no run:" "$opt not allowed" "nothing was written"
done
fresh; li -- --model model-a --outcome ok --fault ours
lrx "helper infra: several run-only options are ALL named in one refusal" 1 "--model, --outcome, --fault not allowed"
fresh; li -- --restarts 0
lrx "helper infra: a zero value is not 'absent': --restarts 0 is refused too" 1 "--restarts not allowed"
# each missing infra field
for k in what cause affected; do
  fresh; li -$k
  lrx "helper infra: a missing --$k is refused and named" 1 "REFUSED: a machine-problem row needs --$k" "nothing was written"
done
fresh; li -minutes
lrx "helper infra: no --minutes and no --duration-ms is refused and --minutes is named" 1 "REFUSED: a machine-problem row needs --minutes"
for k in session branch wave; do
  fresh; li -$k
  lrx "helper infra: a missing --$k is refused (exit 1, never argparse's 2)" 1 "REFUSED: the following arguments are required: --$k"
done
fresh; li -what -cause -minutes
lrx "helper infra: several missing fields are all named, in the order what, cause, minutes" 1 "needs --what, --cause, --minutes"
# time: exactly one source, above 0
fresh; li -- --duration-ms 3600000
lrx "helper infra: --minutes together with --duration-ms is refused ('give the time once')" 1 "give the time once: --minutes and --duration-ms were both given"
fresh; li -minutes -- --duration-ms 3600000
lrlogeq "helper infra: --duration-ms 3600000 is converted to 60.0 minutes" 1 'r["minutes"]' '60.0'
fresh; li -minutes -- --duration-ms 90000
lrlogeq "helper infra: --duration-ms 90000 is 1.5 minutes" 1 'r["minutes"]' '1.5'
fresh; li -minutes -- --duration-ms 0
lrx "helper infra: --duration-ms 0 is refused (a machine problem that cost no time is not a row)" 1 "REFUSED: a machine-problem row needs the minutes lost, above 0"
fresh; li -minutes -- --duration-ms 1
lrx "helper infra: --duration-ms 1 rounds to 0.0 minutes and is refused as 'above 0'" 1 "needs the minutes lost, above 0"
fresh; li -minutes -- --duration-ms -5
lrx "helper infra: --duration-ms -5 is refused" 1 "REFUSED: --duration-ms must be 0 or more"
for m in 0 0.0 0.004; do fresh; li "minutes=$m"; lrx "helper infra: --minutes $m is 0 minutes and is refused as 'above 0'" 1 "REFUSED: a machine-problem row needs the minutes lost, above 0"; done
for m in -1 -0.5 nan NaN 1e400 100000; do fresh; li "minutes=$m"; lrx "helper infra: --minutes $m is refused (finite, 0 or more, below 100000)" 1 "REFUSED: --minutes must be a finite number, 0 or more"; done
for m in inf -inf Infinity abc; do fresh; li "minutes=$m"; lrx "helper infra: --minutes $m is refused" 1 "REFUSED:"; done
fresh; li minutes=0.01
lrlogeq "helper infra sibling (T2): --minutes 0.01 is above 0 and kept" 1 'r["minutes"]' '0.01'
fresh; li minutes=99999.5
lrx "helper infra sibling (T2): --minutes 99999.5 is accepted (below the cap)" 0 "appended as line 1"
fresh; li minutes=2.3456
lrlogeq "helper infra: minutes are rounded to 2 decimals" 1 'r["minutes"]' '2.35'
# free text: one line, no control or invisible character, limits 120 / 600 / 600
for f in what cause affected; do
  fresh; li "$f=$(printf 'one\ntwo')"
  lrx "helper infra: --$f with a newline is refused ('one line')" 1 "REFUSED: --$f must be one line"
  fresh; li "$f=$(printf 'a\033[31mb')"
  lrx "helper infra: --$f with an ESC is refused" 1 "REFUSED: --$f holds a control character"
  fresh; li "$f=a$(printf '\342\200\256')b"
  lrx "helper infra: --$f with U+202E (right-to-left override) is refused" 1 "REFUSED: --$f holds the invisible or direction character U+202E"
  fresh; li "$f=a$(printf '\342\200\213')b"
  lrx "helper infra: --$f with U+200B (zero-width space) is refused" 1 "REFUSED: --$f holds the invisible or direction character U+200B"
  fresh; li "$f=a$(printf '\357\273\277')b"
  lrx "helper infra: --$f with U+FEFF (byte order mark) is refused" 1 "REFUSED: --$f holds the invisible or direction character U+FEFF"
  fresh; li "$f=   "
  lrx "helper infra: --$f of spaces only is refused" 1 "REFUSED: --$f is empty"
  fresh; li "$f=$(printf 'x\205y')"
  lrx "helper infra: --$f with an invalid UTF-8 byte is refused as bad input (exit 1), not a crash" 1 "REFUSED: --$f is not valid UTF-8"
  fresh; li "$f=ünïcode — café 日本語 ✓"
  lrx "helper infra sibling (T2): accents, a dash, CJK and a check mark are accepted in --$f" 0 "appended as line 1"
done
fresh; li "what=$(printf 'w%.0s' $(seq 1 121))"
lrx "helper infra: a 121-character --what is refused (limit 120)" 1 "REFUSED: --what is 121 characters; at most 120"
fresh; li "what=$(printf 'w%.0s' $(seq 1 120))"
lrx "helper infra sibling (T2): a 120-character --what is accepted" 0 "appended as line 1"
fresh; li "cause=$(printf 'c%.0s' $(seq 1 601))"
lrx "helper infra: a 601-character --cause is refused (limit 600)" 1 "REFUSED: --cause is 601 characters; at most 600"
fresh; li "cause=$(printf 'c%.0s' $(seq 1 600))"
lrx "helper infra sibling (T2): a 600-character --cause is accepted" 0 "appended as line 1"
fresh; li "affected=$(printf 'a%.0s' $(seq 1 601))"
lrx "helper infra: a 601-character --affected is refused (limit 600)" 1 "REFUSED: --affected is 601 characters; at most 600"
fresh; li "affected=$(printf 'a%.0s' $(seq 1 600))"
lrx "helper infra sibling (T2): a 600-character --affected is accepted" 0 "appended as line 1"
fresh; li -- --source "$(printf 'a\nb')"
lrx "helper infra: a --source with a newline is refused" 1 "REFUSED: --source must be one line"
fresh; li -- --source "a$(printf '\342\200\213')b"
lrx "helper infra: a --source with U+200B is refused" 1 "REFUSED: --source holds the invisible or direction character"
# the date
fresh; li -- --date 2099-01-01
lrx "helper infra: a future date is refused" 1 "is in the future"
for dt in 2026-13-01 2026-02-30 26-10-19 abc; do fresh; li -- --date "$dt"; lrx "helper infra: a badly shaped date ($dt) is refused" 1 "REFUSED: --date"; done
fresh; li -- --date 2026-10-12
lrlogeq "helper infra sibling (T2): a past date is stored as given" 1 'r["date"]' '"2026-10-12"'
fresh; li -- --date " $TODAY "
lrlogeq "helper infra: a padded date is trimmed" 1 'r["date"]' "\"$TODAY\""
# session / branch / wave patterns, with trimming
for v in Bad_Name "" "a b"; do fresh; li "session=$v"; lrx "helper infra: session \"$v\" is refused" 1 "REFUSED: --session"; done
fresh; li "session=-x"
lrx "helper infra: session \"-x\" is refused (argparse reads it as a flag; still exit 1, nothing written)" 1 "REFUSED:"
for v in "a..b" "a b" "/x" ""; do fresh; li "branch=$v"; lrx "helper infra: branch \"$v\" is refused" 1 "REFUSED: --branch"; done
fresh; li "branch=-x"
lrx "helper infra: branch \"-x\" is refused (argparse reads it as a flag; still exit 1, nothing written)" 1 "REFUSED:"
for v in h62 H62xx None NONE "H 62" ""; do fresh; li "wave=$v"; lrx "helper infra: wave \"$v\" is refused" 1 "REFUSED: --wave"; done
fresh; li wave=none
lrx "helper infra sibling (T2): wave none is accepted (side work outside any wave)" 0 "appended as line 1"
fresh; li "wave= H59a " "session=  s9 " "branch= isa_clone/x-1a2b3c "
lrlogeq "helper infra: padded session, branch and wave are trimmed" 1 '[r["session"],r["branch"],r["wave"]]' '["s9","isa_clone/x-1a2b3c","H59a"]'
# dry run: prints, writes nothing; a refusal under --dry-run is still a refusal
fresh; li -- --dry-run
lrx "helper infra: --dry-run prints the row and 'valid as line 1' and exits 0" 0 "dry run: valid as line 1" "nothing was written" '"kind": "infra"'
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check
gf_check "helper infra: --dry-run created no log file" '[ ! -e "$LOGF" ]'
fresh596 3; li -- --dry-run
lrx "helper infra: --dry-run on a 3-line log says line 4" 0 "dry run: valid as line 4"
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check
gf_check "helper infra: ... and the 3-line log is byte-identical" '[ "$LR_PRE" = "$LR_POST" ]'
HIROW="$(printf '%s\n' "$GF_OUT" | sed -n '/^{/p' | head -1)"
fresh; li minutes=0 -- --dry-run
lrx "helper infra: a refusal under --dry-run is still a refusal (exit 1, no 'dry run:' line)" 1 "REFUSED:" "!dry run:"
# a run row may not carry the machine-problem fields
for k in what cause affected; do
  fresh; lr -- --$k x
  lrx "helper: a run row refuses --$k (it belongs to a machine-problem row), the log untouched" 1 "REFUSED: --$k belongs to a machine-problem row (--kind infra), not a run row" "nothing was written"
done
fresh; lr role=lead -- --kind judgement --findings 3 --accepted 2 --rejected 1 --what x
lrx "helper: a judgement row refuses --what too and names the kind" 1 "REFUSED: --what belongs to a machine-problem row (--kind infra), not a judgement row"
# a run row still needs model, role, task and outcome (not argparse's required any more)
for k in model role task outcome; do
  fresh; lr -$k
  lrx "helper: a run without --$k exits 1 'the following arguments are required: --$k' (never argparse's 2)" 1 "REFUSED: the following arguments are required: --$k" "nothing was written"
done
fresh; lr -model -role -task -outcome
lrx "helper: a run missing all four names all four in order" 1 "the following arguments are required: --model, --role, --task, --outcome"
fresh; lr -model -task
lrx "helper: a run missing two names exactly those two" 1 "the following arguments are required: --model, --task" "!--role"
fresh; li -- --kind INFRA
lrx "helper: the kind is matched exactly: --kind INFRA is not a machine-problem row, it is a run row with no model (refused, nothing written)" 1 "REFUSED: the following arguments are required: --model, --role, --task, --outcome"
fresh; li -- --kind infrastructure
lrx "helper: --kind infrastructure is refused too" 1 "REFUSED:"
# interrupted outcomes
for oc in stopped killed restarted; do
  fresh; lr outcome=$oc -- --failure-reason "lead stopped it" --fault Model
  lrx "helper interrupted: a $oc run with a reason, fault 'Model' (case) and the default 4 minutes is accepted" 0 "appended as line 1"
  lrlogeq "helper interrupted: ... stored as outcome $oc, fault 'model' (lower case), the reason, minutes 4.0" 1 '[r["outcome"],r["fault"],r["failure_reason"],r["minutes"]]' "[\"$oc\",\"model\",\"lead stopped it\",4.0]"
  fresh; lr outcome=$oc -- --failure-reason "our script bug" --fault " OURS "
  lrlogeq "helper interrupted: a padded upper-case fault ' OURS ' is stored as 'ours'" 1 'r["fault"]' '"ours"'
  fresh; lr outcome=$oc -- --failure-reason "limit too low" --fault config
  lrx "helper interrupted sibling (T2): fault config is accepted for a $oc run" 0 "appended as line 1"
  fresh; lr "outcome=$(printf '%s' "$oc" | tr '[:lower:]' '[:upper:]')" -- --failure-reason "x" --fault model
  lrlogeq "helper interrupted: an upper-case outcome is normalised ($oc)" 1 'r["outcome"]' "\"$oc\""
  fresh; lr outcome=$oc -- --failure-reason "x"
  lrx "helper interrupted (lead ruling): a $oc run with no --fault is refused and the judged faults are named" 1 "REFUSED: outcome '$oc' needs --fault config | model | ours" "nothing was written"
  for f in unknown theirs provider ""; do
    fresh; lr outcome=$oc -- --failure-reason "x" --fault "$f"
    lrx "helper interrupted (lead ruling): a $oc run with --fault \"$f\" is refused ('unknown' is not a judgement; 'provider' is spelt 'model')" 1 "REFUSED: outcome '$oc' needs --fault config | model | ours"
  done
  fresh; lr outcome=$oc -- --fault model
  lrx "helper interrupted: a $oc run with no --failure-reason is refused" 1 "REFUSED: outcome '$oc' needs --failure-reason"
  fresh; lr outcome=$oc -- --failure-reason "   " --fault model
  lrx "helper interrupted: a $oc run with a blank --failure-reason is refused" nz "REFUSED"
  fresh; lr -minutes outcome=$oc -- --failure-reason "x" --fault model --not-timed "no time known"
  lrx "helper interrupted: a $oc run with --not-timed is refused: the lost time is the point of the row" 1 "REFUSED: outcome '$oc' needs the minutes lost (--usage, --minutes or --duration-ms), not --not-timed"
  fresh; lr -minutes outcome=$oc -- --failure-reason "x" --fault model
  lrx "helper interrupted: a $oc run with no time at all is refused (needs the minutes lost, above 0)" 1 "REFUSED: outcome '$oc' needs the minutes lost, above 0"
  fresh; lr minutes=0 outcome=$oc -- --failure-reason "x" --fault model
  lrx "helper interrupted: a $oc run with 0 minutes is refused" 1 "REFUSED: outcome '$oc' needs the minutes lost, above 0"
  fresh; lr minutes=0.004 outcome=$oc -- --failure-reason "x" --fault model
  lrx "helper interrupted: a $oc run with 0.004 minutes (rounds to 0.0) is refused" 1 "needs the minutes lost, above 0"
  fresh; lr -minutes outcome=$oc -- --failure-reason "x" --fault model --duration-ms 0
  lrx "helper interrupted: a $oc run with --duration-ms 0 is refused" 1 "needs the minutes lost, above 0"
  fresh; lr -minutes outcome=$oc -- --failure-reason "x" --fault model --usage '<usage><subagent_tokens>10</subagent_tokens><tool_uses>1</tool_uses><duration_ms>0</duration_ms></usage>'
  lrx "helper interrupted: a $oc run whose usage block says duration_ms 0 is refused" 1 "needs the minutes lost, above 0"
  fresh; lr -minutes outcome=$oc -- --failure-reason "x" --fault model --usage "$U1"
  lrlogeq "helper interrupted sibling (T2): a $oc run with a real usage block keeps its 45.2 lost minutes and its tokens" 1 '[r["minutes"],r["tokens"],r["outcome"]]' "[45.2,412000,\"$oc\"]"
  fresh; lr role=lead minutes=0 outcome=$oc -- --failure-reason "x" --fault model
  lrx "helper interrupted: a lead run (not a timed role) still needs the lost minutes: 0 is refused for $oc" 1 "needs the minutes lost, above 0"
  fresh; lr role=lead outcome=$oc -- --failure-reason "x" --fault model
  lrx "helper interrupted sibling (T2): the same lead $oc run with minutes 4 is accepted" 0 "appended as line 1"
done
fresh; lr outcome=ok -- --fault ours
lrx "helper sibling (T2): an ok run may carry a fault and needs no reason (the interrupted rules are for the three outcomes only)" 0 "appended as line 1"
fresh; lr outcome=timeout -- --failure-reason x --fault unknown
lrx "helper sibling (T2): a timeout with fault 'unknown' is still accepted (only the interrupted outcomes refuse it)" 0 "appended as line 1"
# the interrupted rows a user logs end up in the numbers: a stopped model-fault run from the helper raises Fail % (end to end)
fresh; lr model=model-flash role=builder outcome=ok task=first
lr model=model-flash role=builder outcome=stopped task=second minutes=6 -- --failure-reason "lead stopped it" --fault model
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check
# shellcheck disable=SC2016  # single quotes on purpose: the text is evaluated later by gf_check
gf_check "isolation: the real docs/agents/runs.jsonl was not touched by the round-2 rows either" '[ "$(cksum < "$REAL_LOG")" = "$REAL_LOG_SUM" ]'


# ── The helper holds the same cap and the same blank/date checks ─────────────────────────────────────────────────────────
UB() { printf '<usage><subagent_tokens>1</subagent_tokens><tool_uses>1</tool_uses><duration_ms>%s</duration_ms></usage>' "$1"; }
fresh; lr -minutes -- --usage "$(UB 6000000000)"
lrx "cap helper: a --usage block of 6000000000 ms (exactly 100000 minutes) is refused, exit 1" 1 "REFUSED: --duration-ms 6000000000 is 100000 minutes or more" "nothing was written" "!INCOMPLETE"
fresh; lr -minutes -- --usage "$(UB 3000000000)" --usage "$(UB 3000000000)"
lrx "cap helper: two blocks of 3000000000 ms are each fine but SUM to the cap: refused, exit 1" 1 "is 100000 minutes or more" "nothing was written"
fresh; lr -minutes -- --usage "$(UB 3000000000)"
lrlogeq "cap helper sibling (T2): ONE block of 3000000000 ms is accepted: 50000.0 minutes" 1 'r["minutes"]' '50000.0'
fresh; lr -minutes -- --usage "$(UB 3000000000)" --usage "$(UB 2999999999)"
lrx "cap helper: blocks summing to 5999999999 ms pass the ms check but round to 100000.0 minutes, which the gate refuses: the helper refuses too (exit 1, nothing written)" 1 "REFUSED:" "nothing was written" "!appended"
fresh; lr -minutes -- --usage "$(UB 5999940000)"
lrlogeq "cap helper sibling (T2): 5999940000 ms is 99999.0 minutes and is kept" 1 'r["minutes"]' '99999.0'
fresh; lr -minutes -- --usage "$(UB "$(printf '9%.0s' $(seq 1 401))")"
lrx "cap helper: a usage block with a 401-digit duration_ms is a refusal (exit 1), not an OverflowError" 1 "is 100000 minutes or more" "!INCOMPLETE" "!Overflow" "nothing was written"
fresh; lr -minutes -- --duration-ms 6000000000
lrx "cap helper: --duration-ms 6000000000 on a run is refused" 1 "REFUSED: --duration-ms 6000000000 is 100000 minutes or more"
fresh; lr -minutes -- --duration-ms "$(printf '9%.0s' $(seq 1 401))"
lrx "cap helper: a 401-digit --duration-ms on a run is a refusal, not 'INCOMPLETE ... OverflowError'" 1 "is 100000 minutes or more" "!INCOMPLETE" "!Overflow"
fresh; lr -minutes -- --duration-ms 5999940000
lrlogeq "cap helper sibling (T2): --duration-ms 5999940000 on a run is kept as 99999.0" 1 'r["minutes"]' '99999.0'
fresh; lr minutes=99999.99
lrlogeq "cap helper sibling (T2): --minutes 99999.99 on a run is kept" 1 'r["minutes"]' '99999.99'
fresh; lr minutes=100000
lrx "cap helper: --minutes 100000 on a run is refused" 1 "REFUSED: --minutes must be a finite number"
fresh; li -minutes -- --duration-ms 6000000000
lrx "cap helper: --duration-ms 6000000000 on an infra row is refused" 1 "REFUSED: --duration-ms 6000000000 is 100000 minutes or more"
fresh; li -minutes -- --duration-ms "$(printf '9%.0s' $(seq 1 401))"
lrx "cap helper: a 401-digit --duration-ms on an infra row is a refusal, not a crash" 1 "is 100000 minutes or more" "!INCOMPLETE" "!Overflow"
fresh; li -minutes -- --duration-ms 5999940000
lrlogeq "cap helper sibling (T2): --duration-ms 5999940000 on an infra row is kept as 99999.0" 1 'r["minutes"]' '99999.0'
fresh; li minutes=99999.99
lrlogeq "cap helper sibling (T2): --minutes 99999.99 on an infra row is kept" 1 'r["minutes"]' '99999.99'
fresh; lr -minutes outcome=stopped -- --failure-reason "x" --fault model --usage "$(UB 6000000000)"
lrx "cap helper: an interrupted run whose usage reaches the cap is refused with the cap's wording" 1 "is 100000 minutes or more"
fresh; lr outcome=stopped -- --failure-reason "$(printf '\342\200\213')" --fault model
lrx "Q3 helper: a stopped run whose --failure-reason is only U+200B is refused" 1 "REFUSED:"
fresh; li "what=$(printf '\342\200\213')"
lrx "Q3 helper: an infra --what of only U+200B is refused" 1 "REFUSED: --what"
for dt in 2026-13-45 2026-04-31 2026-00-10; do fresh; li -- --date "$dt"; lrx "real day helper: --date $dt is refused (infra)" 1 "REFUSED: --date"; fresh; lr -- --date "$dt"; lrx "real day helper: --date $dt is refused (run)" 1 "REFUSED: --date"; done
fresh; lr -- --date 2024-02-29
lrlogeq "real day helper sibling (T2): a leap day 2024-02-29 is accepted as given" 1 'r["date"]' '"2024-02-29"'


echo
echo "log-agent-run matrix: $GF_PASS pass, $GF_FAIL fail"
[ "$GF_FAIL" = 0 ]
