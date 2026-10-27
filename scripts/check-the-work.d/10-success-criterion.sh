#!/usr/bin/env bash
# scripts/check-the-work.d/10-success-criterion.sh — hook of scripts/check-the-work.sh (S3 of docs/ci/session-resilience.md):
# flags a branch that changed CODE and the files that JUDGE code in one go (or whose goal was replaced), shows how the
# judges were weakened, and makes the sub-session answer in writing before the review is logged. The lead rules.
#
# WHY (MASS study of multi-agent self-supervision, arXiv 2610.12176): output contracts carried most of the gains, and an
# episode that changed the MEANING of success still got 5 of 6 favourable judgements: a reviewer that reads a new test
# against the new code finds them consistent. Git cannot tell which agent wrote a file (every commit of a session has one
# author), so this guard does not guess: it flags EVERY branch that changes code and its judges. The authorship in the
# answer is a declaration the lead reads, not a proof ("builder != test author" stays in the attention column).
#
# JUDGING files (they decide whether code passes): tests (check-the-work.sh file_class 1, plus HARNESS_TEST_GLOBS of the
# stack pack / harness.conf), test fixtures / test data (class 2 there, judge here) and the eval answer keys (evals/*,
# scripts/*-eval*/*, scripts/harness-eval*); the gate scripts scripts/check-*.sh, run-all-gates.sh, mutation-test.sh;
# coverage-floors.txt, lint baselines, *baseline*, *-allow.txt, stacks/*; the baseline folder (HARNESS_BASELINE_DIR),
# harness.conf, scanner configs; the deferred-test registry (the DEFERRED-TEST entry of HARNESS_MARKERS); these hooks
# (scripts/check-the-work.d/*); extra globs in HARNESS_JUDGE_GLOBS (harness.conf) or CHECK_THE_WORK_JUDGE_GLOBS (environment) —
# space-separated shell patterns on the repo-relative path. A goal replaced = a `GC` line in <git-dir>/session-state.txt
# (scripts/session-state.sh).
#
# Usage:
#   10-success-criterion.sh scan [--base REF] [--goal FILE] [--section]
#         by hand, BEFORE `check-the-work.sh run`: scans the work tree (committed, staged, unstaged, untracked) against the
#         merge base with REF (default main). Prints the flag; when it is up, also a ready "## Success-criterion check"
#         section for the --summary file (--section prints only that section, so `scan --section >> summary.md` works).
#         Exit 0 after a good scan (flag or no flag), 3 when it cannot scan.
#   10-success-criterion.sh answer --text "<who wrote the judging files (agent, model) and why no criterion was weakened>"
#         by hand, BEFORE `check-the-work.sh judge`: stores the answer in <git-dir>/check-the-work/criterion-answer, bound
#         to the set of flagged judging files (a judging file added or removed later makes the answer stale: answer again).
#         Exit 1 on an empty or too short text, 3 when it cannot scan.
#   10-success-criterion.sh judge      hook, after the judgement is accepted and before the row is written: flag up and no
#         valid answer -> exit 1 (the command stops, logs nothing); flag up with an answer -> appends ONE row to
#         $HARNESS_AGENT_DIR/criterion.jsonl (default docs/agents) under CTW_ROOT (commit it WITH the work), exit 0; flag down -> exit 0.
#   10-success-criterion.sh verify     hook, for the lead at the merge (usually from the main checkout): scans the branch's
#         COMMITS since its merge base with main (CTW_BASE overrides), reads the criterion row the branch added, prints
#         flag and answer; flag up and no row -> exit 1 (the step was skipped).
#   (no argument)                      runs the self-proof, prints usage, exit 1.
# Env of the hook calls: CTW_STAGE, CTW_ROOT, CTW_STATE (goal.md, base, branch), CTW_BRANCH, CTW_LOG, CTW_JUDGEMENT. By hand
#   they default to the current repository (CTW_STATE to <git-dir>/check-the-work).
# Exit: 0 pass · 1 fail (flag without answer, refused answer, usage) · 3 could not run (no repo, bad base, the detector failed
#   its known-answer proof, no python3) · 4 not applicable (not used here). Bash 3.2 compatible; git is asked about the
#   folder named, never one named by GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE (unset on entry: a git hook sets them).
# Blast radius: writes only the answer file in the git folder, <HARNESS_AGENT_DIR>/criterion.jsonl (one appended row), and a
#   throwaway repository under $TMPDIR for the self-proof (removed on exit). Deletes nothing else.
# Tests: scripts/ctw-success-criterion-test.sh (written by an author other than this script's builder).
set -uo pipefail
# No pathname expansion: the glob lists (CHECK_THE_WORK_LAST, the JUDGE_GLOBS, HARNESS_TEST_GLOBS) are walked unquoted so each
# pattern is one word, and with expansion ON the shell first matches every pattern against the files of the CURRENT folder:
# 'gen/*' became 'gen/runs' and no longer matched gen/runs/x_test.go, so a judging file could read as code or the reverse.
set -f
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# The shortest answer taken: "ok" or "none" would defeat the point of asking for who and why.
MIN_ANSWER_CHARS=15
# Where the criterion rows live: <HARNESS_AGENT_DIR>/criterion.jsonl. These two are the defaults; load_conf sets them for real.
AGENT_DIR_REL="docs/agents"
CRITERION_LOG_REL="docs/agents/criterion.jsonl"
REVIEWS_LOG_REL="docs/agents/reviews.jsonl"
BASELINE_REL=".harness/baselines"
REGISTRY_REL="docs/deferred-test-registry.md"
SELF="10-success-criterion"
HERE="$(cd "$(dirname "$0")" && pwd)" || { echo "$SELF: cannot find its own folder" >&2; exit 3; }

die() { echo "$SELF: $1" >&2; exit "${2:-1}"; }

TMPD=""
# shellcheck disable=SC2329  # runs from the EXIT trap below
cleanup() { if [ -n "$TMPD" ] && [ -d "$TMPD" ]; then rm -rf -- "$TMPD"; fi; }
trap cleanup EXIT
mk_tmp() { # one scratch folder per run
  [ -n "$TMPD" ] || TMPD="$(mktemp -d "${TMPDIR:-/tmp}/ctw-criterion.XXXXXX")" || die "no temp folder" 3
}

# harness.conf, the way the kit's other hooks read it: the generic stack pack as the base, the named pack on top, then the
# project's harness.conf (so it wins). The knobs this hook reads are put back from the ENVIRONMENT afterwards, so a caller
# (or a test) that sets one explicitly is not undone by a file. Needs ROOT. It also derives the paths that depend on the
# knobs (the log, the baseline folder, the deferred-test registry).
load_conf() {
  local k v pack saved="" cfg="$ROOT/harness.conf" w
  for k in HARNESS_AGENT_DIR HARNESS_BASELINE_DIR HARNESS_MARKERS HARNESS_TEST_GLOBS HARNESS_JUDGE_GLOBS; do
    eval "v=\${$k+set}"
    [ "$v" != set ] || saved="$saved $k"
    eval "SAVED_$k=\${$k-}"
  done
  # shellcheck disable=SC1091
  [ -f "$HERE/../stacks/generic.conf" ] && . "$HERE/../stacks/generic.conf"
  if [ -f "$cfg" ]; then
    pack="$(sed -n 's/^[[:space:]]*HARNESS_STACK=["'"'"']\{0,1\}\([A-Za-z0-9_-]\{1,\}\).*/\1/p' "$cfg" | tail -1)"
    # shellcheck disable=SC1090
    [ -z "$pack" ] || [ "$pack" = generic ] || [ ! -f "$HERE/../stacks/$pack.conf" ] || . "$HERE/../stacks/$pack.conf"
    # shellcheck disable=SC1090
    . "$cfg"
  fi
  for k in $saved; do eval "$k=\$SAVED_$k"; done
  AGENT_DIR_REL="${HARNESS_AGENT_DIR:-docs/agents}"; AGENT_DIR_REL="${AGENT_DIR_REL%/}"
  # the folder goes into git pathspecs and is created under the repository: an absolute or ".." path would leave it
  case "/$AGENT_DIR_REL/" in /*//*|*/../*|*/./*) die "HARNESS_AGENT_DIR must be a relative folder inside the repository (got '$AGENT_DIR_REL')" 3 ;; esac
  case "$AGENT_DIR_REL" in /*|"") die "HARNESS_AGENT_DIR must be a relative folder inside the repository (got '$AGENT_DIR_REL')" 3 ;; esac
  CRITERION_LOG_REL="$AGENT_DIR_REL/criterion.jsonl"; REVIEWS_LOG_REL="$AGENT_DIR_REL/reviews.jsonl"
  BASELINE_REL="${HARNESS_BASELINE_DIR:-.harness/baselines}"; BASELINE_REL="${BASELINE_REL%/}"
  for w in ${HARNESS_MARKERS:-}; do
    case "$w" in DEFERRED-TEST:?*) REGISTRY_REL="${w#DEFERRED-TEST:}" ;; esac
  done
}

ROOT="" GITDIR=""
need_repo() {
  [ -z "$ROOT" ] || return 0
  if [ -n "${CTW_ROOT:-}" ]; then ROOT="$CTW_ROOT"; else ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""; fi
  [ -n "$ROOT" ] && [ -d "$ROOT" ] || { ROOT=""; die "not inside a git work tree (set CTW_ROOT)" 3; }
  GITDIR="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || die "cannot find the git folder of $ROOT" 3
  load_conf
}
# Names as they are (core.quotepath off): a quoted "\303\251.txt" matches no file and would hide a judging file.
G() { git -C "$ROOT" -c core.quotepath=false "$@"; }

# ── classification ──────────────────────────────────────────────────────────────────────────────────────────────────
# Copied from scripts/check-the-work.sh file_class on purpose (that file is not sourced: it runs a command on load). If
# the two drift, a test file could read as code here; the cross author's matrix compares them.
# The body of ctw_file_class stays byte-identical to file_class; criterion_class decides the paths of file_class's class-2
# head line itself (before it asks ctw_file_class), so the guard is not weakened by the copy.
ctw_file_class() { # 0 implementation, 1 test, 2 machine-written
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

# The class of one changed path: judge (decides whether code passes), code, or other (docs, logs, machine-written lists).
criterion_class() {
  local p="$1" g
  for g in ${CHECK_THE_WORK_JUDGE_GLOBS:-} ${HARNESS_JUDGE_GLOBS:-}; do
    # shellcheck disable=SC2254  # $g is a glob on purpose (the JUDGE_GLOBS variables hold patterns)
    case "$p" in $g) echo judge; return ;; esac
  done
  case "$p" in
    "$REVIEWS_LOG_REL"|"$CRITERION_LOG_REL") echo other; return ;;
    scripts/check-*.sh|scripts/run-all-gates.sh|scripts/mutation-test.sh|scripts/coverage-floors.txt|scripts/lint-baselines/*|\
    scripts/*baseline*|scripts/*-allow.txt|scripts/stacks/*|harness.conf|.semgrep*|.golangci.yml|.gitleaks.toml|\
    .osv-scanner.toml|evals/*|scripts/*-eval/*|scripts/harness-eval*|scripts/check-the-work.d/*) echo judge; return ;;
  esac
  # the baseline folder and the deferred-test registry are configured paths (harness.conf), so they are compared as variables
  case "$p" in
    "$BASELINE_REL"/*|"$REGISTRY_REL") echo judge; return ;;
  esac
  # WHY: main's file_class opens with a "machine-written" head line (class 2) that only ORDERS check-the-work.sh's
  # review diff. This guard decides those paths here exactly as it did before that line existed (a test under archive/ or
  # runs/, a golden *.answer.md, a *_test.jsonl stay judge; a runs/ source file stays code), except that fixtures and test
  # data are judge: a golden file redefines "passing". The pattern below is a COPY of the head line of file_class in
  # scripts/check-the-work.sh (a matrix row compares them); it is NOT passed to ctw_file_class.
  case "$p" in
    archive/*|*/archive/*|fixtures/*|*/fixtures/*|fixture/*|*/fixture/*|testdata/*|*/testdata/*|runs/*|*/runs/*|*.answer.md|*.jsonl)
      case "$p" in
        fixtures/*|*/fixtures/*|fixture/*|*/fixture/*|testdata/*|*/testdata/*) echo judge; return ;;
      esac
      case "$p" in
        sbom/*|*package-lock.json|*packages.lock.json|*.lockfile|go.sum) echo other; return ;;
      esac
      for g in ${CHECK_THE_WORK_LAST:-}; do
        # shellcheck disable=SC2254  # $g is a glob on purpose (CHECK_THE_WORK_LAST holds patterns)
        case "$p" in $g) echo other; return ;; esac
      done
      case "$p" in
        tests/*|test/*|Tests/*|*/tests/*|*/test/*|*/Tests/*|*-test.*|*_test.*|*Test.*|*Tests.*) echo judge; return ;;
      esac
      case "$p" in
        docs/*|*.md|*.jsonl) echo other ;;
        *) echo code ;;
      esac
      return ;;
  esac
  case "$(ctw_file_class "$p")" in
    1) echo judge; return ;;
    2) echo other; return ;;
  esac
  # the project's own idea of a test file (stack pack / harness.conf): checked AFTER the fixed rules above so a machine-written
  # path the project lists in CHECK_THE_WORK_LAST stays "other" and the fixed class-2 paths keep their meaning
  for g in ${HARNESS_TEST_GLOBS:-}; do
    # shellcheck disable=SC2254  # $g is a glob on purpose (HARNESS_TEST_GLOBS holds patterns)
    case "$p" in $g) echo judge; return ;; esac
  done
  case "$p" in
    docs/*|*.md|*.jsonl) echo other ;;
    *) echo code ;;
  esac
}

# Skip markers among the ADDED lines of ONE file's diff on stdin (a test skipped is a criterion loosened). Only lines inside a
# hunk (after its "@@") count, so an added line that itself starts with "++" (diff line "+++...") is not mistaken for the file
# header and dropped. "xit(" must not sit inside "exit(" (sys.exit(1) is not a skip).
skip_count() {
  awk '/^@@/ { h = 1; next } h && /^\+/ { print }' \
    | grep -cE 't\.Skip|XCTSkip|@Ignore|@Disabled|Skip *=|\.skip\(|[^A-Za-z]skip\(|[^A-Za-z]xit\(|pytest\.mark\.skip|\[Ignore|SKIP_' || true
}

# ── the scan ────────────────────────────────────────────────────────────────────────────────────────────────────────
# scan_to <out file> <merge-base> <tip or ""> <session-state file or ""> <goal file or ""> — TAB lines:
#   code <path> · judge <path> <signals> · goal <message>
# Without <tip>: the work tree (committed, staged, unstaged, untracked), as `run` sees it; with <tip>: the commits only
# (merge base..tip), as `verify` sees them. Returns 3 when git cannot answer: an unreadable diff is not an empty one.
#
# Paths come from git with -z: git QUOTES a name holding a double quote, a backslash or a tab even with core.quotepath off, and
# the quoted string misses every anchored pattern, so a test file would read as code. A tab or line break in a name is shown
# as the two characters \t / \n in the output (the output is TAB-separated; the class is decided on the real name). Each
# per-file git call gets the path as a LITERAL pathspec after "--": a name that starts with "-" or holds glob characters is
# then a file name, never an option or a pattern.

# scan_path <out> <merge-base> <tip or ""> <1 when the file is untracked> <path>
scan_path() {
  local out="$1" mb="$2" tip="$3" untracked="$4" p="$5" cls shown ns st added removed signals skips ps
  cls="$(criterion_class "$p")"
  shown="${p//$'\t'/\\t}"; shown="${shown//$'\n'/\\n}"
  ps=":(literal)$p"
  case "$cls" in
    code) printf 'code\t%s\n' "$shown" >> "$out" ;;
    judge)
      if [ -n "$tip" ]; then
        ns="$(G diff --no-ext-diff --no-color --no-renames --numstat "$mb" "$tip" -- "$ps" 2>/dev/null | head -1)"
        st="$(G diff --no-ext-diff --no-color --no-renames --name-status "$mb" "$tip" -- "$ps" 2>/dev/null | cut -c1 | head -1)"
        skips="$(G diff --no-ext-diff --no-color --no-renames "$mb" "$tip" -- "$ps" 2>/dev/null | skip_count)"
      elif [ "$untracked" = 1 ]; then
        # a new file git has not seen: --no-index is the only way to count its lines and its skip markers
        ns="$(G diff --no-ext-diff --no-color --no-index --numstat -- /dev/null "$p" 2>/dev/null | head -1)"; st="A"
        skips="$(G diff --no-ext-diff --no-color --no-index -- /dev/null "$p" 2>/dev/null | skip_count)"
      else
        ns="$(G diff --no-ext-diff --no-color --no-renames --numstat "$mb" -- "$ps" 2>/dev/null | head -1)"
        st="$(G diff --no-ext-diff --no-color --no-renames --name-status "$mb" -- "$ps" 2>/dev/null | cut -c1 | head -1)"
        skips="$(G diff --no-ext-diff --no-color --no-renames "$mb" -- "$ps" 2>/dev/null | skip_count)"
      fi
      added="$(printf '%s' "$ns" | cut -f1)"; removed="$(printf '%s' "$ns" | cut -f2)"
      [ -n "$ns" ] || { added="?"; removed=0; }
      signals="+$added -$removed"
      [ "$st" != "D" ] || signals="$signals DELETED"
      case "$removed" in ''|0|-) ;; *) [ "$st" = "D" ] || signals="$signals LINES-REMOVED" ;; esac
      [ "${skips:-0}" -eq 0 ] || signals="$signals SKIP-MARKERS-ADDED:$skips"
      printf 'judge\t%s\t%s\n' "$shown" "$signals" >> "$out" ;;
  esac
}

scan_to() {
  local out="$1" mb="$2" tip="$3" sf="$4" gf="$5" body p
  mk_tmp
  body="$TMPD/body.$$"
  : > "$out"
  # tracked changes first (a file is in the diff or untracked, never both), then untracked files; sorted at the end by name
  G diff --no-ext-diff --no-color --no-renames --name-only -z "$mb" ${tip:+"$tip"} -- . ":!$CRITERION_LOG_REL" ":!$REVIEWS_LOG_REL" > "$TMPD/tracked.$$" || return 3
  if [ -z "$tip" ]; then
    G ls-files --others --exclude-standard -z -- . ":!$CRITERION_LOG_REL" ":!$REVIEWS_LOG_REL" > "$TMPD/untracked.$$" || return 3
  else
    : > "$TMPD/untracked.$$"
  fi
  : > "$body"
  while IFS= read -r -d '' p; do
    [ -n "$p" ] || continue
    scan_path "$body" "$mb" "$tip" 0 "$p"
  done < "$TMPD/tracked.$$"
  while IFS= read -r -d '' p; do
    [ -n "$p" ] || continue
    scan_path "$body" "$mb" "$tip" 1 "$p"
  done < "$TMPD/untracked.$$"
  LC_ALL=C sort -t "$(printf '\t')" -k2,2 -s "$body" > "$out"
  # the goal: replaced during the work (session-state.sh keeps a GC line), or given to `run` as another file than the
  # one the record started with
  if [ -n "$sf" ] && [ -f "$sf" ]; then
    if awk -F'\t' '$1 == "GC" { n++ } END { exit n ? 0 : 1 }' "$sf"; then
      printf 'goal\t%s\n' "the session's state record shows the goal REPLACED during the work" >> "$out"
    fi
    if [ -n "$gf" ] && [ -s "$gf" ] && awk -F'\t' '$1 == "G" { n++ } END { exit n ? 0 : 1 }' "$sf"; then
      if [ "$(tr '\t\r' '  ' < "$gf" | sed '/^[[:space:]]*$/d' | tr -s ' ')" \
           != "$(awk -F'\t' '$1 == "G" { print $2 }' "$sf" | sed '/^[[:space:]]*$/d' | tr -s ' ')" ]; then
        printf 'goal\t%s\n' "the goal file given to 'run' differs from the goal the session's state record started with" >> "$out"
      fi
    fi
  fi
  return 0
}
flag_up() { awk -F'\t' '$1 == "code" { c = 1 } $1 == "judge" { j = 1 } $1 == "goal" { g = 1 } END { exit ((c && j) || g) ? 0 : 1 }' "$1"; }
# What the answer must cover: the judging files and the goal lines (not the code list: more code does not change the claim).
fingerprint() { awk -F'\t' '$1 == "judge" || $1 == "goal" { print $1 "\t" $2 }' "$1" | sort | cksum | cut -d' ' -f1; }

print_flag() { # print_flag <scan file>
  echo "SUCCESS-CRITERION FLAG — this branch changed code AND what judges it (or its goal); the lead rules on it:"
  awk -F'\t' '$1 == "judge" { print "  judging file: " $2 "  (" $3 ")" } $1 == "goal" { print "  goal: " $2 }' "$1"
  echo "  code files changed with them: $(awk -F'\t' '$1 == "code" { n++ } END { print n + 0 }' "$1")"
}
print_section() { # print_section <scan file> — for the sub-session's --summary file, so the reviewer is asked to look
  echo "## Success-criterion check (this branch changed code AND what judges it)"
  echo "One session changed code and the tests, gates, floors or goal text that decide whether that code passes. In a"
  echo "multi-agent study (MASS, arXiv 2610.12176) an episode that changed the meaning of success still got 5 of 6"
  echo "favourable judgements. For each file below: if the change WEAKENS the criterion (an assertion removed or loosened,"
  echo "a skip added, a floor lowered, a baseline or allow-list grown, the goal or proof reworded), report it as a finding."
  awk -F'\t' '$1 == "judge" { print "- " $2 "  (" $3 ")" } $1 == "goal" { print "- goal: " $2 }' "$1"
  echo
}

# ── the answer ──────────────────────────────────────────────────────────────────────────────────────────────────────
answer_path() { echo "${CTW_STATE:-$GITDIR/check-the-work}/criterion-answer"; }
# The stored text when it exists AND was given for exactly this flag; empty otherwise (a stale answer is no answer).
read_answer() { # read_answer <fingerprint>
  local f line
  f="$(answer_path)"; [ -f "$f" ] || return 0
  line="$(head -1 "$f")"
  [ "$(printf '%s' "$line" | cut -f1)" = "v1" ] || return 0
  [ "$(printf '%s' "$line" | cut -f2)" = "$1" ] || return 0
  printf '%s' "$line" | cut -f3-
}

# ── the self-proof ──────────────────────────────────────────────────────────────────────────────────────────────────
# The classifier, the flag rule and the skip counter on known answers, then the whole scan (both modes) on a throwaway
# repository with a known positive and a known negative: a "no flag" from a rotted pattern or a git call that quietly
# prints nothing is exactly what rules/scripts.md 1 forbids.
selfproof() {
  local p want got bad="" t n
  for p in "src/a/b.go code" "src/a/b_test.go judge" "scripts/check-x.sh judge" "scripts/coverage-floors.txt judge" \
           "scripts/heavy-run-test.sh judge" "docs/a.md other" "go.sum other" "scripts/heavy-run.sh code" "lib2/Tests/A.txt judge" \
           "evals/cases.jsonl judge" "scripts/stacks/x.conf judge"; do
    # the operator's glob lists are blanked for the proof: a broad pattern in them ("scripts/*") is the operator's choice and
    # must not turn a correct classifier into a failed proof (the proof asks about the fixed rules)
    want="${p##* }"; got="$(CHECK_THE_WORK_LAST="" CHECK_THE_WORK_JUDGE_GLOBS="" HARNESS_JUDGE_GLOBS="" HARNESS_TEST_GLOBS="" criterion_class "${p% *}")"
    [ "$got" = "$want" ] || bad="$bad ${p% *}=$got(want $want)"
  done
  mk_tmp
  t="$TMPD/proof.scan"
  printf 'code\tx.go\njudge\tx_test.go\t+1 -0\n' > "$t";   flag_up "$t" || bad="$bad flag(code+judge)=down"
  printf 'code\tx.go\n' > "$t";                             ! flag_up "$t" || bad="$bad flag(code only)=up"
  printf 'judge\tx_test.go\t+1 -0\n' > "$t";                ! flag_up "$t" || bad="$bad flag(judge only)=up"
  printf 'goal\tchanged\n' > "$t";                          flag_up "$t" || bad="$bad flag(goal)=down"
  # header lines are not hunk lines; a removed skip, sys.exit(1) and plain code are no marker; an added "++" line still counts
  n="$(printf '%s\n' '--- a/x' '+++ b/x' '@@ -1,2 +1,4 @@' '+	t.Skip("x")' '+ ok' '-	t.Skip("old")' '+	sys.exit(1)' | skip_count)"
  [ "$n" = "1" ] || bad="$bad skip_count=$n(want 1)"
  n="$(printf '%s\n' '--- a/x' '+++ b/x' '@@ -1 +1,2 @@' '+++n; t.Skip(1)' '+	xit("later")' | skip_count)"
  [ "$n" = "2" ] || bad="$bad skip_count(++ line, xit)=$n(want 2)"
  [ -z "$bad" ] || { echo "$SELF: INCOMPLETE — the success-criterion detector failed its known-answer proof:$bad" >&2; return 3; }
  selfproof_scan || return 3
  return 0
}
# The throwaway-repository half of the proof, in a function so ROOT can be set for the call only (a subshell would hide
# its exit status behind a pipe, and a failed assignment of ROOT would leak into the real run).
proof_body() { # proof_body <repo> <scan out> <base sha>
  local d="$1" out="$2" base="$3" head1
  # known negative: a docs-only change must NOT flag
  printf 'y\n' >> "$d/docs/n.md"
  scan_to "$out" "$base" "" "" "" || return 3
  if flag_up "$out"; then echo "docs-only change flagged"; return 1; fi
  # known positive, work-tree mode: code + test (a line removed, a skip added) + a new untracked test with a skip
  printf 'package a // changed\n' > "$d/pkg/a.go"
  printf 'a\n\tt.Skip("later")\n' > "$d/pkg/a_test.go"
  printf 'z\n\tt.Skip("new")\n' > "$d/pkg/new_test.go"
  scan_to "$out" "$base" "" "" "" || return 3
  flag_up "$out" || { echo "code+test change not flagged"; return 1; }
  grep -q "judge	pkg/a_test.go	.*LINES-REMOVED.*SKIP-MARKERS-ADDED:1" "$out" || { echo "a_test.go signals wrong: $(cat "$out")"; return 1; }
  grep -q "judge	pkg/new_test.go	.*SKIP-MARKERS-ADDED:1" "$out" || { echo "untracked new_test.go signals wrong"; return 1; }
  # known positive, commits mode
  git -C "$d" add pkg/a.go pkg/a_test.go pkg/new_test.go docs/n.md
  git -C "$d" -c core.hooksPath=/dev/null -c user.name=proof -c user.email=proof@example.invalid -c commit.gpgsign=false commit -q -m work
  head1="$(git -C "$d" rev-parse HEAD)"
  scan_to "$out" "$base" "$head1" "" "" || return 3
  flag_up "$out" || { echo "committed code+test change not flagged"; return 1; }
  grep -q "judge	pkg/a_test.go	.*LINES-REMOVED" "$out" || { echo "committed a_test.go signals wrong"; return 1; }
  return 0
}
selfproof_scan() {
  local d out base rc bad="" gc="git -c core.hooksPath=/dev/null -c user.name=proof -c user.email=proof@example.invalid -c commit.gpgsign=false"
  d="$TMPD/proofrepo"; out="$TMPD/proofrepo.scan"
  (
    set -e
    mkdir -p "$d/pkg" "$d/docs"
    cd "$d"
    $gc init -q -b main . >/dev/null 2>&1 || $gc init -q . >/dev/null 2>&1
    printf 'package a\n' > pkg/a.go
    printf 'a\nb\n' > pkg/a_test.go
    printf 'x\n' > docs/n.md
    $gc add pkg/a.go pkg/a_test.go docs/n.md
    $gc commit -q -m base
    $gc branch -q -M main 2>/dev/null || :
  ) >/dev/null 2>&1 || { echo "$SELF: INCOMPLETE — the self-proof could not build its throwaway repository" >&2; return 3; }
  base="$(git -C "$d" rev-parse HEAD 2>/dev/null)" || { echo "$SELF: INCOMPLETE — self-proof repository has no commit" >&2; return 3; }
  CHECK_THE_WORK_LAST="" CHECK_THE_WORK_JUDGE_GLOBS="" HARNESS_JUDGE_GLOBS="" HARNESS_TEST_GLOBS="" ROOT="$d" proof_body "$d" "$out" "$base" > "$TMPD/proof.msg" 2>&1
  rc=$?
  bad="$(head -5 "$TMPD/proof.msg")"
  # the exit status decides (not an empty message: a subshell that died silently must not read as a pass)
  [ "$rc" -eq 0 ] || { [ -n "$bad" ] || bad="exit $rc without a message"; echo "$SELF: INCOMPLETE — the scan failed its known-answer proof on a throwaway repository: $bad" >&2; return 3; }
  rm -rf -- "$d"
  return 0
}

# ── commands ────────────────────────────────────────────────────────────────────────────────────────────────────────
usage() {
  cat >&2 <<'EOF'
usage: 10-success-criterion.sh scan [--base REF] [--goal FILE] [--section]
       10-success-criterion.sh answer --text "<who wrote the judging files (agent, model) and why no criterion was weakened>"
       10-success-criterion.sh judge | verify        (hook calls of scripts/check-the-work.sh; env CTW_*)
EOF
}

main_base() { # main_base <ref> -> the merge base of <ref> and HEAD, or exit 3
  local ref="$1" mb
  G rev-parse --verify --quiet "$ref^{commit}" >/dev/null || die "base '$ref' is not a commit here" 3
  mb="$(G merge-base "$ref" HEAD 2>/dev/null)" || die "no merge base between '$ref' and HEAD" 3
  printf '%s' "$mb"
}

cmd_scan() {
  local ref="main" gf="" only_section=0 mb out
  while [ $# -gt 0 ]; do
    case "$1" in
      --base) ref="${2-}"; shift 2 || die "--base needs a ref" ;;
      --goal) gf="${2-}"; shift 2 || die "--goal needs a file" ;;
      --section) only_section=1; shift ;;
      *) usage; exit 1 ;;
    esac
  done
  # a mistyped --goal path must not switch the goal comparison off without a word
  # (an existing but EMPTY file is a legitimate "no goal text to compare" and is accepted; only a path that is no readable file is refused)
  if [ -n "$gf" ] && { [ ! -f "$gf" ] || [ ! -r "$gf" ]; }; then die "--goal file not found or not readable: $gf" 1; fi
  need_repo; selfproof || exit 3
  mb="$(main_base "$ref")" || exit 3
  out="$TMPD/scan.out"
  scan_to "$out" "$mb" "" "$GITDIR/session-state.txt" "$gf" || die "the scan could not read the repository's changes" 3
  if flag_up "$out"; then
    if [ "$only_section" -eq 1 ]; then print_section "$out"; exit 0; fi
    print_flag "$out"; echo
    echo "Append this section to your --summary file (or: $0 scan --section >> <summary>), then, before 'judge':"
    echo "  $0 answer --text \"<who wrote the judging files (agent, model) and why no criterion was weakened>\""
    echo
    print_section "$out"
  else
    [ "$only_section" -eq 1 ] || echo "no success-criterion flag (code and what judges it were not changed together, goal not replaced; base $(printf '%s' "$mb" | cut -c1-7))"
  fi
  exit 0
}

cmd_answer() {
  local text="" ref="" mb out fp clean
  while [ $# -gt 0 ]; do
    case "$1" in
      --text) text="${2-}"; shift 2 || die "--text needs the answer" ;;
      --base) ref="${2-}"; shift 2 || die "--base needs a ref" ;;
      *) usage; exit 1 ;;
    esac
  done
  # one line: tabs and line breaks are the file's separators
  clean="$(printf '%s' "$text" | tr '\t\r\n' '   ' | tr -s ' ' | sed 's/^ //; s/ $//')"
  [ -n "$clean" ] || die "the answer is empty: say who wrote the judging files (agent, model) and why no criterion was weakened" 1
  [ "${#clean}" -ge "$MIN_ANSWER_CHARS" ] || die "the answer is too short (under $MIN_ANSWER_CHARS characters): say who wrote the judging files (agent, model) and why no criterion was weakened" 1
  need_repo; selfproof || exit 3
  if [ -n "$ref" ]; then mb="$(main_base "$ref")" || exit 3
  elif [ -s "${CTW_STATE:-$GITDIR/check-the-work}/base" ]; then mb="$(cat "${CTW_STATE:-$GITDIR/check-the-work}/base")"   # the base 'run' used
  else mb="$(main_base main)" || exit 3; fi
  out="$TMPD/scan.out"
  # the goal file `run` stored: judge compares it too, so the answer must be bound to the same flag (a goal line in it)
  scan_to "$out" "$mb" "" "$GITDIR/session-state.txt" "${CTW_STATE:-$GITDIR/check-the-work}/goal.md" || die "the scan could not read the repository's changes" 3
  if ! flag_up "$out"; then echo "no success-criterion flag is up: no answer is needed (nothing stored)"; exit 0; fi
  fp="$(fingerprint "$out")"
  mkdir -p "$(dirname "$(answer_path)")" || die "cannot create the state folder" 3
  if ! { printf 'v1\t%s\t%s\n' "$fp" "$clean" > "$(answer_path).tmp.$$" && mv -f "$(answer_path).tmp.$$" "$(answer_path)"; }; then die "cannot store the answer" 3; fi
  echo "answer stored for $(awk -F'\t' '$1 == "judge" { n++ } END { print n + 0 }' "$out") judging file(s) at $(answer_path)"
  exit 0
}

cmd_judge() {
  local st base branch out fp ans rc
  need_repo; selfproof || exit 3
  st="${CTW_STATE:-$GITDIR/check-the-work}"
  [ -s "$st/base" ] || die "no merge base in $st/base: 'check-the-work.sh run' has not been run here" 3
  base="$(cat "$st/base")"
  G rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "the stored base '$base' is not a commit here" 3
  branch="${CTW_BRANCH:-$(cat "$st/branch" 2>/dev/null)}"
  [ -n "$branch" ] || branch="$(G symbolic-ref --quiet --short HEAD 2>/dev/null || echo detached)"
  out="$TMPD/scan.out"
  scan_to "$out" "$base" "" "$GITDIR/session-state.txt" "$st/goal.md" || die "the scan could not read the repository's changes" 3
  if ! flag_up "$out"; then echo "no success-criterion flag (code and what judges it were not changed together, goal not replaced)"; exit 0; fi
  print_flag "$out"
  fp="$(fingerprint "$out")"
  ans="$(read_answer "$fp")"
  if [ -z "$ans" ]; then
    echo "$SELF: the judgement is NOT logged: this branch changed code and what judges it, and no answer is stored for these files." >&2
    if [ -f "$(answer_path)" ]; then echo "  (an answer exists but was given for another set of judging files: answer again)" >&2; fi
    echo "  Run: $0 answer --text \"<who wrote the judging files (agent, model) and why no criterion was weakened>\"" >&2
    echo "  then judge again. The lead rules on the answer at the merge." >&2
    exit 1
  fi
  CRIT_SCAN="$out" CRIT_ANSWER="$ans" CRIT_BRANCH="$branch" CRIT_BASE="$base" CRIT_LOG="$ROOT/$CRITERION_LOG_REL" \
    python3 -I - <<'PY'
import json, os, sys, datetime
scan = [l.rstrip("\n").split("\t") for l in open(os.environ["CRIT_SCAN"], encoding="utf-8", errors="replace") if l.strip()]
flag = {"code": [c[1] for c in scan if c[0] == "code"],
        "judging": [{"path": c[1], "signals": c[2] if len(c) > 2 else ""} for c in scan if c[0] == "judge"],
        "goal": [c[1] for c in scan if c[0] == "goal"]}
row = {"date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "branch": os.environ["CRIT_BRANCH"],
       "base": os.environ["CRIT_BASE"], "flag": flag, "answer": os.environ["CRIT_ANSWER"]}
log = os.environ["CRIT_LOG"]
os.makedirs(os.path.dirname(log), exist_ok=True)
last = None
prefix = ""
if os.path.exists(log):
    data = open(log, "rb").read()
    if data and not data.endswith(b"\n"):
        prefix = "\n"
    for line in data.decode("utf-8", "replace").splitlines():
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if isinstance(r, dict) and r.get("branch") == row["branch"]:
            last = r
# running judge twice on the same work must not stack identical rows
if last is not None and all(last.get(k) == row[k] for k in ("base", "flag", "answer")):
    print("success-criterion: row already recorded for this branch (unchanged flag and answer)")
    sys.exit(0)
with open(log, "a", encoding="utf-8") as f:
    f.write(prefix + json.dumps(row, ensure_ascii=False) + "\n")
print("success-criterion: row appended to " + log + " — commit it WITH the work")
PY
  rc=$?
  [ "$rc" -eq 0 ] || die "could not write the criterion row (python3 exit $rc)" 3
  exit 0
}

cmd_verify() {
  local br base tip mb wt sf out rows fp covered uncovered p row_date row_answer found=0 goal_cov=0
  need_repo; selfproof || exit 3
  command -v python3 >/dev/null 2>&1 || die "python3 is missing — cannot read the criterion rows" 3
  br="${CTW_BRANCH:-}"
  [ -n "$br" ] || br="$(G symbolic-ref --quiet --short HEAD 2>/dev/null)" || die "no CTW_BRANCH and a detached HEAD: name the branch" 3
  base="${CTW_BASE:-main}"; tip="$br"
  G rev-parse --verify --quiet "$tip^{commit}" >/dev/null || die "branch '$br' is not a commit here" 3
  mb="$(G merge-base "$base" "$tip" 2>/dev/null)" || die "no merge base between '$base' and '$br'" 3
  # the branch's own state record lives in ITS worktree's git folder (the lead runs verify from the main checkout)
  wt="$(G worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$br" '/^worktree / { w = substr($0, 10) } $0 == "branch " b { print w; exit }')"
  sf=""
  if [ -n "$wt" ]; then sf="$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)/session-state.txt"; fi
  [ -n "$sf" ] || echo "success-criterion: goal check NOT DONE — no worktree has '$br' checked out, so its session-state record cannot be read"
  out="$TMPD/scan.out"
  scan_to "$out" "$mb" "$tip" "$sf" "" || die "the scan could not read the branch's commits" 3
  if ! flag_up "$out"; then echo "success-criterion: no success-criterion flag on $br (code and what judges it were not changed together in its commits, goal not replaced)"; exit 0; fi
  print_flag "$out"
  rows="$(G diff --no-ext-diff --no-color "$mb" "$tip" -- "$CRITERION_LOG_REL" 2>/dev/null | sed -n 's/^+{/{/p')"
  covered="$TMPD/covered"; : > "$covered"
  if [ -n "$rows" ]; then
    # the LAST row this branch added; prints ROW<TAB>date<TAB>answer, COVERED<TAB>path, and GOAL when the row flagged the goal
    printf '%s\n' "$rows" > "$TMPD/rows.json"
    CRIT_BRANCH="$br" CRIT_ROWS="$TMPD/rows.json" python3 -I - > "$TMPD/rowinfo" <<'PY' || die "could not read the criterion rows" 3
import json, os, sys
last = None
for line in open(os.environ["CRIT_ROWS"], encoding="utf-8", errors="replace"):
    try: r = json.loads(line)
    except ValueError: continue
    if isinstance(r, dict) and r.get("branch") == os.environ["CRIT_BRANCH"] and isinstance(r.get("answer"), str) and r["answer"].strip():
        last = r
if last is None:
    sys.exit(0)
print("ROW\t%s\t%s" % (last.get("date", "?"), " ".join(last["answer"].split())))
fl = last.get("flag") or {}
for j in fl.get("judging") or []:
    if isinstance(j, dict) and isinstance(j.get("path"), str): print("COVERED\t" + j["path"])
if fl.get("goal"): print("GOAL")
PY
    row_date="$(awk -F'\t' '$1 == "ROW" { print $2; exit }' "$TMPD/rowinfo")"
    row_answer="$(awk -F'\t' '$1 == "ROW" { print $3; exit }' "$TMPD/rowinfo")"
    awk -F'\t' '$1 == "COVERED" { print $2 }' "$TMPD/rowinfo" > "$covered"
    if awk -F'\t' '$1 == "GOAL" { n++ } END { exit n ? 0 : 1 }' "$TMPD/rowinfo"; then goal_cov=1; fi
    [ -z "$row_answer" ] || found=1
  fi
  if [ "$found" -eq 0 ]; then
    echo "$SELF: verify FAIL — the flag is up and the branch adds no answered row to $CRITERION_LOG_REL: the success-criterion step was skipped" >&2
    exit 1
  fi
  echo "  CRITERION answer of the sub-session ($row_date): $row_answer"
  uncovered=""
  while IFS=$'\t' read -r kind p _; do
    [ "$kind" = "judge" ] || continue
    grep -qxF -- "$p" "$covered" || uncovered="$uncovered $p"
  done < "$out"
  [ -z "$uncovered" ] || echo "  WARNING: judging files changed on the branch that the answer's row did not list (changed after the answer?):$uncovered"
  if awk -F'\t' '$1 == "goal" { n++ } END { exit n ? 0 : 1 }' "$out" && [ "$goal_cov" -eq 0 ]; then
    echo "  WARNING: the goal was replaced, and the answer's row did not list it"
  fi
  echo "  The lead rules: is the answer plausible, and were the judging files written by someone other than the code's author?"
  exit 0
}

stage="${1:-${CTW_STAGE:-}}"
[ $# -gt 0 ] && shift
case "$stage" in
  scan) cmd_scan "$@" ;;
  answer) cmd_answer "$@" ;;
  judge) cmd_judge ;;
  verify) cmd_verify ;;
  "")
    # no command: the way a gate self-proof runner calls a check script. Prove the detector, then show usage.
    selfproof || exit 3
    echo "self-proof: OK (classifier on 11 known paths, flag rule on 4 cases, skip counter, and the scan on a throwaway repository in both modes)"
    usage; exit 1 ;;
  *) usage; exit 1 ;;
esac
