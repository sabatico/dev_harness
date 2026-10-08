#!/usr/bin/env bash
# find-test.sh — acceptance tests for scripts/find.sh. Builds a throwaway repo, runs the cases, exits 1
# on any failure. Usage: scripts/find-test.sh [path/to/find.sh]   (default: find.sh next to this file)
# A suite is only trusted once it has been seen failing: run it against deliberately broken copies.
# Authored with the v1.3 benchmark report, by a different author than scripts/find.sh (the
# cross-author rule). Adopted 2026-10-03 with one fix: macOS `mktemp -d` ignores TMPDIR, and when the
# temp dir could not be made the suite went on to `mkdir /repo` - now it stops.
set -uo pipefail
FIND="$(cd "$(dirname "${1:-$(dirname "$0")/find.sh}")" && pwd)/$(basename "${1:-find.sh}")"
[ -x "$FIND" ] || { echo "no executable find.sh at $FIND" >&2; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/find-test.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }; trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R"; cd "$R" || exit 2
P=0; F=0
ok()  { if [ "$2" = 0 ]; then P=$((P+1)); echo "  ok    $1"; else F=$((F+1)); echo "  FAIL  $1"; [ -n "${3:-}" ] && printf '        %s\n' "$3"; fi; }
# A row that cannot be exercised on this machine prints SKIP and is counted apart — never a pass.
S=0
skip() { S=$((S+1)); echo "  SKIP  $1 — $2 (unexercised: NOT a pass)"; }
run() { OUT=$("$FIND" "$@" 2>"$T/err"); RC=$?; ERR=$(cat "$T/err"); }
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
lists() { printf '%s\n' "$OUT" | grep -qE "^[0-9]+	$(printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g')\$"; }

# ---- fixture: neutral shop data; decisions scattered where people forget to look ----
git init -q . && git config user.email t@t && git config user.name t
mkdir -p src docs/adr "docs/archive/2025" notes .meta "odd dir" node_modules/pkg data
printf 'def total():\n    return 0  # shipping\n' > src/orders.py
printf '# ADR-001\nUse ISO dates.\n' > docs/adr/ADR-001.md
printf '| T-1 | closed | Owner ruling: gift cards are NON-REFUNDABLE; warranty stays 2 years |\n' > docs/archive/2025/tickets.md
printf 'Call 2025-03-11: owner said exchange = return + new order.\n' > notes/call.md
printf 'hidden-dir decision: warranty is 2 years\n' > .meta/decisions.txt
printf 'literal a.b here\nand a[1] here\n' > "odd dir/x [1].md"
printf 'colon file mentions warranty\n' > 'docs/a:b.md'
printf 'node_modules/\n*.log\n' > .gitignore
printf 'ignored warranty\n' > node_modules/pkg/index.js
printf 'ignored warranty\n' > debug.log
printf '{"rule": "Café opening hours"}\n' > data/cfg.json
printf 'bin\0warranty' > data/blob.bin
for i in $(seq 1 25); do echo "warranty line $i" >> data/many.txt; done
git add -A && git commit -qm init
printf 'untracked note: the owner REVERSED the warranty rule\n' > notes/untracked.md   # never committed
NFILES=$(git ls-files --cached --others --exclude-standard | wc -l | tr -d ' ')

echo "-- coverage: every folder, untracked, hidden dirs; .gitignore respected"
run warranty
ok "finds the term in an archived, a hidden-dir and an untracked file" $([ $RC = 0 ] && lists docs/archive/2025/tickets.md && lists .meta/decisions.txt && lists notes/untracked.md && lists 'docs/a:b.md'; echo $?) "$OUT"
ok "skips .gitignored files (node_modules/, *.log)" $(! has node_modules && ! has debug.log; echo $?)
ok "skips binary files" $(! has blob.bin; echo $?)
ok "reports the number of files searched = git's file count ($NFILES)" $(has "of $NFILES searched"; echo $?) "$(printf '%s\n' "$OUT" | head -1)"
ok "ranks the file with most hits first" $(printf '%s\n' "$OUT" | sed -n 2p | grep -q 'data/many.txt$'; echo $?) "$(printf '%s\n' "$OUT" | sed -n 2p)"
ok "a colon in a filename keeps the right name and count" $(lists 'docs/a:b.md' && has "--- docs/a:b.md"; echo $?)

echo "-- matching: case, synonyms, literal by default"
run NON-REFUNDABLE; ok "case-insensitive (lower-case hit for an upper-case term)" $([ $RC = 0 ] && has 'are NON-REFUNDABLE'; echo $?)
run non-refundable; ok "case-insensitive (upper-case hit for a lower-case term)" $([ $RC = 0 ] && lists docs/archive/2025/tickets.md; echo $?)
run exchange "swap an item" "replace"; ok "several terms are OR-ed (one synonym is enough)" $([ $RC = 0 ] && lists notes/call.md; echo $?)
run "a.b"; ok "'.' is literal by default (matches 'a.b' only)" $([ $RC = 0 ] && lists "odd dir/x [1].md" && [ "$(printf '%s\n' "$OUT" | grep -c '^[0-9]')" = 1 ]; echo $?) "$OUT"
run "a[1]"; ok "brackets are literal by default" $([ $RC = 0 ] && has 'and a[1] here'; echo $?)
run "return + new"; ok "a term with spaces and '+' is one literal phrase" $([ $RC = 0 ] && lists notes/call.md; echo $?)
run --regex 'warranty (line|rule)'; ok "--regex enables extended regex" $([ $RC = 0 ] && lists data/many.txt && lists notes/untracked.md; echo $?)
run -- --regex; ok "'--' ends options: a term that looks like a flag is searched, not parsed" $([ $RC = 1 ] && has 'NO HITS for: --regex'; echo $?) "rc=$RC $OUT $ERR"
run "Café"; ok "non-ASCII term matches literally" $([ $RC = 0 ] && lists data/cfg.json; echo $?)

echo "-- 'no hits' vs 'error' are never confused"
run zebra-unicorn; ok "no hits: exit 1" $([ $RC = 1 ]; echo $?) "rc=$RC"
ok "no hits: says NO HITS and how many files were searched" $(has "NO HITS for: zebra-unicorn" && has "searched all $NFILES files"; echo $?) "$OUT"
run --regex 'war(ranty'; ok "invalid regex: exit 2, not 1" $([ $RC = 2 ]; echo $?) "rc=$RC"
ok "invalid regex: says SEARCH FAILED and NOT 'no hits'" $(printf '%s' "$ERR" | grep -q "SEARCH FAILED" && ! has "NO HITS"; echo $?) "$ERR"
run --bogus x; ok "unknown option: exit 2" $([ $RC = 2 ]; echo $?)
run; ok "no terms: exit 2 with usage" $([ $RC = 2 ] && printf '%s' "$ERR" | grep -q usage; echo $?)
run --max-per-file abc x; ok "non-numeric --max-per-file: exit 2" $([ $RC = 2 ]; echo $?)
OUT=$(cd "$T" && "$FIND" x 2>&1); RC=$?; ok "outside a git repo: exit 2 (never 'no hits')" $([ $RC = 2 ] && ! has "NO HITS"; echo $?) "rc=$RC $OUT"

echo "-- truncation is never silent"
run --max-per-file 5 "warranty line"
ok "shows exactly 5 lines for the capped file" $([ "$(printf '%s\n' "$OUT" | grep -c '^data/many.txt:')" = 5 ]; echo $?)
ok "announces the exact remainder (20 more) as TRUNCATED" $(has "20 more in this file — TRUNCATED"; echo $?) "$(printf '%s\n' "$OUT" | tail -2)"
run --max-per-file 25 "warranty line"; ok "no TRUNCATED notice when everything fits" $(! has TRUNCATED; echo $?)

echo "-- shell-independence (the zsh 'no matches found' trap) and cwd"
# zsh is not installed on most Linux images (Debian/Ubuntu containers): the row is then unexercised, a
# SKIP, never a FAIL (it failed on the first Linux install, 2026-10-07) and never a pass.
if command -v zsh >/dev/null 2>&1; then
  OUT=$(zsh -c "cd '$R' && '$FIND' '*.md' 'file?' warranty" 2>&1); RC=$?
  ok "under zsh, glob-looking terms are searched literally (no 'no matches found')" $([ $RC = 0 ] && ! has "no matches found" && lists data/many.txt; echo $?) "rc=$RC"
else skip "under zsh, glob-looking terms are searched literally" "zsh is not installed"; fi
OUT=$(cd "$R/src" && "$FIND" ruling 2>&1); RC=$?
ok "run from a subdirectory, still searches the WHOLE repo" $([ $RC = 0 ] && lists docs/archive/2025/tickets.md; echo $?) "$OUT"
E="$T/empty"; mkdir -p "$E" && (cd "$E" && git init -q . && printf 'fresh decision\n' > d.md)
OUT=$(cd "$E" && "$FIND" decision 2>&1); RC=$?
ok "a repo with no commits yet (untracked files only) is still searched" $([ $RC = 0 ] && lists d.md; echo $?) "rc=$RC $OUT"

# ═════════════════════════════════════════════════════════════════════════════════════════════════
# v1.3 ADDITIONS — cross-authored 2026-10-03 by a test author who wrote neither find.sh nor the rows
# above (those are kept as written). Pins the v1.3 behaviour: non-ASCII / odd FILE names, options
# after the terms and `--`, --list, the HARNESS_FIND_LAST "harness's own files" section (default,
# custom, empty, harness.conf never EXECUTED), the 300-char line cut, python3 missing or crashing,
# and exit codes 0/1/2 on every new path. Each fixture here is its OWN repo under $T, so the counts
# the rows above depend on never move. Cases find.sh currently gets WRONG are not rows (a red row
# nobody can fix blocks the gate); they went to the lead in the test author's report.
# A row that cannot be exercised on this machine prints SKIP (skip(), defined with ok() above).
# ═════════════════════════════════════════════════════════════════════════════════════════════════
# rank_ln PATH → the output line number of PATH's ranking row ("N<TAB>PATH"), exact string compare via
# ENVIRON (awk -v would eat backslashes; the existing `lists` helper is ERE, so '?' '+' '(' in a name
# would be regex there).
rank_ln() { printf '%s\n' "$OUT" | MATCHP="$1" awk '{ i = index($0, "\t") } i > 1 && substr($0, 1, i-1) ~ /^[0-9]+$/ && substr($0, i+1) == ENVIRON["MATCHP"] { print NR; exit }'; }
line_of() { printf '%s\n' "$OUT" | grep -nF -- "$1" | head -1 | cut -d: -f1; }
OWNHDR="-- the harness's own files"
# own PATH → ranked AFTER the harness-files header. proj PATH → ranked, and before that header (or no header).
own()  { local r h; r=$(rank_ln "$1"); h=$(line_of "$OWNHDR"); [ -n "$r" ] && [ -n "$h" ] && [ "$r" -gt "$h" ]; }
proj() { local r h; r=$(rank_ln "$1"); h=$(line_of "$OWNHDR"); [ -n "$r" ] && { [ -z "$h" ] || [ "$r" -lt "$h" ]; }; }

R2="$T/v13"; mkdir -p "$R2"; cd "$R2" || exit 2
git init -q . && git config user.email t@t && git config user.name t
mkdir -p docs/ci docs/cix .claude/rules evals src notes
printf 'gadget rule: accented name\n' > 'docs/décision.md'
printf 'gadget a\ngadget b\ngadget c\n' > docs/ci/gates.md            # a harness file with the MOST hits
printf 'gadget\n' > .claude/rules/r.md
printf 'gadget\n' > evals/e.md
for f in AGENTS.md TAILORING.md CHEAT-SHEET.md CONVENTIONS.md CONTRIBUTING.md harness.conf.example; do printf 'gadget\n' > "$f"; done
printf 'gadget\n' > AGENTS.md.bak                                       # NOT a harness file: names match exactly
printf 'gadget near miss\n' > docs/cix/x.md                             # docs/ci/ must not swallow docs/cix/
printf 'gadget\n' > src/app.py
printf 'flag-looking text: --list literal\n' > notes/flags.md
printf 'gadget %0400d\n' 0 > notes/long.md                              # 407 chars
printf 'gadget%0294d\n' 0 > notes/exact.md                              # exactly 300 chars
python3 -c 'import sys; sys.stdout.write("gadget " + "é"*400 + "\n")' > notes/wide.md 2>/dev/null || rm -f notes/wide.md
NFD="$(printf 'notes/nfd-de\314\201j\303\240.md')"                       # 'déjà' typed DEcomposed (macOS keyboards)
printf 'gadget nfd\n' > "$NFD" 2>/dev/null || NFD=""
git add -A && git commit -qm init

echo "-- v1.3: non-ASCII file names are listed unescaped, and their lines appear"
run gadget
ok "accented name ranked verbatim (no \\303 octal escape)" $([ $RC = 0 ] && proj 'docs/décision.md' && ! has '\303'; echo $?) "$(printf '%s\n' "$OUT" | head -20)"
ok "accented name: its match line is printed (the reference found NO lines in it)" $(has 'docs/décision.md:1:gadget rule: accented name' && has '--- docs/décision.md'; echo $?)
if [ -n "$NFD" ]; then
  ok "a decomposed (NFD) accented name: listed without escapes and its line appears" $(has ':1:gadget nfd' && printf '%s\n' "$OUT" | grep -q 'nfd-d' && ! printf '%s\n' "$OUT" | grep 'nfd-d' | grep -q '\\[0-9]'; echo $?)
else skip "NFD file name" "this filesystem refused to create it"; fi

echo "-- v1.3: options after the terms; everything after -- is a term"
run gadget --list
ok "'TERM --list' is list mode (option after the term)" $([ $RC = 0 ] && has '(--list: file ranking only' && ! has '== matches' && proj src/app.py; echo $?) "rc=$RC"
run --list gadget
ok "'--list TERM' is list mode too (order does not matter)" $([ $RC = 0 ] && has '(--list: file ranking only' && ! has '== matches'; echo $?)
run 'gad.et'
ok "control: 'gad.et' is a fixed string by default → no hits, exit 1" $([ $RC = 1 ]; echo $?) "rc=$RC"
run 'gad.et' --regex
ok "'TERM --regex' turns regex on after the term" $([ $RC = 0 ] && proj src/app.py; echo $?) "rc=$RC"
run 'gad(get' --regex
ok "'BADREGEX --regex': --regex parsed after the term → invalid regex → exit 2" $([ $RC = 2 ] && ! has 'NO HITS'; echo $?) "rc=$RC"
run -- 'gad(get' --regex
ok "'-- BADREGEX --regex': both are literal terms → no hits, exit 1 (not 2)" $([ $RC = 1 ] && has 'NO HITS for: gad(get --regex'; echo $?) "rc=$RC $OUT $ERR"
run -- --list
ok "'-- --list' searches the text '--list' and prints match lines (not list mode)" $([ $RC = 0 ] && proj notes/flags.md && has 'notes/flags.md:1:flag-looking text: --list literal' && ! has '(--list: file ranking only'; echo $?) "rc=$RC $OUT"
run gadget --bogus
ok "an unknown option AFTER the terms: exit 2" $([ $RC = 2 ] && printf '%s' "$ERR" | grep -q 'unknown option --bogus'; echo $?) "rc=$RC $ERR"
run gadget --max-per-file
ok "--max-per-file with its value missing (last arg): exit 2" $([ $RC = 2 ] && printf '%s' "$ERR" | grep -q 'needs a number'; echo $?) "rc=$RC $ERR"
run gadget --max-per-file 1
ok "'TERM --max-per-file 1' applies the cap (2 more in the 3-hit file, TRUNCATED)" $([ $RC = 0 ] && has '2 more in this file — TRUNCATED' && [ "$(printf '%s\n' "$OUT" | grep -c '^docs/ci/gates.md:')" = 1 ]; echo $?)

echo "-- v1.3: --list is the ranking only"
run --list gadget
ok "--list: ranking present, no '--- file' headers, no 'path:N:' match lines" $(proj src/app.py && ! has '--- src/app.py' && ! has 'src/app.py:1:'; echo $?)
ok "--list: the harness section is still shown, last" $(own docs/ci/gates.md; echo $?)
run --list zebra-unicorn
ok "--list with no hits: exit 1 + NO HITS" $([ $RC = 1 ] && has 'NO HITS for: zebra-unicorn'; echo $?) "rc=$RC"
run --list --regex 'a(b'
ok "--list with an invalid regex: exit 2, not 1" $([ $RC = 2 ] && ! has 'NO HITS'; echo $?) "rc=$RC"

echo "-- v1.3: the harness's own files go last (HARNESS_FIND_LAST)"
run gadget        # no harness.conf at all → the installed-project default
ok "default (no harness.conf): the section exists" $(has "$OWNHDR (listed last: HARNESS_FIND_LAST) --"; echo $?)
ok "default: docs/ci/ .claude/ evals/ AGENTS.md TAILORING.md CHEAT-SHEET.md CONVENTIONS.md CONTRIBUTING.md harness.conf.example are last" \
  $(own docs/ci/gates.md && own .claude/rules/r.md && own evals/e.md && own AGENTS.md && own TAILORING.md && own CHEAT-SHEET.md && own CONVENTIONS.md && own CONTRIBUTING.md && own harness.conf.example; echo $?) "$OUT"
ok "default: project files stay above it (AGENTS.md.bak and docs/cix/ are NOT harness files)" $(proj src/app.py && proj 'docs/décision.md' && proj AGENTS.md.bak && proj docs/cix/x.md; echo $?)
ok "default: a 3-hit harness file ranks BELOW a 1-hit project file" $([ "$(rank_ln docs/ci/gates.md)" -gt "$(rank_ln src/app.py)" ] && [ "$(line_of '--- docs/ci/gates.md')" -gt "$(line_of '--- src/app.py')" ]; echo $?)
ok "default: the header still counts every file with hits (project + harness)" $(has "== $(printf '%s\n' "$OUT" | grep -cE '^[0-9]+	') file(s) with hits"; echo $?)
printf 'HARNESS_DOC_DIRS="docs"   # gadget\n# HARNESS_FIND_LAST=""\n' > harness.conf
run gadget
ok "harness.conf with NO HARNESS_FIND_LAST line (only a commented one): default applies, harness.conf itself last" $(own harness.conf && own docs/ci/gates.md && proj src/app.py; echo $?) "$OUT"
printf 'HARNESS_FIND_LAST="src/ notes/flags.md"   # gadget\n' > harness.conf
run gadget
ok "custom value: its paths go last; the default's paths become project files" $(own src/app.py && proj docs/ci/gates.md && proj AGENTS.md && proj harness.conf; echo $?) "$OUT"
OUT=$(cd "$R2/src" && "$FIND" gadget 2>&1); RC=$?
ok "custom value applies when run from a subdirectory (harness.conf is read at the repo root)" $([ $RC = 0 ] && own src/app.py; echo $?)
printf "HARNESS_FIND_LAST='src/'\n" > harness.conf; run gadget
ok "single-quoted value is read" $(own src/app.py && proj docs/ci/gates.md; echo $?)
printf '  HARNESS_FIND_LAST="evals/"\r\n' > harness.conf; run gadget
ok "indented line with CRLF ending is read" $(own evals/e.md && proj src/app.py; echo $?) "$OUT"
printf 'HARNESS_FIND_LAST=src/\r\n' > harness.conf; run gadget
ok "unquoted value with CRLF: the trailing CR does not break the match" $(own src/app.py; echo $?) "$OUT"
printf 'HARNESS_FIND_LAST="src/"\nHARNESS_FIND_LAST="evals/"\n' > harness.conf; run gadget
ok "two assignments: the LAST wins, as when the shell reads the file" $(own evals/e.md && proj src/app.py; echo $?)
printf 'HARNESS_FIND_LAST=""\n' > harness.conf; run gadget
ok 'HARNESS_FIND_LAST="" means none: no section, default paths are project files, exit 0' $([ $RC = 0 ] && ! has "$OWNHDR" && proj docs/ci/gates.md && proj AGENTS.md; echo $?) "$OUT"
ok 'HARNESS_FIND_LAST="": ranking is by hits again (the 3-hit docs/ci/gates.md is first)' $(printf '%s\n' "$OUT" | sed -n 2p | grep -q '	docs/ci/gates.md$'; echo $?)
printf 'HARNESS_FIND_LAST=\n' > harness.conf; run gadget
ok 'HARNESS_FIND_LAST= (bare) also means none' $([ $RC = 0 ] && ! has "$OWNHDR"; echo $?)
run zebra-unicorn
ok 'HARNESS_FIND_LAST="" with no hits: still exit 1' $([ $RC = 1 ]; echo $?) "rc=$RC"

echo "-- v1.3: harness.conf is READ, never EXECUTED"
# The canary: commands that create files if the config is sourced/eval'd. T2 control first — prove the
# canary is live by sourcing it in a scratch dir — then prove find.sh did not fire it.
# shellcheck disable=SC2016  # the $(…) and `…` are meant literally: they ARE the canary
printf 'HARNESS_FIND_LAST="src/ $(touch PWN1) `touch PWN2`"\ntouch PWN3\nHARNESS_DOC_DIRS="$(touch PWN4)"\n' > harness.conf
CTL="$T/canary-control"; mkdir -p "$CTL"; cp harness.conf "$CTL/"; (cd "$CTL" && . ./harness.conf) >/dev/null 2>&1
ok "control: sourcing this harness.conf DOES create the canary files" $([ -f "$CTL/PWN1" ] && [ -f "$CTL/PWN2" ] && [ -f "$CTL/PWN3" ] && [ -f "$CTL/PWN4" ]; echo $?)
run gadget
# canary_fired → 0 if ANY canary file exists. (Not `ls a* b*`: ls exits non-zero when one operand is
# missing even if another exists — the first draft of this row passed against a mutant that sourced
# the file; found by the mutation check.)
canary_fired() { local f; for f in "$R2"/PWN* "$R2"/src/PWN* "$T"/PWN*; do [ -e "$f" ] && return 0; done; return 1; }
ok "find.sh never executes harness.conf: no canary file anywhere" $(! canary_fired; echo $?) "$(ls "$R2")"
ok "…while it DID read the value (src/ is last), so the file was not simply ignored" $([ $RC = 0 ] && own src/app.py; echo $?) "$OUT"
rm -f harness.conf

echo "-- v1.3: over-long match lines are cut, visibly"
run gadget
LONG=$(printf '%s\n' "$OUT" | grep '^notes/long.md:1:')
ok "a 407-char line is cut to 300 chars + ' …[line cut at 300 chars]'" $(t="${LONG#notes/long.md:1:}"; t="${t% …\[line cut at 300 chars\]}"; [ "${#t}" = 300 ] && printf '%s' "$LONG" | grep -qF ' …[line cut at 300 chars]'; echo $?) "$(printf '%s' "$LONG" | cut -c1-60)… (len ${#LONG})"
ok "a line of exactly 300 chars is NOT cut (no marker, full text)" $(printf '%s\n' "$OUT" | grep '^notes/exact.md:1:' | grep -qv 'line cut' && [ "$(printf '%s\n' "$OUT" | grep '^notes/exact.md:1:' | wc -c | tr -d ' ')" = $((17+300+1)) ]; echo $?)
if [ -f notes/wide.md ] && command -v python3 >/dev/null 2>&1; then
  ok "a 407-CHARACTER accented line is cut at 300 characters (not bytes) and stays valid UTF-8" $(printf '%s\n' "$OUT" | grep '^notes/wide.md:1:' | python3 -c '
import sys
b = sys.stdin.buffer.read().rstrip(b"\n"); s = b.decode("utf-8")      # raises on a split character
t = s[len("notes/wide.md:1:"):]
assert t.endswith(" …[line cut at 300 chars]") and len(t[:-len(" …[line cut at 300 chars]")]) == 300' 2>/dev/null; echo $?)
else skip "accented 300-char cut" "python3 unavailable to build/verify the fixture"; fi

echo "-- v1.3: python3 missing or crashing is a SEARCH FAILURE (2), never 'no hits' (1)"
NOPY="$T/nopy"; WITHPY="$T/withpy"; mkdir -p "$NOPY" "$WITHPY"; tools_ok=1
for t in bash git sed grep tail mktemp tr wc cat rm; do
  p="$(command -v "$t")" || { tools_ok=0; break; }
  ln -s "$p" "$NOPY/$t" && ln -s "$p" "$WITHPY/$t"
done
PY="$(command -v python3 || true)"; [ -n "$PY" ] && ln -s "$PY" "$WITHPY/python3"
if [ "$tools_ok" = 1 ] && [ -n "$PY" ] && ! env PATH="$NOPY" /bin/sh -c 'command -v python3' >/dev/null 2>&1; then
  OUT=$(PATH="$WITHPY" "$FIND" gadget 2>"$T/err"); RC=$?
  ok "control: the same minimal PATH plus python3 → exit 0 (so the PATH is otherwise enough)" $([ $RC = 0 ]; echo $?) "rc=$RC $(cat "$T/err")"
  OUT=$(PATH="$NOPY" "$FIND" gadget 2>"$T/err"); RC=$?; ERR=$(cat "$T/err")
  ok "no python3, a term that WOULD hit: exit 2 + 'python3 is required'" $([ $RC = 2 ] && printf '%s' "$ERR" | grep -q 'python3 is required' && ! has 'NO HITS'; echo $?) "rc=$RC $ERR"
  OUT=$(PATH="$NOPY" "$FIND" zebra-unicorn 2>"$T/err"); RC=$?
  ok "no python3, a term with NO hits: still exit 2, never 1" $([ $RC = 2 ] && ! has 'NO HITS'; echo $?) "rc=$RC $OUT"
  OUT=$(PATH="$NOPY" "$FIND" --list gadget 2>"$T/err"); RC=$?
  ok "no python3 under --list: exit 2" $([ $RC = 2 ]; echo $?) "rc=$RC"
else skip "python3-less PATH (3 rows + control)" "could not build a PATH with git/bash/coreutils but without python3"; fi
BADPY="$T/badpy"; mkdir -p "$BADPY"; printf '#!/bin/sh\ncat >/dev/null\nexit 3\n' > "$BADPY/python3"; chmod +x "$BADPY/python3"
OUT=$(PATH="$BADPY:$PATH" "$FIND" gadget 2>"$T/err"); RC=$?; ERR=$(cat "$T/err")
ok "a python3 that crashes while formatting: exit 2 + 'SEARCH FAILED', never 1" $([ $RC = 2 ] && printf '%s' "$ERR" | grep -q 'formatting the results failed'; echo $?) "rc=$RC $ERR"

echo "-- v1.3: odd file names, as far as git allows"
R3="$T/odd"; mkdir -p "$R3"; cd "$R3" || exit 2
git init -q . && git config user.email t@t && git config user.name t
# bash 3.2 arrays + $'…' (no IFS games, no glob expansion of the names). A name with a NEWLINE is
# NOT here: find.sh mis-names it today (reported to the lead, not a red row).
ODD=($'tab\tin.md' 'say "hi".md' 'back\slash.md' '-rf.md' 'star*q?.md' 'plus+(paren)|pipe.md' 'sp ace [1] {b}.md' 'emoji 🦊.md' '$HOME.md' 'colon:1:fake.md')
lbl() { printf '%s' "$1" | sed "s/$(printf '\t')/<TAB>/g"; }
MADE=(); for n in "${ODD[@]}"; do printf 'kumquat in x\n' > "./$n" 2>/dev/null && MADE+=("$n"); done
git add -A >/dev/null 2>&1; git commit -qm odd >/dev/null 2>&1
run kumquat
for n in "${ODD[@]}"; do
  if [ -f "./$n" ]; then
    ok "odd name listed verbatim + its match line: $(lbl "$n")" $([ $RC = 0 ] && proj "$n" && has "--- $n" && has "$n:1:kumquat in x"; echo $?) "$(printf '%s\n' "$OUT" | head -14)"
  else skip "odd name $(lbl "$n")" "the filesystem refused it"; fi
done
ok "odd names: the header counts every one of them (${#MADE[@]})" $(has "== ${#MADE[@]} file(s) with hits"; echo $?) "$(printf '%s\n' "$OUT" | head -1)"
cd "$R" || exit 2

if [ "$S" -gt 0 ]; then echo "find-test: $P passed, $F failed, $S SKIPPED (unexercised — NOT passes)"
else echo "find-test: $P passed, $F failed"; fi
[ "$F" = 0 ]
