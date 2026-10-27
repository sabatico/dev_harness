#!/usr/bin/env bash
# ctw-report-contract-test.sh — known-answer matrix for scripts/check-the-work.d/20-report-contract.sh and the one copy of
# the contract it uses, scripts/lib/report-contract.sh (cross author: written by a model that did not build either, from
# their headers and code).
#
# WHY: the hook is what stops the lead from merging on a free-text "done": a FINAL report must name its commits (each one a
# real commit), its raw gate lines, its bug ids, what is deferred and what it still asks. A checker that passes a report
# with an invented commit id, refuses a good one, picks the wrong report at the merge, or says "OK" when it did not look
# lets a sub-session's claim through unchecked. So the matrix pins (1) the field rules (missing, empty, none and its reason,
# bug ids, formatting forms, multi-line values, CRLF), (2) the commit lookup (made-up, tree, blob, ambiguous, abbreviations,
# empty repository, the two controls that stop "git says yes to everything"), (3) which reports are checked at all (FINAL
# versus INTERIM / QUESTION), (4) the verify discovery (CTW_REPORT, HARNESS_REPORT_DIR, depth, newest, whole-word branch match,
# size limit), (5) the exit vocabulary of docs/ci/gates.md (0 pass, 1 refused, 3 could not run, 4 not checked) and (6) the
# missing or broken lib.
#
# Every row runs the script inside THROWAWAY git repositories and report folders under one mktemp folder (removed by a trap);
# the real repository is never touched (the last rows compare it before and after). Oracles are written by hand: the sha
# of each fixture commit comes from `git rev-parse` of the fixture, the expected problem lines from the lib's header.
# The hook script finds the lib relative to itself (../lib) or under CTW_ROOT/scripts/lib: the "no lib" rows build a tree
# with a copy of the script under test and no lib.
#
# KNOWN-DEFECT rows (kbegin) assert the CORRECT behaviour the scripts lack (findings for the lead). They print
# "known-defect (open finding)" and do not fail the matrix; once the script is fixed they fail with "now PASSES - promote",
# so the fix is noticed. CTW_REPORT_STRICT=1 makes them ordinary failing rows. None is open since the builder's fixes after
# the first report: those rows are normal rows now, with the lead's rulings. Rows whose expected
# behaviour rests on an assumption about intent say ASSUMPTION in their name.
# SCRIPT_UNDER_TEST=<path> runs the matrix against a copy; the copy finds the lib at <its folder>/../lib, so a mutant is a
# tree: <root>/scripts/check-the-work.d/20-report-contract.sh + <root>/scripts/lib/report-contract.sh.
# MATRIX_ONLY=<egrep on the row name> runs only the matching rows (a mutant run needs only one rule family's rows).
# Exit: 0 every row passed · 1 any row failed · 3 could not run (a tool missing, or the fixture could not be built).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="${SCRIPT_UNDER_TEST:-$HERE/check-the-work.d/20-report-contract.sh}"
[ -f "$SUT" ] || { echo "ctw-report-contract matrix: INCOMPLETE - the script under test is missing: $SUT"; exit 3; }
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"
# the lib of the script under test: the one beside it (a mutant tree carries its own), else the repository's
REAL_LIB="$(dirname "$SUT")/../lib/report-contract.sh"
[ -f "$REAL_LIB" ] || REAL_LIB="$HERE/lib/report-contract.sh"
for tool in git python3 awk sed grep find touch; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ctw-report-contract matrix: INCOMPLETE - $tool is missing"; exit 3; }
done
[ -f "$REAL_LIB" ] || { echo "ctw-report-contract matrix: INCOMPLETE - scripts/lib/report-contract.sh is missing"; exit 3; }
REAL_GIT="$(command -v git)"

# only the hook's own folder and the lib are watched for stray files: other work may be going on elsewhere in the same tree
real_snapshot() { { shasum "$SUT" "$REAL_LIB" 2>&1; git -C "$HERE" status --porcelain -- check-the-work.d lib/report-contract.sh 2>&1 | shasum; } 2>&1; }
REAL_BEFORE="$(real_snapshot)"

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_NAMESPACE
# CTW_REPORT_STRICT is this matrix's own switch (strict mode), not a variable of the script under test: it must survive the scrub
for v in $(env | sed -n 's/^\(CTW_[A-Z_]*\)=.*/\1/p; s/^\(CHECK_THE_WORK_[A-Z_]*\)=.*/\1/p; s/^\(HARNESS_[A-Z_]*\)=.*/\1/p'); do
  [ "$v" = CTW_REPORT_STRICT ] || unset "$v"
done
T0="$(mktemp -d "${TMPDIR:-/tmp}/ctw-rep-test.XXXXXX")" || { echo "ctw-report-contract matrix: INCOMPLETE - mktemp failed"; exit 3; }
T="$(cd "$T0" && pwd -P)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/tmp" "$T/o" "$T/r"
export HOME="$T/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 TMPDIR="$T/tmp" LC_ALL=C GIT_CEILING_DIRECTORIES="$T"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid
# fixed commit dates: the fixture shas are the same on every run. With the clock in them, about 1 run in 27 produced a sha of
# seven DIGITS, for which "upper case is no id" is not a test (upper-casing digits changes nothing) and a good row failed at random.
export GIT_AUTHOR_DATE="2026-01-01T00:00:00 +0000" GIT_COMMITTER_DATE="2026-01-01T00:00:00 +0000"
TAB="$(printf '\t')"

# ── the framework ────────────────────────────────────────────────────────────────────────────────────────────────────
N=0; PASSED=0; FAILED=0; KD=0; WHY=""; NAME=""; KDROW=0; XE=(); SUT_ALT=""
fail() { WHY="$WHY | $*"; }
setup_fail() { echo "ctw-report-contract matrix: INCOMPLETE - fixture: $*"; exit 3; }
finish() {
  if [ "$KDROW" = 1 ] && [ "${CTW_REPORT_STRICT:-0}" != 1 ]; then
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
has() { grep -qF -- "$2" "$1" 2>/dev/null || fail "${3:-$(basename "$1")}: missing '$2' (has: $(head -c 200 "$1" 2>/dev/null | tr '\n' '~'))"; }
lacks() { ! grep -qF -- "$2" "$1" 2>/dev/null || fail "${3:-$(basename "$1")}: must not contain '$2'"; }
eq() { [ "$1" = "$2" ] || fail "${3:-value}: got '$1', wanted '$2'"; }
# sut <dir> <args...>: run the script from <dir> with the row's extra environment XE; sets OUT, ERR, RC
sut() {
  local dir="$1"; shift
  OUT="$T/o/last.out"; ERR="$T/o/last.err"
  ( cd "$dir" && env ${XE[@]+"${XE[@]}"} "$BASH" "${SUT_ALT:-$SUT}" "$@" ) >"$OUT" 2>"$ERR"; RC=$?
}
problem_count() { grep -c '^  [A-Z-]*: ' "$OUT" | tr -d ' '; }

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
gitc() { git -C "$1" -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m "$2" || setup_fail "commit in $1"; }
REPO="$T/repo"; git init -q -b main "$REPO" || setup_fail "git init"
printf 'one\n' > "$REPO/a.txt"; git -C "$REPO" add a.txt; gitc "$REPO" "first"
printf 'two\n' >> "$REPO/a.txt"; git -C "$REPO" add a.txt; gitc "$REPO" "second"
printf 'three\n' >> "$REPO/a.txt"; git -C "$REPO" add a.txt; gitc "$REPO" "third"
S3="$(git -C "$REPO" rev-parse HEAD)"; S3s="$(printf '%s' "$S3" | cut -c1-7)"
S2="$(git -C "$REPO" rev-parse HEAD~1)"; S2s="$(printf '%s' "$S2" | cut -c1-7)"
TREE="$(git -C "$REPO" rev-parse 'HEAD^{tree}')"; BLOB="$(git -C "$REPO" rev-parse HEAD:a.txt)"
case "$S3s" in *[a-f]*) ;; *) setup_fail "the fixture sha $S3s has no hex letter: the upper-case row would prove nothing" ;; esac
FAKE="deadbee"                                                        # valid hex, no such commit (checked below)
git -C "$REPO" cat-file -e "$FAKE^{commit}" 2>/dev/null && setup_fail "the made-up id $FAKE exists in the fixture"
# two commit objects whose ids share their first 7 hex digits (found by a birthday search on the commit text): the short id is ambiguous
AMB=""
AMB="$(cd "$REPO" && python3 -I - "$TREE" <<'PY'
import hashlib, subprocess, sys
tree = sys.argv[1]
seen = {}
n = 0
while n < 400000:
    n += 1
    body = ("tree %s\nauthor t <t@t.invalid> 1767225600 +0000\ncommitter t <t@t.invalid> 1767225600 +0000\n\ncollide %d\n" % (tree, n)).encode()
    h = hashlib.sha1(b"commit %d\0" % len(body) + body).hexdigest()
    p = h[:7]
    if p in seen:
        out = []
        for b in (seen[p][1], body):
            out.append(subprocess.run(["git", "hash-object", "-t", "commit", "-w", "--stdin"], input=b, check=True, stdout=subprocess.PIPE).stdout.decode().strip())
        print(p, out[0], out[1])
        break
    seen[p] = (h, body)
PY
)" || setup_fail "the ambiguous-id search failed"
AMBP="${AMB%% *}"; AMBF="$(printf '%s' "$AMB" | cut -d' ' -f2)"
[ -n "$AMBP" ] && [ -n "$AMBF" ] || setup_fail "no ambiguous id pair found"
if git -C "$REPO" cat-file -e "$AMBP^{commit}" 2>/dev/null; then setup_fail "the short id $AMBP is not ambiguous"; fi
git -C "$REPO" cat-file -e "$AMBF^{commit}" 2>/dev/null || setup_fail "the full id $AMBF is not a commit"
EMPTY="$T/empty-repo"; git init -q -b main "$EMPTY" || setup_fail "git init empty"
NOREPO="$T/norepo"; mkdir -p "$NOREPO"

# mk_report <file> <first line> <COMMITS> <GATES> <BUGS> <DEFERRED> <QUESTIONS>: a value "@omit" leaves the field line out
mk_report() {
  local f="$1" first="$2" n v; shift 2
  mkdir -p "$(dirname "$f")"
  { printf '%s\n' "$first"; for n in COMMITS GATES BUGS DEFERRED QUESTIONS; do v="$1"; shift; [ "$v" = "@omit" ] || printf '%s: %s\n' "$n" "$v"; done; } > "$f"
}
G_C="$S3s fix: a thing"; G_G="ok 12 passed"; G_B="none"; G_D="none"; G_Q="none"
good_report() { mk_report "$1" "${2:-FINAL — DONE}" "$G_C" "$G_G" "$G_B" "$G_D" "$G_Q"; }
RN=0
newf() { RN=$((RN + 1)); NF="$T/r/r$RN.md"; }   # NF = a fresh report path
# file_rc <report>: --file from the fixture repository
file_chk() { sut "$REPO" --file "$1"; }
ok_report() { file_chk "$1"; want_rc 0; has "$OUT" "report contract: OK"; }
# a COMMITS value check: expect <rc> and optionally a needle
commits_case() { # commits_case <label> <COMMITS value> <rc> [needle]
  newf; mk_report "$NF" "FINAL — DONE" "$2" "$G_G" "$G_B" "$G_D" "$G_Q"
  file_chk "$NF"
  [ "$RC" = "$3" ] || fail "[$1] COMMITS: $2 -> exit $RC, wanted $3 ($(head -c 200 "$OUT" | tr '\n' '~'))"
  [ -z "${4:-}" ] || grep -qF -- "$4" "$OUT" || fail "[$1] output lacks '$4' ($(head -c 200 "$OUT" | tr '\n' '~'))"
}

# ══ 1. the fields ═════════════════════════════════════════════════════════════════════════════════════════════════════
r_file_good() {
  newf; good_report "$NF"; file_chk "$NF"; want_rc 0
  has "$OUT" "report contract: OK — $NF (COMMITS, GATES, BUGS, DEFERRED, QUESTIONS present; 1 commit id(s), each a commit in $REPO)"
}
r_file_each_missing_field() {
  local i f
  for i in 1 2 3 4 5; do
    f="$(printf 'COMMITS GATES BUGS DEFERRED QUESTIONS' | cut -d' ' -f"$i")"
    newf
    case "$i" in
      1) mk_report "$NF" "FINAL — DONE" "@omit" "$G_G" "$G_B" "$G_D" "$G_Q" ;;
      2) mk_report "$NF" "FINAL — DONE" "$G_C" "@omit" "$G_B" "$G_D" "$G_Q" ;;
      3) mk_report "$NF" "FINAL — DONE" "$G_C" "$G_G" "@omit" "$G_D" "$G_Q" ;;
      4) mk_report "$NF" "FINAL — DONE" "$G_C" "$G_G" "$G_B" "@omit" "$G_Q" ;;
      5) mk_report "$NF" "FINAL — DONE" "$G_C" "$G_G" "$G_B" "$G_D" "@omit" ;;
    esac
    file_chk "$NF"; want_rc 1
    has "$OUT" "report contract: REFUSED"; has "$OUT" "  $f: missing" "[$f]"
    eq "$(problem_count)" 1 "[$f] problem lines (only the missing field)"
  done
}
r_file_each_empty_field() {
  local i f v
  for i in 1 2 3 4 5; do
    f="$(printf 'COMMITS GATES BUGS DEFERRED QUESTIONS' | cut -d' ' -f"$i")"
    for v in "" "   " "${TAB}"; do
      newf
      case "$i" in
        1) mk_report "$NF" "FINAL — DONE" "$v" "$G_G" "$G_B" "$G_D" "$G_Q" ;;
        2) mk_report "$NF" "FINAL — DONE" "$G_C" "$v" "$G_B" "$G_D" "$G_Q" ;;
        3) mk_report "$NF" "FINAL — DONE" "$G_C" "$G_G" "$v" "$G_D" "$G_Q" ;;
        4) mk_report "$NF" "FINAL — DONE" "$G_C" "$G_G" "$G_B" "$v" "$G_Q" ;;
        5) mk_report "$NF" "FINAL — DONE" "$G_C" "$G_G" "$G_B" "$G_D" "$v" ;;
      esac
      file_chk "$NF"; [ "$RC" = 1 ] || fail "[$f='$v'] exit $RC, wanted 1"
      grep -qF "  $f: empty (write none" "$OUT" || fail "[$f='$v'] no 'empty' problem: $(head -c 200 "$OUT" | tr '\n' '~')"
    done
  done
}
r_file_multiline_values() {
  newf; printf '%s\n' "FINAL — DONE" "COMMITS:" "  - $S3s third commit" "  - $S2s second commit" "GATES:" "  \`\`\`" "  ok 12 passed" "  \`\`\`" "BUGS:" "  BUG-12 fixed" "DEFERRED:" "  nothing" "QUESTIONS:" "" "  none" > "$NF"
  file_chk "$NF"; want_rc 0; has "$OUT" "2 commit id(s)"
  # a value that is only a heading below it is empty
  newf; printf '%s\n' "FINAL — DONE" "COMMITS:" "# Notes" "$S3s later" "GATES: $G_G" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" > "$NF"
  file_chk "$NF"; want_rc 1; has "$OUT" "COMMITS: empty" "a heading ends the value; text under it belongs to no field"
  # the next field line ends the value: the sha under GATES is not COMMITS
  newf; printf '%s\n' "FINAL — DONE" "COMMITS:" "GATES: $S3s is in the gate text" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" > "$NF"
  file_chk "$NF"; want_rc 1; has "$OUT" "COMMITS: empty"
}
r_file_sha_forms() {
  commits_case "7-char abbreviation" "$S3s fix: a thing" 0 "1 commit id(s)"
  commits_case "full 40 digits" "$S3" 0
  commits_case "12 digits" "$(printf '%s' "$S3" | cut -c1-12) subject" 0
  commits_case "two commits" "$S3s, $S2s" 0 "2 commit id(s)"
  commits_case "in parentheses" "($S3s)" 0
  commits_case "trailing full stop" "fixed in $S3s." 0
  commits_case "same commit twice counts twice" "$S3s and again $S3s" 0 "2 commit id(s)"
  commits_case "made-up id is refused" "$FAKE fix" 1 "COMMITS: $FAKE is not a commit in this repository"
  commits_case "one real, one made-up: only the made-up is named" "$S3s and $FAKE" 1 "$FAKE is not a commit"
  commits_case "6 digits are no id" "abc123 fix" 1 "no commit sha (7-40 hex digits)"
  commits_case "upper case is no id" "$(printf '%s' "$S3s" | tr 'a-f' 'A-F') fix" 1 "no commit sha"
  commits_case "41 digits are no id" "${S3}a" 1 "no commit sha"
  commits_case "prose without any id" "fixed it" 1 "no commit sha"
}
r_file_not_a_commit_object() {
  commits_case "tree id" "$TREE" 1 "COMMITS: $TREE is not a commit"
  commits_case "blob id" "$BLOB" 1 "COMMITS: $BLOB is not a commit"
  commits_case "control: the commit id is accepted" "$S3" 0
}
r_file_ambiguous_short_id() {
  commits_case "ambiguous 7-digit id" "$AMBP subject" 1 "COMMITS: $AMBP is not a commit in this repository"
  commits_case "control: the full id of one of the two" "$AMBF subject" 0 "1 commit id(s)"
}
r_file_none_rules() {
  commits_case "COMMITS none with a reason" "none — not allowed to commit" 0 "0 commit id(s)"
  commits_case "COMMITS none, ASCII dash" "none - docs only" 0
  commits_case "COMMITS none, upper case" "NONE — docs only" 0
  commits_case "COMMITS none, colon" "none: nothing to commit" 0
  commits_case "COMMITS bare none" "none" 1 "COMMITS: none needs a reason"
  commits_case "COMMITS none and a dash only" "none —" 1 "COMMITS: none needs a reason"
  commits_case "COMMITS none, a 1-character reason" "none — x" 1 "none needs a reason"
  commits_case "COMMITS none, a 2-character reason" "none — ab" 1 "none needs a reason"
  commits_case "COMMITS none, a 3-character reason" "none — abc" 0
  commits_case "COMMITS 'nonetheless' is not none" "nonetheless fixed in $S3s" 0 "1 commit id(s)"
  commits_case "COMMITS 'nonexistent' with no id" "nonexistent" 1 "no commit sha"
  # GATES: none needs a reason too
  local v
  for v in "none:1" "none:1" "none — docs only:0" "none — ab:1" "None - docs only:0" "ok 3 passed:0"; do
    newf; mk_report "$NF" "FINAL — DONE" "$G_C" "${v%:*}" "$G_B" "$G_D" "$G_Q"; file_chk "$NF"
    [ "$RC" = "${v##*:}" ] || fail "GATES: ${v%:*} -> exit $RC, wanted ${v##*:}"
  done
  newf; mk_report "$NF" "FINAL — DONE" "$G_C" "none" "$G_B" "$G_D" "$G_Q"; file_chk "$NF"; has "$OUT" "GATES: none needs a reason"
}
r_file_bugs_rules() {
  local v
  for v in "none:0" "none yet:0" "None.:0" "BUG-12:0" "SEC-7:0" "SEC-7 and BUG-9:0" "fixed BUG-123 today:0" "BUG-:1" "BUG-x:1" "nonexistent:1" "some:1" "bug-12:1" "OOPS-12:1"; do
    newf; mk_report "$NF" "FINAL — DONE" "$G_C" "$G_G" "${v%:*}" "$G_D" "$G_Q"; file_chk "$NF"
    [ "$RC" = "${v##*:}" ] || fail "BUGS: ${v%:*} -> exit $RC, wanted ${v##*:}"
  done
  newf; mk_report "$NF" "FINAL — DONE" "$G_C" "$G_G" "some" "$G_D" "$G_Q"; file_chk "$NF"; has "$OUT" "BUGS: no bug id (<PREFIX>-nnn or SEC-nnn) and not none"
}
# the id prefix is a knob (HARNESS_BUG_PREFIX), SEC is always allowed; a prefix that is not letters/digits/_ would change what the
# pattern means, so it falls back to BUG
r_file_bug_prefix_knob() {
  local v
  for v in "TKT-5:0" "SEC-7:0" "TKT-5 and SEC-7:0" "BUG-5:1" "TKT-:1" "tkt-5:1" "none:0"; do
    newf; mk_report "$NF" "FINAL — DONE" "$G_C" "$G_G" "${v%:*}" "$G_D" "$G_Q"; XE=(HARNESS_BUG_PREFIX=TKT); sut "$REPO" --file "$NF"
    [ "$RC" = "${v##*:}" ] || fail "HARNESS_BUG_PREFIX=TKT, BUGS: ${v%:*} -> exit $RC, wanted ${v##*:}"
  done
  for v in 'A|B' 'X)(' '' 'BUG x'; do
    newf; mk_report "$NF" "FINAL — DONE" "$G_C" "$G_G" "BUG-9" "$G_D" "$G_Q"; XE=(HARNESS_BUG_PREFIX="$v"); sut "$REPO" --file "$NF"
    [ "$RC" = 0 ] || fail "hostile prefix '$v': BUG-9 must still pass (falls back to BUG): exit $RC"
    newf; mk_report "$NF" "FINAL — DONE" "$G_C" "$G_G" "A-9" "$G_D" "$G_Q"; XE=(HARNESS_BUG_PREFIX="$v"); sut "$REPO" --file "$NF"
    [ "$RC" = 1 ] || fail "hostile prefix '$v': A-9 must not pass: exit $RC"
  done
}
# harness.conf of the repository is read (HARNESS_REPORT_DIR, HARNESS_BUG_PREFIX); the environment wins over it
r_verify_reads_harness_conf() {
  local d="$T/r/d-conf" e="$T/r/d-conf-env"; mkdir -p "$d" "$e"
  body_for "$d/conf.md" "on $BR"; body_for "$e/env.md" "on $BR"
  printf '%s\n' "HARNESS_REPORT_DIR=\"$d\"" "HARNESS_BUG_PREFIX=\"TKT\"" > "$REPO/harness.conf"
  vrf; want_rc 0; has "$OUT" "report contract: OK — $d/conf.md" "the report folder named in harness.conf"
  vrf HARNESS_REPORT_DIR="$e"; want_rc 0; has "$OUT" "report contract: OK — $e/env.md" "the environment wins over harness.conf"
  mk_report "$d/conf.md" "FINAL — DONE" "$G_C" "$G_G" "TKT-3" "$G_D" "$G_Q"; printf '%s\n' "on $BR" >> "$d/conf.md"
  vrf; want_rc 0; has "$OUT" "report contract: OK — $d/conf.md" "TKT-3 passes with the prefix from harness.conf"
  mk_report "$d/conf.md" "FINAL — DONE" "$G_C" "$G_G" "BUG-3" "$G_D" "$G_Q"; printf '%s\n' "on $BR" >> "$d/conf.md"
  vrf; want_rc 1; has "$OUT" "BUGS: no bug id" "BUG-3 is refused when harness.conf says TKT"
  rm -f "$REPO/harness.conf"
  vrf; want_rc 4; has "$OUT" "NOT CHECKED" "without harness.conf and env, no folder: not checked"
}
r_file_free_text_fields() {
  newf; mk_report "$NF" "FINAL — DONE" "$G_C" "$G_G" "$G_B" "see docs/runner.md row 4" "Which of the two names should the owner pick?"; ok_report "$NF"
  newf; mk_report "$NF" "FINAL — DONE" "$G_C" "$G_G" "$G_B" "-" "?"; ok_report "$NF"
}
r_file_formatting_forms() {
  local n=0 form want pre
  while IFS='|' read -r want form; do
    n=$((n + 1)); newf
    { printf '%s\n' "FINAL — DONE"; printf '%s\n' "$form $S3s fix"; printf '%s\n' "GATES: $G_G" "BUGS: none" "DEFERRED: none" "QUESTIONS: none"; } > "$NF"
    file_chk "$NF"
    if [ "$want" = ok ]; then [ "$RC" = 0 ] || fail "[$form] exit $RC, wanted 0 ($(head -c 200 "$OUT" | tr '\n' '~'))"
    else { [ "$RC" = 1 ] && grep -qF "  COMMITS: missing" "$OUT"; } || fail "[$form] not read as missing (exit $RC; $(head -c 200 "$OUT" | tr '\n' '~'))"; fi
  done <<'EOF_F'
ok|COMMITS:
ok|- COMMITS:
ok|* COMMITS:
ok|+ COMMITS:
ok|- **COMMITS:**
ok|**COMMITS**:
ok|**COMMITS:**
ok|  COMMITS:
ok|    - **COMMITS:**
ok|__COMMITS__:
no|commits:
no|Commits:
no|COMMITS :
no|## COMMITS:
no|> COMMITS:
no|1. COMMITS:
no|NOT COMMITS:
no|The COMMITS:
EOF_F
  eq "$n" 18 "format forms tried"
  pre=""; : "$pre"
}
r_file_formatted_fields_are_looked_up() {
  local form
  for form in "- COMMITS:" "* COMMITS:" "+ COMMITS:" "- **COMMITS:**" "**COMMITS**:" "__COMMITS__:" "  COMMITS:" "    - **COMMITS:**"; do
    newf; { printf '%s\n' "FINAL — DONE" "$form $FAKE made up"; printf '%s\n' "GATES: $G_G" "BUGS: none" "DEFERRED: none" "QUESTIONS: none"; } > "$NF"
    file_chk "$NF"
    { [ "$RC" = 1 ] && grep -qF "COMMITS: $FAKE is not a commit" "$OUT"; } || fail "[$form] a made-up id in this field form was not looked up (exit $RC; $(head -c 160 "$OUT" | tr '\n' '~'))"
  done
}
r_file_crlf() {
  newf; good_report "$NF"; sed 's/$/\r/' "$NF" > "$NF.crlf"; file_chk "$NF.crlf"; want_rc 0; has "$OUT" "1 commit id(s)"
  newf; mk_report "$NF" "FINAL — DONE" "none — docs only" "none — docs only" "none" "none" "none"; sed 's/$/\r/' "$NF" > "$NF.crlf"; file_chk "$NF.crlf"; want_rc 0
  # a CRLF report with a real defect is still refused (the \r is not a hiding place)
  newf; mk_report "$NF" "FINAL — DONE" "fixed it" "$G_G" "$G_B" "$G_D" "$G_Q"; sed 's/$/\r/' "$NF" > "$NF.crlf"; file_chk "$NF.crlf"; want_rc 1; has "$OUT" "COMMITS: no commit sha"
}
r_file_stop_reason_is_not_commits() {
  newf; printf '%s\n' "FINAL — DONE" "COMMITS: none — stopped early" "STOP-REASON: usage limit; last good state abc123def at $FAKE" "GATES: none — nothing ran" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" > "$NF"
  file_chk "$NF"; want_rc 0; has "$OUT" "0 commit id(s)" "ids in STOP-REASON are not looked up"
  # a COMMITS value that is not "none" keeps looking up its own ids, and still ignores the ids of STOP-REASON
  newf; printf '%s\n' "FINAL — DONE" "COMMITS: $S3s the part that was finished" "STOP-REASON: usage limit; last good state at $FAKE" "GATES: none — nothing ran" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" > "$NF"
  file_chk "$NF"; want_rc 0; has "$OUT" "1 commit id(s)" "a real id in COMMITS, a made-up one in STOP-REASON"
  # control: the made-up id under COMMITS (a value that does not start with none) is looked up and refused
  newf; printf '%s\n' "FINAL — DONE" "COMMITS: $S3s and, as the last good state, $FAKE" "STOP-REASON: usage limit" "GATES: none — nothing ran" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" > "$NF"
  file_chk "$NF"; want_rc 1; has "$OUT" "$FAKE is not a commit"
}
r_file_field_names_inside_text() {
  newf; printf '%s\n' "FINAL — DONE" "COMMITS: none — see GATES: below and BUGS: none" "GATES: $G_G" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" > "$NF"
  file_chk "$NF"; want_rc 0
  newf; printf '%s\n' "FINAL — DONE" "Summary: COMMITS: $S3s was made" "GATES: $G_G" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" > "$NF"
  file_chk "$NF"; want_rc 1; has "$OUT" "COMMITS: missing" "a field must start the line"
}
r_file_text_after_the_last_field() {
  newf; good_report "$NF"; printf '\nPlain summary: all good, see %s and %s.\n' "$S3s" "$FAKE" >> "$NF"
  file_chk "$NF"; want_rc 0; has "$OUT" "1 commit id(s)" "text after the last field belongs to QUESTIONS, not COMMITS"
}

# ══ 2. which reports are checked ══════════════════════════════════════════════════════════════════════════════════════
r_file_final_forms() {
  local f; local n=0
  for f in "FINAL" "FINAL — DONE" "**FINAL**" "**FINAL — DONE**" "  FINAL: x" "FINAL-DONE" "FINAL." "FINAL (partial)"; do
    n=$((n + 1)); newf; good_report "$NF" "$f"; file_chk "$NF"; [ "$RC" = 0 ] || fail "first line '$f' is a FINAL report: exit $RC"
  done
  newf; { printf '\n\n   \n'; cat "$T/r/r$((RN - 1)).md"; } > "$NF"; file_chk "$NF"; want_rc 0     # blank lines before FINAL
}
r_file_not_final_forms() {
  local f
  for f in "INTERIM — still working" "QUESTION — which name?" "FINALLY done" "FINAL_x" "FINAL1" "final — done" "# FINAL" "Done. FINAL" "FINAL" ; do
    newf; mk_report "$NF" "$f" "fixed it" "@omit" "some" "$G_D" "$G_Q"       # a broken body: only the first line decides
    file_chk "$NF"
    if [ "$f" = "FINAL" ]; then [ "$RC" = 1 ] || fail "control: the same broken body under FINAL must be refused (exit $RC)"
    else
      [ "$RC" = 4 ] || fail "first line '$f' -> exit $RC, wanted 4 (not a FINAL report)"
      grep -qF "report contract: NOT CHECKED" "$OUT" || fail "first line '$f': no NOT CHECKED line"
    fi
  done
  newf; : > "$NF"; file_chk "$NF"; want_rc 4; has "$OUT" "NOT CHECKED" "an empty file is not FINAL"
  newf; printf 'INTERIM\nFINAL — DONE\n' > "$NF"; file_chk "$NF"; want_rc 4; has "$OUT" "first line: INTERIM" "FINAL on a later line does not count"
}
r_file_blank_only_file_is_not_final() {
  local k=0 body
  for body in '\n\n   \n' '\n' '   \n' '\t\n\t\n' ' '; do
    k=$((k + 1)); newf
    # shellcheck disable=SC2059  # the body is a printf format on purpose (\n and \t)
    printf "$body" > "$NF"; file_chk "$NF"
    [ "$RC" = 4 ] || fail "[form $k] a file of blank lines only is not a FINAL report: exit $RC, wanted 4 ($(head -c 200 "$OUT" | tr '\n' '~'))"
    grep -qF "NOT CHECKED" "$OUT" || fail "[form $k] no NOT CHECKED line"
  done
  # positive control: the same blank lines in front of a FINAL line are skipped (the report is checked)
  newf; { printf '\n  \n'; good_report "$T/r/tmp-good.md"; cat "$T/r/tmp-good.md"; } > "$NF"; file_chk "$NF"; want_rc 0
}
r_file_arguments() {
  newf; good_report "$NF"
  sut "$REPO" --file "$T/r/does-not-exist.md"; want_rc 3; has "$ERR" "report file not found"
  sut "$REPO" --file "$T/r"; want_rc 3; has "$ERR" "report file not found" "a folder is not a report"
  sut "$REPO" --file; want_rc 1; has "$ERR" "usage:"
  sut "$REPO" --file ""; want_rc 1; has "$ERR" "usage:"
  sut "$REPO" --file "$NF" extra args ignored; want_rc 0
  sut "$REPO" --bogus; want_rc 1; has "$ERR" "usage:"
  sut "$REPO" frobnicate; want_rc 1
}
r_file_path_with_spaces_and_hostile_text() {
  mkdir -p "$T/r/my dir"; NF="$T/r/my dir/the report \$(touch PWNED).md"
  mk_report "$NF" "FINAL — DONE" "$S3s fix \$(touch PWNED) \`touch PWNED\`" "$G_G; touch PWNED" "$G_B" "$G_D" "$G_Q"
  file_chk "$NF"; want_rc 0
  [ ! -e "$REPO/PWNED" ] && [ ! -e "$T/r/PWNED" ] && [ ! -e "$T/PWNED" ] || fail "text inside the report or its path was executed"
}

# ══ 3. the repository the commit ids are looked up in ═════════════════════════════════════════════════════════════════
r_repo_empty_and_missing() {
  newf; good_report "$NF"
  sut "$EMPTY" --file "$NF"; want_rc 3; has "$ERR" "has no commit to prove the commit lookup on"
  newf; mk_report "$NF" "FINAL — DONE" "none — nothing" "none — nothing" "none" "none" "none"
  sut "$NOREPO" --file "$NF"; want_rc 3; has "$ERR" "not inside a git work tree (set CTW_ROOT)" "a FINAL report outside any repository"
  newf; mk_report "$NF" "INTERIM — x" "@omit" "@omit" "@omit" "@omit" "@omit"
  sut "$NOREPO" --file "$NF"; want_rc 4
  XE=(CTW_ROOT="$T/does-not-exist"); newf; good_report "$NF"; sut "$NOREPO" --file "$NF"; want_rc 3
}
r_repo_ctw_root_decides() {
  newf; good_report "$NF"
  XE=(CTW_ROOT="$REPO"); sut "$EMPTY" --file "$NF"; want_rc 0; has "$OUT" "each a commit in $REPO" "CTW_ROOT beats the working folder"
  XE=(CTW_ROOT="$EMPTY"); sut "$REPO" --file "$NF"; want_rc 3
  XE=(); sut "$REPO" --file "$NF"; want_rc 0
}
r_repo_from_subfolder() {
  newf; good_report "$NF"; mkdir -p "$REPO/sub"
  sut "$REPO/sub" --file "$NF"; want_rc 0; has "$OUT" "each a commit in $REPO"
}
r_repo_git_env_ignored() {
  newf; good_report "$NF"
  XE=(GIT_DIR="$EMPTY/.git" GIT_WORK_TREE="$EMPTY" GIT_INDEX_FILE="$T/no/such/index"); sut "$REPO" --file "$NF"
  want_rc 0; has "$OUT" "each a commit in $REPO" "GIT_DIR etc. (a git hook) must not redirect the lookup"
}
# the two controls that stop "every sha is a commit" passing because git quietly answers yes (or no) to all
mk_shim() { # mk_shim <name> <exit code for cat-file>
  local d="$T/shim-$1"; mkdir -p "$d"
  printf '#!/bin/sh\ncase " $* " in *" cat-file "*) exit %s ;; esac\nexec "%s" "$@"\n' "$2" "$REAL_GIT" > "$d/git"; chmod +x "$d/git"
  SHIM="$d"
}
r_lookup_controls() {
  newf; mk_report "$NF" "FINAL — DONE" "$FAKE made up" "$G_G" "$G_B" "$G_D" "$G_Q"
  mk_shim yes 0; XE=(PATH="$SHIM:$PATH"); sut "$REPO" --file "$NF"
  want_rc 3; has "$ERR" "INCOMPLETE — the commit lookup accepted a made-up id"; lacks "$OUT" "report contract: OK" "a lookup that says yes to everything"
  mk_shim no 1; XE=(PATH="$SHIM:$PATH"); newf; good_report "$NF"; sut "$REPO" --file "$NF"
  want_rc 3; has "$ERR" "INCOMPLETE — the commit lookup refused HEAD"; lacks "$OUT" "REFUSED" "a lookup that says no to everything is no verdict on the report"
  # positive control: the real git through the same PATH shape
  mk_shim real 0; printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_GIT" > "$SHIM/git"; XE=(PATH="$SHIM:$PATH"); sut "$REPO" --file "$NF"; want_rc 0
  # a report without ids never runs the lookup, so the shim cannot matter
  newf; mk_report "$NF" "FINAL — DONE" "none — nothing to commit" "none — nothing ran" "none" "none" "none"
  mk_shim yes2 0; XE=(PATH="$SHIM:$PATH"); sut "$REPO" --file "$NF"; want_rc 0
}

# ══ 4. the lib ════════════════════════════════════════════════════════════════════════════════════════════════════════
mk_tree() { # mk_tree <name> [lib source]: <name>/scripts/check-the-work.d/20-report-contract.sh (a copy of the script under test) [+ scripts/lib]
  TREE_ROOT="$T/tree-$1"; mkdir -p "$TREE_ROOT/scripts/check-the-work.d"
  cp "$SUT" "$TREE_ROOT/scripts/check-the-work.d/20-report-contract.sh"
  if [ -n "${2:-}" ]; then mkdir -p "$TREE_ROOT/scripts/lib"; cp "$2" "$TREE_ROOT/scripts/lib/report-contract.sh"; fi
  SUT_ALT="$TREE_ROOT/scripts/check-the-work.d/20-report-contract.sh"
}
r_lib_missing_is_3() {
  newf; good_report "$NF"; mk_tree nolib
  sut "$REPO" --file "$NF"; want_rc 3; has "$ERR" "scripts/lib/report-contract.sh is missing"; lacks "$OUT" "report contract: OK" "no lib, no verdict"
  sut "$REPO"; want_rc 3; sut "$REPO" verify; want_rc 3
  XE=(CTW_REPORT="$NF" CTW_ROOT="$REPO"); sut "$REPO" verify; want_rc 3
  # the judge hook needs no lib
  XE=(); sut "$REPO" judge; want_rc 4
  # positive control: the same tree with the lib in place
  mk_tree withlib "$REAL_LIB"; sut "$REPO" --file "$NF"; want_rc 0
}
r_lib_found_under_ctw_root() {
  newf; good_report "$NF"; mk_tree rootlib; mkdir -p "$T/rootlib-repo/scripts/lib"; cp "$REAL_LIB" "$T/rootlib-repo/scripts/lib/report-contract.sh"
  git init -q -b main "$T/rootlib-repo" 2>/dev/null; printf 'x\n' > "$T/rootlib-repo/x"; git -C "$T/rootlib-repo" add x scripts/lib/report-contract.sh; gitc "$T/rootlib-repo" init
  local s; s="$(git -C "$T/rootlib-repo" rev-parse --short=7 HEAD)"; mk_report "$NF" "FINAL — DONE" "$s fix" "$G_G" "$G_B" "$G_D" "$G_Q"
  XE=(CTW_ROOT="$T/rootlib-repo"); sut "$REPO" --file "$NF"; want_rc 0; has "$OUT" "each a commit in $T/rootlib-repo" "lib from CTW_ROOT/scripts/lib"
}
r_lib_broken_is_3() {
  local brk="$T/brk-lib.sh" what
  for what in 'report_contract_problems() { :; }' 'REPORT_CONTRACT_FIELDS="COMMITS GATES BUGS DEFERRED"' 'report_is_final() { return 0; }' 'report_commit_shas() { :; }'; do
    { cat "$REAL_LIB"; printf '\n%s\n' "$what"; } > "$brk"; mk_tree brk "$brk"; newf; good_report "$NF"
    sut "$REPO" --file "$NF"; [ "$RC" = 3 ] || fail "[$what] --file exit $RC, wanted 3"
    grep -qF "failed its own known-answer proof" "$ERR" || fail "[$what] no INCOMPLETE line: $(head -c 200 "$ERR")"
    sut "$REPO"; [ "$RC" = 3 ] || fail "[$what] no-argument exit $RC, wanted 3"
    XE=(CTW_REPORT="$NF" CTW_ROOT="$REPO"); sut "$REPO" verify; [ "$RC" = 3 ] || fail "[$what] verify exit $RC, wanted 3"
    XE=()
  done
  # positive control: the unmodified lib in the same kind of tree
  newf; good_report "$NF"; mk_tree ok3 "$REAL_LIB"; XE=(); sut "$REPO"; want_rc 1; has "$OUT" "self-proof: OK"
}
r_lib_broken_extractor_is_noticed() {
  # report_commit_shas feeds the commit lookup. If it finds nothing, EVERY made-up id passes with "0 commit id(s)". No
  # known-answer proof (lib or script) exercises it, so a rotted extractor reads as "all commits exist".
  local brk="$T/brk-lib-shas.sh"
  { cat "$REAL_LIB"; printf '\nreport_commit_shas() { :; }\n'; } > "$brk"; mk_tree brkshas "$brk"
  newf; mk_report "$NF" "FINAL — DONE" "$FAKE made up" "$G_G" "$G_B" "$G_D" "$G_Q"
  SUT_ALT="$T/tree-brkshas/scripts/check-the-work.d/20-report-contract.sh"
  sut "$REPO" --file "$NF"
  [ "$RC" = 3 ] || fail "with a broken extractor a made-up commit id was not stopped (exit $RC; $(head -c 160 "$OUT" | tr '\n' ' ')): the self-proof did not notice"
  grep -qF "failed its own known-answer proof" "$ERR" || fail "no INCOMPLETE line: $(head -c 160 "$ERR")"
}

# ══ 5. the hook entry points ══════════════════════════════════════════════════════════════════════════════════════════
r_judge_is_always_4() {
  sut "$REPO" judge; want_rc 4; has "$OUT" "checked at verify (the FINAL report is written after the commit)"
  XE=(CTW_STAGE=judge); sut "$REPO"; want_rc 4; has "$OUT" "checked at verify" "CTW_STAGE=judge, no argument"
  newf; mk_report "$NF" "FINAL — DONE" "fixed it" "@omit" "some" "$G_D" "$G_Q"       # even next to a broken report
  XE=(CTW_STAGE=judge CTW_REPORT="$NF" CTW_ROOT="$REPO" HARNESS_REPORT_DIR="$T/r"); sut "$REPO"; want_rc 4
  XE=(CTW_STAGE=judge); sut "$NOREPO"; want_rc 4
}
r_no_argument_self_proof() {
  sut "$REPO"; want_rc 1; has "$OUT" "self-proof: OK"; has "$ERR" "usage: 20-report-contract.sh --file"
  XE=(CTW_STAGE=bogus); sut "$REPO"; want_rc 1; has "$ERR" "usage:"
  XE=(); sut "$NOREPO"; want_rc 1; has "$OUT" "self-proof: OK" "the self-proof needs no repository"
  XE=(CTW_STAGE=judge); sut "$REPO" bogus; want_rc 1; has "$ERR" "usage:" "the argument beats CTW_STAGE"
}
# the script's own discovery proof: a whole-word matcher or a finder that breaks one known answer must make verify and the
# no-argument run INCOMPLETE (exit 3)
finder_case() { # finder_case <label> <old text> <new text> [dir of a find shim to put first on PATH]
  local src="$T/brk-finder-$1.sh" tree="$T/tree-finder-$1" px=()
  [ -z "${4:-}" ] || px=(PATH="$4:$PATH")
  python3 -I - "$SUT" "$src" "$2" "$3" <<'PY' || setup_fail "the finder mutation '$1' does not apply exactly once"
import sys
t = open(sys.argv[1], encoding="utf-8").read()
old, new = sys.argv[3], sys.argv[4]
if t.count(old) != 1: sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(t.replace(old, new))
PY
  mkdir -p "$tree/scripts/check-the-work.d" "$tree/scripts/lib"; cp "$src" "$tree/scripts/check-the-work.d/20-report-contract.sh"; cp "$REAL_LIB" "$tree/scripts/lib/report-contract.sh"
  SUT_ALT="$tree/scripts/check-the-work.d/20-report-contract.sh"
  newf; good_report "$NF"
  XE=(${px[@]+"${px[@]}"}); sut "$REPO"; [ "$RC" = 3 ] || fail "[$1] no argument: exit $RC, wanted 3"
  grep -qF "the report finder failed its known-answer proof" "$ERR" || fail "[$1] no argument: no INCOMPLETE line ($(head -c 160 "$ERR" | tr '\n' '~'))"
  XE=(CTW_REPORT="$NF" CTW_ROOT="$REPO" ${px[@]+"${px[@]}"}); sut "$REPO" verify; [ "$RC" = 3 ] || fail "[$1] verify (even with an explicit CTW_REPORT): exit $RC, wanted 3"
  XE=(); sut "$REPO" --file "$NF"; [ "$RC" = 0 ] || fail "[$1] --file does not use the finder: exit $RC, wanted 0"
}
# shellcheck disable=SC2016  # the mutated text is awk / shell source, kept literal
r_hook_broken_finder_is_3() {
  finder_case word-end 'if (before !~ w && after !~ w && ' 'if (before !~ w && '
  finder_case dot-letter ' && !(after == "." && after2 ~ "[A-Za-z0-9]")' ''
  finder_case newest '[ "$f" -nt "$best" ]' '[ "$f" -ot "$best" ]'
  finder_case final-test '    report_is_final "$f" || continue
    names_branch' '    names_branch'
  # positive control: the unmodified script in the same kind of tree proves itself, whichever order find lists in
  mk_find_shim ctl-asc ''; local a_ctl="$FSHIM"; mk_find_shim ctl-desc '-r'; local d_ctl="$FSHIM"
  mkdir -p "$T/tree-finder-ok/scripts/check-the-work.d" "$T/tree-finder-ok/scripts/lib"; cp "$SUT" "$T/tree-finder-ok/scripts/check-the-work.d/20-report-contract.sh"; cp "$REAL_LIB" "$T/tree-finder-ok/scripts/lib/report-contract.sh"
  SUT_ALT="$T/tree-finder-ok/scripts/check-the-work.d/20-report-contract.sh"; XE=(); sut "$REPO"; want_rc 1; has "$OUT" "self-proof: OK"
  XE=(PATH="$a_ctl:$PATH"); sut "$REPO"; want_rc 1; has "$OUT" "self-proof: OK" "find lists ascending"
  XE=(PATH="$d_ctl:$PATH"); sut "$REPO"; want_rc 1; has "$OUT" "self-proof: OK" "find lists descending"
}
# The equal-mtime tie: a finder without the tie rule keeps whichever file `find` lists first, so a proof that tests one pair of
# names passes when find happens to list the later name first (found by this matrix, fixed by the builder). The proof
# must catch the missing rule under BOTH listing orders (the shims fix the order).
# shellcheck disable=SC2016  # the mutated text is shell source, kept literal
r_hook_finder_proof_does_not_depend_on_find_order() {
  mk_find_shim tie-asc ''; local a="$FSHIM"; mk_find_shim tie-desc '-r'; local d="$FSHIM"
  finder_case tie-asc ' || { ! [ "$best" -nt "$f" ] && [[ "$f" > "$best" ]]; }' '' "$a"
  finder_case tie-desc ' || { ! [ "$best" -nt "$f" ] && [[ "$f" > "$best" ]]; }' '' "$d"
}
r_selfproof_leaves_no_temp_folder() {
  newf; good_report "$NF"
  sut "$REPO"; sut "$REPO" --file "$NF"; XE=(CTW_REPORT="$NF" CTW_ROOT="$REPO"); sut "$REPO" verify
  XE=(CTW_ROOT="$REPO" HARNESS_REPORT_DIR="$T/r" CTW_BRANCH=nobody); sut "$REPO" verify
  local brk="$T/brk-lib2.sh"; { cat "$REAL_LIB"; printf '\nreport_contract_problems() { :; }\n'; } > "$brk"; mk_tree brk2 "$brk"; XE=(); sut "$REPO" --file "$NF"
  eq "$(find "$T/tmp" -maxdepth 1 \( -name 'ctw-report.*' -o -name 'report-contract.*' \) | wc -l | tr -d ' ')" 0 "self-proof folders left in TMPDIR (also after a failed proof)"
}

# a `find` that lists in a fixed order (ascending or descending by path): equal-mtime ties must be decided by the rule, not by the listing
mk_find_shim() { # mk_find_shim <name> <sort option>; sets FSHIM
  local d="$T/findshim-$1"; mkdir -p "$d"
  printf '#!/bin/sh\n"%s" "$@" | sort %s\n' "$(command -v find)" "$2" > "$d/find"; chmod +x "$d/find"
  FSHIM="$d"
}

# ══ 6. verify: finding the report ═════════════════════════════════════════════════════════════════════════════════════
BR="feat/a"
vrf() { XE=(CTW_ROOT="$REPO" CTW_BRANCH="${BR}" "$@"); sut "$REPO" verify; }
body_for() { # body_for <file> <branch text line>: a good FINAL report whose body names the text
  mk_report "$1" "FINAL — DONE" "$G_C" "$G_G" "$G_B" "$G_D" "$G_Q"; printf '%s\n' "$2" >> "$1"
}
r_verify_ctw_report() {
  newf; good_report "$NF"
  vrf CTW_REPORT="$NF"; want_rc 0; has "$OUT" "report contract: OK — $NF"
  newf; mk_report "$NF" "FINAL — DONE" "fixed it" "$G_G" "$G_B" "$G_D" "$G_Q"
  vrf CTW_REPORT="$NF"; want_rc 1; has "$OUT" "REFUSED" "a refusal at verify stops the merge (exit 1)"; has "$OUT" "COMMITS: no commit sha"
  newf; mk_report "$NF" "FINAL — DONE" "$FAKE x" "$G_G" "$G_B" "$G_D" "$G_Q"
  vrf CTW_REPORT="$NF"; want_rc 1; has "$OUT" "$FAKE is not a commit"
  newf; mk_report "$NF" "INTERIM — x" "@omit" "@omit" "@omit" "@omit" "@omit"
  vrf CTW_REPORT="$NF"; want_rc 4; has "$OUT" "NOT CHECKED"
}
r_verify_ctw_report_missing() {
  vrf CTW_REPORT="$T/r/nope.md"; want_rc 3; has "$ERR" "CTW_REPORT is set but is not a file"
  vrf CTW_REPORT="$T/r"; want_rc 3; has "$ERR" "CTW_REPORT is set but is not a file" "a folder"
}
r_verify_ctw_report_beats_dir() {
  local d="$T/r/d-beats"; mkdir -p "$d"; body_for "$d/other.md" "on $BR"; mk_report "$d/other.md" "FINAL — DONE" "fixed it" "$G_G" "$G_B" "$G_D" "$G_Q"; printf '%s\n' "on $BR" >> "$d/other.md"
  newf; good_report "$NF"
  vrf CTW_REPORT="$NF" HARNESS_REPORT_DIR="$d"; want_rc 0; has "$OUT" "report contract: OK — $NF" "CTW_REPORT wins over HARNESS_REPORT_DIR"
  vrf HARNESS_REPORT_DIR="$d"; want_rc 1; has "$OUT" "report contract: REFUSED — $d/other.md" "control: the folder alone finds the broken report"
}
r_verify_nothing_set_is_4() {
  vrf; want_rc 4; has "$OUT" "NOT CHECKED — no FINAL report found (set CTW_REPORT or HARNESS_REPORT_DIR)"; lacks "$OUT" "report contract: OK"
  XE=(CTW_ROOT="$REPO" CTW_REPORT="" HARNESS_REPORT_DIR=""); sut "$REPO" verify; want_rc 4
}
r_verify_dir_errors() {
  vrf HARNESS_REPORT_DIR="$T/r/no-such-dir"; want_rc 3; has "$ERR" "HARNESS_REPORT_DIR is set but is not a folder"
  mkdir -p "$T/r/emptydir"; vrf HARNESS_REPORT_DIR="$T/r/emptydir"; want_rc 4; has "$OUT" "NOT CHECKED — no FINAL report found"
  newf; good_report "$NF"; vrf HARNESS_REPORT_DIR="$NF"; want_rc 3; has "$ERR" "is not a folder" "a file given as the folder"
}
r_verify_depth_limit() {
  local base="$T/r/depth" lvl rel
  for lvl in 1 2 3 4 5; do
    rm -rf "$base"; mkdir -p "$base"; rel="$base"
    local i=1; while [ "$i" -lt "$lvl" ]; do rel="$rel/sub$i"; i=$((i + 1)); done
    mkdir -p "$rel"; body_for "$rel/report.md" "branch $BR"
    vrf HARNESS_REPORT_DIR="$base"
    if [ "$lvl" -le 3 ]; then { [ "$RC" = 0 ] && grep -qF "report contract: OK — $rel/report.md" "$OUT"; } || fail "a report $lvl level(s) down must be found (exit $RC)"
    else [ "$RC" = 4 ] || fail "a report $lvl levels down must NOT be found (exit $RC)"; fi
  done
}
r_verify_newest_wins() {
  local d="$T/r/newest"; rm -rf "$d"; mkdir -p "$d/a" "$d/b"
  mk_report "$d/a/old-good.md" "FINAL — DONE" "$G_C" "$G_G" "$G_B" "$G_D" "$G_Q"; printf '%s\n' "on $BR" >> "$d/a/old-good.md"
  mk_report "$d/b/new-bad.md" "FINAL — DONE" "fixed it" "$G_G" "$G_B" "$G_D" "$G_Q"; printf '%s\n' "on $BR" >> "$d/b/new-bad.md"
  touch -t 202601010000 "$d/a/old-good.md"; touch -t 202601020000 "$d/b/new-bad.md"
  vrf HARNESS_REPORT_DIR="$d"; want_rc 1; has "$OUT" "REFUSED — $d/b/new-bad.md" "the newer report is the one checked"
  touch -t 202601030000 "$d/a/old-good.md"
  vrf HARNESS_REPORT_DIR="$d"; want_rc 0; has "$OUT" "OK — $d/a/old-good.md" "the order follows the modification time, not the folder or name"
}
# equal modification times (one-second resolution): the later PATH wins, whatever order the files were made or find lists them
r_verify_tie_goes_to_the_later_name() {
  local d="$T/r/tie" k ord shimdir
  for ord in asc desc; do
    if [ "$ord" = asc ]; then mk_find_shim asc ''; else mk_find_shim desc '-r'; fi
    shimdir="$FSHIM"
    for k in 1 2; do
      rm -rf "$d"; mkdir -p "$d/a" "$d/z"
      if [ "$k" = 1 ]; then   # the earlier name is bad, the later name good: the later name wins -> OK
        mk_report "$d/z/rep.md" "FINAL — DONE" "$G_C" "$G_G" "$G_B" "$G_D" "$G_Q"; mk_report "$d/a/rep.md" "FINAL — DONE" "fixed it" "$G_G" "$G_B" "$G_D" "$G_Q"
      else                   # the earlier name is good, the later name bad: the later name wins -> REFUSED
        mk_report "$d/a/rep.md" "FINAL — DONE" "$G_C" "$G_G" "$G_B" "$G_D" "$G_Q"; mk_report "$d/z/rep.md" "FINAL — DONE" "fixed it" "$G_G" "$G_B" "$G_D" "$G_Q"
      fi
      printf '%s\n' "on $BR" >> "$d/a/rep.md"; printf '%s\n' "on $BR" >> "$d/z/rep.md"
      touch -t 202601010000 "$d/a/rep.md" "$d/z/rep.md"
      vrf HARNESS_REPORT_DIR="$d" PATH="$shimdir:$PATH"
      if [ "$k" = 1 ]; then { [ "$RC" = 0 ] && grep -qF "OK — $d/z/rep.md" "$OUT"; } || fail "[tie $k, find lists $ord] the later path must win (exit $RC; $(head -c 160 "$OUT" | tr '\n' '~'))"
      else { [ "$RC" = 1 ] && grep -qF "REFUSED — $d/z/rep.md" "$OUT"; } || fail "[tie $k, find lists $ord] the later path must win (exit $RC; $(head -c 160 "$OUT" | tr '\n' '~'))"; fi
    done
    # an older mtime on the later name does NOT win: the mtime comes first
    touch -t 202601020000 "$d/a/rep.md"
    vrf HARNESS_REPORT_DIR="$d" PATH="$shimdir:$PATH"; has "$OUT" "$d/a/rep.md" "[find lists $ord] a newer mtime beats a later name"
  done
}
r_verify_interim_newer_than_final() {
  local d="$T/r/interim"; rm -rf "$d"; mkdir -p "$d"
  body_for "$d/final.md" "on $BR"; printf 'INTERIM — still on %s\n' "$BR" > "$d/interim.md"
  touch -t 202601010000 "$d/final.md"; touch -t 202601050000 "$d/interim.md"
  vrf HARNESS_REPORT_DIR="$d"; want_rc 0; has "$OUT" "OK — $d/final.md" "an INTERIM report is never picked, however new"
  printf 'QUESTION — about %s\nFINAL — DONE\n' "$BR" > "$d/q.md"; touch -t 202601090000 "$d/q.md"
  vrf HARNESS_REPORT_DIR="$d"; has "$OUT" "OK — $d/final.md" "FINAL on a later line is not FINAL"
}
# which text counts as naming the branch (whole word: not glued to a letter, digit, "_", "/" or "-")
r_verify_branch_whole_word() {
  local n=0 want br txt d
  while IFS='|' read -r want br txt; do
    n=$((n + 1)); d="$T/r/bw$n"; mkdir -p "$d"; body_for "$d/r.md" "$txt"
    BR="$br"; vrf HARNESS_REPORT_DIR="$d"
    if [ "$want" = Y ]; then { [ "$RC" = 0 ] && grep -qF "OK — $d/r.md" "$OUT"; } || fail "[$br] '$txt' must name the branch (exit $RC)"
    else [ "$RC" = 4 ] || fail "[$br] '$txt' must NOT name the branch (exit $RC)"; fi
  done <<'EOF_B'
Y|feat/a|on feat/a now
Y|feat/a|feat/a at the line start
Y|feat/a|the branch is feat/a
Y|feat/a|merged feat/a.
Y|feat/a|merged feat/a, done
Y|feat/a|(feat/a)
Y|feat/a|`feat/a`
Y|feat/a|"feat/a"
Y|feat/a|feat/a: done
N|feat/a|feat/a.b is another name
N|feat/a|see feat/a.9 for the details
N|feat/a|feat/a.B and feat/a.0
Y|feat/a|ends the sentence: feat/a. Next sentence
Y|feat/a|feat/a.
Y|feat/a|feat/a.)
Y|feat/a|feat/a.-
Y|feat/a|x/feat/a-2 is another, but feat/a is this one
Y|feat/a|feat/ab first, then feat/a at last
N|feat/a|feat/a-2
N|feat/a|x/feat/a
N|feat/a|feat/ab
N|feat/a|feat/a/b
N|feat/a|feat/a_x
N|feat/a|afeat/a
N|feat/a|feat/a1
N|feat/a|FEAT/A
N|feat/a|feat/
N|feat/a|feat
Y|fix/a.b+c(1)$x|branch fix/a.b+c(1)$x merged
N|fix/a.b+c(1)$x|branch fix/aXb+c(1)$x merged
N|fix/a.b+c(1)$x|branch fix/a.b+c(1)$xy merged
N|fix/a.b+c(1)$x|branch pre/fix/a.b+c(1)$x merged
Y|a&b|branch a&b merged
N|a&b|branch aXb merged
Y|rel/1.0|branch rel/1.0 merged
N|rel/1.0|branch rel/1x0 merged
EOF_B
  BR="feat/a"
  eq "$n" 36 "branch cases tried"
}
r_verify_branch_in_first_line_and_unrelated_reports() {
  local d="$T/r/mixed"; rm -rf "$d"; mkdir -p "$d"
  mk_report "$d/first.md" "FINAL — on $BR" "$G_C" "$G_G" "$G_B" "$G_D" "$G_Q"
  body_for "$d/other.md" "on feat/other"; touch -t 202601010000 "$d/first.md"; touch -t 202601090000 "$d/other.md"
  vrf HARNESS_REPORT_DIR="$d"; want_rc 0; has "$OUT" "OK — $d/first.md" "the branch on the FINAL line itself; the newer report of another branch is skipped"
}
r_verify_big_files_skipped() {
  local d="$T/r/big"; rm -rf "$d"; mkdir -p "$d"
  { printf 'FINAL — DONE\n'; printf '%s\n' "COMMITS: $G_C" "GATES: $G_G" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" "on $BR"; awk 'BEGIN { for (i = 0; i < 13000; i++) print "padding padding padding padding padding padding padding padding padding padding padding" }'; } > "$d/huge.md"
  [ "$(wc -c < "$d/huge.md")" -gt 1100000 ] || setup_fail "the big report is not over 1100 KB"
  vrf HARNESS_REPORT_DIR="$d"; want_rc 4; has "$OUT" "no FINAL report found" "a file over 1000 KB is not read"
  { printf 'FINAL — DONE\n'; printf '%s\n' "COMMITS: $G_C" "GATES: $G_G" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" "on $BR"; awk 'BEGIN { for (i = 0; i < 8000; i++) print "padding padding padding padding padding padding padding padding padding padding padding" }'; } > "$d/large.md"
  [ "$(wc -c < "$d/large.md")" -lt 900000 ] || setup_fail "the large report is not under 900 KB"
  vrf HARNESS_REPORT_DIR="$d"; want_rc 0; has "$OUT" "OK — $d/large.md" "control: a 700+ KB report is read"
  touch -t 202601010000 "$d/large.md"; touch -t 202601090000 "$d/huge.md"
  vrf HARNESS_REPORT_DIR="$d"; has "$OUT" "OK — $d/large.md" "the newer huge file is skipped, the older readable one is used"
}
r_verify_odd_files_in_the_folder() {
  local d="$T/r/odd"; rm -rf "$d"; mkdir -p "$d/sub dir"
  head -c 3000 /dev/urandom > "$d/blob.bin"                                  # binary
  printf '\000\001FINAL\n' > "$d/nul.bin"
  : > "$d/empty.md"
  printf '\n\n' > "$d/blank.md"
  body_for "$d/sub dir/my report.md" "on $BR"                                   # spaces in the names
  cp "$d/sub dir/my report.md" "$d/unreadable.md"; chmod 000 "$d/unreadable.md"
  ln -s "$d/sub dir/my report.md" "$d/link.md"
  vrf HARNESS_REPORT_DIR="$d"; want_rc 0; has "$OUT" "OK — $d/sub dir/my report.md" "the one real report among binary, empty, unreadable and linked files"
  chmod 600 "$d/unreadable.md"
}
r_verify_branch_from_head_and_detached() {
  local d="$T/r/head"; rm -rf "$d"; mkdir -p "$d"; body_for "$d/r.md" "on feat/q"
  git -C "$REPO" checkout -q -b feat/q
  XE=(CTW_ROOT="$REPO" HARNESS_REPORT_DIR="$d"); sut "$REPO" verify; want_rc 0; has "$OUT" "OK — $d/r.md" "no CTW_BRANCH: the checked-out branch"
  XE=(CTW_ROOT="$REPO" HARNESS_REPORT_DIR="$d" CTW_BRANCH=feat/other); sut "$REPO" verify; want_rc 4
  git -C "$REPO" checkout -q --detach 2>/dev/null
  XE=(CTW_ROOT="$REPO" HARNESS_REPORT_DIR="$d"); sut "$REPO" verify; want_rc 3; has "$ERR" "no CTW_BRANCH and a detached HEAD"
  XE=(CTW_ROOT="$REPO" HARNESS_REPORT_DIR="$d" CTW_BRANCH=feat/q); sut "$REPO" verify; want_rc 0
  git -C "$REPO" checkout -q main
  # an explicit CTW_REPORT needs no branch at all
  XE=(CTW_ROOT="$REPO" CTW_REPORT="$d/r.md"); git -C "$REPO" checkout -q --detach 2>/dev/null; sut "$REPO" verify; want_rc 0; git -C "$REPO" checkout -q main
}
r_verify_needs_a_repository() {
  newf; good_report "$NF"
  XE=(CTW_REPORT="$NF"); sut "$NOREPO" verify; want_rc 3; has "$ERR" "not inside a git work tree"
  XE=(CTW_REPORT="$NF" CTW_ROOT="$REPO"); sut "$NOREPO" verify; want_rc 0
}
r_verify_stage_from_environment() {
  newf; good_report "$NF"
  XE=(CTW_STAGE=verify CTW_REPORT="$NF" CTW_ROOT="$REPO"); sut "$REPO"; want_rc 0; has "$OUT" "report contract: OK" "CTW_STAGE=verify with no argument"
  XE=(CTW_STAGE=verify CTW_ROOT="$REPO"); sut "$REPO"; want_rc 4
}
r_verify_lookup_controls() {
  newf; good_report "$NF"; mk_shim vyes 0
  XE=(PATH="$SHIM:$PATH" CTW_REPORT="$NF" CTW_ROOT="$REPO"); sut "$REPO" verify; want_rc 3; has "$ERR" "accepted a made-up id"
}

# ══ 7. defects found while writing the matrix (see the header) ═══════════════════════════════════════════════════════
r_file_glued_hex_tokens_are_no_id() {
  # "1234567x" and "xabc1234" hold 7 hex digits glued to a letter: not an id. The field check counts them as an id, the
  # extractor does not, so the report passes with "0 commit id(s)" although COMMITS names no commit at all.
  commits_case "7 digits then a letter" "1234567x" 1 "no commit sha"
  commits_case "a letter then 7 digits" "xabc1234" 1 "no commit sha"
  commits_case "digits then a dash" "1234567-8" 1 "is not a commit"          # '-' is not a letter or digit: an id-shaped token, so it IS looked up
  commits_case "an id and a glued token" "$S3s and 1234567x" 0 "1 commit id(s)" # the real id carries the field
  commits_case "underscore after the digits" "abc1234_x" 1 "is not a commit"      # '_' is not a letter or digit: id-shaped, so it IS looked up
}
r_file_none_reason_looks_nothing_up() {
  # ASSUMPTION: a number of 7 or more digits in the REASON of "none — ..." (bytes, a date, a ticket) is not a commit id to look up.
  commits_case "none with a long number" "none — not allowed to commit; the file is 1048576 bytes" 0 "0 commit id(s)"
  commits_case "none with a date and a hash-like word" "none — see 20261024 and deadbeef" 0 "0 commit id(s)"
  commits_case "none, a made-up id in the reason" "none — the id $FAKE was dropped" 0 "0 commit id(s)"
  # the number on the next line under a 'none' value is still part of the reason
  newf; printf '%s\n' "FINAL — DONE" "COMMITS:" "  none — not allowed to commit" "  the file is 1048576 bytes and 20261024 old" "GATES: $G_G" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" > "$NF"
  file_chk "$NF"; want_rc 0; has "$OUT" "0 commit id(s)" "multi-line none"
  # positive control: without 'none' the same number is looked up and refused
  commits_case "no none: the number is an id-shaped token" "the file is 1048576 bytes" 1 "is not a commit"
  # and a real id after a 'none' is NOT looked up either (the field says none)
  commits_case "none, then a real id" "none — nothing new, last was $S3s" 0 "0 commit id(s)"
}
r_file_unreadable_report_is_3() {
  newf; good_report "$NF"; chmod 000 "$NF"
  [ ! -r "$NF" ] || { chmod 600 "$NF"; setup_fail "cannot make an unreadable file (running as root?)"; }
  file_chk "$NF"; local rc1="$RC"; local o1; o1="$(head -c 150 "$OUT" | tr '\n' '~')"
  XE=(CTW_REPORT="$NF" CTW_ROOT="$REPO"); sut "$REPO" verify; local rc2="$RC"
  chmod 600 "$NF"
  [ "$rc1" = 3 ] || fail "--file on an unreadable report: exit $rc1, wanted 3 (could not run); said: $o1"
  case "$o1" in *"NOT CHECKED"*) fail "an unreadable report must not be called 'not a FINAL report': $o1" ;; esac
  [ "$rc2" = 3 ] || fail "verify on an unreadable CTW_REPORT: exit $rc2, wanted 3 - exit 4 lets the merge go on"
}
r_real_repo_untouched() {
  eq "$(real_snapshot)" "$REAL_BEFORE" "the real repository status, the script under test and the lib"
}

# ── run the rows ───────────────────────────────────────────────────────────────────────────────────────────────────────
if begin "file: a good report is OK and counts its commit ids"; then r_file_good; finish; fi
if begin "file: each missing field is refused, alone"; then r_file_each_missing_field; finish; fi
if begin "file: each empty field (blank, spaces, tab) is refused as empty"; then r_file_each_empty_field; finish; fi
if begin "file: values on following lines count; a heading ends a value; the next field ends it"; then r_file_multiline_values; finish; fi
if begin "file: commit id forms (7, 12, 40 digits, lists, punctuation) accepted; made-up, 6, upper case, 41 digits refused"; then r_file_sha_forms; finish; fi
if begin "file: a tree id and a blob id are not commits"; then r_file_not_a_commit_object; finish; fi
if begin "file: an ambiguous 7-digit id is refused; the full id of one of the two is accepted"; then r_file_ambiguous_short_id; finish; fi
if begin "file: COMMITS / GATES none needs a reason of 3+ characters; nonetheless / nonexistent are not none"; then r_file_none_rules; finish; fi
if begin "file: BUGS wants BUG-n or SEC-n or none; look-alikes are refused"; then r_file_bugs_rules; finish; fi
if begin "file: the BUGS id prefix is HARNESS_BUG_PREFIX (SEC always allowed); a hostile prefix falls back to BUG"; then r_file_bug_prefix_knob; finish; fi
if begin "verify: harness.conf supplies HARNESS_REPORT_DIR and HARNESS_BUG_PREFIX; the environment wins"; then r_verify_reads_harness_conf; finish; fi
if begin "file: DEFERRED and QUESTIONS take any non-empty text"; then r_file_free_text_fields; finish; fi
if begin "file: field line forms (list marks, bold, indent, underscores) read; lower case, spaced colon, headings do not"; then r_file_formatting_forms; finish; fi
if begin "file: ids in bold / list-marked / indented COMMITS lines are looked up too (a made-up one is refused)"; then r_file_formatted_fields_are_looked_up; finish; fi
if begin "file: CRLF line endings do not change the verdict"; then r_file_crlf; finish; fi
if begin "file: ids in STOP-REASON are not looked up (control: the same text under COMMITS is)"; then r_file_stop_reason_is_not_commits; finish; fi
if begin "file: a field name inside text or not at the line start is no field"; then r_file_field_names_inside_text; finish; fi
if begin "file: text after the last field does not leak into COMMITS"; then r_file_text_after_the_last_field; finish; fi
if begin "file: FINAL first-line forms are checked (FINAL, bold, indented, FINAL-DONE, after blank lines)"; then r_file_final_forms; finish; fi
if begin "file: INTERIM, QUESTION, FINALLY, FINAL_x, lower case, heading, empty file are not checked (exit 4)"; then r_file_not_final_forms; finish; fi
if begin "file: a file of blank lines only is not a FINAL report (exit 4, not five 'missing' lines)"; then r_file_blank_only_file_is_not_final; finish; fi
if begin "file: missing file / folder exit 3; no value / empty value / unknown option exit 1; extra arguments ignored"; then r_file_arguments; finish; fi
if begin "file: a path with spaces and a report full of \$() and backticks is data"; then r_file_path_with_spaces_and_hostile_text; finish; fi
if begin "repo: an empty repository and no repository exit 3 for a FINAL report; INTERIM never needs one"; then r_repo_empty_and_missing; finish; fi
if begin "repo: CTW_ROOT decides which repository the ids are looked up in"; then r_repo_ctw_root_decides; finish; fi
if begin "repo: started from a subfolder the lookup uses the repository root"; then r_repo_from_subfolder; finish; fi
if begin "repo: GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE in the environment are ignored"; then r_repo_git_env_ignored; finish; fi
if begin "repo: a git that says yes to everything, or no to everything, makes the run INCOMPLETE (exit 3), never OK"; then r_lookup_controls; finish; fi
if begin "lib: a missing lib exits 3 for --file, no argument and verify; judge still exits 4; the lib is found with the script"; then r_lib_missing_is_3; finish; fi
if begin "lib: a lib under CTW_ROOT/scripts/lib is used when none sits beside the script"; then r_lib_found_under_ctw_root; finish; fi
if begin "lib: a lib that fails its own known-answer proof exits 3 in every mode"; then r_lib_broken_is_3; finish; fi
if begin "lib: a broken commit-id extractor is noticed by the self-proof (exit 3), not read as 'all commits exist'"; then r_lib_broken_extractor_is_noticed; finish; fi
if begin "judge: always exits 4 with a one-line note, whatever else is set"; then r_judge_is_always_4; finish; fi
if begin "hook: no argument runs the self-proof and prints usage (exit 1); unknown stage exits 1"; then r_no_argument_self_proof; finish; fi
if begin "hook: a broken report finder makes the no-argument run and verify INCOMPLETE (exit 3)"; then r_hook_broken_finder_is_3; finish; fi
if begin "hook: the discovery proof catches a finder without the equal-mtime tie rule whichever order find lists in"; then r_hook_finder_proof_does_not_depend_on_find_order; finish; fi
if begin "hook: no self-proof temp folder is left in TMPDIR, also after a failed proof"; then r_selfproof_leaves_no_temp_folder; finish; fi
if begin "verify: CTW_REPORT is checked (OK 0, refused 1, INTERIM 4)"; then r_verify_ctw_report; finish; fi
if begin "verify: CTW_REPORT that is not a file exits 3"; then r_verify_ctw_report_missing; finish; fi
if begin "verify: CTW_REPORT wins over HARNESS_REPORT_DIR"; then r_verify_ctw_report_beats_dir; finish; fi
if begin "verify: nothing set prints NOT CHECKED and exits 4, never OK"; then r_verify_nothing_set_is_4; finish; fi
if begin "verify: HARNESS_REPORT_DIR that is not a folder exits 3; an empty folder exits 4"; then r_verify_dir_errors; finish; fi
if begin "verify: a report is found up to 3 levels down, not at 4 or 5"; then r_verify_depth_limit; finish; fi
if begin "verify: the newest matching report wins, by modification time"; then r_verify_newest_wins; finish; fi
if begin "verify: at equal modification times the later path wins; a newer mtime still beats a later name"; then r_verify_tie_goes_to_the_later_name; finish; fi
if begin "verify: an INTERIM report is never picked, however new"; then r_verify_interim_newer_than_final; finish; fi
if begin "verify: the branch must be named as a whole word (36 cases incl. regex and shell characters)"; then r_verify_branch_whole_word; finish; fi
if begin "verify: the branch on the FINAL line counts; a newer report of another branch is skipped"; then r_verify_branch_in_first_line_and_unrelated_reports; finish; fi
if begin "verify: a report over 1000 KB is skipped; a 700+ KB one is read"; then r_verify_big_files_skipped; finish; fi
if begin "verify: binary, empty, blank, unreadable and linked files in the folder do not stop the search; names with spaces work"; then r_verify_odd_files_in_the_folder; finish; fi
if begin "verify: no CTW_BRANCH uses the checked-out branch; a detached HEAD exits 3; CTW_REPORT needs no branch"; then r_verify_branch_from_head_and_detached; finish; fi
if begin "verify: a FINAL report outside any repository exits 3"; then r_verify_needs_a_repository; finish; fi
if begin "verify: CTW_STAGE=verify selects the mode"; then r_verify_stage_from_environment; finish; fi
if begin "verify: the lookup controls apply here too"; then r_verify_lookup_controls; finish; fi
if begin "file: 7 hex digits glued to a letter or digit are no commit id (check and extractor use one rule)"; then r_file_glued_hex_tokens_are_no_id; finish; fi
if begin "file: COMMITS none — <reason> looks nothing up, whatever hex-like numbers the reason holds"; then r_file_none_reason_looks_nothing_up; finish; fi
if begin "file: an unreadable report is 'could not run' (exit 3), not 'not a FINAL report' (exit 4)"; then r_file_unreadable_report_is_3; finish; fi
if begin "the real repository status, the script under test and the lib are untouched"; then r_real_repo_untouched; finish; fi

MIN_ROWS=50
echo "ctw-report-contract matrix: $PASSED pass, $FAILED fail, $KD known-defect (open findings)"
if [ -z "${MATRIX_ONLY:-}" ] && [ "$N" -lt "$MIN_ROWS" ]; then echo "ctw-report-contract matrix: only $N rows ran (expected >= $MIN_ROWS) - refusing to report green"; exit 1; fi
[ "$FAILED" -eq 0 ] || exit 1
exit 0
