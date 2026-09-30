#!/usr/bin/env bash
# second-opinion-test.sh — known-answer matrix for second-opinion.sh. The property that matters most:
# a missing or failing outside reviewer NEVER breaks the run — it falls through the configured chain,
# then to the local reviewer, and always says who (if anyone) answered. Fake reviewers only; no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/so-test.XXXXXX")"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; export HARNESS_ROOT_OVERRIDE="$T"
printf '#!/bin/sh\necho "reviewer-A says: looks risky"\n' > "$T/bin/good";  chmod +x "$T/bin/good"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/fails"; chmod +x "$T/bin/fails"
printf '#!/bin/sh\nprintf "   \\n"\n' > "$T/bin/blank"; chmod +x "$T/bin/blank"
printf '#!/bin/sh\ncat\n' > "$T/bin/echo"; chmod +x "$T/bin/echo"
pass=0; fail=0
run() { # conf-lines → sets RC OUT ERR
  printf '%s\n' "$1" > "$T/harness.conf"
  OUT="$(echo "the prompt" | bash "$HERE/second-opinion.sh" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"
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
echo "second-opinion matrix: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
