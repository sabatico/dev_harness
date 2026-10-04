#!/usr/bin/env bash
# librarian-sweep-test.sh — acceptance matrix for scripts/librarian-sweep.sh (the v1.3 additions).
#
# Pins: the last surface "everything else in the repo" finds a hit in a folder no named surface covers
# and prints "hits by folder"; files a named surface already enumerated are NOT searched again there;
# .gitignore'd files are never searched; "0 file(s) left" when the named surfaces covered the whole
# repo; the surface is ⚠ ABSENT (and counted) outside a git repo; a per-surface cap says TRUNCATED;
# over-long lines carry "…[cut]"; the history pickaxe runs once PER TERM.
# Every "must not appear" row has a sibling proving the same machinery DOES find something (T2).
#
# Runs against throwaway git repos under a temp dir, each with its OWN harness.conf (the sweep sources
# it), and with every HARNESS_* / SWEEP_CAP variable unset, so the caller's environment cannot steer it.
# Cross-authored 2026-10-03 by a test author who did not build librarian-sweep.sh. Cases the sweep
# currently gets WRONG are not rows; they went to the lead in the test author's report.
# Usage: scripts/librarian-sweep-test.sh [path/to/librarian-sweep.sh]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SWEEP="${1:-$HERE/librarian-sweep.sh}"
[ -f "$SWEEP" ] || { echo "no librarian-sweep.sh at $SWEEP" >&2; exit 2; }
SWEEP="$(cd "$(dirname "$SWEEP")" && pwd)/$(basename "$SWEEP")"
T=$(mktemp -d "${TMPDIR:-/tmp}/sweep-test.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
for v in $(env | sed -n 's/^\(HARNESS_[A-Z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset SWEEP_CAP
export GIT_CEILING_DIRECTORIES="$T"      # the non-git fixture must not find a repo above $T
P=0; F=0; S=0
ok()   { if [ "$2" = 0 ]; then P=$((P+1)); echo "  ok    $1"; else F=$((F+1)); echo "  FAIL  $1"; [ -n "${3:-}" ] && printf '        %s\n' "$3"; fi; }
skip() { S=$((S+1)); echo "  SKIP  $1 — $2 (unexercised: NOT a pass)"; }
run()  { OUT=$(cd "$1" && shift && env ${RUN_ENV:-} bash "$SWEEP" "$@" 2>"$T/err"); RC=$?; ERR=$(cat "$T/err"); }
has()  { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
# sect START END → the output lines strictly between the first line containing START and the next
# line containing END (fixed strings; ENVIRON, so no awk escape processing).
sect() { printf '%s\n' "$OUT" | S1="$1" S2="$2" awk 'f && index($0, ENVIRON["S2"]) { exit } f { print } index($0, ENVIRON["S1"]) { f = 1 }'; }
ELSE_HDR="── everything else in the repo"; HIST_HDR="── git history"
else_sect() { sect "$ELSE_HDR" "$HIST_HDR"; }
in_else()   { else_sect | grep -qF -- "$1"; }

# ---- fixture: every NAMED surface present (so ⚠ ABSENT = 0 in the repo), plus files only the
# catch-all can see: a notes/ tree, a CSV, a non-.md file inside docs/, a root file, an untracked file,
# an accented name; and .gitignore'd files that hold the term but must never be searched.
R="$T/repo"; mkdir -p "$R"; cd "$R" || exit 2
git init -q . && git config user.email t@t && git config user.name t
printf 'HARNESS_DOC_DIRS="docs"\nHARNESS_CODE_DIRS="src"\n' > harness.conf
printf 'ignored/\n*.log\n' > .gitignore
mkdir -p docs src scripts .claude/rules db api notes/sub data ignored
printf 'zorbic in a doc\n' > docs/a.md                      # named: docs/
printf 'id,zorbic csv in docs\n' > docs/table.csv           # docs/ folder, but NOT a .md → catch-all
printf '# readme zorbic\n' > README.md                      # named: root docs
printf 'x = 1  # zorbic\n' > src/a.py                       # named: code
printf 'echo zorbic\n' > scripts/s.sh                       # named: scripts/
printf 'rule zorbic\n' > .claude/rules/r.md                 # named: .claude
printf 'create table zorbic (id int);\n' > db/s.sql         # named: schema
printf 'openapi: zorbic\n' > api/openapi.yaml               # named: API contracts
printf 'note: zorbic ruling\n' > notes/sub/n.md
printf 'accented: zorbic\n' > 'notes/décision.md'
printf 'zorbic %0300d\n' 0 > notes/long.txt                  # hit line "notes/long.txt:1:…" is 324 chars
printf 'zorbic%0176d\n' 0 > notes/exact.txt                  # hit line "notes/exact.txt:1:…" is exactly 200
printf 'id,rule\n1,zorbic\n' > data/rulings.csv
printf 'root file zorbic\n' > top.txt
printf 'IGNORED zorbic\n' > ignored/secret.txt               # .gitignore'd folder
printf 'IGNORED zorbic\n' > debug.log                        # .gitignore'd pattern, at the root
git add -A && git commit -qm init
printf 'untracked zorbic\n' > notes/untracked.md             # never committed
# What the catch-all must see: git's file list minus what the named surfaces enumerated.
ELSE_FILES=10   # .gitignore harness.conf docs/table.csv notes/sub/n.md notes/décision.md notes/long.txt notes/exact.txt notes/untracked.md data/rulings.csv top.txt
ELSE_HITS=8     # all of those except .gitignore and harness.conf
NAMED_HITS=7    # docs/a.md README.md src/a.py scripts/s.sh .claude/rules/r.md db/s.sql api/openapi.yaml

echo "-- the catch-all surface finds what no named surface covers"
run "$R" zorbic
ok "exit 0 and the 'everything else' surface is printed" $([ $RC = 0 ] && has "$ELSE_HDR" && else_sect | grep -q '^  everything else '; echo $?) "rc=$RC $ERR"
ok "it enumerates exactly the $ELSE_FILES uncovered files and reports $ELSE_HITS hits" $(else_sect | grep -qE "^  everything else +$ELSE_HITS hit\(s\) in $ELSE_FILES file\(s\)"; echo $?) "$(else_sect | head -2)"
ok "a hit in notes/ (a folder no named surface names) is shown" $(in_else 'notes/sub/n.md:1:note: zorbic ruling'; echo $?)
ok "a hit in a .csv data file is shown" $(in_else 'data/rulings.csv:2:1,zorbic'; echo $?)
ok "a non-.md file INSIDE a named folder (docs/table.csv) is caught here" $(in_else 'docs/table.csv:1:'; echo $?)
ok "a repo-root file is caught" $(in_else 'top.txt:1:root file zorbic'; echo $?)
ok "an UNTRACKED file is caught" $(in_else 'notes/untracked.md:1:untracked zorbic'; echo $?)
ok "an accented file name is caught (core.quotePath=false)" $(in_else 'notes/décision.md:1:accented: zorbic'; echo $?)
ok "'hits by folder' is printed" $(in_else 'hits by folder'; echo $?)
BYF="$(sect 'hits by folder' "$HIST_HDR")"
ok "hits by folder: notes/ 5 · data/ 1 · docs/ 1 · (repo root) 1 — and nothing else" \
  $(printf '%s\n' "$BYF" | grep -qE '^ +5 notes/$' && printf '%s\n' "$BYF" | grep -qE '^ +1 data/$' && printf '%s\n' "$BYF" | grep -qE '^ +1 docs/$' && printf '%s\n' "$BYF" | grep -qE '^ +1 \(repo root\)$' && [ "$(printf '%s\n' "$BYF" | grep -c .)" = 4 ]; echo $?) "$BYF"
ok "hits by folder: the folder with most hits is first" $(printf '%s\n' "$BYF" | head -1 | grep -qE '^ +5 notes/$'; echo $?)

echo "-- no double counting with the named surfaces"
ok "control: docs/a.md IS reported, under its named surface 'docs: docs/'" $(sect 'docs: docs/' 'root docs' | grep -qF 'docs/a.md:1:zorbic in a doc'; echo $?)
ok "…and is NOT searched again by the catch-all" $(! in_else 'docs/a.md'; echo $?)
ok "no named-surface file (README, src, scripts, .claude, sql, openapi) appears in the catch-all" \
  $(! in_else 'README.md' && ! in_else 'src/a.py' && ! in_else 'scripts/s.sh' && ! in_else '.claude/rules' && ! in_else 'db/s.sql' && ! in_else 'api/openapi'; echo $?)
ok "TOTAL = named $NAMED_HITS + catch-all $ELSE_HITS = $((NAMED_HITS+ELSE_HITS)), ⚠ ABSENT 0" $(has "TOTAL: $((NAMED_HITS+ELSE_HITS)) hit(s) · ⚠ ABSENT surfaces: 0"; echo $?) "$(printf '%s\n' "$OUT" | grep TOTAL)"

echo "-- .gitignore'd files are never searched"
ok "fixture sanity: the ignored files really hold the term" $(grep -q zorbic ignored/secret.txt && grep -q zorbic debug.log; echo $?)
ok "ignored/secret.txt and debug.log appear NOWHERE in the sweep" $(! has 'ignored/secret.txt' && ! has 'debug.log' && ! has 'IGNORED zorbic'; echo $?)
ok "control: the identical text in a NON-ignored file is found (top.txt)" $(has 'top.txt:1:'; echo $?)

echo "-- over-long hit lines are cut, visibly"
LONG="$(else_sect | grep -F 'notes/long.txt:1:')"; LONG="${LONG#      }"
# cut_ok LINE → it ends with ' …[cut]' and what precedes the marker is exactly 200 chars (a function:
# bash 3.2 cannot parse a `case` pattern's ')' inside $( ).
cut_ok() { local t="${1% …\[cut\]}"; [ "$t" != "$1" ] && [ "${#t}" = 200 ]; }
ok "a 324-char hit line shows its first 200 chars + ' …[cut]'" $(cut_ok "$LONG"; echo $?) "len=${#LONG}: $(printf '%s' "$LONG" | cut -c1-50)…"
EXACT="$(else_sect | grep -F 'notes/exact.txt:1:')"; EXACT="${EXACT#      }"
ok "a hit line of exactly 200 chars is not cut" $([ "${#EXACT}" = 200 ] && ! printf '%s' "$EXACT" | grep -qF '[cut]'; echo $?) "len=${#EXACT}"

echo "-- a per-surface cap is never silent"
ok "default cap (8) with exactly 8 hits: no TRUNCATED" $(! else_sect | grep -q TRUNCATED; echo $?)
RUN_ENV="SWEEP_CAP=3" run "$R" zorbic
ok "SWEEP_CAP=3: the catch-all shows 3 hit lines" $([ "$(else_sect | grep -cE '^      [^ ].*:[0-9]+:')" = 3 ]; echo $?) "$(else_sect)"
ok "SWEEP_CAP=3: '… and 5 more — TRUNCATED (SWEEP_CAP=3)'" $(in_else "… and $((ELSE_HITS-3)) more — TRUNCATED (SWEEP_CAP=3)"; echo $?)
ok "SWEEP_CAP=3: hits by folder still counts ALL hits, not only the shown ones (notes/ 5)" $(sect 'hits by folder' "$HIST_HDR" | grep -qE '^ +5 notes/$'; echo $?)
ok "SWEEP_CAP=3: a named surface under the cap (docs: 1 hit) is not marked" $(! sect 'docs: docs/' 'root docs' | grep -q TRUNCATED; echo $?)
RUN_ENV="SWEEP_CAP=1" run "$R" ruling
ok "a cap equal to the hit count (1 = 1) is not TRUNCATED" $([ $RC = 0 ] && in_else 'notes/sub/n.md' && ! has TRUNCATED; echo $?) "$OUT"

echo "-- the git pickaxe runs once PER TERM"
printf 'q = "quillon"\n' > src/q.py && git add src/q.py && git commit -qm 'add the quillon rule'
run "$R" zorbic quillon nopenope
PICK_Z="$(sect "pickaxe -S 'zorbic'" "pickaxe -S 'quillon'")"
PICK_Q="$(sect "pickaxe -S 'quillon'" "pickaxe -S 'nopenope'")"
ok "pickaxe line printed for EVERY term (3)" $([ "$(printf '%s\n' "$OUT" | grep -c "pickaxe -S '")" = 3 ]; echo $?)
ok "term 1 (zorbic): its commit 'init' is listed" $(printf '%s\n' "$PICK_Z" | grep -qE '^      [0-9a-f]+ init$'; echo $?) "$PICK_Z"
ok "term 2 (quillon): ITS commit is listed — not only the first term's" $(printf '%s\n' "$PICK_Q" | grep -qE '^      [0-9a-f]+ add the quillon rule$' && ! printf '%s\n' "$PICK_Q" | grep -q ' init$'; echo $?) "$PICK_Q"
ok "term 3 with no history says '0 commits'" $(has "pickaxe -S 'nopenope' (bounded, newest 8) 0 commits"; echo $?)
ok "log --grep also runs per term (quillon: 1 commit)" $(printf '%s\n' "$OUT" | grep -qE "log --grep 'quillon' +1 commit"; echo $?)
git rm -q src/q.py && git commit -qm 'drop q'

echo "-- '0 file(s) left' when the named surfaces cover the whole repo"
R0="$T/covered"; mkdir -p "$R0/docs" "$R0/src"; (cd "$R0" && git init -q . && printf 'zorbic\n' > docs/a.md && printf 'zorbic\n' > README.md && printf '# zorbic\n' > src/a.py)
run "$R0" zorbic       # no harness.conf: defaults (docs/, src/ *.py, root *.md)
ok "every repo file covered → '0 file(s) left — the named surfaces covered the whole repo'" $([ $RC = 0 ] && else_sect | grep -qE '^  everything else +0 file\(s\) left — the named surfaces covered the whole repo'; echo $?) "$(else_sect)"
ok "…with no hit lines and no 'hits by folder' there" $(! in_else 'hits by folder' && ! else_sect | grep -q ':1:'; echo $?)
ok "control: the same files WERE searched by the named surfaces (3 hits)" $(has 'TOTAL: 3 hit(s)'; echo $?) "$(printf '%s\n' "$OUT" | grep TOTAL)"
printf 'zorbic\n' > "$R0/stray.txt"; run "$R0" zorbic
ok "control: one uncovered file → the surface searches it (1 hit in 1 file)" $(else_sect | grep -qE '^  everything else +1 hit\(s\) in 1 file\(s\)' && in_else 'stray.txt:1:zorbic'; echo $?) "$(else_sect)"

echo "-- outside a git repo the catch-all is ⚠ ABSENT, and counted"
NG="$T/nongit"; mkdir -p "$NG"; (cd "$R" && tar cf - --exclude .git . ) | (cd "$NG" && tar xf -)
if [ -d "$NG/notes" ] && ! (cd "$NG" && git rev-parse --git-dir >/dev/null 2>&1); then
  run "$NG" zorbic
  ok "exit 0, and '⚠ everything else … ABSENT — not a git repo'" $([ $RC = 0 ] && else_sect | grep -qE '^  ⚠ everything else +ABSENT — not a git repo'; echo $?) "rc=$RC $(else_sect)"
  ok "the ⚠ ABSENT count is 1 (the same tree inside git counted 0)" $(has '⚠ ABSENT surfaces: 1'; echo $?) "$(printf '%s\n' "$OUT" | grep TOTAL)"
  ok "it does not pretend: no 'hits by folder', no notes/ hits from the catch-all" $(! in_else 'hits by folder' && ! has 'notes/sub/n.md'; echo $?)
  ok "control: the named surfaces still ran (docs/a.md found)" $(has 'docs/a.md:1:zorbic in a doc'; echo $?)
else skip "non-git ABSENT rows (4)" "could not build a tree outside any git repo"; fi

echo "-- usage"
run "$R"
ok "no term: exit 2 with usage" $([ $RC = 2 ] && printf '%s' "$ERR" | grep -q usage; echo $?) "rc=$RC"

if [ "$S" -gt 0 ]; then echo "librarian-sweep-test: $P passed, $F failed, $S SKIPPED (unexercised — NOT passes)"
else echo "librarian-sweep-test: $P passed, $F failed"; fi
[ "$F" = 0 ]
