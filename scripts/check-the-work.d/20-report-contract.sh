#!/usr/bin/env bash
# scripts/check-the-work.d/20-report-contract.sh — hook of scripts/check-the-work.sh (S2 of docs/ci/session-resilience.md):
# checks that a sub-session's FINAL report meets the fixed-field contract of scripts/lib/report-contract.sh (COMMITS, GATES,
# BUGS, DEFERRED, QUESTIONS) and that every commit id it names is a commit in this repository.
#
# WHY (MASS study of multi-agent self-supervision, arXiv 2610.12176): output contracts carried most of the gains; a
# free-text "done" makes the next hop (the lead's merge) re-derive the commits, the raw gate lines, the bug ids and the open
# questions, and in the first adopting project three dead sessions in one day left no usable report at all. One copy of the
# contract (the lib) is used here and by anything else that flags a report, so they cannot disagree.
#
# Usage:
#   20-report-contract.sh --file <report>
#         by hand: by the sub-session BEFORE it sends its FINAL report, and by the lead. Exit 0 OK · 1 refused (each problem
#         printed) · 4 not a FINAL report (INTERIM / QUESTION are not checked; an empty file is not FINAL) · 3 could not run
#         (the file is missing, the lib is missing, or the checker failed its known-answer proof).
#   20-report-contract.sh judge     hook: exit 4 with one line — the FINAL report is written AFTER the commit, so it cannot
#         exist yet when the judgement is logged.
#   20-report-contract.sh verify    hook, for the lead at the merge: the report is CTW_REPORT (a file), else the newest file
#         in HARNESS_REPORT_DIR (a folder, up to 3 levels deep) whose first non-blank line starts with FINAL and whose text names
#         CTW_BRANCH as a whole word. None found -> prints "NOT CHECKED" and exits 4: a skip said loudly, never a pass.
#         Found -> the same check as --file, but a refusal exits 1 (the merge stops).
#   (no argument)                   runs the self-proof, prints usage, exit 1.
# Env of the hook calls: CTW_STAGE, CTW_ROOT (the repository the commit ids are looked up in; by hand: the current one),
#   CTW_BRANCH, CTW_REPORT, HARNESS_REPORT_DIR (set it in the environment or in harness.conf; empty = no folder to search, so
#   verify says NOT CHECKED unless CTW_REPORT names the file) and HARNESS_BUG_PREFIX (the BUGS field's id prefix; default BUG,
#   SEC always allowed). The environment wins over harness.conf (the others of the check-the-work hook design are not used here).
# Exit vocabulary: 0 pass · 1 fail · 3 could not run · 4 not applicable / not checked. Bash 3.2 compatible.
# Blast radius: read-only (reads the report files and asks git); one scratch folder under $TMPDIR for the lib's self-proof
#   (made and removed by the lib). Deletes nothing else.
# Tests: scripts/ctw-report-contract-test.sh (written by an author other than this script's builder).
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# A report is a page or two of text; a bigger file in a report folder is not one, and the discovery
# loop must not read a build artefact or a log dump looking for FINAL.
MAX_REPORT_KB=1000
SELF="20-report-contract"

HERE="$(cd "$(dirname "$0")" && pwd)" || { echo "$SELF: cannot find its own folder" >&2; exit 3; }
die() { echo "$SELF: $1" >&2; exit "${2:-1}"; }

load_lib() {
  local c
  for c in "$HERE/../lib/report-contract.sh" "${CTW_ROOT:+$CTW_ROOT/scripts/lib/report-contract.sh}"; do
    [ -n "$c" ] && [ -f "$c" ] || continue
    # shellcheck source=../lib/report-contract.sh
    . "$c" && return 0
  done
  echo "$SELF: scripts/lib/report-contract.sh is missing — install it; no report was checked" >&2
  return 3
}

# harness.conf, the way the kit's other hooks read it: the generic stack pack as the base, the named pack on top, then the
# project's harness.conf (so it wins). The three knobs this hook reads are put back from the ENVIRONMENT afterwards, so a
# caller (or a test) that sets one explicitly is not undone by a file. Needs ROOT.
load_conf() {
  local k v pack saved="" cfg="$ROOT/harness.conf"
  for k in HARNESS_REPORT_DIR HARNESS_BUG_PREFIX; do
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
  HARNESS_REPORT_DIR="${HARNESS_REPORT_DIR:-}"
}

ROOT=""
need_repo() {
  [ -z "$ROOT" ] || return 0
  if [ -n "${CTW_ROOT:-}" ]; then ROOT="$CTW_ROOT"; else ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""; fi
  [ -n "$ROOT" ] && [ -d "$ROOT" ] || { ROOT=""; die "not inside a git work tree (set CTW_ROOT)" 3; }
  load_conf
}

# Two controls for the commit lookup, so "every sha is a commit" cannot pass because git quietly answers yes (or no) to all:
# a made-up id must NOT be a commit, and this repository's own HEAD must be one.
commit_lookup_selfproof() {
  local head1
  if git -C "$ROOT" cat-file -e "0000000000000000000000000000000000000000^{commit}" 2>/dev/null; then
    echo "$SELF: INCOMPLETE — the commit lookup accepted a made-up id; no report was checked" >&2; return 3
  fi
  head1="$(git -C "$ROOT" rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null)" \
    || { echo "$SELF: INCOMPLETE — $ROOT has no commit to prove the commit lookup on; no report was checked" >&2; return 3; }
  git -C "$ROOT" cat-file -e "$head1^{commit}" 2>/dev/null \
    || { echo "$SELF: INCOMPLETE — the commit lookup refused HEAD; no report was checked" >&2; return 3; }
  return 0
}

# check_report <file> <exit code for a refusal> — 0 OK, <refusal code> problems, 4 not FINAL, 3 could not run
check_report() {
  local f="$1" refuse="$2" probs sha n=0 shas
  [ -f "$f" ] || { echo "$SELF: report file not found: $f" >&2; return 3; }
  # unreadable is "could not run", not "not a FINAL report": exit 4 would let the merge go on past a report nobody read
  [ -r "$f" ] || { echo "$SELF: report file is not readable: $f" >&2; return 3; }
  load_lib || return 3
  report_contract_selfproof || { echo "$SELF: INCOMPLETE — the report-contract checker failed its own known-answer proof" >&2; return 3; }
  report_is_final "$f" || {
    echo "report contract: NOT CHECKED — $f is not a FINAL report (first line: $(awk 'NF { print; exit }' "$f" 2>/dev/null | cut -c1-60)); the contract applies to FINAL reports only"
    return 4
  }
  need_repo
  probs="$(report_contract_problems "$f")"
  shas="$(report_commit_shas "$f")"
  if [ -n "$shas" ]; then commit_lookup_selfproof || return 3; fi
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    n=$((n + 1))
    git -C "$ROOT" cat-file -e "$sha^{commit}" 2>/dev/null || probs="$probs${probs:+
}COMMITS: $sha is not a commit in this repository"
  done <<EOF_SHAS
$shas
EOF_SHAS
  if [ -n "$probs" ]; then
    echo "report contract: REFUSED — $f breaks the contract (scripts/lib/report-contract.sh):"
    printf '%s\n' "$probs" | sed 's/^/  /'
    return "$refuse"
  fi
  echo "report contract: OK — $f (COMMITS, GATES, BUGS, DEFERRED, QUESTIONS present; $n commit id(s), each a commit in $ROOT)"
  return 0
}

# names_branch <file> <branch> — the branch appears as a WHOLE word: not glued to a letter, digit, "_", "/" or "-" on either
# side ("feat/a" must not match "feat/a-2" or "x/feat/a"), and not followed by "." plus a letter or digit ("feat/a.b" is another
# name; the same rule as the sub-session status scan's notes match). A trailing "." or "," at the end of a sentence still matches.
names_branch() {
  BR="$2" awk '
    BEGIN { b = ENVIRON["BR"]; n = length(b); w = "[A-Za-z0-9_/-]" }
    { pos = 1
      while (n > 0 && (i = index(substr($0, pos), b)) > 0) {
        i += pos - 1
        before = (i > 1) ? substr($0, i - 1, 1) : ""
        after = substr($0, i + n, 1)
        after2 = substr($0, i + n + 1, 1)
        if (before !~ w && after !~ w && !(after == "." && after2 ~ "[A-Za-z0-9]")) { found = 1; exit }
        pos = i + 1
      } }
    END { exit found ? 0 : 1 }' "$1" 2>/dev/null
}

# The newest FINAL report under <dir> that names <branch>; prints its path (nothing when none).
find_report() { # find_report <dir> <branch>
  local dir="$1" br="$2" f best=""
  load_lib || return 3
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -r "$f" ] || continue
    report_is_final "$f" || continue
    names_branch "$f" "$br" || continue
    # newest wins; the list is sorted first so the result never depends on the order find lists in; mtimes have one-second resolution here, so a tie goes to the later name (deterministic, not find order)
    if [ -z "$best" ] || [ "$f" -nt "$best" ] || { ! [ "$best" -nt "$f" ] && [[ "$f" > "$best" ]]; }; then best="$f"; fi
  done <<EOF_FIND
$(find "$dir" -maxdepth 3 -type f -size -"${MAX_REPORT_KB}"k 2>/dev/null | LC_ALL=C sort)
EOF_FIND
  [ -z "$best" ] || printf '%s\n' "$best"
}

# The detector proves itself before it may say "no FINAL report found" or "OK": the whole-word matcher on known answers.
selfproof() {
  local d t bad=""
  load_lib || return 3
  report_contract_selfproof || { echo "$SELF: INCOMPLETE — the report-contract checker failed its own known-answer proof" >&2; return 3; }
  d="$(mktemp -d "${TMPDIR:-/tmp}/ctw-report.XXXXXX")" || { echo "$SELF: no temp folder" >&2; return 3; }
  t="$d/r"
  printf 'FINAL — DONE\nbranch feat/a-b merged\nfeat/a.\n' > "$t"
  names_branch "$t" "feat/a" || bad="$bad whole-word(feat/a. matched=no)"
  printf 'FINAL — DONE\nbranch feat/a-b merged\nx/feat/a\nfeat/ab\nfeat/a.b\n' > "$t"
  ! names_branch "$t" "feat/a" || bad="$bad whole-word(feat/a-b|x/feat/a|feat/ab|feat/a.b matched=yes)"
  mkdir -p "$d/sub/deeper"
  printf 'FINAL — DONE\non dev/x\n' > "$d/sub/deeper/new.md"
  printf 'INTERIM — on dev/x\n' > "$d/sub/old.md"
  [ "$(find_report "$d" "dev/x")" = "$d/sub/deeper/new.md" ] || bad="$bad discovery(FINAL naming the branch, 3 levels deep, not found or INTERIM picked)"
  # newest wins: explicit mtimes (touch -t), never "touched a moment ago"; and an equal-second tie goes to the later name
  printf 'FINAL — DONE\non dev/y\n' > "$d/sub/a-old.md"; printf 'FINAL — DONE\non dev/y\n' > "$d/sub/b-new.md"
  touch -t 202001010101 "$d/sub/b-new.md"; touch -t 202101010101 "$d/sub/a-old.md"
  [ "$(find_report "$d" "dev/y")" = "$d/sub/a-old.md" ] || bad="$bad discovery(the file with the newer mtime must win)"
  touch -t 202201010101 "$d/sub/b-new.md" "$d/sub/a-old.md"
  [ "$(find_report "$d" "dev/y")" = "$d/sub/b-new.md" ] || bad="$bad discovery(an mtime tie must go to the later name)"
  [ -z "$(find_report "$d" "dev/other")" ] || bad="$bad discovery(a report for another branch found)"
  rm -rf -- "$d"
  [ -z "$bad" ] || { echo "$SELF: INCOMPLETE — the report finder failed its known-answer proof:$bad" >&2; return 3; }
  return 0
}

usage() {
  cat >&2 <<'EOF'
usage: 20-report-contract.sh --file <FINAL report>
       20-report-contract.sh judge | verify        (hook calls of scripts/check-the-work.sh; env CTW_*, CTW_REPORT, HARNESS_REPORT_DIR)
EOF
}

stage="${1:-${CTW_STAGE:-}}"
[ $# -gt 0 ] && shift
case "$stage" in
  judge)
    echo "report contract: checked at verify (the FINAL report is written after the commit)"
    exit 4 ;;
  --file)
    [ $# -ge 1 ] && [ -n "$1" ] || { usage; exit 1; }
    f="$1"
    check_report "$f" 1; exit $? ;;
  verify)
    selfproof || exit 3
    need_repo
    report=""
    if [ -n "${CTW_REPORT:-}" ]; then
      [ -f "$CTW_REPORT" ] || die "CTW_REPORT is set but is not a file: $CTW_REPORT" 3
      report="$CTW_REPORT"
    elif [ -n "${HARNESS_REPORT_DIR:-}" ]; then
      [ -d "$HARNESS_REPORT_DIR" ] || die "HARNESS_REPORT_DIR is set but is not a folder: $HARNESS_REPORT_DIR" 3
      br="${CTW_BRANCH:-}"
      [ -n "$br" ] || br="$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null)" || die "no CTW_BRANCH and a detached HEAD: cannot tell which report is this branch's" 3
      report="$(find_report "$HARNESS_REPORT_DIR" "$br")" || exit 3
    fi
    if [ -z "$report" ]; then
      echo "report contract: NOT CHECKED — no FINAL report found (set CTW_REPORT or HARNESS_REPORT_DIR)"
      exit 4
    fi
    check_report "$report" 1; exit $? ;;
  "")
    selfproof || exit 3
    echo "self-proof: OK (report-contract known answers, commit-lookup controls run per report, whole-word branch match, report discovery)"
    usage; exit 1 ;;
  *) usage; exit 1 ;;
esac
