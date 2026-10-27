#!/usr/bin/env bash
# ctw-success-criterion-test.sh — known-answer matrix for scripts/check-the-work.d/10-success-criterion.sh (cross author:
# written by a model that did not build the script, from its header and code).
#
# WHY: the hook is the lead's one guard against "the same session changed the code AND the tests, gates or goal that judge it"
# (the MASS study, arXiv 2610.12176). A classifier that reads a judging file as code, a scan that misses one kind of change
# (committed, staged, unstaged, untracked, deleted, renamed), an answer that can never satisfy `judge`, or a `verify` that
# passes a skipped step all let a weakened criterion through unseen. So the matrix pins (1) the classifier on every judging
# pattern and its near misses, (2) the scan in the work-tree and commits-only modes, the signals and the skip counter,
# (3) the flag rule incl. the goal (`G` / `GC` lines written by the REAL scripts/session-state.sh), (4) `answer`, `judge`
# and `verify` end to end (the verify rows build the criterion row through the real answer + judge), (5) the self-proof
# (a broken detector must exit 3 and no mode may then run), (6) hostile file names and environment.
#
# Every row runs the script inside a THROWAWAY git repository under one mktemp folder (removed by a trap); the real
# repository, its git folder and its docs/agents/criterion.jsonl are never touched (the last rows compare them before and after).
# Oracles are written by hand (expected signals, cksum of the fingerprint text, exit codes of docs/ci/gates.md: 0 pass,
# 1 fail, 3 could not run), never computed by the script under test.
#
# KNOWN-DEFECT rows (kbegin) assert the CORRECT behaviour the script lacks (findings for the lead). They print
# "known-defect (open finding)" and do not fail the matrix; once the script is fixed they fail with "now PASSES - promote",
# so the fix is noticed. CTW_CRITERION_STRICT=1 makes them ordinary failing rows. None is open since the builder's fixes after
# the first report: those rows are normal rows now, with the lead's rulings. Rows whose expected
# behaviour rests on an assumption about intent say ASSUMPTION in their name.
# SCRIPT_UNDER_TEST=<path> runs the matrix against a copy (a mutant, to watch a row go red).
# MATRIX_ONLY=<egrep on the row name> runs only the matching rows (a mutant run needs only the rows of one rule family).
# Exit: 0 every row passed · 1 any row failed · 3 could not run (a tool missing, or the fixture could not be built).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="${SCRIPT_UNDER_TEST:-$HERE/check-the-work.d/10-success-criterion.sh}"
[ -f "$SUT" ] || { echo "ctw-success-criterion matrix: INCOMPLETE - the script under test is missing: $SUT"; exit 3; }
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"
SESSION_STATE="$HERE/session-state.sh"
CTW_RUNNER="$HERE/check-the-work.sh"
for tool in git python3 awk sed grep cksum; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ctw-success-criterion matrix: INCOMPLETE - $tool is missing"; exit 3; }
done
[ -f "$SESSION_STATE" ] || { echo "ctw-success-criterion matrix: INCOMPLETE - scripts/session-state.sh is missing (the goal rows write the real record)"; exit 3; }
[ -f "$CTW_RUNNER" ] || { echo "ctw-success-criterion matrix: INCOMPLETE - scripts/check-the-work.sh is missing (the classifier-copy row compares with it)"; exit 3; }

# what the real repository looks like before the matrix runs (the last rows compare)
real_snapshot() {
  { shasum "$HERE/../docs/agents/criterion.jsonl" 2>&1
    git -C "$HERE" status --porcelain -- docs/agents 2>&1
    shasum "$SUT" 2>&1; } 2>&1
}
REAL_BEFORE="$(real_snapshot)"

# Isolation: nothing of the user's git configuration and no inherited git or hook variables reach the throwaway repositories.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_NAMESPACE
# CTW_CRITERION_STRICT is this matrix's own switch (strict mode), not a variable of the script under test: it must survive the scrub
for v in $(env | sed -n 's/^\(CTW_[A-Z_]*\)=.*/\1/p; s/^\(CHECK_THE_WORK_[A-Z_]*\)=.*/\1/p; s/^\(HARNESS_[A-Z_]*\)=.*/\1/p'); do
  [ "$v" = CTW_CRITERION_STRICT ] || unset "$v"
done
T0="$(mktemp -d "${TMPDIR:-/tmp}/ctw-crit-test.XXXXXX")" || { echo "ctw-success-criterion matrix: INCOMPLETE - mktemp failed"; exit 3; }
T="$(cd "$T0" && pwd -P)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/tmp" "$T/fx" "$T/o" "$T/mut"
export HOME="$T/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 TMPDIR="$T/tmp" LC_ALL=C GIT_CEILING_DIRECTORIES="$T"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid
TAB="$(printf '\t')"
NL='
'

# ── the framework ────────────────────────────────────────────────────────────────────────────────────────────────────
N=0; PASSED=0; FAILED=0; KD=0; WHY=""; NAME=""; KDROW=0; XE=(); SUT_ALT=""
fail() { WHY="$WHY | $*"; }
setup_fail() { echo "ctw-success-criterion matrix: INCOMPLETE - fixture: $*"; exit 3; }
finish() {
  if [ "$KDROW" = 1 ] && [ "${CTW_CRITERION_STRICT:-0}" != 1 ]; then
    if [ -z "$WHY" ]; then FAILED=$((FAILED + 1)); echo "FAIL  KNOWN-DEFECT now PASSES - promote to a normal row: $NAME"
    else KD=$((KD + 1)); echo "known-defect (open finding)  $NAME -- ${WHY# | }"; fi
    KDROW=0; return
  fi
  if [ -z "$WHY" ]; then PASSED=$((PASSED + 1)); echo "PASS  $NAME"; else FAILED=$((FAILED + 1)); echo "FAIL  $NAME -- ${WHY# | }"; fi
}
# begin "<name>": starts a row; returns 1 (row skipped) when MATRIX_ONLY does not match its name
begin() {
  NAME="$1"; WHY=""; KDROW=0; XE=(); SUT_ALT=""
  if [ -n "${MATRIX_ONLY:-}" ] && ! printf '%s' "$NAME" | grep -qE "$MATRIX_ONLY"; then return 1; fi
  N=$((N + 1)); return 0
}
# shellcheck disable=SC2329  # no known-defect row is open since the first fixes; kept for the next finding (house style)
kbegin() { begin "KNOWN-DEFECT $1" || return 1; KDROW=1; return 0; }  # a KNOWN-DEFECT row
want_rc() { [ "$RC" = "$1" ] || fail "exit $RC, wanted $1 (out: $(head -c 300 "$OUT" | tr '\n' '~') err: $(head -c 300 "$ERR" | tr '\n' '~'))"; }
has() { grep -qF -- "$2" "$1" 2>/dev/null || fail "${3:-$(basename "$1")}: missing '$2'"; }
lacks() { ! grep -qF -- "$2" "$1" 2>/dev/null || fail "${3:-$(basename "$1")}: must not contain '$2'"; }
eq() { [ "$1" = "$2" ] || fail "${3:-value}: got '$1', wanted '$2'"; }
# sut <dir> <args...>: run the script from <dir> with the row's extra environment XE; sets OUT, ERR, RC
sut() {
  local dir="$1"; shift
  OUT="$T/o/last.out"; ERR="$T/o/last.err"
  ( cd "$dir" && env ${XE[@]+"${XE[@]}"} "$BASH" "${SUT_ALT:-$SUT}" "$@" ) >"$OUT" 2>"$ERR"; RC=$?
}
# the scan output lines
flag_up_out() { grep -qF "SUCCESS-CRITERION FLAG" "$OUT"; }
judged() { grep -qF -- "  judging file: $1  ($2)" "$OUT"; }
code_count() { sed -n 's/^  code files changed with them: \([0-9]*\)$/\1/p' "$OUT" | head -1; }

# ── fixtures (all through real git commands) ─────────────────────────────────────────────────────────────────────────
gitc() { git -C "$1" -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m "${2:-c}" || setup_fail "commit in $1"; }
# shellcheck disable=SC2059  # wf passes a printf format on purpose (callers write \n and %s)
wf() { local f="$1/$2"; shift 2; mkdir -p "$(dirname "$f")" || setup_fail "mkdir"; printf "$@" > "$f" || setup_fail "write $f"; } # wf <repo> <path> <printf args>
TPL="$T/tpl"; mkdir -p "$TPL"
git init -q -b main "$TPL" || setup_fail "git init"
wf "$TPL" pkg/a.go 'package a\n'
wf "$TPL" pkg/a_test.go 'a\nb\n'
wf "$TPL" pkg/c_test.go '1\n2\n3\n'
wf "$TPL" pkg/d_test.go 'keep\nold t.Skip("old")\n'
wf "$TPL" pkg/e_test.go 'x\n'
wf "$TPL" pkg/f_test.go 'p\nq\n'
printf '\000\001\002' > "$TPL/pkg/bin_test.dat"
wf "$TPL" docs/n.md 'x\n'
wf "$TPL" README.md 'r\n'
wf "$TPL" .gitignore '*.ignored\n'
git -C "$TPL" add pkg/a.go pkg/a_test.go pkg/c_test.go pkg/d_test.go pkg/e_test.go pkg/f_test.go pkg/bin_test.dat docs/n.md README.md .gitignore || setup_fail "add"
gitc "$TPL" base
FX=""; BASESHA=""; SD=""
new_fx() { # new_fx <name>: FX = a copy of the template on branch feat/x (main is the base); BASESHA = main's commit
  FX="$T/fx/$1"; cp -R "$TPL" "$FX" || setup_fail "cp $1"
  git -C "$FX" checkout -q -b feat/x || setup_fail "branch"
  BASESHA="$(git -C "$FX" rev-parse main)"
}
mkstate() { # what `check-the-work.sh run` writes (save_state base / branch): SD = the state folder of $FX
  SD="$(git -C "$FX" rev-parse --absolute-git-dir)/check-the-work"; mkdir -p "$SD"
  printf '%s' "$BASESHA" > "$SD/base"; printf '%s' "feat/x" > "$SD/branch"
}
code_and_test() { wf "$FX" pkg/a.go 'package a // changed\n'; wf "$FX" pkg/new_test.go 'z\n'; }  # the smallest flagging change (untracked test)
GOAL1="$T/goal1.md"; printf '%s\n' 'GOAL: make a.txt say hello' 'PROOF: the test passes' 'LIMIT: only a.txt' > "$GOAL1"
GOAL2="$T/goal2.md"; printf '%s\n' 'GOAL: make a.txt say goodbye' 'PROOF: nothing' 'LIMIT: anything' > "$GOAL2"
ss() { # ss <repo> <session-state.sh args>: the REAL state writer
  local r="$1"; shift
  "$BASH" "$SESSION_STATE" -C "$r" "$@" >"$T/o/ss.out" 2>&1 || setup_fail "session-state $*: $(head -c 300 "$T/o/ss.out")"
}
# the judge command as the hook runner calls it; state folder and root as the runner sets them
hook_env() { XE=(CTW_ROOT="$FX" CTW_STATE="$SD" CTW_BRANCH=feat/x); }

# ══ 1. the classifier ═════════════════════════════════════════════════════════════════════════════════════════════════
# One work tree holds code (pkg/c.go) + the path list; the scan names every judging file, so a path is judged by whether
# it appears among them, and "code" by the count of code files.
JUDGE_PATHS="src/a/b_test.go tests/x.sh test/y.py lib/Tests/Z.txt pkg/tests/q.go pkg/test/q.go lib2/Tests/A.txt tools/foo-test.sh pkg/Foo_test.go src/FooTest.cs src/FooTests.cs scripts/check-x.sh scripts/run-all-gates.sh scripts/mutation-test.sh scripts/coverage-floors.txt scripts/lint-baselines/shellcheck.txt scripts/foo-baseline.txt scripts/x-allow.txt scripts/stacks/x.conf .harness/baselines/x harness.conf .semgrep.yml .semgrepignore .golangci.yml .gitleaks.toml .osv-scanner.toml docs/deferred-test-registry.md scripts/check-the-work.d/30-new.sh scripts/check-the-work.d/README.md scripts/check-the-work.d/50-x.py"
CODE_PATHS="scripts/check.sh scripts/checkout.sh scripts/heavy-run.sh scripts/foo.sh src/x.go src/latest.go src/contest.go pkg/testdata2/x.go pkg/fixturesx/y.go pkg/mytestdata/z.go pkg/mytests/x.go pkg/attests.go cmd/main.go scripts/coverage-floors.csv"
OTHER_PATHS="docs/a.md docs/x.txt notes.md logs/run.jsonl docs/agents/reviews.jsonl docs/agents/criterion.jsonl go.sum sbom/x.json web/package-lock.json packages.lock.json x.lockfile"
mk_files() { local p; for p in "$@"; do wf "$FX" "$p" 'x\n'; done; }

r_cls_judge() {
  new_fx cj; local p; wf "$FX" pkg/c.go 'package c\n'
  # shellcheck disable=SC2086  # the lists are space-separated paths without spaces or globs
  mk_files $JUDGE_PATHS
  sut "$FX" scan; want_rc 0
  for p in $JUDGE_PATHS; do grep -qF -- "  judging file: $p  (" "$OUT" || fail "$p not read as a judging file"; done
  eq "$(code_count)" 1 "code files (only pkg/c.go)"
}
r_cls_capital_tests_dir() { # separate from the list above: macOS folds tests/ and Tests/ into one folder
  new_fx ct; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" Tests/Z.txt 'x\n'
  sut "$FX" scan; want_rc 0; grep -qF -- "  judging file: Tests/Z.txt  (" "$OUT" || fail "Tests/Z.txt not read as a judging file"
}
r_cls_code() {
  new_fx cc; local p n; wf "$FX" pkg/zz_test.go 'x\n'
  # shellcheck disable=SC2086
  mk_files $CODE_PATHS
  sut "$FX" scan; want_rc 0
  # shellcheck disable=SC2086  # the path list is space-separated, without spaces or globs inside a path
  n="$(printf '%s\n' $CODE_PATHS | wc -l | tr -d ' ')"
  eq "$(code_count)" "$n" "code files (every near miss is code)"
  eq "$(grep -c '^  judging file: ' "$OUT")" 1 "judging files (only the sentinel pkg/zz_test.go)"
  for p in $CODE_PATHS; do ! grep -qF -- "  judging file: $p  (" "$OUT" || fail "$p wrongly read as a judging file"; done
}
r_cls_other() {
  new_fx co; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" pkg/zz_test.go 'x\n'
  # shellcheck disable=SC2086
  mk_files $OTHER_PATHS
  sut "$FX" scan; want_rc 0
  eq "$(code_count)" 1 "code files (docs, logs and machine-written files are neither code nor judges)"
  eq "$(grep -c '^  judging file: ' "$OUT")" 1 "judging files (only the sentinel)"
}
# Test fixtures and test data redefine success as surely as an assertion (a changed golden file), so criterion_class reads them as
# judging although ctw_file_class (a copy of check-the-work.sh file_class) puts them in class 2 (lead's ruling).
FIXTURE_JUDGE_PATHS="src/x/testdata/golden.json pkg/a/fixtures/b.txt pkg/fixture/c.txt server/test/cases.jsonl testdata/top.json fixtures/top.txt fixture/top.txt tests/cases.jsonl Tests/cases.jsonl test/cases.jsonl pkg/tests/cases.jsonl pkg/ios/Tests/cases.jsonl"
r_cls_fixtures_are_judging() {
  local p i=0
  # positive control in the same repository: code + a real test file flags (so a "flag" below is not an artefact of the fixture)
  new_fx cfx0; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" pkg/zz_test.go 'x\n'
  sut "$FX" scan; want_rc 0; flag_up_out || fail "control: code + a real test file must flag"
  # shellcheck disable=SC2086  # the list is space-separated paths without spaces or globs
  for p in $FIXTURE_JUDGE_PATHS; do
    i=$((i + 1))   # a number, not the path, names the folder: macOS folds tests/ and Tests/ into one name
    new_fx "cfx-$i"; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" "$p" '{}\n'
    sut "$FX" scan; want_rc 0
    flag_up_out || fail "$p next to a code change: no flag"
    judged "$p" "+1 -0" || fail "$p not listed as a judging file: $(grep 'judging file' "$OUT" | tr '\n' '~')"
    eq "$(code_count)" 1 "$p: code files (only pkg/c.go)"
    # the fixture alone is a judge without code: no flag
    new_fx "cfy-$i"; wf "$FX" "$p" '{}\n'
    sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "$p alone"
  done
}
# paths of main's class-2 head line that are neither tests, fixtures nor source stay "other" (docs/, *.md, *.jsonl): code + them = no flag;
# a runs/ or archive/ SOURCE file is code again (round 2, r_cls_head_line_sources_stay_code). Control: the sentinel test file flags.
r_cls_machine_written_stay_other() {
  local p i=0
  for p in docs/archive/old.md foo.answer.md data/x.jsonl docs/runs/x.md; do
    i=$((i + 1)); new_fx "cmo-$i"; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" "$p" 'x\n'
    sut "$FX" scan; want_rc 0
    has "$OUT" "no success-criterion flag" "$p next to code"
    ! grep -qF -- "  judging file: $p  (" "$OUT" || fail "$p wrongly read as a judging file"
    # control: the same tree plus one real test file flags, and still lists only that test file as judging
    wf "$FX" pkg/zz_test.go 'x\n'
    sut "$FX" scan; want_rc 0; flag_up_out || fail "control for $p: code + a real test file must flag"
    eq "$(grep -c '^  judging file: ' "$OUT")" 1 "$p: judging files (only the sentinel)"
    eq "$(code_count)" 1 "$p: code files (only pkg/c.go; it is neither code nor a judge)"
  done
}
# Round 2 (reviewer finding): main's file_class opens with a "machine-written" head line (archive/, runs/, fixtures,
# *.answer.md, *.jsonl ...) that only orders check-the-work.sh's review diff. criterion_class decides those paths itself, so a TEST
# under archive/ or runs/ stays judging and a SOURCE file there stays code; only fixtures and test data became judging.
r_cls_head_line_tests_stay_judging() {
  local p i=0
  new_fx chl0; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" pkg/zz_test.go 'x\n'
  sut "$FX" scan; want_rc 0; flag_up_out || fail "control: code + a real test file must flag"
  for p in src/runs/runs_test.go tests/archive/old_test.sh tests/golden/x.answer.md pkg/cases_test.jsonl src/FooTests.jsonl; do
    i=$((i + 1))
    new_fx "chl-$i"; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" "$p" 'x\n'
    sut "$FX" scan; want_rc 0
    flag_up_out || fail "$p (a test under a machine-written path) next to a code change: no flag"
    judged "$p" "+1 -0" || fail "$p not listed as a judging file: $(grep 'judging file' "$OUT" | tr '\n' '~')"
    eq "$(code_count)" 1 "$p: code files (only pkg/c.go)"
    new_fx "chm-$i"; wf "$FX" "$p" 'x\n'
    sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "$p alone"
  done
}
r_cls_head_line_sources_stay_code() {
  local p i=0
  for p in src/runs/runner.go pkg/archive/a.go runs/x.log archive/y.txt pkg/runs/z.log; do
    i=$((i + 1))
    # alone: code without a judge does not flag
    new_fx "chs-$i"; wf "$FX" "$p" 'package x\n'
    sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "$p alone"
    # control: with a real test file it IS the code (count 1) and the test file is the only judging file
    wf "$FX" pkg/zz_test.go 'x\n'
    sut "$FX" scan; want_rc 0; flag_up_out || fail "control: $p + a real test file must flag"
    eq "$(code_count)" 1 "$p: code files (it is the code)"
    judged pkg/zz_test.go "+1 -0" || fail "$p: the test file is not listed as judging"
    ! grep -qF -- "  judging file: $p  (" "$OUT" || fail "$p wrongly read as a judging file"
  done
  # CHECK_THE_WORK_LAST still wins over the test pattern for a path under a head-line folder (as in r_cls_last_globs). The glob
  # is written so that the unquoted ${CHECK_THE_WORK_LAST} expansion matches the same file either way (see the KNOWN-DEFECT row)
  new_fx chs-last; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" gen/runs/x_test.go 'x\n'
  XE=(CHECK_THE_WORK_LAST="gen/*/*")
  sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "gen/runs/x_test.go matches LAST"
  ! grep -qF -- "  judging file: gen/runs/x_test.go  (" "$OUT" || fail "gen/runs/x_test.go matches CHECK_THE_WORK_LAST but is judging"
  # control: without LAST the same test file is judging
  XE=(); sut "$FX" scan; want_rc 0; flag_up_out || fail "control: without LAST gen/runs/x_test.go + code must flag"
  judged gen/runs/x_test.go "+1 -0" || fail "control: without LAST gen/runs/x_test.go is not judging"
}
# FINDING (found by this matrix, fixed in the hook with `set -f`): the glob list is expanded UNQUOTED (for g in ${CHECK_THE_WORK_LAST:-}), so the shell
# first matches each pattern against FILES IN THE CURRENT FOLDER: 'gen/*' becomes 'gen/runs' (the one entry of gen/) and no longer
# matches gen/runs/x_test.go. Same in check-the-work.sh file_class (not fixed there by this port) and for the JUDGE_GLOBS variables. Correct: 'gen/*' matches it.
r_cls_last_glob_not_expanded_by_the_shell() {
  new_fx chk; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" gen/runs/x_test.go 'x\n'
  XE=(CHECK_THE_WORK_LAST="gen/*")
  sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "gen/runs/x_test.go matches LAST gen/*"
}
# F4: the eval answer key (cases.jsonl) decides whether the reviewer passes, so it is a judging file in spite of *.jsonl
r_cls_reviewer_eval_answer_key_is_judging() {
  new_fx cre; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" evals/cases.jsonl 'x\n'
  sut "$FX" scan; want_rc 0; flag_up_out || fail "evals/cases.jsonl next to code: no flag"
  judged evals/cases.jsonl "+1 -0" || fail "not listed as a judging file: $(grep 'judging file' "$OUT" | tr '\n' '~')"
  eq "$(code_count)" 1 "code files (only pkg/c.go)"
  # control: a .jsonl file elsewhere stays other (no flag)
  new_fx cre2; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" data/evals/cases.jsonl 'x\n'
  sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "data/evals/cases.jsonl next to code"
}
# The head-line pattern is copied twice in the script under test (ctw_file_class and the block in criterion_class); both must equal
# the first case label of file_class in check-the-work.sh, or a path is decided differently here than in the runner.
r_cls_head_line_pattern_drift() {
  local a b c
  a="$(awk '/^criterion_class\(\) \{/ { on = 1 } on && /archive\/\*\|/ { print; exit }' "$SUT" | sed 's/^ *//; s/) echo 2; return ;;$//; s/)$//')"
  b="$(awk '/^file_class\(\) \{/ { on = 1 } on && /archive\/\*\|/ { print; exit }' "$CTW_RUNNER" | sed 's/^ *//; s/) echo 2; return ;;$//; s/)$//')"
  c="$(awk '/^ctw_file_class\(\) \{/ { on = 1 } on && /archive\/\*\|/ { print; exit }' "$SUT" | sed 's/^ *//; s/) echo 2; return ;;$//; s/)$//')"
  [ -n "$a" ] || fail "no head-line pattern found in criterion_class of the script under test"
  [ -n "$b" ] || fail "no head-line pattern found in file_class of check-the-work.sh"
  [ "$a" = "$b" ] || fail "criterion_class head-line pattern drifted from file_class: '$a' vs '$b'"
  [ "$c" = "$b" ] || fail "ctw_file_class head-line pattern drifted from file_class: '$c' vs '$b'"
}
r_cls_judge_globs() {
  new_fx cg; wf "$FX" pkg/c.go 'package c\n'
  wf "$FX" gen/api.pb.go 'x\n'; wf "$FX" configs/rules.cfg 'x\n'; wf "$FX" docs/rules-doc.md 'x\n'; wf "$FX" gen/other.go 'x\n'
  XE=(CHECK_THE_WORK_JUDGE_GLOBS="gen/*.pb.go configs/*.cfg docs/rules-*.md")
  sut "$FX" scan; want_rc 0
  for p in gen/api.pb.go configs/rules.cfg docs/rules-doc.md; do grep -qF -- "  judging file: $p  (" "$OUT" || fail "$p (matches CHECK_THE_WORK_JUDGE_GLOBS) not judging"; done
  ! grep -qF -- "  judging file: gen/other.go  (" "$OUT" || fail "gen/other.go matches no glob but is judging"
  eq "$(code_count)" 2 "code files (pkg/c.go and gen/other.go)"
  # positive control: without the variable the same tree has no judge at all
  XE=(); sut "$FX" scan; want_rc 0; lacks "$OUT" "SUCCESS-CRITERION FLAG" "without the globs"
}
# The project's own idea of a test file (HARNESS_TEST_GLOBS: stack pack or harness.conf) and its extra judging globs
# (HARNESS_JUDGE_GLOBS) add judges the fixed rules do not know. The environment wins over harness.conf.
r_cls_project_globs() {
  new_fx cpg; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" pkg/checks/a.rb 'x\n'; wf "$FX" pkg/other/b.rb 'x\n'
  XE=(HARNESS_TEST_GLOBS="*/checks/*.rb")
  sut "$FX" scan; want_rc 0; flag_up_out || fail "env HARNESS_TEST_GLOBS: pkg/checks/a.rb next to code: no flag"
  judged pkg/checks/a.rb "+1 -0" || fail "pkg/checks/a.rb (matches HARNESS_TEST_GLOBS) not judging: $(grep 'judging file' "$OUT" | tr '\n' '~')"
  ! grep -qF -- "  judging file: pkg/other/b.rb  (" "$OUT" || fail "pkg/other/b.rb matches no glob but is judging"
  eq "$(code_count)" 2 "code files (pkg/c.go and pkg/other/b.rb)"
  XE=(); sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "control: without the globs this tree has no judge"
  # a broad operator glob must not break the self-proof (it proves the fixed rules; the operator's lists are blanked for it)
  new_fx cpb; wf "$FX" src/c.go 'package c\n'; wf "$FX" lib/e.go 'package e\n'
  XE=(CHECK_THE_WORK_JUDGE_GLOBS="src/* docs/*" CHECK_THE_WORK_LAST="scripts/* docs/*")
  sut "$FX" scan; want_rc 0; judged src/c.go "+1 -0" || fail "broad globs: src/c.go is judging by the operator's list: $(head -c 300 "$ERR")"
  XE=()
  # a stack pack named in harness.conf: python.conf calls a top-level test_*.py a test file, the fixed rules do not
  new_fx cpk; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" test_x.py 'x\n'; wf "$FX" gen/api.proto 'x\n'
  wf "$FX" harness.conf 'HARNESS_STACK="python"\nHARNESS_JUDGE_GLOBS="gen/*.proto"\n'
  sut "$FX" scan; want_rc 0
  judged test_x.py "+1 -0" || fail "test_x.py (HARNESS_TEST_GLOBS of the python pack) not judging: $(grep 'judging file' "$OUT" | tr '\n' '~')"
  judged gen/api.proto "+1 -0" || fail "gen/api.proto (HARNESS_JUDGE_GLOBS of harness.conf) not judging"
  judged harness.conf "+2 -0" || fail "harness.conf is a judging file"
  eq "$(code_count)" 1 "code files (only pkg/c.go)"
  XE=(HARNESS_JUDGE_GLOBS="nothing/*"); sut "$FX" scan; want_rc 0
  ! grep -qF -- "  judging file: gen/api.proto  (" "$OUT" || fail "the environment must win over harness.conf: gen/api.proto still judging"
  judged test_x.py "+1 -0" || fail "the pack's globs stay when only the judge globs are overridden"
  # a pack that does not exist is ignored here (the gates report it); the fixed rules still work
  new_fx cpn; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" pkg/zz_test.go 'x\n'; wf "$FX" harness.conf 'HARNESS_STACK="no-such-pack"\n'
  sut "$FX" scan; want_rc 0; judged pkg/zz_test.go "+1 -0" || fail "an unknown pack must not switch the fixed rules off"
}
# The baseline folder and the deferred-test registry are configured paths: they judge where harness.conf says, not where the defaults were.
r_cls_configured_paths() {
  new_fx ccp; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" qa/base/x.txt 'x\n'; wf "$FX" docs/registers/dt.md 'x\n'; wf "$FX" docs/deferred-test-registry.md 'x\n'
  XE=(HARNESS_BASELINE_DIR="qa/base/" HARNESS_MARKERS="TODO-REGISTERED:docs/t.md DEFERRED-TEST:docs/registers/dt.md STUB:docs/s.md")
  sut "$FX" scan; want_rc 0
  judged qa/base/x.txt "+1 -0" || fail "qa/base/x.txt (HARNESS_BASELINE_DIR) not judging: $(grep 'judging file' "$OUT" | tr '\n' '~')"
  judged docs/registers/dt.md "+1 -0" || fail "docs/registers/dt.md (the DEFERRED-TEST entry of HARNESS_MARKERS) not judging"
  ! grep -qF -- "  judging file: docs/deferred-test-registry.md  (" "$OUT" || fail "the default registry path must not judge once HARNESS_MARKERS names another"
  eq "$(code_count)" 1 "code files (only pkg/c.go; the default registry is a docs file)"
  # without the knobs the defaults hold
  XE=(); sut "$FX" scan; want_rc 0
  judged docs/deferred-test-registry.md "+1 -0" || fail "default registry path"
  ! grep -qF -- "  judging file: qa/base/x.txt  (" "$OUT" || fail "qa/base/x.txt judges only when HARNESS_BASELINE_DIR names it"
}
r_cls_last_globs() {
  new_fx cl; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" tests/gen_data.go 'x\n'; wf "$FX" tests/real_test.go 'x\n'; wf "$FX" scripts/check-z.sh 'x\n'
  XE=(CHECK_THE_WORK_LAST="tests/gen_* scripts/*")
  sut "$FX" scan; want_rc 0
  ! grep -qF -- "  judging file: tests/gen_data.go  (" "$OUT" || fail "tests/gen_data.go matches CHECK_THE_WORK_LAST (machine-written) but is judging"
  grep -qF -- "  judging file: tests/real_test.go  (" "$OUT" || fail "tests/real_test.go (not in LAST) must stay judging"
  grep -qF -- "  judging file: scripts/check-z.sh  (" "$OUT" || fail "a gate script stays judging even when LAST matches it (the judge patterns come first)"
  # positive control: without LAST the generated test data is judging
  XE=(); sut "$FX" scan; grep -qF -- "  judging file: tests/gen_data.go  (" "$OUT" || fail "control: without LAST tests/gen_data.go must be judging"
}
r_cls_judge_beats_last() {
  new_fx cb; wf "$FX" pkg/c.go 'package c\n'; wf "$FX" gen/api.pb.go 'x\n'
  XE=(CHECK_THE_WORK_JUDGE_GLOBS="gen/*" CHECK_THE_WORK_LAST="gen/*")
  sut "$FX" scan; want_rc 0
  grep -qF -- "  judging file: gen/api.pb.go  (" "$OUT" || fail "a path in both JUDGE_GLOBS and LAST must be judging (judge wins)"
}
# The classifier is a copy of check-the-work.sh file_class on purpose; if the two drift, a test file reads as code here.
r_cls_copy_of_runner() {
  local a b
  # without the first line: the header comment after the opening brace may differ
  a="$(awk '/^ctw_file_class\(\) \{/ { on = 1 } on { print } on && /^\}/ { exit }' "$SUT" | sed '1d')"
  b="$(awk '/^file_class\(\) \{/ { on = 1 } on { print } on && /^\}/ { exit }' "$CTW_RUNNER" | sed '1d')"
  [ -n "$a" ] || fail "ctw_file_class not found in the script under test"
  [ -n "$b" ] || fail "file_class not found in check-the-work.sh"
  [ "$a" = "$b" ] || fail "ctw_file_class drifted from check-the-work.sh file_class: $(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | head -6 | tr '\n' '~')"
}

# ══ 2. the scan: every kind of change, both modes ═════════════════════════════════════════════════════════════════════
r_scan_docs_only_no_flag() {
  new_fx sd; wf "$FX" docs/n.md 'y\n'; wf "$FX" README.md 'q\n'
  sut "$FX" scan; want_rc 0
  has "$OUT" "no success-criterion flag"; lacks "$OUT" "SUCCESS-CRITERION FLAG"
  has "$OUT" "base $(printf '%s' "$BASESHA" | cut -c1-7))" "the message names the base"
}
r_scan_code_only_and_judge_only() {
  new_fx sc; wf "$FX" pkg/a.go 'package a // changed\n'
  sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "code only"
  git -C "$FX" checkout -q pkg/a.go
  wf "$FX" pkg/new_test.go 'z\n'
  sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "judge only"
  # positive control: both together flag, in the same repository
  wf "$FX" pkg/a.go 'package a // changed\n'
  sut "$FX" scan; want_rc 0; flag_up_out || fail "control: code + test together must flag"
}
# code and judge in every pairing of committed / staged / unstaged / untracked (the work tree as `run` sees it)
r_scan_all_change_kinds() {
  local ck jk
  for ck in committed staged unstaged untracked; do
    for jk in committed staged unstaged untracked; do
      new_fx "sk-$ck-$jk"
      case "$ck" in untracked) wf "$FX" pkg/new.go 'package n\n' ;; *) wf "$FX" pkg/a.go 'package a // changed\n' ;; esac
      case "$jk" in untracked) wf "$FX" pkg/new_test.go 'z\n' ;; *) wf "$FX" pkg/a_test.go 'a\nb\nnew\n' ;; esac
      case "$ck" in committed) git -C "$FX" add pkg/a.go; gitc "$FX" code ;; staged) git -C "$FX" add pkg/a.go ;; esac
      case "$jk" in committed) git -C "$FX" add pkg/a_test.go; gitc "$FX" test ;; staged) git -C "$FX" add pkg/a_test.go ;; esac
      sut "$FX" scan
      { [ "$RC" = 0 ] && flag_up_out; } || fail "code $ck + judge $jk: no flag (rc $RC)"
      case "$jk" in untracked) judged pkg/new_test.go "+1 -0" || fail "code $ck + judge $jk: signals wrong: $(grep 'judging file' "$OUT" | tr '\n' '~')" ;;
                    *) judged pkg/a_test.go "+1 -0" || fail "code $ck + judge $jk: signals wrong: $(grep 'judging file' "$OUT" | tr '\n' '~')" ;; esac
      eq "$(code_count)" 1 "code $ck + judge $jk: code count"
    done
  done
}
r_scan_deleted_judge() {
  new_fx dj; wf "$FX" pkg/a.go 'package a // changed\n'
  rm "$FX/pkg/e_test.go"                                  # deleted in the work tree, not staged
  git -C "$FX" rm -q pkg/f_test.go                        # deleted and staged
  sut "$FX" scan; want_rc 0
  judged pkg/e_test.go "+0 -1 DELETED" || fail "unstaged delete: $(grep 'e_test' "$OUT" | head -1)"
  judged pkg/f_test.go "+0 -2 DELETED" || fail "staged delete: $(grep 'f_test' "$OUT" | head -1)"
  lacks "$OUT" "LINES-REMOVED" "a deleted file is DELETED, not LINES-REMOVED"
}
r_scan_renamed_test_listed_twice() {
  new_fx rn; wf "$FX" pkg/a.go 'package a // changed\n'
  git -C "$FX" mv pkg/c_test.go pkg/c2_test.go
  sut "$FX" scan; want_rc 0
  judged pkg/c2_test.go "+3 -0" || fail "the new name is a judging file with all its lines added: $(grep 'c2_test' "$OUT" | head -1)"
  judged pkg/c_test.go "+0 -3 DELETED" || fail "the old name is a deleted judging file (no rename detection: a rename must not hide its old half)"
}
r_scan_binary_judge() {
  new_fx bj; wf "$FX" pkg/a.go 'package a // changed\n'
  printf '\000\001\003' > "$FX/pkg/bin_test.dat"            # tracked binary, modified
  printf '\000zz' > "$FX/pkg/new_test.dat"                  # untracked binary
  sut "$FX" scan; want_rc 0
  judged pkg/bin_test.dat "+- --" || fail "tracked binary signals: $(grep 'bin_test' "$OUT" | head -1)"
  judged pkg/new_test.dat "+- --" || fail "untracked binary signals: $(grep 'new_test.dat' "$OUT" | head -1)"
  lacks "$OUT" "LINES-REMOVED" "a binary numstat '-' is no removed-lines signal"
}
r_scan_ignored_file_not_scanned() {
  new_fx ig; wf "$FX" pkg/a.go 'package a // changed\n'; wf "$FX" pkg/hidden_test.ignored 'x\n'
  sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "an ignored file is not part of any commit"
}
r_scan_empty_new_test_still_judge() {
  new_fx et; wf "$FX" pkg/a.go 'package a // changed\n'; : > "$FX/pkg/empty_test.go"
  sut "$FX" scan; want_rc 0; flag_up_out || fail "an empty new test file next to a code change must still flag"
  judged pkg/empty_test.go "+0 -0" || fail "signals of an empty new file: $(grep 'empty_test' "$OUT" | head -1)"
}
r_scan_merge_base_not_main_tip() {
  new_fx mb
  git -C "$FX" checkout -q main; wf "$FX" pkg/main_test.go 'm\n'; wf "$FX" pkg/main_code.go 'm\n'
  git -C "$FX" add pkg/main_test.go pkg/main_code.go; gitc "$FX" "main moved on"
  git -C "$FX" checkout -q feat/x; wf "$FX" pkg/a.go 'package a // changed\n'
  sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "work that main added after the fork is not this branch's"
  # positive control: a test of the branch itself flags
  wf "$FX" pkg/own_test.go 'o\n'
  sut "$FX" scan; want_rc 0; flag_up_out || fail "control: the branch's own test must flag"
  lacks "$OUT" "main_test.go" "main's later test"
}
r_scan_from_subdirectory() {
  new_fx sub; code_and_test
  sut "$FX/pkg" scan; want_rc 0; flag_up_out || fail "a scan started in a subfolder must see the whole repository"
  judged pkg/new_test.go "+1 -0" || fail "path relative to the repository root: $(grep 'judging file' "$OUT" | head -1)"
}
r_scan_base_option() {
  new_fx bo
  git -C "$FX" checkout -q -b dev main; wf "$FX" pkg/a.go 'package a // dev\n'; git -C "$FX" add pkg/a.go; gitc "$FX" "code on the dev line"
  git -C "$FX" checkout -q -b feat/y; wf "$FX" pkg/y_test.go 'y\n'
  sut "$FX" scan --base dev; want_rc 0; has "$OUT" "no success-criterion flag" "against dev only a test is new"
  sut "$FX" scan --base main; want_rc 0; flag_up_out || fail "against main the code commit + the test flag"
  sut "$FX" scan; want_rc 0; flag_up_out || fail "default base is main"
}
r_scan_bad_base_is_3() {
  new_fx bb; code_and_test
  sut "$FX" scan --base nosuchref; want_rc 3; has "$ERR" "is not a commit here"
  sut "$FX" scan --base ""; want_rc 3
  # an unrelated history has no merge base
  git -C "$FX" branch -q other "$(git -C "$FX" commit-tree "$(git -C "$FX" hash-object -t tree /dev/null)" -m orphan)" || setup_fail "orphan commit"
  sut "$FX" scan --base other; want_rc 3; has "$ERR" "no merge base"
}
r_scan_arguments() {
  new_fx ar; code_and_test
  sut "$FX" scan --base; want_rc 1; has "$ERR" "--base needs a ref"
  sut "$FX" scan --goal; want_rc 1; has "$ERR" "--goal needs a file"
  sut "$FX" scan --bogus; want_rc 1; has "$ERR" "usage:"
  sut "$FX" frobnicate; want_rc 1; has "$ERR" "usage:"
  sut "$FX" scan; want_rc 0; flag_up_out || fail "control: a plain scan of the same tree flags"
}
r_scan_section_only() {
  new_fx so; code_and_test
  sut "$FX" scan --section; want_rc 0
  has "$OUT" "## Success-criterion check"; has "$OUT" "- pkg/new_test.go  (+1 -0)"
  lacks "$OUT" "SUCCESS-CRITERION FLAG" "--section prints only the section"; lacks "$OUT" "Append this section"
  # flag down: --section prints nothing at all (so `>> summary.md` appends nothing)
  new_fx so2; wf "$FX" docs/n.md 'y\n'
  sut "$FX" scan --section; want_rc 0; eq "$(wc -c < "$OUT" | tr -d ' ')" 0 "flag down + --section: bytes printed"
}
r_scan_no_repo_is_3() {
  mkdir -p "$T/norepo"
  sut "$T/norepo" scan; want_rc 3; has "$ERR" "not inside a git work tree"
  XE=(CTW_ROOT="$T/norepo"); sut "$T/norepo" scan; want_rc 3
  XE=(CTW_ROOT="$T/does-not-exist"); sut "$T/norepo" scan; want_rc 3
}
r_scan_no_main_branch() {
  new_fx nm; git -C "$FX" branch -q -m main trunk; code_and_test
  sut "$FX" scan; want_rc 3; has "$ERR" "base 'main' is not a commit here"
  sut "$FX" scan --base trunk; want_rc 0; flag_up_out || fail "control: --base trunk scans the same tree"
}
r_scan_ctw_root_beats_cwd() {
  new_fx r1; code_and_test; local one="$FX"
  new_fx r2                      # no changes
  XE=(CTW_ROOT="$one"); sut "$FX" scan; want_rc 0; flag_up_out || fail "CTW_ROOT (the changed repo) must win over the cwd (a clean repo)"
  XE=(); sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "control: the clean repo alone"
}
r_scan_git_env_ignored() {
  new_fx decoy                    # a clean repo the git variables point at
  local dec="$FX"; new_fx ge2; code_and_test
  XE=(GIT_DIR="$dec/.git" GIT_WORK_TREE="$dec" GIT_INDEX_FILE="$T/no/such/index"); sut "$FX" scan
  want_rc 0; flag_up_out || fail "GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE set (a git hook) must not redirect the scan: $(head -c 200 "$ERR")"
}
r_scan_on_main_itself_and_detached() {
  new_fx md; git -C "$FX" checkout -q main
  sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "on main itself nothing differs"
  git -C "$FX" checkout -q feat/x; code_and_test; git -C "$FX" checkout -q --detach 2>/dev/null
  sut "$FX" scan; want_rc 0; flag_up_out || fail "a detached HEAD scans like a branch"
}

# ══ 3. signals and the skip counter ═══════════════════════════════════════════════════════════════════════════════════
r_sig_counts_and_flags() {
  new_fx sg; wf "$FX" pkg/a.go 'package a // changed\n'
  wf "$FX" pkg/a_test.go 'a\nb\nc1\nc2\nc3\n'              # +3 -0 (line b kept)
  wf "$FX" pkg/c_test.go '1\nx\ny\n3\n'                    # line 2 replaced by two: +2 -1
  wf "$FX" pkg/d_test.go 'keep\n'                          # the skip line REMOVED: -1, not a skip added
  wf "$FX" pkg/f_test.go 'p t.Skip("n")\nq\n'              # one line rewritten with a skip: +1 -1
  wf "$FX" pkg/g_test.go 'one\ntwo\nthree\nfour\n'         # new untracked file: +4 -0
  sut "$FX" scan; want_rc 0
  judged pkg/a_test.go "+3 -0" || fail "append: $(grep 'a_test' "$OUT" | head -1)"
  judged pkg/c_test.go "+2 -1 LINES-REMOVED" || fail "replace: $(grep 'c_test' "$OUT" | head -1)"
  judged pkg/d_test.go "+0 -1 LINES-REMOVED" || fail "a removed skip marker is not a skip ADDED: $(grep 'd_test' "$OUT" | head -1)"
  judged pkg/f_test.go "+1 -1 LINES-REMOVED SKIP-MARKERS-ADDED:1" || fail "rewrite with skip: $(grep 'f_test' "$OUT" | head -1)"
  judged pkg/g_test.go "+4 -0" || fail "new file: $(grep 'g_test' "$OUT" | head -1)"
}
# one new test file per marker, each with ITS OWN count in the same scan: a rotted alternative shows as the one file
r_sig_skip_marker_alternatives() {
  new_fx sm; wf "$FX" pkg/a.go 'package a // changed\n'
  local i=0 m mf="$T/o/markers.txt"
  cat > "$mf" <<'EOF_M'
	t.Skip("later")
	t.Skipf("later %d", 1)
	throw XCTSkip("later")
@Ignore
@Disabled("flaky")
[Fact(Skip = "later")]
[Fact(Skip="later")]
	it.skip("later", fn)
	skip(reason)
xit("later", fn)
@pytest.mark.skip
[Ignore]
	SKIP_SLOW_TESTS=1 make
EOF_M
  while IFS= read -r m; do
    i=$((i + 1)); mkdir -p "$FX/mk"; printf 'ok\n%s\n' "$m" > "$FX/mk/m${i}_test.txt"
  done < "$mf"
  eq "$i" 13 "markers in the list"
  sut "$FX" scan; want_rc 0
  i=0
  while IFS= read -r m; do
    i=$((i + 1))
    judged "mk/m${i}_test.txt" "+2 -0 SKIP-MARKERS-ADDED:1" || fail "marker not counted: $m  (got: $(grep "mk/m${i}_test" "$OUT" | head -1))"
  done < "$mf"
}
r_sig_skip_count_is_lines_not_matches() {
  new_fx sl; wf "$FX" pkg/a.go 'package a // changed\n'
  wf "$FX" pkg/two_test.go 'a\n\tt.Skip("1")\n\tt.Skip("2")\nb\n'            # two lines
  wf "$FX" pkg/oneline_test.go 'a\n\tt.Skip("x"); xit("y"); @Ignore\n'         # three markers on ONE line
  wf "$FX" pkg/none_test.go 'a\n\tdoskip(x)\n\tskipper(x)\n\tt.Run("skipping = false")\n\tSkipped := 1\n'
  sut "$FX" scan; want_rc 0
  judged pkg/two_test.go "+4 -0 SKIP-MARKERS-ADDED:2" || fail "two skip lines: $(grep 'two_test' "$OUT" | head -1)"
  judged pkg/oneline_test.go "+2 -0 SKIP-MARKERS-ADDED:1" || fail "three markers on one line count as one line: $(grep 'oneline_test' "$OUT" | head -1)"
  judged pkg/none_test.go "+5 -0" || fail "near misses (doskip, skipper, 'skipping =', Skipped) are no markers: $(grep 'none_test' "$OUT" | head -1)"
}
r_sig_skip_beside_an_old_skip() {
  new_fx sv; wf "$FX" pkg/a.go 'package a // changed\n'
  wf "$FX" pkg/d_test.go 'keep\nold t.Skip("old")\nnew t.Skip("new")\n'     # the old skip stays; one more is added
  sut "$FX" scan; want_rc 0
  judged pkg/d_test.go "+1 -0 SKIP-MARKERS-ADDED:1" || fail "an old skip next to a new one: only the new counts: $(grep 'd_test' "$OUT" | head -1)"
}
r_sig_skip_in_commits_mode_and_staged() {
  new_fx sc2; wf "$FX" pkg/a.go 'package a // changed\n'; wf "$FX" pkg/s_test.go 'a\n\tt.Skip("later")\n'
  git -C "$FX" add pkg/a.go pkg/s_test.go
  sut "$FX" scan; want_rc 0; judged pkg/s_test.go "+2 -0 SKIP-MARKERS-ADDED:1" || fail "staged new file: $(grep 's_test' "$OUT" | head -1)"
  gitc "$FX" work; mkstate; XE=(CTW_ROOT="$FX" CTW_BRANCH=feat/x); sut "$FX" verify
  has "$OUT" "pkg/s_test.go  (+2 -0 SKIP-MARKERS-ADDED:1)" "commits mode shows the skip too"
}
r_sig_exit_is_not_a_skip() {
  new_fx xe; wf "$FX" pkg/a.go 'package a // changed\n'; wf "$FX" tests/run_test.py 'import sys\nsys.exit(1)\n'
  sut "$FX" scan; want_rc 0
  judged tests/run_test.py "+2 -0" || fail "sys.exit(1) is no skip marker: $(grep 'run_test.py' "$OUT" | head -1)"
  # positive control: a bare xit( (a skipped Jasmine / Mocha test) at the start of a line, after a space and after a tab IS one
  wf "$FX" tests/xit_test.js 'xit("a", fn)\n x\n'; wf "$FX" tests/xit2_test.js '\txit("b", fn)\n'; wf "$FX" tests/exit_test.js 'exit(1)\nprocess.exit(2)\n'
  sut "$FX" scan; want_rc 0
  judged tests/xit_test.js "+2 -0 SKIP-MARKERS-ADDED:1" || fail "xit( at the start of a line: $(grep 'xit_test' "$OUT" | head -1)"
  judged tests/xit2_test.js "+1 -0 SKIP-MARKERS-ADDED:1" || fail "xit( after a tab: $(grep 'xit2_test' "$OUT" | head -1)"
  judged tests/exit_test.js "+2 -0" || fail "exit( and process.exit( are no marker: $(grep 'exit_test' "$OUT" | head -1)"
}
r_sig_plus_plus_line_keeps_its_skip() {
  new_fx pp; wf "$FX" pkg/a.go 'package a // changed\n'; wf "$FX" pkg/b_test.go 'a\n++n; t.Skip("later")\n'
  sut "$FX" scan; want_rc 0
  judged pkg/b_test.go "+2 -0 SKIP-MARKERS-ADDED:1" || fail "an added line that itself starts with '++' (diff line '+++...') still holds a skip: $(grep 'b_test' "$OUT" | head -1)"
}

# ══ 4. the flag rule and the goal ═════════════════════════════════════════════════════════════════════════════════════
r_goal_replaced_flags_alone() {
  new_fx gr; ss "$FX" init --goal "$GOAL1" --session s
  sut "$FX" scan; want_rc 0; has "$OUT" "no success-criterion flag" "first goal only: no GC line"
  wf "$FX" docs/n.md 'y\n'                                  # only a doc changes
  ss "$FX" init --goal "$GOAL2" --replace-goal --session s
  sut "$FX" scan; want_rc 0; flag_up_out || fail "a replaced goal flags with no code and no judge"
  has "$OUT" "goal: the session's state record shows the goal REPLACED"
  has "$OUT" "- goal: the session's state record shows the goal REPLACED" "section lists the goal"
  eq "$(code_count)" 0 "code files"
}
r_goal_run_goal_file_compare() {
  new_fx gf; ss "$FX" init --goal "$GOAL1" --session s
  sut "$FX" scan --goal "$GOAL2"; want_rc 0; flag_up_out || fail "a goal file that differs from the record's goal must flag"
  has "$OUT" "differs from the goal the session's state record started with"
  sut "$FX" scan --goal "$GOAL1"; want_rc 0; has "$OUT" "no success-criterion flag" "the same goal file"
  # blanks, tabs and doubled spaces are not a change of goal
  printf '\n%s\n\n%s\n%s\n' 'GOAL:  make a.txt say hello' "PROOF:${TAB}the test passes" 'LIMIT: only   a.txt' > "$T/goal1-ws.md"
  sut "$FX" scan --goal "$T/goal1-ws.md"; want_rc 0; has "$OUT" "no success-criterion flag" "white-space-only reformatting"
  # the same lines in another order ARE a different goal
  printf '%s\n' 'PROOF: the test passes' 'GOAL: make a.txt say hello' 'LIMIT: only a.txt' > "$T/goal1-order.md"
  sut "$FX" scan --goal "$T/goal1-order.md"; want_rc 0; flag_up_out || fail "reordered goal lines must flag"
  # one word changed
  sed 's/hello/hullo/' "$GOAL1" > "$T/goal1-word.md"
  sut "$FX" scan --goal "$T/goal1-word.md"; want_rc 0; flag_up_out || fail "one changed word must flag"
}
r_goal_no_record_or_empty_file() {
  new_fx gn
  sut "$FX" scan --goal "$GOAL2"; want_rc 0; has "$OUT" "no success-criterion flag" "no state record: nothing to compare with"
  ss "$FX" init --goal "$GOAL1" --session s
  : > "$T/empty-goal.md"
  sut "$FX" scan --goal "$T/empty-goal.md"; want_rc 0; has "$OUT" "no success-criterion flag" "an empty goal file is not compared"
  sut "$FX" scan --goal "$GOAL2"; want_rc 0; flag_up_out || fail "control: with a record, another goal file flags"
}
r_goal_with_code_and_judge_lists_all() {
  new_fx ga; code_and_test; ss "$FX" init --goal "$GOAL1" --session s; ss "$FX" init --goal "$GOAL2" --replace-goal --session s
  sut "$FX" scan; want_rc 0
  judged pkg/new_test.go "+1 -0" || fail "judging file listed"; has "$OUT" "  goal: the session's state record shows the goal REPLACED"
  has "$OUT" "- pkg/new_test.go  (+1 -0)"; has "$OUT" "- goal: "
}
r_goal_file_must_be_a_readable_file() {
  new_fx gm; code_and_test; ss "$FX" init --goal "$GOAL1" --session s
  sut "$FX" scan --goal "$T/no-such-goal-file.md"; want_rc 1; has "$ERR" "--goal file not found or not readable"
  sut "$FX" scan --goal "$T"; want_rc 1; has "$ERR" "--goal file not found or not readable" "a folder is no goal file"
  printf 'GOAL: x\n' > "$T/unreadable-goal.md"; chmod 000 "$T/unreadable-goal.md"
  [ ! -r "$T/unreadable-goal.md" ] || { chmod 600 "$T/unreadable-goal.md"; setup_fail "cannot make an unreadable file (running as root?)"; }
  sut "$FX" scan --goal "$T/unreadable-goal.md"; local rc_u="$RC" err_u; err_u="$(head -c 160 "$ERR")"; chmod 600 "$T/unreadable-goal.md"
  [ "$rc_u" = 1 ] || fail "an unreadable --goal file: exit $rc_u, wanted 1 ($err_u)"
  case "$err_u" in *"not found or not readable"*) ;; *) fail "an unreadable --goal file: no message ($err_u)" ;; esac
  # an existing EMPTY goal file is a legitimate "no goal text to compare": accepted, compares nothing, adds no goal line
  : > "$T/empty-goal2.md"
  sut "$FX" scan --goal "$T/empty-goal2.md"; want_rc 0; flag_up_out || fail "control: the code + test of the tree still flag"
  lacks "$OUT" "  goal: " "an empty goal file adds no goal line"
  # positive control: the same call with a real, equal goal file
  sut "$FX" scan --goal "$GOAL1"; want_rc 0; lacks "$OUT" "  goal: "
}

# ══ 5. answer ═════════════════════════════════════════════════════════════════════════════════════════════════════════
LONG="Written by the tester agent (model A), no floor lowered"
r_ans_refusals() {
  new_fx ae; code_and_test; mkstate; hook_env
  sut "$FX" answer --text ""; want_rc 1; has "$ERR" "the answer is empty"
  sut "$FX" answer --text "   ${TAB}  ${NL}  "; want_rc 1; has "$ERR" "the answer is empty"
  sut "$FX" answer --text "short answer ok"; want_rc 0     # exactly 15 characters: the limit is "at least 15"
  rm -f "$SD/criterion-answer"
  sut "$FX" answer --text "short answer o"; want_rc 1; has "$ERR" "too short (under 15 characters)"
  sut "$FX" answer --text "a        b        c"; want_rc 1; has "$ERR" "too short"   # 17 raw characters, 5 after squeezing blanks
  sut "$FX" answer --text; want_rc 1; has "$ERR" "--text needs the answer"
  sut "$FX" answer; want_rc 1; has "$ERR" "the answer is empty"
  sut "$FX" answer --bogus x; want_rc 1; has "$ERR" "usage:"
  [ ! -e "$SD/criterion-answer" ] || fail "a refused answer must store nothing"
}
r_ans_stores_bound_to_judging_set() {
  new_fx as; code_and_test; mkstate; hook_env
  sut "$FX" answer --text "$LONG"; want_rc 0
  has "$OUT" "answer stored for 1 judging file(s)"; has "$OUT" "$SD/criterion-answer"
  local fp; fp="$(printf 'judge\tpkg/new_test.go\n' | sort | cksum | cut -d' ' -f1)"
  eq "$(cat "$SD/criterion-answer")" "v1${TAB}${fp}${TAB}${LONG}" "stored line (v1 TAB cksum-of-the-judging-set TAB text)"
}
r_ans_text_normalised_to_one_line() {
  new_fx an; code_and_test; mkstate; hook_env
  sut "$FX" answer --text "  line one${NL}line${TAB}two  ${NL}${NL}three   end of answer  "; want_rc 0
  eq "$(wc -l < "$SD/criterion-answer" | tr -d ' ')" 1 "lines in the answer file"
  eq "$(cut -f3- "$SD/criterion-answer")" "line one line two three end of answer" "text with newlines and tabs turned into single blanks"
  eq "$(awk -F'\t' '{ print NF }' "$SD/criterion-answer")" 3 "tab-separated fields (a tab in the text must not add one)"
}
r_ans_flag_down_stores_nothing() {
  new_fx af; wf "$FX" docs/n.md 'y\n'; mkstate; hook_env
  sut "$FX" answer --text "$LONG"; want_rc 0; has "$OUT" "no answer is needed (nothing stored)"
  [ ! -e "$SD/criterion-answer" ] || fail "flag down: an answer file was written"
  # positive control: the same call with a flag up stores
  code_and_test; sut "$FX" answer --text "$LONG"; want_rc 0; [ -f "$SD/criterion-answer" ] || fail "control: flag up must store"
}
r_ans_default_state_folder_and_run_base() {
  new_fx ad; code_and_test
  sut "$FX" answer --text "$LONG"; want_rc 0                  # no CTW_STATE, no base file: <git-dir>/check-the-work, base main
  [ -f "$FX/.git/check-the-work/criterion-answer" ] || fail "default answer path is <git-dir>/check-the-work/criterion-answer"
  # the base 'run' used wins over main: a base that is HEAD leaves no change, so no flag, nothing stored
  new_fx ad2; code_and_test; git -C "$FX" add pkg/a.go pkg/new_test.go; gitc "$FX" work
  mkdir -p "$FX/.git/check-the-work"; git -C "$FX" rev-parse HEAD | tr -d '\n' > "$FX/.git/check-the-work/base"
  sut "$FX" answer --text "$LONG"; want_rc 0; has "$OUT" "no answer is needed" "base = HEAD"
  # --base REF beats the state folder's base file
  sut "$FX" answer --text "$LONG" --base main; want_rc 0; has "$OUT" "answer stored" "--base main sees the commit"
  sut "$FX" answer --text "$LONG" --base nosuchref; want_rc 3
}
r_ans_state_folder_from_ctw_state() {
  new_fx ac; code_and_test; SD="$T/elsewhere-state"; mkdir -p "$SD"; printf '%s' "$BASESHA" > "$SD/base"
  XE=(CTW_ROOT="$FX" CTW_STATE="$SD" CTW_BRANCH=feat/x)
  sut "$FX" answer --text "$LONG"; want_rc 0
  [ -f "$SD/criterion-answer" ] || fail "CTW_STATE is where the answer is stored"
  [ ! -e "$FX/.git/check-the-work/criterion-answer" ] || fail "the default folder must stay untouched when CTW_STATE is set"
  sut "$FX" judge; want_rc 0; has "$OUT" "row appended" "judge reads the answer from the same CTW_STATE"
}
r_ans_in_linked_worktree_uses_its_own_git_dir() {
  new_fx aw; git -C "$FX" worktree add -q -b feat/w "$T/fx/aw-wt" main || setup_fail "worktree"
  wf "$T/fx/aw-wt" pkg/a.go 'package a // w\n'; wf "$T/fx/aw-wt" pkg/new_test.go 'z\n'
  sut "$T/fx/aw-wt" answer --text "$LONG"; want_rc 0
  local gd; gd="$(git -C "$T/fx/aw-wt" rev-parse --absolute-git-dir)"
  [ -f "$gd/check-the-work/criterion-answer" ] || fail "answer must be stored in the worktree's own git folder ($gd)"
  [ ! -e "$FX/.git/check-the-work/criterion-answer" ] || fail "the main checkout's folder must stay untouched"
}

# ══ 6. judge ══════════════════════════════════════════════════════════════════════════════════════════════════════════
LOG_REL="docs/agents/criterion.jsonl"
pyj() { python3 -I - "$1" "$2" "$3" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1], encoding="utf-8").read().split("\n") if l.strip()]
r = json.loads(lines[int(sys.argv[2])])
print(eval(sys.argv[3]))
PY
}
judge_ready() { # judge_ready <name>: a flagged tree, the state folder, the answer given through the real command
  new_fx "$1"; code_and_test; mkstate; hook_env
  sut "$FX" answer --text "$LONG"; [ "$RC" = 0 ] || setup_fail "answer: $(head -c 200 "$ERR")"
}
r_judge_missing_or_bad_base_is_3() {
  new_fx jb; code_and_test; SD="$FX/.git/check-the-work"; mkdir -p "$SD"; XE=(CTW_ROOT="$FX" CTW_STATE="$SD")
  sut "$FX" judge; want_rc 3; has "$ERR" "no merge base"
  : > "$SD/base"; sut "$FX" judge; want_rc 3; has "$ERR" "no merge base" "an empty base file"
  printf '%s' "0123456789abcdef0123456789abcdef01234567" > "$SD/base"; sut "$FX" judge; want_rc 3; has "$ERR" "is not a commit here"
  printf '%s' "not a sha at all" > "$SD/base"; sut "$FX" judge; want_rc 3; has "$ERR" "is not a commit here"
  [ ! -e "$FX/$LOG_REL" ] || fail "nothing is logged when judge cannot run"
}
r_judge_flag_down_logs_nothing() {
  new_fx jd; wf "$FX" docs/n.md 'y\n'; mkstate; hook_env
  sut "$FX" judge; want_rc 0; has "$OUT" "no success-criterion flag"
  [ ! -e "$FX/$LOG_REL" ] || fail "flag down: a row was written"
}
r_judge_flag_up_without_answer_stops() {
  new_fx jn; code_and_test; mkstate; hook_env
  sut "$FX" judge; want_rc 1
  has "$OUT" "SUCCESS-CRITERION FLAG"; has "$ERR" "the judgement is NOT logged"; has "$ERR" "answer --text"
  lacks "$ERR" "another set of judging files" "no answer file exists yet"
  [ ! -e "$FX/$LOG_REL" ] || fail "a refused judge must log nothing"
}
r_judge_row_fields() {
  judge_ready jr
  sut "$FX" judge; want_rc 0; has "$OUT" "row appended to $FX/$LOG_REL"
  [ -f "$FX/$LOG_REL" ] || { fail "no log"; return; }
  eq "$(wc -l < "$FX/$LOG_REL" | tr -d ' ')" 1 "rows"
  eq "$(pyj "$FX/$LOG_REL" 0 "r['branch']")" "feat/x" "branch"
  eq "$(pyj "$FX/$LOG_REL" 0 "r['base']")" "$BASESHA" "base"
  eq "$(pyj "$FX/$LOG_REL" 0 "r['answer']")" "$LONG" "answer"
  eq "$(pyj "$FX/$LOG_REL" 0 "r['flag']['code']")" "['pkg/a.go']" "flag.code"
  eq "$(pyj "$FX/$LOG_REL" 0 "r['flag']['judging']")" "[{'path': 'pkg/new_test.go', 'signals': '+1 -0'}]" "flag.judging"
  eq "$(pyj "$FX/$LOG_REL" 0 "r['flag']['goal']")" "[]" "flag.goal"
  pyj "$FX/$LOG_REL" 0 "__import__('re').fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', r['date']) is not None" | grep -q '^True$' || fail "date is not a UTC timestamp: $(pyj "$FX/$LOG_REL" 0 "r['date']")"
}
# HARNESS_AGENT_DIR moves the log; the log and reviews.jsonl there are never part of the scan; a folder outside the repository is refused
r_judge_agent_dir() {
  local v i=0
  judge_ready jad; XE=("${XE[@]}" HARNESS_AGENT_DIR=ops/agents/)
  sut "$FX" judge; want_rc 0; has "$OUT" "row appended to $FX/ops/agents/criterion.jsonl"
  [ -f "$FX/ops/agents/criterion.jsonl" ] || fail "no log in the configured folder"
  [ ! -e "$FX/$LOG_REL" ] || fail "the default folder must stay unused"
  wf "$FX" ops/agents/reviews.jsonl 'x\n'
  sut "$FX" judge; want_rc 0; has "$OUT" "row already recorded" "the log and reviews.jsonl in the folder do not change the flag"
  XE=("${XE[@]}"); sut "$FX" scan; want_rc 0; lacks "$OUT" "ops/agents" "the folder's files are not scanned"
  for v in "../out" "/abs/dir" "a/../../b" "docs//agents" "docs/./agents" "."; do
    i=$((i + 1)); new_fx "jadh-$i"; code_and_test; XE=(HARNESS_AGENT_DIR="$v"); sut "$FX" scan; want_rc 3; has "$ERR" "HARNESS_AGENT_DIR must be a relative folder inside the repository" "[$v]"
  done
}
r_judge_idempotent_and_new_row_on_change() {
  judge_ready ji
  sut "$FX" judge; want_rc 0; sut "$FX" judge; want_rc 0; has "$OUT" "row already recorded for this branch (unchanged flag and answer)"
  eq "$(wc -l < "$FX/$LOG_REL" | tr -d ' ')" 1 "rows after a second identical judge"
  wf "$FX" pkg/more.go 'package m\n'                       # another CODE file changes the flag's code list
  sut "$FX" judge; want_rc 0; has "$OUT" "row appended"
  eq "$(wc -l < "$FX/$LOG_REL" | tr -d ' ')" 2 "rows after the flag changed"
  sut "$FX" answer --text "A different answer given later on"; sut "$FX" judge; want_rc 0
  eq "$(wc -l < "$FX/$LOG_REL" | tr -d ' ')" 3 "rows after the answer changed"
}
r_judge_stale_answer_when_judging_set_changes() {
  judge_ready js
  sut "$FX" judge; want_rc 0
  wf "$FX" pkg/second_test.go 's\n'                         # a judging file added after the answer
  sut "$FX" judge; want_rc 1; has "$ERR" "an answer exists but was given for another set of judging files"
  rm "$FX/pkg/second_test.go"                                # removed again: the answer fits again
  sut "$FX" judge; want_rc 0
  rm "$FX/pkg/new_test.go"; wf "$FX" pkg/third_test.go 't\n'  # a judging file swapped for another: the set differs
  sut "$FX" judge; want_rc 1; has "$ERR" "another set of judging files"
  # a CODE file added later does not make the answer stale (the claim is about the judges)
  rm "$FX/pkg/third_test.go"; wf "$FX" pkg/new_test.go 'z\n'; wf "$FX" pkg/more.go 'package m\n'
  sut "$FX" judge; want_rc 0
}
r_judge_goal_change_makes_answer_stale() {
  new_fx jgs; code_and_test; mkstate; hook_env; ss "$FX" init --goal "$GOAL1" --session s
  sut "$FX" answer --text "$LONG"; want_rc 0; sut "$FX" judge; want_rc 0
  ss "$FX" init --goal "$GOAL2" --replace-goal --session s                     # the goal is replaced AFTER the answer
  sut "$FX" judge; want_rc 1; has "$ERR" "another set of judging files" "an answer given before the goal changed does not cover the new flag"
  sut "$FX" answer --text "$LONG and the goal change"; want_rc 0; sut "$FX" judge; want_rc 0
}
r_judge_answer_file_forms() {
  judge_ready jf
  local fp; fp="$(printf 'judge\tpkg/new_test.go\n' | sort | cksum | cut -d' ' -f1)"
  printf 'v2\t%s\t%s\n' "$fp" "$LONG" > "$SD/criterion-answer";   sut "$FX" judge; want_rc 1; has "$ERR" "NOT logged" "version v2"
  printf 'v1\t%s\t\n' "$fp" > "$SD/criterion-answer";             sut "$FX" judge; want_rc 1; has "$ERR" "NOT logged" "empty text"
  printf 'v1\t%s\t%s\n' "0000" "$LONG" > "$SD/criterion-answer"; sut "$FX" judge; want_rc 1; has "$ERR" "another set" "wrong fingerprint"
  : > "$SD/criterion-answer";                                      sut "$FX" judge; want_rc 1; has "$ERR" "NOT logged" "empty file"
  printf 'v1\t%s\t%s\n' "$fp" "$LONG" > "$SD/criterion-answer";   sut "$FX" judge; want_rc 0              # positive control
}
r_judge_branch_fallbacks() {
  judge_ready jbr
  XE=(CTW_ROOT="$FX" CTW_STATE="$SD"); sut "$FX" judge; want_rc 0                       # no CTW_BRANCH: the state file 'branch'
  eq "$(pyj "$FX/$LOG_REL" -1 "r['branch']")" "feat/x" "branch from <state>/branch"
  rm "$FX/$LOG_REL"; printf '%s' "from-state-file" > "$SD/branch"
  sut "$FX" judge; eq "$(pyj "$FX/$LOG_REL" -1 "r['branch']")" "from-state-file" "state branch file is read"
  rm "$FX/$LOG_REL"; XE=(CTW_ROOT="$FX" CTW_STATE="$SD" CTW_BRANCH=from-env); sut "$FX" judge
  eq "$(pyj "$FX/$LOG_REL" -1 "r['branch']")" "from-env" "CTW_BRANCH beats the state file"
  rm "$FX/$LOG_REL" "$SD/branch"; XE=(CTW_ROOT="$FX" CTW_STATE="$SD"); sut "$FX" judge
  eq "$(pyj "$FX/$LOG_REL" -1 "r['branch']")" "feat/x" "no env, no file: the checked-out branch"
  rm "$FX/$LOG_REL"; git -C "$FX" checkout -q --detach 2>/dev/null; sut "$FX" judge
  eq "$(pyj "$FX/$LOG_REL" -1 "r['branch']")" "detached" "detached HEAD"
}
r_judge_log_edge_cases() {
  judge_ready jl
  mkdir -p "$FX/docs/agents"
  printf 'not json at all\n{"branch": "other", "answer": "x"}' > "$FX/$LOG_REL"   # a junk line, then a row WITHOUT a trailing newline
  sut "$FX" judge; want_rc 0
  eq "$(wc -l < "$FX/$LOG_REL" | tr -d ' ')" 3 "lines (old row, junk, new row)"
  eq "$(pyj "$FX/$LOG_REL" 1 "r['branch']")" "other" "the old row survives"
  grep -qx 'not json at all' "$FX/$LOG_REL" || fail "a junk line in the log was dropped"
  eq "$(pyj "$FX/$LOG_REL" -1 "r['branch']")" "feat/x" "new row is on its own line"
  # a row of ANOTHER branch with identical fields does not make this branch's row 'already recorded'
  new_fx jl2; code_and_test; mkstate; hook_env; sut "$FX" answer --text "$LONG"
  mkdir -p "$FX/docs/agents"
  printf '{"branch": "feat/other", "base": "%s", "flag": {"code": ["pkg/a.go"], "judging": [{"path": "pkg/new_test.go", "signals": "+1 -0"}], "goal": []}, "answer": "%s"}\n' "$BASESHA" "$LONG" > "$FX/$LOG_REL"
  sut "$FX" judge; want_rc 0; has "$OUT" "row appended"; eq "$(wc -l < "$FX/$LOG_REL" | tr -d ' ')" 2 "rows"
}
r_judge_answer_json_roundtrip() {
  new_fx jq; code_and_test; mkstate; hook_env
  # shellcheck disable=SC2016  # the text holds $( and backticks on purpose: they must stay literal
  local txt='Written by "ModelB" \ the lead; é ü 日本 — no <criterion> weakened & $(x) `y`'
  sut "$FX" answer --text "$txt"; want_rc 0; sut "$FX" judge; want_rc 0
  eq "$(pyj "$FX/$LOG_REL" 0 "r['answer']")" "$txt" "answer with quotes, a backslash, non-ASCII and shell characters"
}
r_judge_goal_file_of_the_run() {
  new_fx jg; wf "$FX" docs/n.md 'y\n'; mkstate; hook_env; ss "$FX" init --goal "$GOAL1" --session s
  cp "$GOAL2" "$SD/goal.md"                                  # the goal 'run' got differs from the record's
  sut "$FX" judge; want_rc 1; has "$OUT" "goal: the goal file given to 'run' differs"; has "$ERR" "NOT logged"
  cp "$GOAL1" "$SD/goal.md"; sut "$FX" judge; want_rc 0; has "$OUT" "no success-criterion flag" "control: the same goal"
}
r_judge_answer_satisfies_judge_when_run_goal_differs() {
  # the lead's own design case: `run --goal <another file>` -> the goal flag is up at judge time; the sub-session must be
  # able to answer it. answer does not read $CTW_STATE/goal.md, so it finds no flag and stores nothing; judge then refuses
  # for ever (a dead end). Also with code + judge: the stored fingerprint lacks the goal line judge adds.
  new_fx jg2; wf "$FX" docs/n.md 'y\n'; mkstate; hook_env; ss "$FX" init --goal "$GOAL1" --session s; cp "$GOAL2" "$SD/goal.md"
  sut "$FX" answer --text "$LONG"; local said; said="$(head -c 120 "$OUT" | tr '\n' ' ')"
  sut "$FX" judge
  [ "$RC" = 0 ] || fail "judge still refuses (rc $RC) after answer; answer said: '$said' (a dead end for the sub-session)"
  new_fx jg3; code_and_test; mkstate; hook_env; ss "$FX" init --goal "$GOAL1" --session s; cp "$GOAL2" "$SD/goal.md"
  sut "$FX" answer --text "$LONG"; sut "$FX" judge
  [ "$RC" = 0 ] || fail "code + judge + a different run goal: judge refuses (rc $RC) after a stored answer: $(head -c 200 "$ERR" | tr '\n' ' ')"
}
r_judge_goal_replaced_in_record_is_answerable() {
  new_fx jgc; wf "$FX" docs/n.md 'y\n'; mkstate; hook_env
  ss "$FX" init --goal "$GOAL1" --session s; ss "$FX" init --goal "$GOAL2" --replace-goal --session s
  sut "$FX" judge; want_rc 1; has "$OUT" "goal REPLACED"
  sut "$FX" answer --text "$LONG"; want_rc 0; has "$OUT" "answer stored"
  sut "$FX" judge; want_rc 0
  eq "$(pyj "$FX/$LOG_REL" 0 "r['flag']['judging']")" "[]" "no judging file"
  pyj "$FX/$LOG_REL" 0 "r['flag']['goal']" | grep -qF "REPLACED" || fail "the row lists the goal flag: $(pyj "$FX/$LOG_REL" 0 "r['flag']['goal']")"
}
r_judge_stage_from_environment() {
  judge_ready jst
  XE=(CTW_ROOT="$FX" CTW_STATE="$SD" CTW_STAGE=judge); sut "$FX"; want_rc 0; has "$OUT" "row appended" "CTW_STAGE=judge, no argument"
  XE=(CTW_ROOT="$FX" CTW_STATE="$SD" CTW_STAGE=verify CTW_BRANCH=feat/x); sut "$FX"; has "$OUT" "feat/x" "CTW_STAGE=verify, no argument runs verify"
  XE=(CTW_STAGE=bogus); sut "$FX"; want_rc 1; has "$ERR" "usage:"
  # the argument beats the environment
  XE=(CTW_ROOT="$FX" CTW_STATE="$SD" CTW_STAGE=bogus); sut "$FX" judge; want_rc 0
}
r_judge_without_python3() {
  local b="$T/nopy-bin" t; mkdir -p "$b"
  for t in git awk sed grep tr cut sort cksum head tail cat mkdir mktemp rm mv dirname basename date find wc cp; do
    ln -sf "$(command -v "$t")" "$b/$t" 2>/dev/null || setup_fail "cannot link $t"
  done
  PATH="$b" command -v python3 >/dev/null 2>&1 && setup_fail "python3 is still on the narrowed PATH"
  # flag down needs no python: control that the narrowed PATH itself runs the script
  new_fx jnp2; wf "$FX" docs/n.md 'y\n'; mkstate; XE=(PATH="$b" CTW_ROOT="$FX" CTW_STATE="$SD" CTW_BRANCH=feat/x)
  sut "$FX" judge; want_rc 0; has "$OUT" "no success-criterion flag" "control: narrowed PATH, flag down"
  judge_ready jnp3; XE=(PATH="$b" CTW_ROOT="$FX" CTW_STATE="$SD" CTW_BRANCH=feat/x)
  sut "$FX" judge; want_rc 3; has "$ERR" "could not write the criterion row"
  [ ! -e "$FX/$LOG_REL" ] || fail "no row without python3"
  sut "$FX" verify; want_rc 3; has "$ERR" "python3 is missing"
}

# ══ 7. verify ═════════════════════════════════════════════════════════════════════════════════════════════════════════
VM=""; VW=""
vx_new() { # vx_new <name>: VM = main checkout (on main), VW = linked worktree on feat/x, SD = VW's state folder
  local root="$T/fx/$1"; mkdir -p "$root"; VM="$root/main"; VW="$root/wt"
  cp -R "$TPL" "$VM" || setup_fail "cp"; git -C "$VM" worktree add -q -b feat/x "$VW" main || setup_fail "worktree add"
  BASESHA="$(git -C "$VM" rev-parse main)"; FX="$VW"; mkstate
}
vx_commit() { git -C "$VW" add "$@" || setup_fail "add"; gitc "$VW" work; }
vx_flag_work() { wf "$VW" pkg/b.go 'package b\n'; wf "$VW" pkg/b_test.go 'b\n'; vx_commit pkg/b.go pkg/b_test.go; }
vx_say() { # the sub-session answers and judges through the real commands (worktree state)
  XE=(CTW_ROOT="$VW" CTW_STATE="$SD" CTW_BRANCH=feat/x)
  sut "$VW" answer --text "$1"; [ "$RC" = 0 ] || setup_fail "vx_say answer: $(head -c 200 "$ERR")"
  sut "$VW" judge; [ "$RC" = 0 ] || setup_fail "vx_say judge: $(head -c 200 "$ERR")"
}
vx_commit_log() { vx_commit "$LOG_REL"; }
vx_verify() { XE=(CTW_ROOT="$VM" CTW_BRANCH=feat/x "$@"); sut "$VM" verify; }
r_verify_no_flag() {
  vx_new vn; wf "$VW" docs/n.md 'y\n'; vx_commit docs/n.md
  vx_verify; want_rc 0; has "$OUT" "no success-criterion flag on feat/x"
}
r_verify_flag_with_row_passes() {
  vx_new vp; vx_flag_work; vx_say "$LONG"; vx_commit_log
  vx_verify; want_rc 0
  has "$OUT" "pkg/b_test.go  (+1 -0)" "the flag is shown"
  grep -qE "^  CRITERION answer of the sub-session \(20[0-9-]+T[0-9:]+Z\): " "$OUT" || fail "answer line missing: $(grep CRITERION "$OUT")"
  has "$OUT" "): $LONG" "the answer text"
  lacks "$OUT" "WARNING" "the row lists every judging file"; has "$OUT" "The lead rules"
  lacks "$OUT" "goal check NOT DONE" "the branch is checked out in a worktree"
}
r_verify_flag_without_row_fails() {
  vx_new vf; vx_flag_work
  vx_verify; want_rc 1; has "$ERR" "the success-criterion step was skipped"; has "$OUT" "SUCCESS-CRITERION FLAG"
}
r_verify_uses_commits_not_work_tree() {
  vx_new vc; wf "$VW" pkg/b.go 'package b\n'; wf "$VW" pkg/b_test.go 'b\n'     # uncommitted only
  vx_verify; want_rc 0; has "$OUT" "no success-criterion flag on feat/x" "uncommitted work is not on the branch"
  vx_commit pkg/b.go pkg/b_test.go
  vx_verify; want_rc 1; has "$ERR" "step was skipped" "control: once committed the flag is up"
}
r_verify_row_must_be_committed() {
  vx_new vr; vx_flag_work; vx_say "$LONG"                       # the row exists in the work tree, not in a commit
  vx_verify; want_rc 1; has "$ERR" "step was skipped" "an uncommitted row is no row"
  vx_commit_log; vx_verify; want_rc 0
}
r_verify_last_answered_row_wins() {
  vx_new vl; vx_flag_work; vx_say "First answer about who wrote the tests"
  wf "$VW" pkg/c.go 'package c\n'                                   # the flag's code list changes -> a second row
  vx_say "Second answer about who wrote the tests"; vx_commit_log
  eq "$(wc -l < "$VW/$LOG_REL" | tr -d ' ')" 2 "rows the branch added"
  vx_verify; want_rc 0; has "$OUT" "): Second answer about who wrote the tests" "the last row is used"; lacks "$OUT" "First answer" "the older row"
  # a LATER row with an empty (or blank) answer is no row: the last ANSWERED row counts
  printf '{"branch": "feat/x", "answer": "   "}\n' >> "$VW/$LOG_REL"; vx_commit "$LOG_REL"
  vx_verify; want_rc 0; has "$OUT" "Second answer" "blank-answer row ignored"
}
r_verify_blank_answer_row_alone_is_no_row() {
  vx_new vb; vx_flag_work; mkdir -p "$VW/docs/agents"; printf '{"branch": "feat/x", "answer": ""}\n{"branch": "feat/x"}\n{"branch": "feat/x", "answer": 5}\n' > "$VW/$LOG_REL"; vx_commit "$LOG_REL"
  vx_verify; want_rc 1; has "$ERR" "step was skipped"
}
r_verify_row_of_another_branch_ignored() {
  vx_new vo; vx_flag_work; mkdir -p "$VW/docs/agents"
  printf '{"branch": "feat/other", "answer": "%s", "flag": {"judging": [{"path": "pkg/b_test.go"}]}}\n' "$LONG" > "$VW/$LOG_REL"; vx_commit "$LOG_REL"
  vx_verify; want_rc 1; has "$ERR" "step was skipped"
  vx_verify; lacks "$OUT" "CRITERION answer" "the other branch's answer is not shown"
}
r_verify_row_already_in_base_does_not_count() {
  vx_new vi; mkdir -p "$VM/docs/agents"
  printf '{"branch": "feat/x", "answer": "%s", "flag": {"judging": []}}\n' "$LONG" > "$VM/$LOG_REL"; git -C "$VM" add "$LOG_REL"; gitc "$VM" "old row on main"
  git -C "$VW" merge -q main 2>&1 | head -1 >/dev/null; BASESHA="$(git -C "$VM" rev-parse main)"
  vx_flag_work; vx_verify; want_rc 1; has "$ERR" "step was skipped" "a row that is already in the base was not added by the branch"
}
r_verify_row_removed_again_is_no_row() {
  vx_new vm2; vx_flag_work; vx_say "$LONG"; vx_commit_log
  git -C "$VW" rm -q "$LOG_REL"; gitc "$VW" "drop the row"
  vx_verify; want_rc 1; has "$ERR" "step was skipped"
}
r_verify_judging_file_after_the_answer_warns() {
  vx_new vw; vx_flag_work; vx_say "$LONG"; vx_commit_log
  wf "$VW" pkg/late_test.go 'late\n'; vx_commit pkg/late_test.go            # a judging file committed after the answer
  vx_verify; want_rc 0; has "$OUT" "WARNING: judging files changed on the branch that the answer's row did not list"; has "$OUT" "pkg/late_test.go"
  lacks "$OUT" "WARNING: judging files changed on the branch that the answer's row did not list (changed after the answer?): pkg/b_test.go" "pkg/b_test.go was listed"
}
r_verify_goal_replaced() {
  vx_new vg; vx_flag_work; ss "$VW" init --goal "$GOAL1" --session s
  vx_say "$LONG"; vx_commit_log                                              # answer BEFORE the goal changed
  ss "$VW" init --goal "$GOAL2" --replace-goal --session s
  vx_verify; want_rc 0; has "$OUT" "goal: the session's state record shows the goal REPLACED"
  has "$OUT" "WARNING: the goal was replaced, and the answer's row did not list it"
  # answering AFTER the replacement lists the goal in the row: no warning
  vx_say "Answered after the goal was replaced, tests by the tester"; vx_commit_log
  vx_verify; want_rc 0; lacks "$OUT" "the goal was replaced, and the answer's row did not list it" "row lists the goal"
}
r_verify_goal_replaced_alone_needs_a_row() {
  vx_new vga; wf "$VW" docs/n.md 'y\n'; vx_commit docs/n.md; ss "$VW" init --goal "$GOAL1" --session s; ss "$VW" init --goal "$GOAL2" --replace-goal --session s
  vx_verify; want_rc 1; has "$ERR" "step was skipped"; has "$OUT" "goal REPLACED"
}
r_verify_branch_without_worktree() {
  vx_new vno; vx_flag_work; vx_say "$LONG"; vx_commit_log
  git -C "$VM" worktree remove --force "$VW" || setup_fail "worktree remove"
  vx_verify; want_rc 0; has "$OUT" "goal check NOT DONE — no worktree has 'feat/x' checked out"
  # positive control: the worktree back -> the line is gone
  git -C "$VM" worktree add -q "$VW" feat/x || setup_fail "worktree re-add"
  vx_verify; lacks "$OUT" "goal check NOT DONE" "control: with the worktree"
}
r_verify_ctw_base_override() {
  vx_new vbo
  wf "$VW" pkg/b.go 'package b\n'; vx_commit pkg/b.go                        # the code first ...
  git -C "$VM" branch -q dev feat/x                                           # ... dev = feat/x so far
  wf "$VW" pkg/b_test.go 'b\n'; vx_commit pkg/b_test.go                       # ... then the test
  vx_verify CTW_BASE=dev; want_rc 0; has "$OUT" "no success-criterion flag on feat/x" "against dev only the test is new"
  vx_verify; want_rc 1; has "$ERR" "step was skipped" "against main both are new"
  vx_verify CTW_BASE=nosuchbase; want_rc 3; has "$ERR" "no merge base"
}
r_verify_branch_errors() {
  vx_new vbe; vx_flag_work
  vx_verify CTW_BRANCH=no/such/branch; want_rc 3; has "$ERR" "is not a commit here"
  XE=(CTW_ROOT="$VM"); sut "$VM" verify; want_rc 0; has "$OUT" "no success-criterion flag on main" "no CTW_BRANCH: the checked-out branch (main in the main checkout)"
  git -C "$VM" checkout -q --detach 2>/dev/null; XE=(CTW_ROOT="$VM"); sut "$VM" verify; want_rc 3; has "$ERR" "detached HEAD: name the branch"
}
r_verify_from_inside_the_worktree() {
  vx_new vi2; vx_flag_work; vx_say "$LONG"; vx_commit_log
  XE=(CTW_ROOT="$VW" CTW_BRANCH=feat/x); sut "$VW" verify; want_rc 0; has "$OUT" "CRITERION answer" "verify run from the branch's own worktree"
  lacks "$OUT" "goal check NOT DONE" "its own worktree is found"
}
r_verify_deleted_judge_is_listed() {
  vx_new vdl; wf "$VW" pkg/b.go 'package b\n'; git -C "$VW" rm -q pkg/e_test.go; vx_commit pkg/b.go
  vx_verify; want_rc 1; has "$OUT" "pkg/e_test.go  (+0 -1 DELETED)" "a deleted test counts as a judging change"
}
r_verify_row_json_variants() {
  vx_new vjv; vx_flag_work; mkdir -p "$VW/docs/agents"
  # a pretty-printed or non-object line is skipped; a valid row after them still counts
  printf '[1,2]\n"x"\n{broken\n{"branch": "feat/x", "answer": "Valid row after junk lines, tests by the tester", "flag": {"judging": "oops", "goal": null}}\n' > "$VW/$LOG_REL"; vx_commit "$LOG_REL"
  vx_verify; want_rc 0; has "$OUT" "Valid row after junk lines" "junk lines skipped"
  has "$OUT" "WARNING: judging files changed on the branch that the answer's row did not list" "a row with malformed flag.judging covers nothing"
}
r_verify_hostile_branch_name() {
  vx_new vhb; git -C "$VM" worktree remove --force "$VW"
  # shellcheck disable=SC2016  # the name holds $( and backticks on purpose: they must stay literal
  local br='h$(touch${IFS}PWNED)`id`ile'
  git -C "$VM" worktree add -q -b "$br" "$VW" main 2>/dev/null || { fail "cannot create the hostile branch name"; return; }
  FX="$VW"; mkstate; printf '%s' "$br" > "$SD/branch"
  wf "$VW" pkg/b.go 'package b\n'; wf "$VW" pkg/b_test.go 'b\n'; vx_commit pkg/b.go pkg/b_test.go
  XE=(CTW_ROOT="$VW" CTW_STATE="$SD" CTW_BRANCH="$br"); sut "$VW" answer --text "$LONG"; sut "$VW" judge; want_rc 0
  vx_commit_log; XE=(CTW_ROOT="$VM" CTW_BRANCH="$br"); sut "$VM" verify; want_rc 0; has "$OUT" "CRITERION answer"
  eq "$(pyj "$VW/$LOG_REL" 0 "r['branch']")" "$br" "branch name kept literally in the row"
  [ ! -e "$VW/PWNED" ] && [ ! -e "$VM/PWNED" ] && [ ! -e "$T/PWNED" ] || fail "a command inside the branch name was executed"
}

# ══ 8. the self-proof ═════════════════════════════════════════════════════════════════════════════════════════════════
mutate() { # mutate <name> <old> <new>: a copy of the script with the text <old> (exactly once) replaced; sets SUT_ALT
  local out="$T/mut/$1.sh"
  python3 -I - "$SUT" "$out" "$2" "$3" <<'PY' || setup_fail "mutation '$1' does not apply exactly once"
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old, new = sys.argv[3], sys.argv[4]
if src.count(old) != 1:
    sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new))
PY
  SUT_ALT="$out"
}
r_proof_clean_no_argument() {
  new_fx pc
  sut "$FX"; want_rc 1; has "$OUT" "self-proof: OK"; has "$ERR" "usage: 10-success-criterion.sh"
  XE=(CTW_STAGE=""); sut "$FX"; want_rc 1; has "$OUT" "self-proof: OK" "an empty CTW_STAGE is no stage"
}
proof_broken() { # proof_broken <label> <old> <new>: the mutant must exit 3 (INCOMPLETE) on a no-argument run AND refuse every mode
  new_fx "pb-$1"; code_and_test; mkstate; hook_env; mutate "pb-$1" "$2" "$3"
  sut "$FX"; want_rc 3; has "$ERR" "INCOMPLETE —" "[$1] no argument"
  sut "$FX" scan; [ "$RC" = 3 ] || fail "[$1] scan ran on a broken detector (rc $RC)"
  sut "$FX" answer --text "$LONG"; [ "$RC" = 3 ] || fail "[$1] answer ran on a broken detector (rc $RC)"
  sut "$FX" judge; [ "$RC" = 3 ] || fail "[$1] judge ran on a broken detector (rc $RC)"
  sut "$FX" verify; [ "$RC" = 3 ] || fail "[$1] verify ran on a broken detector (rc $RC)"
  [ ! -e "$FX/$LOG_REL" ] || fail "[$1] a row was logged by a broken detector"
}
r_proof_broken_classifier_machine_files() { proof_broken classifier-go.sum 'sbom/*|*package-lock.json|*packages.lock.json|*.lockfile|go.sum) echo 2' 'sbom/*|*package-lock.json|*packages.lock.json|*.lockfile) echo 2'; }
# the line occurs twice (the head-line block has it at 8 spaces, the tail at 4): the leading newline + 4 spaces picks the tail
r_proof_broken_classifier_docs() { proof_broken classifier-docs $'\n    docs/*|*.md|*.jsonl) echo other ;;' $'\n    *.jsonl) echo other ;;'; }
r_proof_broken_flag_rule() { proof_broken flag-rule '(c && j) || g' '(c || j) || g'; }
r_proof_broken_skip_counter() { proof_broken skip-counter 't\.Skip|XCTSkip' 'XCTSkip'; }
# shellcheck disable=SC2016  # the mutated text is shell source, kept literal
r_proof_broken_scan_signals() { proof_broken scan-signals 'signals="$signals LINES-REMOVED"' 'signals="$signals LINES-GONE"'; }
# shellcheck disable=SC2016  # the mutated text is shell source, kept literal
r_proof_broken_untracked_collection() { proof_broken untracked 'G ls-files --others --exclude-standard -z -- . ":!$CRITERION_LOG_REL" ":!$REVIEWS_LOG_REL" > "$TMPD/untracked.$$" || return 3' ': > "$TMPD/untracked.$$"'; }
# shellcheck disable=SC2016  # the mutated text is shell source, kept literal
r_proof_broken_skip_anchor() { proof_broken skip-exit '[^A-Za-z]xit\(|' 'xit\(|'; }
# shellcheck disable=SC2016  # the mutated text is awk source, kept literal
r_proof_broken_skip_hunk_filter() { proof_broken skip-hunk 'h && /^\+/ { print }' '/^\+/ && !/^\+\+\+/ { print }'; }
r_proof_leaves_no_temp_folder() {
  new_fx pt; code_and_test; mkstate; hook_env
  sut "$FX" scan; sut "$FX" answer --text "$LONG"; sut "$FX" judge; sut "$FX" verify; sut "$FX"; sut "$FX" bogus
  # shellcheck disable=SC2016  # the mutated text is shell source, kept literal
  mutate "pt" 'signals="$signals LINES-REMOVED"' 'signals="$signals LINES-GONE"'; sut "$FX" scan; want_rc 3     # a failing proof cleans up too
  local left; left="$(find "$T/tmp" -maxdepth 1 -name 'ctw-criterion.*' | wc -l | tr -d ' ')"
  eq "$left" 0 "ctw-criterion.* folders left in TMPDIR"
}

# ══ 9. hostile names and the real repository ══════════════════════════════════════════════════════════════════════════
r_hostile_names_that_survive() {
  new_fx hn; wf "$FX" pkg/a.go 'package a // changed\n'
  wf "$FX" 'my dir/a b_test.go' 'x\n'
  wf "$FX" 'pkg/é_test.go' 'x\n'
  wf "$FX" 'pkg/日本_test.go' 'x\n'
  wf "$FX" '-n_test.go' 'x\n'
  # shellcheck disable=SC2016  # the name holds $( on purpose: it must stay literal
  wf "$FX" 'pkg/$(touch PWNED)_test.go' 'x\n'
  wf "$FX" 'pkg/semi;colon&amp_test.go' 'x\n'
  sut "$FX" scan; want_rc 0
  local p
  # shellcheck disable=SC2016  # the name holds $( on purpose: it must stay literal
  for p in 'my dir/a b_test.go' 'pkg/é_test.go' 'pkg/日本_test.go' 'pkg/$(touch PWNED)_test.go' 'pkg/semi;colon&amp_test.go'; do
    judged "$p" "+1 -0" || fail "name not handled: $p  (got: $(grep -F 'judging file' "$OUT" | tr '\n' '~'))"
  done
  grep -qF -- "  judging file: -n_test.go  (" "$OUT" || fail "a leading-dash name is not listed as a judging file"
  [ ! -e "$FX/PWNED" ] || fail "a command inside a file name was executed"
  eq "$(code_count)" 1 "code files"
}
# a repository config that changes what `git diff` prints (an external diff program, forced colours) must not change the signals
r_hostile_diff_config_does_not_change_signals() {
  local ext="$T/garbage-diff.sh" n cfg
  printf '#!/bin/sh\necho GARBAGE-EXTERNAL-DIFF\nexit 0\n' > "$ext"; chmod +x "$ext"
  for cfg in 0 1; do
    new_fx "dc$cfg"
    if [ "$cfg" = 1 ]; then
      git -C "$FX" config diff.external "$ext"; git -C "$FX" config color.diff always; git -C "$FX" config color.ui always
    fi
    wf "$FX" pkg/a.go 'package a // changed\n'
    wf "$FX" pkg/c_test.go '1\nx\ny\n3\n'                  # +2 -1
    wf "$FX" pkg/f_test.go 'p t.Skip("n")\nq\n'            # +1 -1 and a skip
    wf "$FX" pkg/s_test.go 'a\n\tt.Skip("new")\n'          # untracked, a skip
    sut "$FX" scan; want_rc 0
    judged pkg/c_test.go "+2 -1 LINES-REMOVED" || fail "[config $cfg] work tree: $(grep 'c_test' "$OUT" | head -1)"
    judged pkg/f_test.go "+1 -1 LINES-REMOVED SKIP-MARKERS-ADDED:1" || fail "[config $cfg] work tree: $(grep 'f_test' "$OUT" | head -1)"
    judged pkg/s_test.go "+2 -0 SKIP-MARKERS-ADDED:1" || fail "[config $cfg] untracked: $(grep 's_test' "$OUT" | head -1)"
    # commits-only mode (verify), and the criterion row read back
    git -C "$FX" add pkg/a.go pkg/c_test.go pkg/f_test.go pkg/s_test.go; gitc "$FX" work; mkstate
    XE=(CTW_ROOT="$FX" CTW_BRANCH=feat/x); sut "$FX" verify; want_rc 1
    has "$OUT" "pkg/f_test.go  (+1 -1 LINES-REMOVED SKIP-MARKERS-ADDED:1)" "[config $cfg] verify"
    has "$OUT" "pkg/s_test.go  (+2 -0 SKIP-MARKERS-ADDED:1)" "[config $cfg] verify"
    lacks "$OUT" "GARBAGE-EXTERNAL-DIFF" "[config $cfg] verify"
    n="$(cat "$OUT" "$ERR" | LC_ALL=C grep -c "$(printf '\033')" || true)"; eq "$n" 0 "[config $cfg] escape characters in the output"
  done
}
r_hostile_names_committed_and_staged() {
  new_fx hc; wf "$FX" pkg/a.go 'package a // changed\n'
  wf "$FX" 'my dir/a b_test.go' 'x\n'; wf "$FX" 'pkg/é_test.go' 'x\n'
  git -C "$FX" add 'my dir/a b_test.go' pkg/é_test.go pkg/a.go; gitc "$FX" work; mkstate
  XE=(CTW_ROOT="$FX" CTW_BRANCH=feat/x); sut "$FX" verify; want_rc 1
  has "$OUT" "my dir/a b_test.go  (+1 -0)"; has "$OUT" "pkg/é_test.go  (+1 -0)"
}
r_hostile_leading_dash_name_signals() {
  new_fx hd; wf "$FX" pkg/a.go 'package a // changed\n'; wf "$FX" '-n_test.go' 'one\n\tt.Skip("x")\n'
  sut "$FX" scan; want_rc 0
  judged -n_test.go "+2 -0 SKIP-MARKERS-ADDED:1" || fail "an untracked file whose name starts with '-' must get its line count and skip count (git reads the name as an option): $(grep -F 'n_test.go' "$OUT" | head -1)"
}
r_hostile_quoted_names_are_judging() {
  # git prints a name holding a double quote, a backslash or a tab quoted ("tests/x\"y.go") even with core.quotepath=false;
  # the classifier then sees a leading quote, so `tests/*` does not match and a TEST FILE reads as code.
  new_fx hq; wf "$FX" pkg/a.go 'package a // changed\n'; wf "$FX" 'tests/x"y.go' 'x\n'
  sut "$FX" scan; want_rc 0
  flag_up_out || fail "tests/x\"y.go next to a code change: no flag (the quoted name was read as code)"
  new_fx hq2; wf "$FX" pkg/a.go 'package a // changed\n'; wf "$FX" "tests/a${TAB}b.go" 'x\n'
  sut "$FX" scan; want_rc 0
  flag_up_out || fail "a tab in a tests/ file name: no flag"
  new_fx hq3; wf "$FX" pkg/a.go 'package a // changed\n'; wf "$FX" 'scripts/check-q"x.sh' 'x\n'
  sut "$FX" scan; want_rc 0
  flag_up_out || fail "a gate script with a double quote in its name: no flag"
  judged 'scripts/check-q"x.sh' "+1 -0" || fail "the name is shown as it is: $(grep -F 'check-q' "$OUT" | head -1)"
}
# tab and line break in a name: the class is decided on the real name; the TAB-separated output shows them as \t and \n
r_hostile_tab_and_newline_names_are_shown_escaped() {
  new_fx ht; wf "$FX" pkg/a.go 'package a // changed\n'; wf "$FX" "tests/a${TAB}b.go" 'x\n'; wf "$FX" "tests/c${NL}d.go" 'one\ntwo\n'
  sut "$FX" scan; want_rc 0; flag_up_out || fail "tab / newline names next to a code change: no flag"
  judged 'tests/a\tb.go' "+1 -0" || fail "tab name: $(grep -F 'tests/a' "$OUT" | head -1)"
  judged 'tests/c\nd.go' "+2 -0" || fail "newline name: $(grep -F 'tests/c' "$OUT" | head -1)"
  eq "$(code_count)" 1 "code files (the odd names are not code)"
  # the same names in commits-only mode
  git -C "$FX" add pkg/a.go "tests/a${TAB}b.go" "tests/c${NL}d.go"; gitc "$FX" work; mkstate
  XE=(CTW_ROOT="$FX" CTW_BRANCH=feat/x); sut "$FX" verify
  has "$OUT" 'tests/a\tb.go  (+1 -0)' "verify: tab name"; has "$OUT" 'tests/c\nd.go  (+2 -0)' "verify: newline name"
}
# glob characters in a name are a file name: a tracked "pkg/q?_test.go" must not borrow the numbers of "pkg/q1_test.go"
r_hostile_glob_characters_in_names_are_literal() {
  new_fx hg; wf "$FX" pkg/q1_test.go 'one\n'; wf "$FX" 'pkg/q?_test.go' 'one\ntwo\nthree\n'
  git -C "$FX" add pkg/q1_test.go 'pkg/q?_test.go'; gitc "$FX" tests; wf "$FX" pkg/a.go 'package a // changed\n'
  sut "$FX" scan; want_rc 0
  judged 'pkg/q?_test.go' "+3 -0" || fail "work tree: glob name got another file's numbers: $(grep -F 'q' "$OUT" | grep judging | tr '\n' '~')"
  judged pkg/q1_test.go "+1 -0" || fail "work tree: plain name: $(grep -F 'q1' "$OUT" | head -1)"
  git -C "$FX" add pkg/a.go; gitc "$FX" code; mkstate
  XE=(CTW_ROOT="$FX" CTW_BRANCH=feat/x); sut "$FX" verify
  has "$OUT" 'pkg/q?_test.go  (+3 -0)' "verify: glob name"; has "$OUT" 'pkg/q1_test.go  (+1 -0)' "verify: plain name"
}
r_hostile_control_for_quoted_names() {
  # positive control for the row above: the same files with plain names flag
  new_fx hq4; wf "$FX" pkg/a.go 'package a // changed\n'; wf "$FX" 'tests/xy.go' 'x\n'
  sut "$FX" scan; want_rc 0; flag_up_out || fail "tests/xy.go next to code must flag"
}
r_real_repo_untouched() {
  eq "$(real_snapshot)" "$REAL_BEFORE" "the real criterion.jsonl, its git status and the script under test"
}

# ── run the rows ───────────────────────────────────────────────────────────────────────────────────────────────────────
if begin "cls: every judging pattern is read as judging (tests, gate scripts, floors, baselines, harness files, these hooks)"; then r_cls_judge; finish; fi
if begin "cls: a top-level Tests/ folder is judging"; then r_cls_capital_tests_dir; finish; fi
if begin "cls: near misses are code (check.sh, checkout.sh, latest.go, look-alike folders testdata2 / fixturesx / mytestdata / mytests, floors.csv ...)"; then r_cls_code; finish; fi
if begin "cls: docs, logs, reviews/criterion logs and machine-written files are neither code nor judges"; then r_cls_other; finish; fi
if begin "cls: test fixtures and test data (testdata/, fixtures/, fixture/, tests/*.jsonl) are judging files next to code"; then r_cls_fixtures_are_judging; finish; fi
if begin "cls: documents and data under head-line paths (docs/archive/, *.answer.md, *.jsonl outside test folders) stay other"; then r_cls_machine_written_stay_other; finish; fi
if begin "cls: tests under archive/, runs/, *.answer.md and *.jsonl head-line paths stay judging next to code"; then r_cls_head_line_tests_stay_judging; finish; fi
if begin "cls: source files under archive/ and runs/ stay code; CHECK_THE_WORK_LAST still wins over the test pattern there"; then r_cls_head_line_sources_stay_code; finish; fi
if begin "cls: a CHECK_THE_WORK_LAST glob is matched as a pattern, not expanded against the files of the current folder (gen/* vs gen/runs/x_test.go)"; then r_cls_last_glob_not_expanded_by_the_shell; finish; fi
if begin "cls: the eval answer key (evals/cases.jsonl) is a judging file"; then r_cls_reviewer_eval_answer_key_is_judging; finish; fi
if begin "cls: the head-line pattern in criterion_class equals the first case label of check-the-work.sh file_class"; then r_cls_head_line_pattern_drift; finish; fi
if begin "cls: CHECK_THE_WORK_JUDGE_GLOBS adds judges (also over a docs/*.md path); without it the tree is clean"; then r_cls_judge_globs; finish; fi
if begin "cls: CHECK_THE_WORK_LAST makes generated files other; it does not un-judge a gate script"; then r_cls_last_globs; finish; fi
if begin "cls: a path in both JUDGE_GLOBS and LAST is judging"; then r_cls_judge_beats_last; finish; fi
if begin "cls: ctw_file_class is an exact copy of check-the-work.sh file_class"; then r_cls_copy_of_runner; finish; fi
if begin "scan: a docs-only change does not flag and names the base"; then r_scan_docs_only_no_flag; finish; fi
if begin "scan: code alone and a judge alone do not flag; both together do (positive control)"; then r_scan_code_only_and_judge_only; finish; fi
if begin "scan: code + judge in every pairing of committed / staged / unstaged / untracked flags"; then r_scan_all_change_kinds; finish; fi
if begin "scan: a deleted judging file (unstaged and staged) is listed DELETED"; then r_scan_deleted_judge; finish; fi
if begin "scan: a renamed test file is listed under both names (no rename detection)"; then r_scan_renamed_test_listed_twice; finish; fi
if begin "scan: binary judging files (tracked and untracked) are listed with '+- --' and no LINES-REMOVED"; then r_scan_binary_judge; finish; fi
if begin "scan: a git-ignored file is not scanned"; then r_scan_ignored_file_not_scanned; finish; fi
if begin "scan: an empty new test file next to code still flags"; then r_scan_empty_new_test_still_judge; finish; fi
if begin "scan: changes main made after the fork are not the branch's (merge base, not main's tip)"; then r_scan_merge_base_not_main_tip; finish; fi
if begin "scan: started from a subfolder it scans the whole repository"; then r_scan_from_subdirectory; finish; fi
if begin "scan: --base REF scans against that ref"; then r_scan_base_option; finish; fi
if begin "scan: a bad --base, an empty --base and an unrelated history exit 3"; then r_scan_bad_base_is_3; finish; fi
if begin "scan: argument errors exit 1 with usage"; then r_scan_arguments; finish; fi
if begin "scan: --section prints only the section, and nothing when the flag is down"; then r_scan_section_only; finish; fi
if begin "scan: not a repository / CTW_ROOT not a repository exits 3"; then r_scan_no_repo_is_3; finish; fi
if begin "scan: no main branch exits 3; --base fixes it"; then r_scan_no_main_branch; finish; fi
if begin "scan: CTW_ROOT wins over the working folder"; then r_scan_ctw_root_beats_cwd; finish; fi
if begin "scan: GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE in the environment are ignored"; then r_scan_git_env_ignored; finish; fi
if begin "scan: on main itself nothing flags; a detached HEAD scans like a branch"; then r_scan_on_main_itself_and_detached; finish; fi
if begin "sig: +N -M counts, LINES-REMOVED only for removals, removed skip is not a skip added, new file counts"; then r_sig_counts_and_flags; finish; fi
if begin "sig: every skip-marker alternative is counted (13 markers, one file each)"; then r_sig_skip_marker_alternatives; finish; fi
if begin "sig: the skip count is lines, not matches; near misses are no marker"; then r_sig_skip_count_is_lines_not_matches; finish; fi
if begin "sig: a new skip next to an old one counts once (the old one is context)"; then r_sig_skip_beside_an_old_skip; finish; fi
if begin "sig: skip markers are counted in staged files and in commits-only mode"; then r_sig_skip_in_commits_mode_and_staged; finish; fi
if begin "sig: sys.exit(1) in a test file is not a skip marker; a bare xit( is"; then r_sig_exit_is_not_a_skip; finish; fi
if begin "sig: an added line starting with '++' still counts its skip marker"; then r_sig_plus_plus_line_keeps_its_skip; finish; fi
if begin "goal: a replaced goal (GC line from the real session-state.sh) flags alone, with no code and no judge"; then r_goal_replaced_flags_alone; finish; fi
if begin "goal: scan --goal compares with the record's goal (white space ignored, order and words matter)"; then r_goal_run_goal_file_compare; finish; fi
if begin "goal: no record or an empty goal file is not compared"; then r_goal_no_record_or_empty_file; finish; fi
if begin "goal: the flag lists judging files and the goal together"; then r_goal_with_code_and_judge_lists_all; finish; fi
if begin "goal: scan --goal needs a readable file (missing, folder, unreadable exit 1); an existing empty file is accepted and compares nothing"; then r_goal_file_must_be_a_readable_file; finish; fi
if begin "ans: empty, blank, short (<15) and missing-value answers are refused; exactly 15 is taken; nothing stored on refusal"; then r_ans_refusals; finish; fi
if begin "ans: the stored line is v1<TAB>cksum of the judging set<TAB>text"; then r_ans_stores_bound_to_judging_set; finish; fi
if begin "ans: tabs and line breaks in the text become single blanks (one line, three fields)"; then r_ans_text_normalised_to_one_line; finish; fi
if begin "ans: flag down stores nothing and says so; flag up stores"; then r_ans_flag_down_stores_nothing; finish; fi
if begin "ans: default state folder, the base 'run' used, --base override"; then r_ans_default_state_folder_and_run_base; finish; fi
if begin "ans: CTW_STATE decides where the answer is stored and read"; then r_ans_state_folder_from_ctw_state; finish; fi
if begin "ans: in a linked worktree the answer lives in that worktree's own git folder"; then r_ans_in_linked_worktree_uses_its_own_git_dir; finish; fi
if begin "judge: missing, empty or non-commit base exits 3 and logs nothing"; then r_judge_missing_or_bad_base_is_3; finish; fi
if begin "judge: flag down exits 0 and logs nothing"; then r_judge_flag_down_logs_nothing; finish; fi
if begin "judge: flag up without an answer exits 1, logs nothing, prints the command to run"; then r_judge_flag_up_without_answer_stops; finish; fi
if begin "cls: HARNESS_TEST_GLOBS (pack or env) and HARNESS_JUDGE_GLOBS add judges; the environment wins over harness.conf"; then r_cls_project_globs; finish; fi
if begin "cls: HARNESS_BASELINE_DIR and the DEFERRED-TEST entry of HARNESS_MARKERS decide the judging paths"; then r_cls_configured_paths; finish; fi
if begin "judge: HARNESS_AGENT_DIR moves the log; an escaping folder is refused (exit 3)"; then r_judge_agent_dir; finish; fi
if begin "judge: the appended row has date, branch, base, flag.code / judging / goal and the answer"; then r_judge_row_fields; finish; fi
if begin "judge: a second identical run adds no row; a changed flag or answer adds one"; then r_judge_idempotent_and_new_row_on_change; finish; fi
if begin "judge: an answer given for another set of judging files is stale (added, removed, swapped); a code file is not"; then r_judge_stale_answer_when_judging_set_changes; finish; fi
if begin "judge: a goal replaced after the answer makes the answer stale"; then r_judge_goal_change_makes_answer_stale; finish; fi
if begin "judge: answer file of another version, empty text, wrong fingerprint or empty is no answer"; then r_judge_answer_file_forms; finish; fi
if begin "judge: branch name comes from CTW_BRANCH, then <state>/branch, then HEAD, then 'detached'"; then r_judge_branch_fallbacks; finish; fi
if begin "judge: a log without a trailing newline and with junk lines is appended to safely; another branch's identical row does not suppress"; then r_judge_log_edge_cases; finish; fi
if begin "judge: an answer with quotes, a backslash, non-ASCII and shell characters survives into valid JSON"; then r_judge_answer_json_roundtrip; finish; fi
if begin "judge: a goal.md that differs from the record flags and needs an answer"; then r_judge_goal_file_of_the_run; finish; fi
if begin "judge: answer then judge succeeds when the goal given to run differs from the record's (answer binds the same goal.md as judge)"; then r_judge_answer_satisfies_judge_when_run_goal_differs; finish; fi
if begin "judge: a goal replaced in the record is answerable (answer, then judge logs a row listing the goal)"; then r_judge_goal_replaced_in_record_is_answerable; finish; fi
if begin "judge: CTW_STAGE selects the mode when no argument is given; the argument wins"; then r_judge_stage_from_environment; finish; fi
if begin "judge: without python3 a flagged judge exits 3 and logs nothing; verify exits 3 (flag-down judge still runs)"; then r_judge_without_python3; finish; fi
if begin "verify: no flag on the branch's commits exits 0"; then r_verify_no_flag; finish; fi
if begin "verify: flag + a committed answered row exits 0, prints the answer, no warnings"; then r_verify_flag_with_row_passes; finish; fi
if begin "verify: flag and no row exits 1 (the step was skipped)"; then r_verify_flag_without_row_fails; finish; fi
if begin "verify: scans the commits, not the work tree"; then r_verify_uses_commits_not_work_tree; finish; fi
if begin "verify: an uncommitted row is no row"; then r_verify_row_must_be_committed; finish; fi
if begin "verify: the last answered row wins; a later blank-answer row is ignored"; then r_verify_last_answered_row_wins; finish; fi
if begin "verify: rows with blank, missing or non-text answers are no row"; then r_verify_blank_answer_row_alone_is_no_row; finish; fi
if begin "verify: another branch's row is ignored"; then r_verify_row_of_another_branch_ignored; finish; fi
if begin "verify: a row already in the base does not count"; then r_verify_row_already_in_base_does_not_count; finish; fi
if begin "verify: a row added then removed on the branch is no row"; then r_verify_row_removed_again_is_no_row; finish; fi
if begin "verify: a judging file committed after the answer gives a WARNING and exit 0"; then r_verify_judging_file_after_the_answer_warns; finish; fi
if begin "verify: a goal replaced after the answer warns; answering after it clears the warning"; then r_verify_goal_replaced; finish; fi
if begin "verify: a replaced goal alone needs an answered row"; then r_verify_goal_replaced_alone_needs_a_row; finish; fi
if begin "verify: a branch with no worktree says 'goal check NOT DONE' and goes on"; then r_verify_branch_without_worktree; finish; fi
if begin "verify: CTW_BASE overrides main; a bad base exits 3"; then r_verify_ctw_base_override; finish; fi
if begin "verify: unknown branch exits 3; no CTW_BRANCH uses HEAD; detached HEAD exits 3"; then r_verify_branch_errors; finish; fi
if begin "verify: run from the branch's own worktree works"; then r_verify_from_inside_the_worktree; finish; fi
if begin "verify: a deleted test file in the commits is a judging change"; then r_verify_deleted_judge_is_listed; finish; fi
if begin "verify: junk lines and malformed fields in the log do not crash it"; then r_verify_row_json_variants; finish; fi
if begin "verify: a hostile branch name is data (judge, verify, row)"; then r_verify_hostile_branch_name; finish; fi
if begin "proof: no argument runs the self-proof, prints usage, exits 1"; then r_proof_clean_no_argument; finish; fi
if begin "proof: a classifier that loses go.sum exits 3 and no mode runs"; then r_proof_broken_classifier_machine_files; finish; fi
if begin "proof: a classifier that reads docs/*.md as code exits 3 and no mode runs"; then r_proof_broken_classifier_docs; finish; fi
if begin "proof: a flag rule that flags code alone exits 3 and no mode runs"; then r_proof_broken_flag_rule; finish; fi
if begin "proof: a skip counter that misses t.Skip exits 3 and no mode runs"; then r_proof_broken_skip_counter; finish; fi
if begin "proof: a scan that loses its signals on the throwaway repository exits 3 and no mode runs"; then r_proof_broken_scan_signals; finish; fi
if begin "proof: a scan that loses untracked files exits 3 and no mode runs"; then r_proof_broken_untracked_collection; finish; fi
if begin "proof: a skip counter that reads exit( as xit( exits 3 and no mode runs"; then r_proof_broken_skip_anchor; finish; fi
if begin "proof: a skip counter that drops an added '++' line exits 3 and no mode runs"; then r_proof_broken_skip_hunk_filter; finish; fi
if begin "proof: no ctw-criterion.* folder is left in TMPDIR (also after a failed proof)"; then r_proof_leaves_no_temp_folder; finish; fi
if begin "hostile: names with spaces, non-ASCII, a leading dash, \$(), ; and & are listed and never executed"; then r_hostile_names_that_survive; finish; fi
if begin "hostile: diff.external and forced colours in the repository config do not change the signals (control: no config)"; then r_hostile_diff_config_does_not_change_signals; finish; fi
if begin "hostile: such names in commits-only mode"; then r_hostile_names_committed_and_staged; finish; fi
if begin "hostile: an untracked judging file whose name starts with a dash gets its real signals"; then r_hostile_leading_dash_name_signals; finish; fi
if begin "hostile: tab and line break in a file name are judged on the real name and shown as \\t and \\n"; then r_hostile_tab_and_newline_names_are_shown_escaped; finish; fi
if begin "hostile: glob characters in a name are literal (a tracked q?_test.go keeps its own numbers)"; then r_hostile_glob_characters_in_names_are_literal; finish; fi
if begin "hostile: a double quote or tab in a tests/ or scripts/check- file name does not hide the judging file"; then r_hostile_quoted_names_are_judging; finish; fi
if begin "hostile: control - the same file with a plain name flags"; then r_hostile_control_for_quoted_names; finish; fi
if begin "the real criterion.jsonl, the real git folder state and the script under test are untouched"; then r_real_repo_untouched; finish; fi

MIN_ROWS=87
echo "ctw-success-criterion matrix: $PASSED pass, $FAILED fail, $KD known-defect (open findings)"
if [ -z "${MATRIX_ONLY:-}" ] && [ "$N" -lt "$MIN_ROWS" ]; then echo "ctw-success-criterion matrix: only $N rows ran (expected >= $MIN_ROWS) - refusing to report green"; exit 1; fi
[ "$FAILED" -eq 0 ] || exit 1
exit 0
