#!/usr/bin/env bash
# second-opinion-test.sh — known-answer matrix for second-opinion.sh. The property that matters most:
# a missing or failing outside reviewer NEVER breaks the run — it falls through the configured chain,
# then to the local reviewer, and always says who (if anyone) answered. Fake reviewers only; no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# SCRIPT_UNDER_TEST=<path> runs the matrix against another copy of second-opinion.sh (bite-verification of the rows).
# MAIN_CHECKOUT_UNDER_TEST=<path> does the same for scripts/lib/main-checkout.sh (the worktree hand-over rule
# second-opinion.sh sources). WHY the subject is COPIED into the temp tree: it sources its lib from its own folder, so a
# mutant of either file needs both beside each other; and every row then runs a script that lives under $T.
# A key-file name set in the caller's environment would change every hand-over row below: the matrix owns that knob.
unset HARNESS_KEY_FILE
SUBJECT_SRC="${SCRIPT_UNDER_TEST:-$HERE/second-opinion.sh}"
LIB_SRC="${MAIN_CHECKOUT_UNDER_TEST:-$HERE/lib/main-checkout.sh}"
[ -f "$SUBJECT_SRC" ] && [ -f "$LIB_SRC" ] || { echo "second-opinion matrix: INCOMPLETE - $SUBJECT_SRC or $LIB_SRC missing"; exit 3; }
T="$(mktemp -d "${TMPDIR:-/tmp}/so-test.XXXXXX")"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/scripts/lib"; export HARNESS_ROOT_OVERRIDE="$T"
cp "$SUBJECT_SRC" "$T/scripts/second-opinion.sh"; chmod +x "$T/scripts/second-opinion.sh"; cp "$LIB_SRC" "$T/scripts/lib/main-checkout.sh"
SUBJECT="$T/scripts/second-opinion.sh"
printf '#!/bin/sh\necho "reviewer-A says: looks risky"\n' > "$T/bin/good";  chmod +x "$T/bin/good"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/fails"; chmod +x "$T/bin/fails"
printf '#!/bin/sh\nprintf "   \\n"\n' > "$T/bin/blank"; chmod +x "$T/bin/blank"
printf '#!/bin/sh\ncat\n' > "$T/bin/echo"; chmod +x "$T/bin/echo"
pass=0; fail=0
# WATCHDOG: a subject that hangs (a mutant, or a real regression of the time limit) must end a row as a FAILURE
# after RUN_LIMIT_S, not hang the matrix. macOS has no `timeout`, so a tiny python3 wrapper runs the subject in its own session and
# kills the whole group when the time is up (exit 124, "watchdog" on stderr). The extras' runners are in that group.
command -v python3 >/dev/null 2>&1 || { echo "second-opinion matrix: INCOMPLETE - python3 missing (the extra reviewers and the watchdog need it)"; exit 3; }
cat > "$T/bin/runlimit.py" <<'PYWD'
import os, signal, subprocess, sys
limit, argv = float(sys.argv[1]), sys.argv[2:]
p = subprocess.Popen(argv, start_new_session=True)
try:
    sys.exit(p.wait(timeout=limit))
except subprocess.TimeoutExpired:
    os.killpg(p.pid, signal.SIGTERM)
    try:
        p.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
    sys.stderr.write("watchdog: the run did not end within %s s\n" % sys.argv[1])
    sys.exit(124)
PYWD
run() { # conf-lines → sets RC OUT ERR
  printf '%s\n' "$1" > "$T/harness.conf"
  OUT="$(echo "${PROMPT_TEXT:-the prompt}" | TMPDIR="${RUN_TMPDIR:-${TMPDIR:-/tmp}}" python3 -I "$T/bin/runlimit.py" "${RUN_LIMIT_S:-150}" bash "$SUBJECT" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"
}
chk() { if eval "$2"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  $1 (rc=$RC out=${OUT:0:60} err=${ERR:0:80})"; fi; }

run 'HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS="a='"$T"'/bin/good"'
chk "external answers → exit 0, answer on stdout"   '[ $RC = 0 ] && [[ "$OUT" == *"looks risky"* ]]'
chk "names who answered"                          '[[ "$ERR" == *"answered by a"* ]]'
run 'HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS="x='"$T"'/bin/fails y=/no/such/cli b='"$T"'/bin/good"'
chk "failing + missing reviewers fall through to the next" '[ $RC = 0 ] && [[ "$ERR" == *"answered by b"* ]] && [[ "$ERR" == *"x:failed"* ]] && [[ "$ERR" == *"y:missing"* ]]'
run 'HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS="x='"$T"'/bin/fails z='"$T"'/bin/blank"'
chk "all external fail (blank counts as fail) → local, exit 3" '[ $RC = 3 ] && [[ "$OUT" == *"red-team"* ]]'
run 'HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS=""'
chk "external with no reviewers configured → local, exit 3" '[ $RC = 3 ]'
run 'HARNESS_SECOND_OPINION=local
HARNESS_LOCAL_REVIEWER=my-critic'
chk "local mode → exit 3, names the nominated agent" '[ $RC = 3 ] && [[ "$OUT" == *"my-critic"* ]]'
run 'HARNESS_SECOND_OPINION=off'
chk "off → exit 4, says self-review"               '[ $RC = 4 ] && [[ "$OUT" == *"self-review"* ]]'
run ''
chk "no config at all → defaults to local, exit 3" '[ $RC = 3 ]'
run 'HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS="e='"$T"'/bin/echo"'
chk "the prompt reaches the reviewer on stdin"     '[ $RC = 0 ] && [[ "$OUT" == *"the prompt"* ]]'
run 'HARNESS_SECOND_OPINION=sometimes'
chk "invalid mode → usage error, exit 2"           '[ $RC = 2 ]'

# shellcheck disable=SC2016  # the block's chk tests are single-quoted ON PURPOSE (chk evals them later) and the fake reviewers are literal sh text
{
# ── a FAILING reviewer's reason reaches the caller . Before, its stderr went
# nowhere and the caller saw only "every external reviewer failed" — a brief over the cap and a secret refusal looked alike.
# Fake reviewers: exit 2 (wrapper.sh "brief too big"), exit 5 (REFUSED, eight lines so the last-6 window shows), exit 1.
printf '#!/bin/sh\necho "wrapper.sh: REFUSED - the brief is 200000 bytes, over the 150 KB cap" >&2\nexit 2\n' > "$T/bin/big"; chmod +x "$T/bin/big"
printf '#!/bin/sh\nfor i in 1 2 3 4 5 6 7; do echo "refusal-line$i" >&2; done\necho "REFUSED - rule aws-access-key-id matched; NOTHING was sent" >&2\nexit 5\n' > "$T/bin/refuse"; chmod +x "$T/bin/refuse"
printf '#!/bin/sh\necho "slowmodel: TIMED OUT after 10 min" >&2\nexit 1\n' > "$T/bin/slow"; chmod +x "$T/bin/slow"
run 'HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS="x='"$T"'/bin/big b='"$T"'/bin/good"'
chk "reviewer exit 2: its stderr reaches the user, prefixed"  '[ $RC = 0 ] && [[ "$ERR" == *"second-opinion: x failed (exit 2); its last messages:"* ]] && [[ "$ERR" == *"second-opinion: | wrapper.sh: REFUSED - the brief is 200000 bytes"* ]]'
chk "reviewer exit 2 is named 'brief too big, split it'"      '[[ "$ERR" == *"second-opinion: x exit 2 = brief too big, split it"* ]]'
chk "a passing reviewer after a failing one: both reported, the answer on stdout" '[[ "$OUT" == *"looks risky"* ]] && [[ "$ERR" == *"x failed (exit 2)"* ]] && [[ "$ERR" == *"answered by b (after: x:failed)"* ]]'
run 'HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS="r='"$T"'/bin/refuse"'
chk "reviewer exit 5: the refusal naming the rule reaches the user, then local (exit 3)" '[ $RC = 3 ] && [[ "$ERR" == *"r failed (exit 5)"* ]] && [[ "$ERR" == *"second-opinion: | REFUSED - rule aws-access-key-id"* ]]'
chk "sibling (T2): exit 5 is NOT called 'brief too big'"       '! [[ "$ERR" == *"brief too big"* ]]'
chk "only the LAST 6 stderr lines: line 3 shown, line 2 not"   '[[ "$ERR" == *"| refusal-line3"* ]] && [[ "$ERR" == *"| refusal-line7"* ]] && ! [[ "$ERR" == *"refusal-line2"* ]]'
run 'HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS="s='"$T"'/bin/slow"'
chk "reviewer exit 1 (timeout): exit code and reason shown, not 'brief too big'" '[ $RC = 3 ] && [[ "$ERR" == *"s failed (exit 1)"* ]] && [[ "$ERR" == *"| slowmodel: TIMED OUT after 10 min"* ]] && ! [[ "$ERR" == *"brief too big"* ]]'
run 'HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS="f='"$T"'/bin/fails"'
chk "a silent failing reviewer (exit 1, no stderr) still gets its 'failed (exit 1)' line" '[ $RC = 3 ] && [[ "$ERR" == *"f failed (exit 1); its last messages:"* ]]'
# ── no temp file is left behind, on success AND on failure. Positive control (T2): a spy reviewer lists TMPDIR while it
# runs and the prompt file IS there; afterwards the folder is empty.
mkdir -p "$T/tmpd"; RUN_TMPDIR="$T/tmpd"
printf '#!/bin/sh\nls "$TMPDIR" >&2\nexit 1\n' > "$T/bin/spy"; chmod +x "$T/bin/spy"
run 'HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS="p='"$T"'/bin/spy"'
chk "control (T2): while a reviewer runs, the prompt temp file lives in TMPDIR" '[[ "$ERR" == *"| so-prompt."* ]]'
chk "after a FAILED run nothing is left in TMPDIR (.err/.out/prompt removed)" '[ -z "$(ls -A "$T/tmpd")" ]'
run 'HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS="a='"$T"'/bin/good"'
chk "after a SUCCESSFUL run nothing is left in TMPDIR"     '[ $RC = 0 ] && [ -z "$(ls -A "$T/tmpd")" ]'
unset RUN_TMPDIR
# ── the prompt itself is never echoed: a reviewer that receives a secret-shaped brief and refuses must not cause the brief
# to appear on stdout or stderr. Control (T2): the reviewer DID receive it. The value is built from fragments.
SEC_VAL="AK""IA""QWERTYUIOPASDFGH"
printf '#!/bin/sh\ncat > "%s/got"\necho "REFUSED - rule aws-access-key-id" >&2\nexit 5\n' "$T" > "$T/bin/keep"; chmod +x "$T/bin/keep"
PROMPT_TEXT="review this: key $SEC_VAL end"
run 'HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS="k='"$T"'/bin/keep"'
unset PROMPT_TEXT
chk "control (T2): the refusing reviewer received the secret-shaped brief" 'grep -q "$SEC_VAL" "$T/got"'
chk "the brief is not echoed on stdout or stderr; only the rule NAME is" '[ $RC = 3 ] && ! [[ "$OUT$ERR" == *"$SEC_VAL"* ]] && [[ "$ERR" == *"| REFUSED - rule aws-access-key-id"* ]]'
}

# shellcheck disable=SC2016  # as above: chk tests are single-quoted on purpose (eval'd later); fake reviewers are literal sh
{
# ══ HARNESS_ALSO_ASK — extra reviewers asked NEXT TO the chain (an extra independent view next to the chain)
# Cross author; the builder wrote none of these rows. What they pin: an extra runs in PARALLEL with the chain (proven by
# start/end markers the fakes write, not by wall time), its answer is printed AFTER the chain's answer under a header that
# names it, in registration order; it never changes the exit code; a failed, blank, missing or malformed extra is only a
# note on stderr; when the chain fails (exit 3) an extra that answered is still printed, before the local-reviewer text;
# modes local and off ask no extra; the scratch folder <prompt>.also is gone afterwards.
# shellcheck disable=SC2034  # read inside the single-quoted chk strings below (eval), which shellcheck cannot see
HDR="===== ALSO-ASKED OPINION:"
kdef=0
kchk() { if eval "$2"; then fail=$((fail+1)); echo "FAIL  KNOWN-DEFECT now PASSES - promote to a normal row: $1"; else kdef=$((kdef+1)); echo "  known-defect (open finding): $1"; fi; }
printf '#!/bin/sh\necho "PRIMARY-ANSWER"\necho "p1 note: model=fake-pro" >&2\n' > "$T/bin/p1"; chmod +x "$T/bin/p1"
printf '#!/bin/sh\necho "EXTRA-ANSWER"\necho "x1 note: model=fake-fast" >&2\n' > "$T/bin/x1"; chmod +x "$T/bin/x1"
printf '#!/bin/sh\necho "xfail: the fast model is unreachable" >&2\nexit 1\n' > "$T/bin/xfail"; chmod +x "$T/bin/xfail"
printf '#!/bin/sh\nprintf "  \\n\\t\\n"\n' > "$T/bin/xblank"; chmod +x "$T/bin/xblank"
printf '#!/bin/sh\necho "HALF-ANSWER"\nexit 1\n' > "$T/bin/xhalf"; chmod +x "$T/bin/xhalf"
printf '#!/bin/sh\nsleep 1\necho "E1-ANSWER"\n' > "$T/bin/xslow"; chmod +x "$T/bin/xslow"
printf '#!/bin/sh\necho "E2-ANSWER"\n' > "$T/bin/xfast"; chmod +x "$T/bin/xfast"
printf '#!/bin/sh\nprintf "EXTRA-GOT: "\ncat\n' > "$T/bin/xcat"; chmod +x "$T/bin/xcat"
printf '#!/bin/sh\ntouch "%s/xmark.called"\necho "MARK-ANSWER"\n' "$T" > "$T/bin/xmark"; chmod +x "$T/bin/xmark"
printf '#!/bin/sh\necho "SPY-SEES:"; ls -a "$TMPDIR"\n' > "$T/bin/xspy"; chmod +x "$T/bin/xspy"
# the parallel pair: the extra marks its start, holds 3 s, marks its end. The primary waits (up to 5 s) for the extra's
# start mark, then records an overlap only if the extra has started AND not yet ended. Serial runs cannot overlap.
D="$T/par"
printf '#!/bin/sh\ntouch "%s/x.start"\nsleep 3\ntouch "%s/x.end"\necho "PX-ANSWER"\n' "$D" "$D" > "$T/bin/px"; chmod +x "$T/bin/px"
printf '#!/bin/sh\ni=0\nwhile [ ! -e "%s/x.start" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done\n[ -e "%s/x.start" ] && [ ! -e "%s/x.end" ] && touch "%s/overlap"\necho "PP-ANSWER"\n' "$D" "$D" "$D" "$D" > "$T/bin/pp"; chmod +x "$T/bin/pp"
# lineof <text>: the first stdout line number holding the text (0 = absent)
lineof() { local n; n="$(printf '%s\n' "$OUT" | grep -nF -- "$1" | head -1 | cut -d: -f1)"; echo "${n:-0}"; }
EXT='HARNESS_SECOND_OPINION=external'

run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK=\"fl=$T/bin/x1\""
chk "also-ask primary + extra both answer -> exit 0, both answers on stdout" '[ $RC = 0 ] && [[ "$OUT" == *"PRIMARY-ANSWER"* ]] && [[ "$OUT" == *"EXTRA-ANSWER"* ]]'
chk "also-ask order: the chain answer, THEN the header naming fl, THEN the extra answer" 'a=$(lineof PRIMARY-ANSWER); h=$(lineof "$HDR fl ("); e=$(lineof EXTRA-ANSWER); [ "$a" -gt 0 ] && [ "$h" -gt "$a" ] && [ "$e" -gt "$h" ]'
chk "also-ask the header line reads exactly as specified" '[[ "$OUT" == *"$HDR fl (an independent extra view, asked next to the reviewers above; not their replacement) ====="* ]]'
chk "also-ask stderr names BOTH: 'answered by p' and 'also asked fl: answered', with each one's own stderr" '[[ "$ERR" == *"second-opinion: answered by p"* ]] && [[ "$ERR" == *"second-opinion: also asked fl: answered"* ]] && [[ "$ERR" == *"| p1 note: model=fake-pro"* ]] && [[ "$ERR" == *"| x1 note: model=fake-fast"* ]]'
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\""
chk "also-ask sibling (T2): the same chain with NO HARNESS_ALSO_ASK -> exit 0, the answer alone, no header, no 'also asked'" '[ $RC = 0 ] && [ "$OUT" = "PRIMARY-ANSWER" ] && ! [[ "$ERR" == *"also asked"* ]]'
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK=\"fl=$T/bin/xfail\""
chk "also-ask primary answers, the extra FAILS -> exit 0, stdout is exactly the chain answer (no header)" '[ $RC = 0 ] && [ "$OUT" = "PRIMARY-ANSWER" ]'
chk "also-ask ... and stderr says 'also asked fl: failed (exit 1)' with the extra's last message" '[[ "$ERR" == *"second-opinion: also asked fl: failed (exit 1); its last messages:"* ]] && [[ "$ERR" == *"second-opinion: | xfail: the fast model is unreachable"* ]]'
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"x=$T/bin/fails\"
HARNESS_ALSO_ASK=\"fl=$T/bin/x1\""
chk "also-ask the chain FAILS, the extra answers -> exit 3 (an extra is not a replacement), the extra printed under its header" '[ $RC = 3 ] && [[ "$OUT" == *"$HDR fl ("* ]] && [[ "$OUT" == *"EXTRA-ANSWER"* ]]'
chk "also-ask ... the local-reviewer instruction is present and comes AFTER the extra" 'e=$(lineof EXTRA-ANSWER); l=$(lineof "SECOND-OPINION: no external reviewer answered"); [ "$e" -gt 0 ] && [ "$l" -gt "$e" ] && [[ "$OUT" == *"spawn the '"'"'red-team'"'"' subagent"* ]]'
chk "also-ask ... stderr: the chain failure, 'answered by NONE', and 'also asked fl: answered'" '[[ "$ERR" == *"x failed (exit 1)"* ]] && [[ "$ERR" == *"answered by NONE"* ]] && [[ "$ERR" == *"also asked fl: answered"* ]]'
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"\"
HARNESS_ALSO_ASK=\"fl=$T/bin/x1\""
chk "also-ask external mode with NO chain reviewer configured but an extra -> exit 3, the extra still printed" '[ $RC = 3 ] && [[ "$OUT" == *"EXTRA-ANSWER"* ]] && [[ "$OUT" == *"HARNESS_EXTERNAL_REVIEWERS is empty"* ]]'
# parallel, by markers
rm -rf "$D"; mkdir -p "$D"
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/pp\"
HARNESS_ALSO_ASK=\"fl=$T/bin/px\""
chk "also-ask PARALLEL: the extra had started and not yet ended while the primary ran (overlap marker written)" '[ -e "$D/overlap" ]'
chk "also-ask PARALLEL: ... and both answers were printed, exit 0 (the slower extra was waited for)" '[ $RC = 0 ] && [[ "$OUT" == *"PP-ANSWER"* ]] && [[ "$OUT" == *"PX-ANSWER"* ]] && [ -e "$D/x.end" ]'
# malformed and missing entries
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK=\"justaname empty= gone=/no/such/reviewer fl=$T/bin/x1\""
chk "also-ask a malformed entry (no '=') -> 'extra reviewer 'justaname' is malformed (want name=command) — not asked'" '[[ "$ERR" == *"second-opinion: extra reviewer '"'"'justaname'"'"' is malformed (want name=command) — not asked"* ]]'
chk "also-ask an entry with an EMPTY command ('empty=') -> malformed, not asked" '[[ "$ERR" == *"extra reviewer '"'"'empty='"'"' is malformed"* ]]'
chk "also-ask a missing command -> 'extra reviewer gone is missing (/no/such/reviewer) — not asked'" '[[ "$ERR" == *"second-opinion: extra reviewer gone is missing (/no/such/reviewer) — not asked"* ]]'
chk "also-ask ... the bad entries are skipped, the good extra still answers, exit 0, no header for the bad ones" '[ $RC = 0 ] && [[ "$OUT" == *"$HDR fl ("* ]] && ! [[ "$OUT" == *"$HDR gone"* ]] && ! [[ "$OUT" == *"$HDR justaname"* ]] && [ "$(printf "%s\n" "$OUT" | grep -cF "$HDR")" = 1 ]'
# modes local and off ask no extra; T2 control: the same extra IS asked in external mode
rm -f "$T/xmark.called"
run "HARNESS_SECOND_OPINION=local
HARNESS_ALSO_ASK=\"fl=$T/bin/xmark\""
chk "also-ask mode local -> exit 3, the extra is NOT asked (its fake never ran), no header" '[ $RC = 3 ] && [ ! -e "$T/xmark.called" ] && ! [[ "$OUT" == *"$HDR"* ]] && ! [[ "$OUT" == *"MARK-ANSWER"* ]]'
run "HARNESS_SECOND_OPINION=off
HARNESS_ALSO_ASK=\"fl=$T/bin/xmark\""
chk "also-ask mode off -> exit 4, the extra is NOT asked" '[ $RC = 4 ] && [ ! -e "$T/xmark.called" ] && ! [[ "$OUT" == *"MARK-ANSWER"* ]]'
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK=\"fl=$T/bin/xmark\""
chk "also-ask sibling (T2): the same extra in mode external IS asked (marker written, answer printed)" '[ $RC = 0 ] && [ -e "$T/xmark.called" ] && [[ "$OUT" == *"MARK-ANSWER"* ]]'
# registration order, even when the second extra finishes first
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK=\"slow=$T/bin/xslow fast=$T/bin/xfast\""
chk "also-ask two extras keep REGISTRATION order (slow registered first, finishing last, printed first)" 'a=$(lineof "$HDR slow ("); b=$(lineof E1-ANSWER); c=$(lineof "$HDR fast ("); d=$(lineof E2-ANSWER); [ "$a" -gt 0 ] && [ "$b" -gt "$a" ] && [ "$c" -gt "$b" ] && [ "$d" -gt "$c" ]'
# output without text, or text with a failing exit, counts as failed
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK=\"bl=$T/bin/xblank hf=$T/bin/xhalf\""
chk "also-ask an extra printing only whitespace (exit 0) counts as FAILED: 'also asked bl: failed (exit 0)', no header" '[ $RC = 0 ] && [[ "$ERR" == *"also asked bl: failed (exit 0)"* ]] && ! [[ "$OUT" == *"$HDR bl"* ]]'
chk "also-ask an extra printing text but exiting 1 counts as FAILED: its text is NOT printed" '[[ "$ERR" == *"also asked hf: failed (exit 1)"* ]] && ! [[ "$OUT" == *"HALF-ANSWER"* ]] && [ "$OUT" = "PRIMARY-ANSWER" ]'
# the prompt reaches the extra on stdin, exactly as it reaches a chain reviewer
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK=\"c=$T/bin/xcat\""
chk "also-ask the prompt reaches the extra on stdin" '[ $RC = 0 ] && [[ "$OUT" == *"EXTRA-GOT: the prompt"* ]]'
# the scratch folder <prompt>.also: present while an extra runs (T2), gone after success and after a chain failure
mkdir -p "$T/tmpa"; RUN_TMPDIR="$T/tmpa"
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK=\"spy=$T/bin/xspy\""
chk "also-ask control (T2): while an extra runs, the scratch folder so-prompt.*.also exists in TMPDIR" '[[ "$OUT" == *"SPY-SEES:"* ]] && printf "%s\n" "$OUT" | grep -q "^so-prompt\..*\.also$"'
chk "also-ask after a SUCCESSFUL run with an extra, TMPDIR is empty (.also folder removed)" '[ $RC = 0 ] && [ -z "$(ls -A "$T/tmpa")" ]'
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"x=$T/bin/fails\"
HARNESS_ALSO_ASK=\"spy=$T/bin/xspy fl=$T/bin/xfail\""
chk "also-ask after a FAILED chain (exit 3) with extras, TMPDIR is empty" '[ $RC = 3 ] && [ -z "$(ls -A "$T/tmpa")" ]'
unset RUN_TMPDIR
# nastier cases
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK=\"fl=$T/bin/x1 fl=$T/bin/xfast\""
chk "extra also-ask: the SAME name registered twice -> both asked, both printed in order under the same name" 'a=$(lineof EXTRA-ANSWER); b=$(lineof E2-ANSWER); [ $RC = 0 ] && [ "$(printf "%s\n" "$OUT" | grep -cF "$HDR fl (")" = 2 ] && [ "$a" -gt 0 ] && [ "$b" -gt "$a" ]'
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK=\"fl=$T/bin/x1 --flag\""
# Re-pinned when arguments were added, the property kept: this row said "--flag is reported malformed"
# because the OLD parser read every word as an entry; now a word without "name=" is an ARGUMENT of the entry before it. What
# stays: the bad-word handling never stops the extra from being asked (x1 still answers), and nothing is called malformed.
chk "extra also-ask: 'fl=cmd --flag' -> --flag is an ARGUMENT of fl (no 'malformed' note), fl is still asked and answers" '[ $RC = 0 ] && ! [[ "$ERR" == *"malformed"* ]] && [[ "$OUT" == *"EXTRA-ANSWER"* ]]'
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK=\"=$T/bin/x1\""
# formerly a known defect found by this matrix (asked and printed under a header naming nobody); fixed, promoted
chk "also-ask an entry with an EMPTY NAME ('=cmd') -> malformed, NOT asked, no nameless header; the chain answer alone, exit 0" '[ $RC = 0 ] && [[ "$ERR" == *"extra reviewer '"'"'=$T/bin/x1'"'"' is malformed (want name=command) — not asked"* ]] && ! [[ "$OUT" == *"$HDR"* ]] && ! [[ "$OUT" == *"EXTRA-ANSWER"* ]] && [ "$OUT" = "PRIMARY-ANSWER" ]'
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/fails\"
HARNESS_ALSO_ASK=\"fl=$T/bin/xfail\""
chk "extra also-ask: the chain AND the extra fail -> exit 3, no header, the local instruction, both failures on stderr" '[ $RC = 3 ] && ! [[ "$OUT" == *"$HDR"* ]] && [[ "$OUT" == *"Use the LOCAL reviewer"* ]] && [[ "$ERR" == *"p failed (exit 1)"* ]] && [[ "$ERR" == *"also asked fl: failed (exit 1)"* ]]'
}
# shellcheck disable=SC2016  # the block's chk tests are single-quoted ON PURPOSE (chk evals them later); fakes are literal sh text
{
# ══ also-ask — arguments and a time limit per extra reviewer ══════════
# Cross author; the builder wrote none of these rows. What they pin: a word "name[@SECONDS]=..." starts an entry, every
# other word is an ARGUMENT of the entry before it and reaches the program EXACTLY (no globbing, no $ expansion, no ";" meaning,
# no second shell reading); "name@SECONDS=" is that entry's own limit (1-99999, else the entry is NOT asked and the others are);
# HARNESS_ALSO_ASK_LIMIT_S is the default (900; a bad value is said and 900 used); a stopped extra is "timed out" (exit 124) and
# stopped WITH its whole process group, TERM then KILL after 5 s; the exit code and the chain answer never change; TERM or INT
# to the script stops the runners; no python3 = no extras (said), the chain still answers.
# Seen process ids are read from files the fakes write (never from ps names): a pid file whose process is gone = stopped.
alive() { kill -0 "$1" 2>/dev/null; }
# gone <pidfile> [seconds]: true when the pid in the file is no longer alive within the time (polled; a pid is never reused here)
gone() { local p i=0; p="$(cat "$1" 2>/dev/null)"; [ -n "$p" ] || return 1; while alive "$p" && [ "$i" -lt "$(( ${2:-3} * 10 ))" ]; do sleep 0.1; i=$((i+1)); done; ! alive "$p"; }
printf '#!/bin/sh\ncat >/dev/null\necho "ARGC=$#"\nfor a in "$@"; do echo "[arg:$a]"; done\n' > "$T/bin/argshow"; chmod +x "$T/bin/argshow"
# a hang that spawns a child and writes both pids; sleeps are long and odd so no other process looks like them
printf '#!/bin/sh\necho $$ > "%s/h.pid"\nsleep 3011 &\necho $! > "%s/h.child"\nwait\n' "$T" "$T" > "$T/bin/xhang"; chmod +x "$T/bin/xhang"
printf '#!/bin/sh\necho "HALF-ANSWER-BEFORE-HANG"\necho $$ > "%s/h2.pid"\nsleep 3012\n' "$T" > "$T/bin/xhang2"; chmod +x "$T/bin/xhang2"
# a stubborn one: ignores TERM (and so does its sleep), so only the KILL 5 s later can stop it
printf '#!/bin/sh\ntrap "" TERM\necho $$ > "%s/s.pid"\nsleep 3013\n' "$T" > "$T/bin/xstubborn"; chmod +x "$T/bin/xstubborn"
# answers and exits 0, leaving a child behind in its group (the child writes its pid first)
printf '#!/bin/sh\nsleep 3014 &\necho $! > "%s/l.child"\necho "LEFT-ANSWER"\nexit 0\n' "$T" > "$T/bin/xleft"; chmod +x "$T/bin/xleft"
# the same, but the leftover ignores TERM (found by this matrix: see the known-defect row)
# (the leftover touches a ready file AFTER it ignores TERM and the extra waits for it, so the runner's TERM can never arrive first)
printf '#!/bin/sh\n(trap "" TERM; : > "%s/l2.ready"; exec sleep 3015) &\necho $! > "%s/l2.child"\ni=0\nwhile [ ! -e "%s/l2.ready" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done\necho "LEFT2-ANSWER"\nexit 0\n' "$T" "$T" "$T" > "$T/bin/xleft2"; chmod +x "$T/bin/xleft2"
printf '#!/bin/sh\ncat >/dev/null\nkill -9 $$\n' > "$T/bin/xkill"; chmod +x "$T/bin/xkill"
printf 'echo "never runs: no interpreter line"\n' > "$T/bin/xnoshebang"; chmod +x "$T/bin/xnoshebang"
mkdir -p "$T/bin/adir"
# shellcheck disable=SC2034  # SECS is read inside the single-quoted chk strings (eval), which shellcheck cannot see
secs_run() { local t0=$SECONDS; run "$1"; SECS=$((SECONDS - t0)); }
PEXT="HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\""

# ── arguments reach the program exactly
secs_run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=$T/bin/argshow --model pro \$HOME * ; a;b \$(echo X) \`id\` ~'"
chk "also-ask args: 'fl=cmd w1 w2 ...' -> ONE entry, exit 0, the extra's header printed" '[ $RC = 0 ] && [ "$(printf "%s\n" "$OUT" | grep -cF "$HDR")" = 1 ] && [[ "$OUT" == *"$HDR fl ("* ]]'
chk "also-ask args: all 10 words arrive, in order, as separate arguments (ARGC=10)" '[[ "$OUT" == *"ARGC=10"* ]] && [ "$(printf "%s\n" "$OUT" | grep -c "^\[arg:")" = 10 ]'
chk "also-ask args: -- a plain flag and its value arrive untouched" 'printf "%s\n" "$OUT" | grep -qxF "[arg:--model]" && printf "%s\n" "$OUT" | grep -qxF "[arg:pro]"'
chk "also-ask args: \$HOME, a lone *, ';', 'a;b', '\$(echo', 'X)', a backtick word and ~ arrive LITERALLY (no second shell reading)" 'for a in "\$HOME" "*" ";" "a;b" "\$(echo" "X)" "\`id\`" "~"; do printf "%s\n" "$OUT" | grep -qxF "[arg:$a]" || { echo "missing [arg:$a]"; false; break; }; done'
chk "also-ask args sibling (T2): the * was NOT expanded to the files of the working folder (no harness.conf / bin argument)" '! printf "%s\n" "$OUT" | grep -qE "^\[arg:(harness.conf|bin|scripts|err)\]"'
# two entries with arguments, in order
run "$EXT
$PEXT
HARNESS_ALSO_ASK='a=$T/bin/argshow one two b=$T/bin/argshow three'"
chk "also-ask two entries with arguments: a gets 2, b gets 1, both printed, a before b" 'x=$(lineof "$HDR a ("); y=$(lineof "$HDR b ("); [ $RC = 0 ] && [ "$x" -gt 0 ] && [ "$y" -gt "$x" ] && [[ "$OUT" == *"ARGC=2"* ]] && [[ "$OUT" == *"ARGC=1"* ]] && printf "%s\n" "$OUT" | grep -qxF "[arg:three]" && printf "%s\n" "$OUT" | grep -qxF "[arg:one]"'
# --k=v stays an argument; a bare k=v starts an entry (documented limit)
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=$T/bin/argshow --k=v'"
chk "also-ask an argument '--k=v' stays an ARGUMENT (ARGC=1, no new entry, no malformed/missing note)" '[ $RC = 0 ] && [[ "$OUT" == *"ARGC=1"* ]] && printf "%s\n" "$OUT" | grep -qxF "[arg:--k=v]" && ! [[ "$ERR" == *"extra reviewer"* ]]'
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=$T/bin/argshow k=v'"
chk "also-ask documented limit: a bare 'k=v' word STARTS an entry: fl gets no argument (ARGC=0) and 'k' is reported missing (v) -- not asked" '[ $RC = 0 ] && [[ "$OUT" == *"ARGC=0"* ]] && [[ "$ERR" == *"second-opinion: extra reviewer k is missing (v) — not asked"* ]]'
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=$T/bin/argshow user@host.example'"
chk "also-ask an argument with an '@' but no '=' (an address) stays an argument" '[ $RC = 0 ] && [[ "$OUT" == *"ARGC=1"* ]] && printf "%s\n" "$OUT" | grep -qxF "[arg:user@host.example]"'
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=$T/bin/argshow user@host=1'"
chk "also-ask documented limit: 'user@host=1' reads as an entry 'user@host' with the bad time limit 'host' -- that entry is not asked, fl gets ARGC=0" '[[ "$OUT" == *"ARGC=0"* ]] && [[ "$ERR" == *"extra reviewer '"'"'user@host'"'"' has a bad time limit"* ]]'
# entries separated by a NEWLINE or tabs inside the value
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=$T/bin/argshow one
	g=$T/bin/argshow two'"
chk "also-ask entries may be separated by a newline and a tab (the value is split on blanks of any kind)" '[ $RC = 0 ] && [[ "$OUT" == *"$HDR fl ("* ]] && [[ "$OUT" == *"$HDR g ("* ]] && printf "%s\n" "$OUT" | grep -qxF "[arg:one]" && printf "%s\n" "$OUT" | grep -qxF "[arg:two]"'
# a realistic name (dots, dashes, underscores, digits) with @SECONDS: the header names the entry WITHOUT the limit
run "$EXT
$PEXT
HARNESS_ALSO_ASK='deep-seek.fast_2@5=$T/bin/argshow x'"
chk "also-ask name@SECONDS: the header names 'deep-seek.fast_2' only (no '@5'), the program gets its argument" '[[ "$OUT" == *"$HDR deep-seek.fast_2 ("* ]] && ! [[ "$OUT" == *"@5"* ]] && [[ "$OUT" == *"ARGC=1"* ]]'
# a bare command name through PATH, with an argument
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=printf BARE-NAME-ANSWER'"
chk "also-ask a bare command name (found on PATH) with an argument runs: 'fl=printf WORD' answers WORD" '[ $RC = 0 ] && [[ "$OUT" == *"BARE-NAME-ANSWER"* ]]'
# a missing command with arguments is still "missing" (the argument is not read as the command)
run "$EXT
$PEXT
HARNESS_ALSO_ASK='gone=/no/such/reviewer --flag x1=$T/bin/x1'"
chk "also-ask a missing command that has arguments: 'gone ... missing (/no/such/reviewer) -- not asked', the next entry x1 still asked" '[[ "$ERR" == *"extra reviewer gone is missing (/no/such/reviewer) — not asked"* ]] && [[ "$OUT" == *"EXTRA-ANSWER"* ]]'

# ── the time limit per entry
rm -f "$T/h.pid" "$T/h.child"
secs_run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl@1=$T/bin/xhang'"
chk "also-ask limit: a hung extra with @1 is stopped; the run ends well before the extra's 3000 s sleep (took <= 12 s)" '[ "$SECS" -le 12 ]'
chk "also-ask limit: the chain answer is still printed and the exit code is the chain's (0); no header for the stopped extra" '[ $RC = 0 ] && [ "$OUT" = "PRIMARY-ANSWER" ]'
chk "also-ask limit: stderr says 'also asked fl: timed out (exit 124)' and the runner says it stopped the whole process group" '[[ "$ERR" == *"second-opinion: also asked fl: timed out (exit 124); its last messages:"* ]] && [[ "$ERR" == *"timed out after 1 s: stopped (its whole process group)"* ]]'
chk "also-ask limit: the hung program AND its child are both gone (no orphan)" 'gone "$T/h.pid" 3 && gone "$T/h.child" 3'
chk "also-ask limit: the run took at least ~1 s (the limit, not an instant cut: the extra was given its time)" '[ "$SECS" -ge 1 ]'
# a stopped extra that already printed text: the text is NOT shown (exit 124 is a failure)
rm -f "$T/h2.pid"
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl@1=$T/bin/xhang2'"
chk "also-ask limit: an extra that printed text and then hung is 'timed out'; its text is not printed" '[ $RC = 0 ] && [ "$OUT" = "PRIMARY-ANSWER" ] && [[ "$ERR" == *"timed out (exit 124)"* ]] && gone "$T/h2.pid" 3'
# the chain FAILS and the extra times out: exit 3, the local instruction, the timeout said
rm -f "$T/h.pid" "$T/h.child"
run "$EXT
HARNESS_EXTERNAL_REVIEWERS=\"x=$T/bin/fails\"
HARNESS_ALSO_ASK='fl@1=$T/bin/xhang'"
chk "also-ask limit: chain failed + extra timed out -> exit 3 (not 124), the local-reviewer instruction, the timeout on stderr" '[ $RC = 3 ] && [[ "$OUT" == *"Use the LOCAL reviewer"* ]] && [[ "$ERR" == *"timed out (exit 124)"* ]]'
chk "also-ask limit: ... and nothing of it is left running" 'gone "$T/h.pid" 3 && gone "$T/h.child" 3'
# per-entry limits are independent: fast extra with a big limit is not cut, slow one with a small limit is
run "$EXT
$PEXT
HARNESS_ALSO_ASK='slow@99=$T/bin/xslow cut@1=$T/bin/xhang2'"
chk "also-ask limit: two entries, two limits: slow@99 (sleeps 1 s) is answered, cut@1 is timed out" '[[ "$OUT" == *"E1-ANSWER"* ]] && [[ "$ERR" == *"also asked cut: timed out"* ]] && ! [[ "$OUT" == *"HALF-ANSWER-BEFORE-HANG"* ]]'
# bad limits: that entry is NOT asked, the others are
for v in "" abc 0 00 000000 100000 -1 1.5 1e3 0x10; do
  rm -f "$T/xmark.called"
  run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl@$v=$T/bin/xmark ok=$T/bin/xfast'"
  chk "also-ask bad limit '@$v' -> that entry is named and NOT asked (its marker never written); the next entry still answers" '[[ "$ERR" == *"extra reviewer '"'"'fl@'"$v"''"'"' has a "* ]] && [[ "$ERR" == *"not asked"* ]] && [ ! -e "$T/xmark.called" ] && [[ "$OUT" == *"E2-ANSWER"* ]] && [ $RC = 0 ]'
done
for v in 1 007 99999; do
  rm -f "$T/xmark.called"
  run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl@$v=$T/bin/xmark'"
  chk "also-ask sibling (T2): the valid limit '@$v' IS asked and answers" '[ $RC = 0 ] && [ -e "$T/xmark.called" ] && [[ "$OUT" == *"MARK-ANSWER"* ]] && ! [[ "$ERR" == *"time limit"* ]]'
done
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl@100000=$T/bin/xmark'"
chk "also-ask a 6-digit limit is 'outside 1 to 99999 s' (the message names the range)" '[[ "$ERR" == *"has a time limit outside 1 to 99999 s — not asked"* ]]'
rm -f "$T/xmark.called"
run "$EXT
$PEXT
HARNESS_ALSO_ASK='@5=$T/bin/xmark'"
chk "also-ask an entry with an empty name and a limit ('@5=cmd') is not asked" '[ ! -e "$T/xmark.called" ] && [[ "$ERR" == *"extra reviewer"* ]] && ! [[ "$OUT" == *"MARK-ANSWER"* ]]'

# ── the default limit: HARNESS_ALSO_ASK_LIMIT_S
rm -f "$T/h.pid" "$T/h.child" "$T/h2.pid"
secs_run "$EXT
$PEXT
HARNESS_ALSO_ASK_LIMIT_S=1
HARNESS_ALSO_ASK='a=$T/bin/xhang b@3=$T/bin/xhang2'"
chk "also-ask default limit: LIMIT_S=1 stops the entry that has no @ after 1 s; the entry with @3 keeps its own 3 s (the run took >= 3 s)" '[[ "$ERR" == *"also asked a: timed out"* ]] && [[ "$ERR" == *"timed out after 1 s"* ]] && [[ "$ERR" == *"timed out after 3 s"* ]] && [ "$SECS" -ge 3 ]'
chk "also-ask default limit: both hung programs are gone afterwards" 'gone "$T/h.pid" 3 && gone "$T/h2.pid" 3'
for v in abc 0 -5 1.5 100000 999999999999 0x10; do
  run "$EXT
$PEXT
HARNESS_ALSO_ASK_LIMIT_S='$v'
HARNESS_ALSO_ASK='fl=$T/bin/x1'"
  chk "also-ask bad HARNESS_ALSO_ASK_LIMIT_S '$v' -> said once, 900 is used, the extra is still asked and answers" '[ $RC = 0 ] && [[ "$ERR" == *"HARNESS_ALSO_ASK_LIMIT_S '"'"''"$v"''"'"' is not "* ]] && [[ "$ERR" == *"900 is used"* ]] && [[ "$OUT" == *"EXTRA-ANSWER"* ]] && [ "$(printf "%s\n" "$ERR" | grep -c "HARNESS_ALSO_ASK_LIMIT_S")" = 1 ]'
done
for v in "" 5 007 99999; do
  run "$EXT
$PEXT
HARNESS_ALSO_ASK_LIMIT_S='$v'
HARNESS_ALSO_ASK='fl=$T/bin/x1'"
  chk "also-ask sibling (T2): HARNESS_ALSO_ASK_LIMIT_S '$v' is fine -> no note, the extra answers" '[ $RC = 0 ] && ! [[ "$ERR" == *"HARNESS_ALSO_ASK_LIMIT_S"* ]] && [[ "$OUT" == *"EXTRA-ANSWER"* ]]'
done
# the limit variable is only read when an extra is asked: a bad value with no HARNESS_ALSO_ASK says nothing
run "$EXT
$PEXT
HARNESS_ALSO_ASK_LIMIT_S=abc"
chk "also-ask a bad HARNESS_ALSO_ASK_LIMIT_S with NO extra registered says nothing" '[ $RC = 0 ] && [ "$OUT" = "PRIMARY-ANSWER" ] && ! [[ "$ERR" == *"HARNESS_ALSO_ASK_LIMIT_S"* ]]'

# ── TERM then KILL: an extra that ignores TERM is killed 5 s later
rm -f "$T/s.pid"
secs_run "$EXT
$PEXT
HARNESS_ALSO_ASK='st@1=$T/bin/xstubborn'"
chk "also-ask TERM-ignoring extra: stopped by KILL after the 5 s grace (the run took 6 to 20 s), timed out, exit 0" '[ $RC = 0 ] && [ "$SECS" -ge 6 ] && [ "$SECS" -le 20 ] && [[ "$ERR" == *"also asked st: timed out (exit 124)"* ]]'
chk "also-ask TERM-ignoring extra: the process is really gone" 'gone "$T/s.pid" 3'

# ── a normal exit stops group members left behind; a signal death is a failure with the 128+n code
rm -f "$T/l.child" "$T/l2.child" "$T/l2.ready"
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=$T/bin/xleft'"
chk "also-ask leftovers: an extra that answers and exits 0 leaves a child -> the answer is printed and the child is stopped" '[ $RC = 0 ] && [[ "$OUT" == *"LEFT-ANSWER"* ]] && gone "$T/l.child" 3'
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=$T/bin/xleft2'"
# Found by this matrix: only TERM was sent to leftover group members, so a leftover that ignores TERM outlived the script.
# FIXED in the runner's stop_group (TERM, a 5 s grace, then KILL); this was a known-defect row until then.
chk "also-ask leftovers: a leftover child of a finished extra that IGNORES TERM is gone after the run (TERM, then KILL after the grace)" 'gone "$T/l2.child" 3'
[ -s "$T/l2.child" ] && kill -9 "$(cat "$T/l2.child")" 2>/dev/null
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=$T/bin/xkill'"
chk "also-ask an extra killed by SIGKILL is 'failed (exit 137)' (128+9), the chain answer alone is printed" '[ $RC = 0 ] && [ "$OUT" = "PRIMARY-ANSWER" ] && [[ "$ERR" == *"also asked fl: failed (exit 137)"* ]]'
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=$T/bin/xnoshebang'"
chk "also-ask an executable that cannot start (no interpreter line) is 'failed (exit 127)' with 'could not start', not a crash; chain answer alone" '[ $RC = 0 ] && [ "$OUT" = "PRIMARY-ANSWER" ] && [[ "$ERR" == *"also asked fl: failed (exit 127)"* ]] && [[ "$ERR" == *"could not start"* ]]'
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=$T/bin/adir'"
chk "also-ask a directory (executable bit) as the command is 'failed (exit 127)', not a crash; chain answer alone" '[ $RC = 0 ] && [ "$OUT" = "PRIMARY-ANSWER" ] && [[ "$ERR" == *"also asked fl: failed (exit 127)"* ]]'

# ── TERM / INT to second-opinion.sh itself stops the runner and the whole extra group, and clears the scratch folder
mkdir -p "$T/tmps"
for SIG in SIGTERM SIGINT; do
  rm -f "$T/h.pid" "$T/h.child"
  printf '%s\n' "HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK='fl=$T/bin/xhang'" > "$T/harness.conf"
  echo "the prompt" > "$T/prompt.in"
  SIGRC="$(SIGNAME=$SIG SUBJ="$SUBJECT" PIN="$T/prompt.in" CHILDF="$T/h.child" TMPDIR="$T/tmps" python3 -I -c '
import os, signal, subprocess, sys, time
# WHY preexec_fn: a matrix started as a background job inherits SIGINT as IGNORED, and an ignored signal stays ignored through
# exec; the child must start with the default action or the INT row measures the caller, not the script (found when the matrix ran as a background job).
p = subprocess.Popen(["bash", os.environ["SUBJ"]], stdin=open(os.environ["PIN"]), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
end = time.time() + 8
while not os.path.exists(os.environ["CHILDF"]) and time.time() < end:
    time.sleep(0.05)
time.sleep(0.5)  # the script is now waiting for the extra
p.send_signal(getattr(signal, os.environ["SIGNAME"]))
try:
    print(p.wait(timeout=8))
except subprocess.TimeoutExpired:
    p.kill(); print("HUNG")
' 2>&1)"
  chk "also-ask $SIG to second-opinion.sh while an extra runs: the script ends (does not hang), exit status is not 0" '[ "$SIGRC" != "HUNG" ] && [ "$SIGRC" != 0 ]'
  chk "also-ask $SIG: the extra program and its child are both gone within 3 s (the EXIT trap stopped the runner's group)" 'gone "$T/h.pid" 3 && gone "$T/h.child" 3'
  chk "also-ask $SIG: the scratch folder and the prompt file are gone from TMPDIR" '[ -z "$(ls -A "$T/tmps")" ]'
done
chk "also-ask sibling (T2) of the two rows above: the extra WAS running and was alive at the signal (pid file written by the fake)" '[ -s "$T/h.pid" ] && [ -s "$T/h.child" ]'

# ── no python3: the extras are not asked, said so, the chain still answers
mkdir -p "$T/bin-nopy"
for t in bash sh cat mktemp rm mkdir dirname git grep tail sed touch ls sleep env head cut; do p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$T/bin-nopy/$t"; done
BASH_BIN="$(command -v bash)"
rm -f "$T/xmark.called"
printf '%s\n' "HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK='fl=$T/bin/xmark'" > "$T/harness.conf"
OUT="$(echo "the prompt" | PATH="$T/bin-nopy" "$BASH_BIN" "$SUBJECT" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"
chk "also-ask no python3 on PATH: the extras are NOT asked (marker never written), the reason is said, the chain still answers, exit 0" '[ $RC = 0 ] && [ "$OUT" = "PRIMARY-ANSWER" ] && [ ! -e "$T/xmark.called" ] && [[ "$ERR" == *"python3 is not installed, so no time limit can be kept — the extra reviewers were not asked"* ]]'
nopy_has_python() { "$BASH_BIN" -c 'PATH=$1; command -v python3' _ "$T/bin-nopy" >/dev/null 2>&1; }
chk "also-ask no python3: control (T2) -- the restricted PATH really has no python3 but does have bash" '! nopy_has_python && [ -x "$T/bin-nopy/bash" ]'
run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=$T/bin/xmark'"
chk "also-ask no python3: sibling (T2) -- with python3 on PATH the extra IS asked" '[ -e "$T/xmark.called" ] && [[ "$OUT" == *"MARK-ANSWER"* ]]'
}

# shellcheck disable=SC2016  # chk tests are single-quoted on purpose (eval'd later); the fake scripts are literal sh text
{
# ══ worktree hand-over — a call from a linked git worktree without a key file is handed to the MAIN
# checkout's own copy of the script. KEY-HANDLING CODE: these rows are the evidence for the key-handling review. Cross author; the builder wrote none.
# ⛔ SAFETY (read before touching): nothing here may reach a REAL key or a REAL model. Every row runs a script that lives
# in a THROWAWAY git repository made under $T (mktemp), with a FIXTURE key file holding a fake value, and a FAKE main-checkout
# script that only echoes. Running second-opinion.sh in place from the real repo's worktree would hand the call to the real
# main checkout with the real keys. So: (1) hrun REFUSES to run unless the script and the repo it runs in are both
# under $T (guard_ok; the rows below prove the guard bites on the real repo); (2) the fixture value is never printed -- every
# row asserts it is absent from stdout and stderr; (3) the "main" script is a fake unless a row says "real copy", and a real
# copy runs with a fixture harness.conf whose mode is local/off, which asks no model at all.
KEYF=".e""nv"                                  # the key file's name, spelled in two parts as the scripts do
FIXVAL="FIXTURE-NOT-A-KEY-$$-7c1d9e"           # a fake value; never printed
FX="$T/ho"; mkdir -p "$FX"
gq() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE -u GIT_PREFIX -u GIT_OBJECT_DIRECTORY git \
        -c user.name=fixture -c user.email=fixture@example.invalid -c init.defaultBranch=main -c commit.gpgsign=false \
        -c protocol.file.allow=always "$@"; }
physical() { (cd "$1" 2>/dev/null && pwd -P); }
gitq_common() { env -u GIT_DIR git rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }
# guard_ok <script> <cwd>: both must be physically inside $T, and the git common dir of cwd too (never the real repo)
guard_ok() {
  local s c g
  s="$(physical "$(dirname "$1")")" || return 1; c="$(physical "$2")" || return 1
  g="$(cd "$c" && gitq_common)"
  case "$s/" in "$T"/*) ;; *) return 1 ;; esac
  case "$c/" in "$T"/*) ;; *) return 1 ;; esac
  case "$g/" in "$T"/*) ;; *) return 1 ;; esac
  return 0
}
# nokey: neither stream holds the fixture value
nokey() { ! [[ "$OUT$ERR" == *"$FIXVAL"* ]]; }
# hrun <cwd> <script> [args...]  (stdin: HO_STDIN, default "the prompt")  -> RC OUT ERR; HARNESS_ROOT_OVERRIDE is NOT set
hrun() {
  local cwd="$1" script="$2"; shift 2
  guard_ok "$script" "$cwd" || { echo "second-opinion matrix: INCOMPLETE - refusing to run $script in $cwd: not inside the throwaway tree (a real key could be reached)"; exit 3; }
  OUT="$(cd "$cwd" && printf '%s' "${HO_STDIN-the prompt}" | env -u HARNESS_ROOT_OVERRIDE -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
        TMPDIR="$T/tmp-ho" bash "$script" "$@" 2>"$T/err-ho")"; RC=$?; ERR="$(cat "$T/err-ho")"
}
mkdir -p "$T/tmp-ho"
FAKE_MAIN='#!/bin/sh
echo "MAIN-FAKE-RAN override=$HARNESS_ROOT_OVERRIDE argc=$# pwd=$(pwd -P)"
echo "STDIN=[$(cat)]"
for a in "$@"; do echo "[arg:$a]"; done
'
# mkho <name> [flags]: builds $FX/<name>/main (a committed repo: subject copy, lib, harness.conf "off") + a linked worktree
# $FX/<name>/wt; sets MAIN WT. Flags (words): real = main keeps a real copy of the subject (default: a fake that echoes);
# nomainkey, wtkey, wtkeylink, noscript, noexec, maincolon (main's harness.conf becomes 'local' after the worktree exists),
# keymode000 (main's key file unreadable).
mkho() {
  local name="$1" f; shift
  local base="$FX/$name"; mkdir -p "$base/main" || return 1
  ( cd "$base/main" && gq init -q . && mkdir -p scripts/lib && cp "$T/scripts/second-opinion.sh" scripts/ && cp "$T/scripts/lib/main-checkout.sh" scripts/lib/ \
      && printf 'HARNESS_SECOND_OPINION=off\n' > harness.conf && gq add . && gq commit -q -m fixture && gq worktree add -q "$base/wt" -b wtbranch ) >/dev/null 2>&1 || { echo "second-opinion matrix: INCOMPLETE - could not build the fixture repo $name (git)"; exit 3; }
  MAIN="$(physical "$base/main")"; WT="$(physical "$base/wt")"
  printf 'FIXTURE_API_KEY=%s\n' "$FIXVAL" > "$MAIN/$KEYF"
  case " $* " in *" real "*|*" noscript "*) ;; *) printf '%s' "$FAKE_MAIN" > "$MAIN/scripts/second-opinion.sh"; chmod +x "$MAIN/scripts/second-opinion.sh" ;; esac
  for f in "$@"; do case "$f" in
    real) ;;                                                    # keep the committed real copy
    nomainkey) rm -f "${MAIN:?}/${KEYF:?}" ;;
    wtkey) printf 'FIXTURE_API_KEY=%s\n' "$FIXVAL" > "$WT/$KEYF" ;;
    wtkeylink) ln -s "$MAIN/$KEYF" "$WT/$KEYF" ;;
    noscript) rm -f "${MAIN:?}/scripts/second-opinion.sh" ;;
    scriptdir) rm -f "${MAIN:?}/scripts/second-opinion.sh"; mkdir "$MAIN/scripts/second-opinion.sh" ;;
    noexec) chmod -x "$MAIN/scripts/second-opinion.sh" ;;
    maincolon) printf 'HARNESS_SECOND_OPINION=local\n' > "$MAIN/harness.conf" ;;
    keymode000) chmod 000 "$MAIN/$KEYF" ;;
  esac; done
}
handed() { [[ "$OUT" == *"MAIN-FAKE-RAN"* ]]; }
SO_OFF='[ $RC = 4 ] && [[ "$OUT" == *"SECOND-OPINION: off"* ]] && ! handed && ! [[ "$ERR" == *"takes the call"* ]] && nokey'

# ── the guard itself bites: the real repo and a script outside $T are refused (proves no row can reach the real main checkout)
mkho g0
chk "hand-over SAFETY: guard_ok REFUSES the real repo's own second-opinion.sh run from the real repo (a real key could be reached)" '! guard_ok "$HERE/second-opinion.sh" "$HERE"'
chk "hand-over SAFETY: guard_ok REFUSES the real script with a fixture cwd, and a fixture script with the real repo as cwd" '! guard_ok "$HERE/second-opinion.sh" "$WT" && ! guard_ok "$MAIN/scripts/second-opinion.sh" "$HERE"'
chk "hand-over SAFETY control (T2): guard_ok ACCEPTS a throwaway worktree with its own script copy" 'guard_ok "$WT/scripts/second-opinion.sh" "$WT"'
chk "hand-over SAFETY: the fixture git dir is not the real repo's, and lies under the temp area" '[ "$(cd "$WT" && gitq_common)" != "$(cd "$HERE" && gitq_common)" ] && case "$(cd "$WT" && gitq_common)/" in "$T"/*) true ;; *) false ;; esac'

# ── fires when ALL hold
mkho h0
HO_STDIN="the prompt text without a newline"
hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over: worktree, no key file, main has key file + executable script -> main's script ran" 'handed'
chk "hand-over: it ran with HARNESS_ROOT_OVERRIDE = the main checkout (physical path), and exit status 0 of the main script" '[ $RC = 0 ] && [[ "$OUT" == *"override=$MAIN "* ]]'
chk "hand-over: stdin arrived intact" '[[ "$OUT" == *"STDIN=[the prompt text without a newline]"* ]]'
chk "hand-over: no argument was invented (argc=0)" '[[ "$OUT" == *"argc=0"* ]]'
chk "hand-over: the note names the main checkout path" '[[ "$ERR" == *"second-opinion: this worktree has no key file; the main checkout'"'"'s own script takes the call ($MAIN)"* ]]'
chk "hand-over: the fixture key value appears in neither stdout nor stderr" 'nokey'
unset HO_STDIN
# stdin edge: empty stdin, a multi-line prompt, a very large prompt
HO_STDIN=""; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over: EMPTY stdin arrives as empty (handed, STDIN=[])" 'handed && [[ "$OUT" == *"STDIN=[]"* ]]'
HO_STDIN="$(printf 'line1\n\nline3 with  spaces and \\ backslash and "quotes"')"; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over: a multi-line prompt with backslash and quotes arrives intact" 'handed && [[ "$OUT" == *"line3 with  spaces and \\ backslash and \"quotes\"]"* ]]'
HO_STDIN="$(head -c 200000 /dev/zero | tr '\0' 'x')"; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over: a 200 KB prompt arrives whole (the exec passes the same stdin; nothing is read twice)" 'handed && [ "$(printf "%s" "$OUT" | wc -c)" -gt 200000 ]'
unset HO_STDIN
# the key file of main is unreadable: the rule only tests that it EXISTS (a read would fail here)
mkho h1 keymode000; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over: main's key file with mode 000 (unreadable) still hands over -- the rule only tests existence, never reads it" 'handed && nokey'
chmod 600 "$MAIN/$KEYF"
# main path with spaces and non-ASCII characters
mkho "dir with space é"; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over: a main checkout whose path has spaces and an accented letter works" 'handed && [[ "$OUT" == *"override=$MAIN "* ]]'
# from a SUBFOLDER of the worktree: the script finds the top level itself
mkho h2b; mkdir -p "$WT/sub/deeper"; hrun "$WT/sub/deeper" "$WT/scripts/second-opinion.sh"
chk "hand-over: called from a subfolder of the worktree it still hands over (ROOT is git's top level)" 'handed'
# a symlink to the worktree as the working folder
mkho h2
# shellcheck disable=SC2034  # MAIN_H2 is read by the lib SYMLINK row further down (line "hand-over lib: <root> given through a SYMLINK"), inside a single-quoted chk string that is eval'd, which shellcheck cannot see; MAIN changes by then
MAIN_H2="$MAIN"
ln -s "$WT" "$FX/h2/wtlink"; hrun "$FX/h2/wtlink" "$WT/scripts/second-opinion.sh"
chk "hand-over: the worktree reached through a SYMLINK hands over, with the main's PHYSICAL path" 'handed && [[ "$OUT" == *"override=$MAIN "* ]]'
# HARNESS_ROOT_OVERRIDE set but EMPTY counts as unset (like the script's own ${..:-})
mkho h3
OUT="$(cd "$WT" && printf 'the prompt' | env HARNESS_ROOT_OVERRIDE= TMPDIR="$T/tmp-ho" bash "$WT/scripts/second-opinion.sh" 2>"$T/err-ho")"; RC=$?; ERR="$(cat "$T/err-ho")"
chk "hand-over: HARNESS_ROOT_OVERRIDE set to the EMPTY string counts as unset -> handed over" 'handed && nokey'

# ── one row per condition NEGATED: no hand-over, the worktree's own script carries on (mode off from its harness.conf)
mkho n1; OUT="$(cd "$WT" && printf 'the prompt' | env HARNESS_ROOT_OVERRIDE="$WT" TMPDIR="$T/tmp-ho" bash "$WT/scripts/second-opinion.sh" 2>"$T/err-ho")"; RC=$?; ERR="$(cat "$T/err-ho")"
chk "hand-over negated: HARNESS_ROOT_OVERRIDE set (to the worktree) -> NO hand-over; the worktree's own conf ran (off, exit 4)" "$SO_OFF"
mkho n1b; OUT="$(cd "$WT" && printf 'the prompt' | env HARNESS_ROOT_OVERRIDE="/nonexistent/anywhere" TMPDIR="$T/tmp-ho" bash "$WT/scripts/second-opinion.sh" 2>"$T/err-ho")"; RC=$?; ERR="$(cat "$T/err-ho")"
chk "hand-over negated: HARNESS_ROOT_OVERRIDE set to a path that does not exist -> no hand-over (exit 2 from the script's own cd)" '[ $RC = 2 ] && ! handed && nokey'
mkho n2 wtkey; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over negated: the worktree has its OWN key file -> no hand-over" "$SO_OFF"
mkho n2b wtkeylink; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over negated: the worktree's key file is a SYMLINK to main's -> it counts as its own, no hand-over" "$SO_OFF"
mkho n3 nomainkey; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over negated: main has NO key file -> no hand-over" "$SO_OFF"
mkho n4 noscript; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over negated: main's script is MISSING -> no hand-over" "$SO_OFF"
mkho n5 noexec; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over negated: main's script is NOT executable -> no hand-over" "$SO_OFF"
# a plain (non-worktree) repository, with and without a key file
mkdir -p "$FX/plain" && ( cd "$FX/plain" && gq init -q . && mkdir -p scripts/lib && cp "$T/scripts/second-opinion.sh" scripts/ && cp "$T/scripts/lib/main-checkout.sh" scripts/lib/ && printf 'HARNESS_SECOND_OPINION=off\n' > harness.conf && gq add . && gq commit -q -m f ) >/dev/null 2>&1
PL="$(physical "$FX/plain")"
hrun "$PL" "$PL/scripts/second-opinion.sh"
chk "hand-over negated: a plain repository (not a worktree), no key file -> no hand-over" "$SO_OFF"
printf 'FIXTURE_API_KEY=%s\n' "$FIXVAL" > "$PL/$KEYF"; hrun "$PL" "$PL/scripts/second-opinion.sh"
chk "hand-over negated: a plain repository WITH a key file (the main checkout itself) -> no hand-over" "$SO_OFF"
# the main checkout itself, no key file: its git dir IS the common dir
mkho n6 nomainkey; cp "$T/scripts/second-opinion.sh" "$MAIN/scripts/second-opinion.sh"; hrun "$MAIN" "$MAIN/scripts/second-opinion.sh"
chk "hand-over negated: the main checkout itself without a key file (gitdir == common dir) -> no hand-over (it must not hand to itself)" '[ $RC = 4 ] && ! handed && nokey'
# not a git repository at all
mkdir -p "$FX/nogit/scripts/lib"; cp "$T/scripts/second-opinion.sh" "$FX/nogit/scripts/"; cp "$T/scripts/lib/main-checkout.sh" "$FX/nogit/scripts/lib/"
OUT="$(cd "$FX/nogit" && printf 'the prompt' | env -u HARNESS_ROOT_OVERRIDE TMPDIR="$T/tmp-ho" bash "$FX/nogit/scripts/second-opinion.sh" 2>"$T/err-ho")"; RC=$?; ERR="$(cat "$T/err-ho")"
chk "hand-over negated: no git repository at all (a folder inside \$T) -> no hand-over, no crash (mode local default -> exit 3)" '[ $RC = 3 ] && ! handed && ! [[ "$ERR" == *"takes the call"* ]]'
# bare common dir: a worktree of a BARE repository. The folder above the bare repo HAS a key file and an executable script,
# so a missing basename check WOULD hand over (the row is not vacuous).
BP="$FX/bare"; mkdir -p "$BP/up/scripts/lib"
( cd "$BP" && gq init -q --bare up/bare.git && gq clone -q up/bare.git seed && cd seed && mkdir -p scripts/lib && cp "$T/scripts/second-opinion.sh" scripts/ && cp "$T/scripts/lib/main-checkout.sh" scripts/lib/ && printf 'HARNESS_SECOND_OPINION=off\n' > harness.conf && gq add . && gq commit -q -m f && gq push -q origin HEAD:main && cd ../up/bare.git && gq worktree add -q "$BP/bwt" main ) >/dev/null 2>&1
printf '%s' "$FAKE_MAIN" > "$BP/up/scripts/second-opinion.sh"; chmod +x "$BP/up/scripts/second-opinion.sh"; printf 'FIXTURE_API_KEY=%s\n' "$FIXVAL" > "$BP/up/$KEYF"
BW="$(physical "$BP/bwt")"
if [ -f "$BW/scripts/second-opinion.sh" ]; then
  hrun "$BW" "$BW/scripts/second-opinion.sh"
  chk "hand-over negated: a worktree of a BARE repository (common dir 'bare.git', not '.git') -> no hand-over even though the folder above it has a key file and a script" "$SO_OFF"
else
  RC=-; OUT="fixture not built"; ERR=""; chk "hand-over bare-repository fixture could not be built (git)" 'false'
fi
# a submodule checkout: its git dir lives under the superproject's .git/modules, it is not a linked worktree
SP="$FX/super"; mkdir -p "$SP"
( cd "$SP" && gq init -q . && printf x > a && gq add a && gq commit -q -m s && gq submodule add -q "$PL" sub ) >/dev/null 2>&1
if [ -f "$SP/sub/scripts/second-opinion.sh" ]; then
  printf 'FIXTURE_API_KEY=%s\n' "$FIXVAL" > "$SP/$KEYF"; mkdir -p "$SP/scripts"; printf '%s' "$FAKE_MAIN" > "$SP/scripts/second-opinion.sh"; chmod +x "$SP/scripts/second-opinion.sh"
  rm -f "${SP:?}/sub/${KEYF:?}"
  hrun "$SP/sub" "$SP/sub/scripts/second-opinion.sh"
  chk "hand-over negated: a SUBMODULE checkout (superproject has a key file and a script) -> no hand-over" "$SO_OFF"
else
  RC=-; OUT="fixture not built"; ERR=""; chk "hand-over submodule fixture could not be built (git)" 'false'
fi
# main without scripts/lib (an older main): the hand-over still happens (the fake needs no lib)
mkho n7; rm -rf "${MAIN:?}/scripts/lib"; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over main without scripts/lib (an older main checkout) still takes the call -- only its script file is needed" 'handed'
# the lib missing in the WORKTREE's copy: the script says so and carries on without a hand-over
mkho n8; rm -rf "${WT:?}/scripts/lib"; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over negated: the lib missing next to the worktree's script -> a note on stderr, NO hand-over, the call carries on in the worktree" '[ $RC = 4 ] && ! handed && [[ "$ERR" == *"lib/main-checkout.sh is missing, so a worktree call is not handed to the main checkout"* ]]'

# ── no loop, and main's own conf is what answers
mkho l0 real maincolon; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over no loop: main's script is a REAL copy with the hand-over code too -> the call ends there (exit 3: main's conf says local), no recursion" '[ $RC = 3 ] && ! handed && nokey'
chk "hand-over no loop: the hand-over note was printed exactly ONCE" '[ "$(printf "%s\n" "$ERR" | grep -c "takes the call")" = 1 ]'
chk "hand-over main's harness.conf answered, not the worktree's (the worktree says off/4, main says local/3)" '[[ "$OUT" == *"SECOND-OPINION: no external reviewer answered (mode local)"* ]]'
mkho l1 real; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over no loop sibling (T2): main without the conf change answers 'off' (exit 4) -- the same real-copy path works" '[ $RC = 4 ] && [[ "$OUT" == *"SECOND-OPINION: off"* ]] && [ "$(printf "%s\n" "$ERR" | grep -c "takes the call")" = 1 ]'

# ── the rule called directly (lib): every answer is a path or nothing, exit 0 / 1
libcall() { OUT="$(env -u HARNESS_ROOT_OVERRIDE bash -c '. "$1"; main_checkout_for "$2" "$3"' _ "$T/scripts/lib/main-checkout.sh" "$1" "$2" 2>&1)"; RC=$?; ERR=""; }
mkho b0; mkdir -p "$WT/sub/deeper"
libcall "$WT" scripts/second-opinion.sh
chk "hand-over lib: the top of the worktree -> prints exactly the main path (nothing else), exit 0" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
libcall "$WT/sub/deeper" scripts/second-opinion.sh
chk "hand-over lib: a SUBFOLDER of the worktree as <root> (not the top level) -> nothing, exit 1" '[ $RC = 1 ] && [ -z "$OUT" ]'
libcall "$WT/sub/.." scripts/second-opinion.sh
chk "hand-over lib: <root> written as 'wt/sub/..' (the top, with dot-dot) -> still the main path" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
libcall "$WT/" scripts/second-opinion.sh
chk "hand-over lib: <root> with a trailing slash -> the main path" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
libcall "$WT/no/such/folder" scripts/second-opinion.sh
chk "hand-over lib: a <root> that does not exist -> nothing, exit 1" '[ $RC = 1 ] && [ -z "$OUT" ]'
libcall "$WT" scripts/no-such-script.sh
chk "hand-over lib: a script path that does not exist in main -> nothing, exit 1" '[ $RC = 1 ] && [ -z "$OUT" ]'
libcall "$WT" "scripts/../scripts/second-opinion.sh"
chk "hand-over lib: sibling (T2) -- the script path written with dot-dot is still found (the rule tests the file, not the spelling)" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
libcall "$FX/h2/wtlink" scripts/second-opinion.sh
chk "hand-over lib: <root> given through a SYMLINK to the worktree -> still the main path (physical), exit 0" '[ $RC = 0 ] && [ "$OUT" = "$MAIN_H2" ]'
libcall "$MAIN" scripts/second-opinion.sh
chk "hand-over lib: <root> = the main checkout (it HAS a key file) -> nothing, exit 1" '[ $RC = 1 ] && [ -z "$OUT" ]'
OUT="$(env HARNESS_ROOT_OVERRIDE="$WT" bash -c '. "$1"; main_checkout_for "$2" "$3"' _ "$T/scripts/lib/main-checkout.sh" "$WT" scripts/second-opinion.sh 2>&1)"; RC=$?
chk "hand-over lib: HARNESS_ROOT_OVERRIDE set -> nothing, exit 1 (a caller that chose a root, or a call already handed over)" '[ $RC = 1 ] && [ -z "$OUT" ]'
chk "hand-over lib: the fixture key value is not in any answer above (the lib prints a path only)" 'nokey'
}

# shellcheck disable=SC2016  # chk tests are single-quoted on purpose (eval'd later); the fake programs are literal sh text
{
# ══ group kill (TERM, grace, KILL) and the lib's edge cases (empty root, a folder with the x-bit, GIT_DIR) ═════
# a hang whose child ignores TERM but whose leader does not: only the KILL after the grace can end the child
printf '#!/bin/sh\n(trap "" TERM; : > "%s/t.ready"; exec sleep 3016) &\necho $! > "%s/t.child"\necho $$ > "%s/t.pid"\ni=0\nwhile [ ! -e "%s/t.ready" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done\nsleep 3017\n' "$T" "$T" "$T" "$T" > "$T/bin/xhang3"; chmod +x "$T/bin/xhang3"
printf '#!/bin/sh\nhead -c 2000000 /dev/zero | tr "\\000" x\necho\n' > "$T/bin/xbig"; chmod +x "$T/bin/xbig"

# group-kill after a timeout: the TERM-ignoring child of a hung extra is gone (it needs the KILL after the grace)
rm -f "$T/t.pid" "$T/t.child" "$T/t.ready"
secs_run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl@1=$T/bin/xhang3'"
chk "also-ask group-kill timeout: an extra whose child IGNORES TERM is timed out (exit 124), the chain answer is printed, exit 0" '[ $RC = 0 ] && [ "$OUT" = "PRIMARY-ANSWER" ] && [[ "$ERR" == *"also asked fl: timed out (exit 124)"* ]]'
chk "also-ask group-kill timeout: ... and the TERM-ignoring child is gone afterwards (TERM, 5 s grace, KILL)" 'gone "$T/t.child" 3 && gone "$T/t.pid" 3'
chk "also-ask group-kill timeout: ... the stop took the grace (>= 5 s) but is bounded (<= 20 s)" '[ "$SECS" -ge 5 ] && [ "$SECS" -le 20 ]'
chk "also-ask group-kill sibling (T2): the program and its child were really started (pid files written)" '[ -s "$T/t.pid" ] && [ -s "$T/t.child" ]'
# how long does an ordinary, TERM-obeying hang take to stop? (the group has no member left after the TERM, so no grace is needed)
secs_run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl@1=$T/bin/xhang'"
chk "also-ask group-kill: an ordinary hung extra (it obeys TERM) is stopped well inside the grace + limit (<= 12 s)" '[ "$SECS" -le 12 ]'

# group-kill on TERM / INT to the script: the runner keeps going after the script is gone (about 5 s) and then ends the child
for SIG in SIGTERM SIGINT; do
  rm -f "$T/t.pid" "$T/t.child" "$T/t.ready"
  printf '%s\n' "HARNESS_SECOND_OPINION=external
HARNESS_EXTERNAL_REVIEWERS=\"p=$T/bin/p1\"
HARNESS_ALSO_ASK='fl=$T/bin/xhang3'" > "$T/harness.conf"
  echo "the prompt" > "$T/prompt.in"
  # shellcheck disable=SC2034  # SIGRC is read inside a single-quoted chk string (eval)
  SIGRC="$(SIGNAME=$SIG SUBJ="$SUBJECT" PIN="$T/prompt.in" CHILDF="$T/t.child" TMPDIR="$T/tmps" python3 -I -c '
import os, signal, subprocess, sys, time
p = subprocess.Popen(["bash", os.environ["SUBJ"]], stdin=open(os.environ["PIN"]), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
end = time.time() + 8
while not os.path.exists(os.environ["CHILDF"]) and time.time() < end:
    time.sleep(0.05)
time.sleep(0.5)
p.send_signal(getattr(signal, os.environ["SIGNAME"]))
try:
    print(p.wait(timeout=8))
except subprocess.TimeoutExpired:
    p.kill(); print("HUNG")
' 2>&1)"
  chk "also-ask group-kill $SIG to the script with an extra whose child ignores TERM: the script ends at once (exit not 0, no hang)" '[ "$SIGRC" != "HUNG" ] && [ "$SIGRC" != 0 ]'
  chk "also-ask group-kill $SIG: the TERM-ignoring child is gone within 12 s (the runner sends KILL after its 5 s grace)" 'gone "$T/t.child" 12'
  chk "also-ask group-kill $SIG: sibling (T2) -- the child had been started" '[ -s "$T/t.child" ]'
done

# a very large answer from an extra (2 MB) is printed whole; the exit code and the header are the usual ones
secs_run "$EXT
$PEXT
HARNESS_ALSO_ASK='big=$T/bin/xbig'"
chk "also-ask a 2 MB answer from an extra is printed whole, under its header, exit 0" '[ $RC = 0 ] && [[ "$OUT" == *"$HDR big ("* ]] && [ "${#OUT}" -gt 2000000 ]'

# the watchdog of this matrix itself bites: a run that would last 900 s (no limit on the extra, default 900) ends at once as exit 124
rm -f "$T/h.pid" "$T/h.child"
RUN_LIMIT_S=3 secs_run "$EXT
$PEXT
HARNESS_ALSO_ASK='fl=$T/bin/xhang'"
chk "also-ask WATCHDOG: a run that would hang is ended by the matrix's own watchdog (exit 124, 'watchdog' on stderr, within 20 s)" '[ $RC = 124 ] && [[ "$ERR" == *"watchdog: the run did not end within 3 s"* ]] && [ "$SECS" -le 20 ]'
chk "also-ask WATCHDOG: ... and the hung extra and its child are gone afterwards" 'gone "$T/h.pid" 8 && gone "$T/h.child" 8'
chk "also-ask WATCHDOG control (T2): a normal run is not touched (exit 0 with the default limit)" 'run "$EXT
$PEXT"; [ $RC = 0 ] && [ "$OUT" = "PRIMARY-ANSWER" ]'

# ── the lib fixes
libcall_in() { # libcall_in <cwd> [VAR=value ...] -- <root> <rel>
  local cwd="$1"; shift
  local envs=(); while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  OUT="$(cd "$cwd" && env -u HARNESS_ROOT_OVERRIDE ${envs[@]+"${envs[@]}"} bash -c '. "$1"; main_checkout_for "$2" "$3"' _ "$T/scripts/lib/main-checkout.sh" "$1" "$2" 2>&1)"; RC=$?; ERR=""
}
mkho r1
libcall_in "$WT" -- . scripts/second-opinion.sh
chk "hand-over lib control (T2): root '.' from inside the worktree -> the main path" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
libcall_in "$WT" -- "" scripts/second-opinion.sh
chk "hand-over lib: an EMPTY root (it would be read as the current folder, which here IS a worktree) -> nothing, exit 1" '[ $RC = 1 ] && [ -z "$OUT" ]'
libcall_in "$WT" -- "$WT" ""
chk "hand-over lib: an EMPTY script path -> nothing, exit 1" '[ $RC = 1 ] && [ -z "$OUT" ]'
mkho r2 scriptdir
libcall_in "$WT" -- "$WT" scripts/second-opinion.sh
chk "hand-over lib: main's script path is a FOLDER (x-bit set) -> nothing, exit 1 (an exec would fail with 126)" '[ $RC = 1 ] && [ -z "$OUT" ] && [ -d "$MAIN/scripts/second-opinion.sh" ] && [ -x "$MAIN/scripts/second-opinion.sh" ]'
hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over main's script is a FOLDER: the call carries on in the worktree (off, exit 4), no hand-over, no exec failure" "$SO_OFF"
# GIT_DIR / GIT_WORK_TREE / GIT_COMMON_DIR naming ANOTHER repository (a git hook sets them): the lib still answers for <root>
mkho r3
libcall_in "$WT" "GIT_DIR=$PL/.git" "GIT_WORK_TREE=$PL" -- "$WT" scripts/second-opinion.sh
chk "hand-over lib: GIT_DIR and GIT_WORK_TREE pointing at ANOTHER repository do not change the answer (the main path)" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
libcall_in "$WT" "GIT_COMMON_DIR=$PL/.git" -- "$WT" scripts/second-opinion.sh
chk "hand-over lib: GIT_COMMON_DIR pointing at another repository does not change the answer either" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
libcall_in "$WT" "GIT_DIR=$MAIN/.git" -- "$WT" scripts/second-opinion.sh
chk "hand-over lib: GIT_DIR set to the MAIN repository's own git dir (what a hook in main would set) -> still the worktree's answer (the main path)" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
chk "hand-over lib: the fixture key value is in none of the edge-case answers" 'nokey'

# ── HARNESS_KEY_FILE: the key file's NAME is a knob (default .env), read from the environment, then from the harness.conf of
# the root being asked about (read as text, never sourced). A name that is unusable means no hand-over, never a wrong one.
kf_conf() { printf 'HARNESS_SECOND_OPINION=off\n%s\n' "$1" > "$WT/harness.conf"; }
mkho k1; rm -f "${MAIN:?}/${KEYF:?}"
printf 'FIXTURE_API_KEY=%s\n' "$FIXVAL" > "$MAIN/secrets.local"; mkdir -p "$MAIN/keys"; printf 'FIXTURE_API_KEY=%s\n' "$FIXVAL" > "$MAIN/keys/api.key"
printf 'FIXTURE_API_KEY=%s\n' "$FIXVAL" > "$FX/k1/up.key"
libcall "$WT" scripts/second-opinion.sh
chk "key-file control (T2): main holds only 'secrets.local' and the default name is in force -> no hand-over" '[ $RC = 1 ] && [ -z "$OUT" ]'
kf_conf 'HARNESS_KEY_FILE=secrets.local'; libcall "$WT" scripts/second-opinion.sh
chk "key-file: HARNESS_KEY_FILE=secrets.local in the worktree's harness.conf -> handed to the main checkout" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
kf_conf 'HARNESS_KEY_FILE="secrets.local"   # where the keys live'; libcall "$WT" scripts/second-opinion.sh
chk "key-file: a double-quoted value with a trailing comment is read as the name" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
kf_conf "HARNESS_KEY_FILE='secrets.local'"; libcall "$WT" scripts/second-opinion.sh
chk "key-file: a single-quoted value is read as the name" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
kf_conf 'export HARNESS_KEY_FILE=secrets.local # note'; libcall "$WT" scripts/second-opinion.sh
chk "key-file: 'export NAME=value # comment' is read as the name" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
kf_conf 'HARNESS_KEY_FILE=keys/api.key'; libcall "$WT" scripts/second-opinion.sh
chk "key-file: a name with a sub-folder (keys/api.key) works" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
kf_conf 'HARNESS_KEY_FILE=other.key'; libcall_in "$WT" HARNESS_KEY_FILE=secrets.local -- "$WT" scripts/second-opinion.sh
chk "key-file: the environment wins over harness.conf (conf names a file main lacks, env names the one it has)" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
kf_conf 'HARNESS_KEY_FILE=other.key'; libcall "$WT" scripts/second-opinion.sh
chk "key-file control (T2): conf names a file main does NOT have -> no hand-over" '[ $RC = 1 ] && [ -z "$OUT" ]'
kf_conf 'HARNESS_KEY_FILE=secrets.local'; printf 'FIXTURE_API_KEY=%s\n' "$FIXVAL" > "$WT/secrets.local"; libcall "$WT" scripts/second-opinion.sh
chk "key-file: the worktree has its OWN file of the configured name -> no hand-over" '[ $RC = 1 ] && [ -z "$OUT" ]'
rm -f "$WT/secrets.local"; printf 'FIXTURE_API_KEY=%s\n' "$FIXVAL" > "$WT/$KEYF"; libcall "$WT" scripts/second-opinion.sh
chk "key-file: a default-named file in the worktree does NOT stop the hand-over once the conf names another file" '[ $RC = 0 ] && [ "$OUT" = "$MAIN" ]'
rm -f "$WT/$KEYF"
for v in '/etc/hosts' '../up.key' 'keys/../secrets.local' '"a b"' 'x;y' '$HOME/k'; do
  kf_conf "HARNESS_KEY_FILE=$v"; libcall "$WT" scripts/second-opinion.sh
  chk "key-file: an unusable name '$v' -> no hand-over (nothing printed, exit 1)" '[ $RC = 1 ] && [ -z "$OUT" ]'
done
kf_conf 'HARNESS_KEY_FILE=secrets.local'; libcall_in "$WT" 'HARNESS_KEY_FILE=../up.key' -- "$WT" scripts/second-opinion.sh
chk "key-file: an unusable name in the ENVIRONMENT ('../up.key', which exists) -> no hand-over, the conf does not rescue it" '[ $RC = 1 ] && [ -z "$OUT" ]'
mkho k2; rm -f "${MAIN:?}/${KEYF:?}"; printf 'FIXTURE_API_KEY=%s\n' "$FIXVAL" > "$MAIN/secrets.local"
hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "key-file end-to-end control (T2): default name, main holds only 'secrets.local' -> the worktree's own script carries on (off, exit 4)" "$SO_OFF"
kf_conf 'HARNESS_KEY_FILE=secrets.local'; hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "key-file end-to-end: the conf names 'secrets.local' -> main's script takes the call" 'handed && [[ "$OUT" == *"override=$MAIN "* ]] && nokey'
}

# shellcheck disable=SC2016  # chk tests are single-quoted on purpose (eval'd later)
{
# ══ the hand-over passes its arguments; ROOT ignores the git variables a hook exports ═════════════
mkho a1
hrun "$WT" "$WT/scripts/second-opinion.sh" "" "a b" --flag '*' 'x;y'
chk "hand-over args hand-over: the arguments given to the worktree's script reach main's script exactly (empty string, a space, a flag, a *, a ;)" 'handed && [[ "$OUT" == *"argc=5"* ]] && [ "$(printf "%s\n" "$OUT" | grep "^\[arg:" | tr "\n" "|")" = "[arg:]|[arg:a b]|[arg:--flag]|[arg:*]|[arg:x;y]|" ]'
hrun "$WT" "$WT/scripts/second-opinion.sh"
chk "hand-over args sibling (T2): without arguments the fake sees none (argc=0)" 'handed && [[ "$OUT" == *"argc=0"* ]]'
# git-env: the git variables name ANOTHER throwaway repository ($PL has a key file and a script of its own: had ROOT followed it, the
# call would end there, never reaching main). hrun unsets them, so these rows call the script directly (guarded the same way).
ghrun() { # ghrun <cwd> <script> VAR=value ...  -> RC OUT ERR, HARNESS_ROOT_OVERRIDE unset
  local cwd="$1" script="$2"; shift 2
  guard_ok "$script" "$cwd" || { echo "second-opinion matrix: INCOMPLETE - refusing to run $script in $cwd: not inside the throwaway tree"; exit 3; }
  OUT="$(cd "$cwd" && printf 'the prompt' | env -u HARNESS_ROOT_OVERRIDE "$@" TMPDIR="$T/tmp-ho" bash "$script" 2>"$T/err-ho")"; RC=$?; ERR="$(cat "$T/err-ho")"
}
ghrun "$WT" "$WT/scripts/second-opinion.sh" "GIT_DIR=$PL/.git" "GIT_WORK_TREE=$PL"
chk "hand-over git-env: GIT_DIR and GIT_WORK_TREE naming ANOTHER repository -> ROOT is still the worktree: the hand-over to ITS main happens" 'handed && [[ "$OUT" == *"override=$MAIN "* ]] && ! [[ "$OUT$ERR" == *"$PL"* ]] && nokey'
ghrun "$WT" "$WT/scripts/second-opinion.sh" "GIT_DIR=$PL/.git"
chk "hand-over git-env: GIT_DIR alone naming another repository -> the same" 'handed && [[ "$OUT" == *"override=$MAIN "* ]]'
ghrun "$WT" "$WT/scripts/second-opinion.sh" "GIT_COMMON_DIR=$PL/.git"
chk "hand-over git-env: GIT_COMMON_DIR alone naming another repository -> the same" 'handed && [[ "$OUT" == *"override=$MAIN "* ]]'
ghrun "$WT" "$WT/scripts/second-opinion.sh" "GIT_WORK_TREE=$PL"
chk "hand-over git-env: GIT_WORK_TREE alone naming another folder -> the same" 'handed && [[ "$OUT" == *"override=$MAIN "* ]]'
}

echo "second-opinion matrix: $pass pass, $fail fail$([ "${kdef:-0}" -gt 0 ] && printf ', %s known-defect (open findings)' "$kdef")"
[ "$fail" -eq 0 ]
