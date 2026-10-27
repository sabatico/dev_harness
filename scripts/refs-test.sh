#!/usr/bin/env bash
# refs-test.sh — acceptance matrix for scripts/refs.sh + scripts/refs-index.py (the reference index).
# Usage: scripts/refs-test.sh [path/to/refs.sh]     run the matrix (default: refs.sh next to this file)
#        scripts/refs-test.sh --mutants             also prove the guards: break a scratch copy of the code, one
#                                                   guard at a time, and require the NAMED rows to go red
# Exit: 0 every row passes · 1 a row failed · 2 cannot run.
#
# WHY (CLAUDE.md "a guard test proves nothing until you have watched it fail"): refs.sh answers "what points at X"
# for every agent; a wrong answer there is silent. Every case group below pins one behaviour the header of
# scripts/refs-index.py promises, with a known positive beside every "must not" row.
# Ported from the first adopting project's matrix, written by a different author than the builder of refs.sh (the
# cross-author rule); rows for product-only kinds (stories, coming-soon blocks, endpoint tags, Go test definitions) were
# dropped when the tool was generalised. Each fixture is a throwaway git repo under a mktemp dir; the real repo, the
# real .refs-cache/ and the network are never touched. The code under test is only ever READ: the mutation mode
# works on copies in the temp dir. The matrix runs with the DEFAULT knobs (no harness.conf in a fixture) plus
# HARNESS_REFS_IDS naming one extra family (T), so the env-override path of a knob is exercised by the T-001 row.
#
# Row labels start with a group letter: A definitions+edges · B exits+hostile input · C cache · D yaml, duplicates ·
# E generated views · F short forms · X extra nasty cases · R review fixes · G guard rows (tagged [G:name], the rows that
# must go red when that guard is broken; --mutants checks it). known() marks a row that fails on purpose because it names
# a defect in the code under test: it is counted apart, never as a pass, and prints FIXED once the code is fixed. No row
# uses it today.
# Nothing here deletes anything outside its own mktemp dir.
# No pipefail on purpose: rows pipe a variable into `grep -q`, which exits at the first match and sends the writer a
# SIGPIPE; under pipefail that read as "no match" and made rows fail at random on a loaded machine.
set -u
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
MODE=matrix
if [ "${1:-}" = "--mutants" ]; then MODE=mutants; shift; fi
# hermetic: a knob exported by the caller's shell must not change what the fixtures mean
unset HARNESS_DOC_DIRS HARNESS_DECISION_DIR HARNESS_DECISION_PREFIX HARNESS_BUG_PREFIX HARNESS_BUG_REGISTER
export HARNESS_REFS_IDS="USER DEC FEAT DOC BIZ SEC TBD T"
REFS="$(cd "$(dirname "${1:-$(dirname "$SELF")/refs.sh}")" && pwd)/$(basename "${1:-refs.sh}")"
[ -x "$REFS" ] || { echo "refs-test: no executable refs.sh at $REFS" >&2; exit 2; }
[ -f "$(dirname "$REFS")/refs-index.py" ] || { echo "refs-test: refs-index.py is not next to $REFS" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "refs-test: python3 is required" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "refs-test: git is required" >&2; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/refs-test.XXXXXX") || { echo "refs-test: cannot create a temp dir" >&2; exit 2; }
T=$(cd "$T" && pwd -P)
cleanup() { chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

# ───────────────────────────── mutation mode ─────────────────────────────────────────────────────────────────────
# Each mutant: NAME | file | exact text to replace | replacement | a row tag that must go red.
# A mutant whose target text is absent is an ERROR (the mutation would be a no-op and prove nothing).
if [ "$MODE" = mutants ]; then
  MB="$T/mut"; mkdir -p "$MB"; BAD=0; N=0
  mutate() { python3 -I -c '
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(old) < 1:
    sys.exit(3)
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))' "$@"; }
  SRC="$(dirname "$REFS")"
  # real files are fingerprinted before and after: they must never change
  before=$(shasum "$SRC/refs.sh" "$SRC/refs-index.py" | awk '{print $1}' | tr '\n' ' ')
  # Mutants run four at a time (each one runs the whole matrix on its own copy); results are printed in order.
  run_mutant() {  # name old new tag
    local name="$1" old="$2" new="$3" tag="$4" d log red tagred
    # REFS_MUTANT_ONLY=dir|link re-runs only the mutants whose tag matches (the other results are not printed)
    if [ -n "${REFS_MUTANT_ONLY:-}" ] && ! printf '%s' "$tag" | grep -Eq "^(${REFS_MUTANT_ONLY})\$"; then return; fi
    N=$((N+1)); d="$MB/$N"; mkdir -p "$d"; cp "$SRC/refs.sh" "$SRC/refs-index.py" "$d/"
    if ! mutate "$d/refs-index.py" "$old" "$new"; then
      echo "  ERROR  mutant '$name': the target text is not in refs-index.py (a no-op mutation proves nothing)" > "$d/result"; return
    fi
    if cmp -s "$d/refs-index.py" "$SRC/refs-index.py"; then echo "  ERROR  mutant '$name' left the file unchanged" > "$d/result"; return; fi
    (
      log="$d/log"; bash "$SELF" "$d/refs.sh" > "$log" 2>&1
      red=$(grep -c '^  FAIL ' "$log"); tagred=$(grep '^  FAIL ' "$log" | grep -cF "[G:$tag]")
      if [ "$red" -ge 1 ] && [ "$tagred" -ge 1 ]; then
        { echo "  ok    mutant '$name': $red row(s) red, $tagred tagged [G:$tag]"; grep '^  FAIL ' "$log" | grep -F "[G:$tag]" | cut -c1-118 | sed 's/^  FAIL  /          red: /'; } > "$d/result"
      else echo "  FAIL  mutant '$name' survived or the tagged rows stayed green (red=$red, [G:$tag] red=$tagred) — the guard is not guarded" > "$d/result"; fi
    ) &
    [ $((N % 4)) = 0 ] && wait
  }
  echo "-- G: guard mutants (each runs the whole matrix on a scratch copy of refs.sh + refs-index.py)"
  run_mutant "SHORTENABLE widened to WIN"      "SHORTENABLE = (DECISION_PREFIX, BUG_PREFIX)" "SHORTENABLE = (DECISION_PREFIX, BUG_PREFIX, 'WIN')" shortenable
  run_mutant "SHORTENABLE narrowed to ADR"     "SHORTENABLE = (DECISION_PREFIX, BUG_PREFIX)" "SHORTENABLE = (DECISION_PREFIX,)" shortenable
  run_mutant "generated rule: file header off" "generated_here = gen_file or in_gen" "generated_here = in_gen" generated
  run_mutant "generated rule: region off"      "generated_here = gen_file or in_gen" "generated_here = gen_file" generated
  run_mutant "generated rule: always off"      "generated_here = gen_file or in_gen" "generated_here = False" generated
  run_mutant "generated rule: header window 8 -> 80" "for l in lines[:8])" "for l in lines[:80])" generated
  run_mutant "DEC_SPACE regex never matches"   "re.escape(DECISION_PREFIX) + r' (\\d{1,3})" "re.escape(DECISION_PREFIX) + r'X (\\d{1,3})" adrspace
  run_mutant "DEC_SPACE loses its right guard" "r' (\\d{1,3})(?![A-Za-z0-9_])')" "r' (\\d{1,3})')" adrspace
  run_mutant "DEC_SPACE loses its left guard"  "DEC_SPACE = re.compile(r'(?<![A-Za-z0-9_-])' + " "DEC_SPACE = re.compile(r'' + " adrspace
  run_mutant "TOK loses its left guard"        "TOK = re.compile(r'(?<![A-Za-z0-9_-])([A-Z]" "TOK = re.compile(r'([A-Z]" tok
  run_mutant "TOK loses its right guard"       "{0,2})-(\\d{1,4})(?![A-Za-z0-9_])')" "{0,2})-(\\d{1,4})')" tok
  run_mutant "owner lookup off by one (bisect_left)" "bisect.bisect_right(st, ln) - 1" "bisect.bisect_left(st, ln) - 1" owner
  run_mutant "owner lookup ignores the span end" "sp[i][0] <= ln <= sp[i][1]" "sp[i][0] <= ln" owner
  run_mutant "cache key ignores the script content" "h.update(f.read())" "h.update(b'')" cachekey
  run_mutant "cache key ignores mtime"         "h.update(('%s\\0%s\\0%s\\n' % (n, s, m))" "h.update(('%s\\0%s\\0%s\\n' % (n, s, 0))" cachekey
  run_mutant "cache key ignores size"          "h.update(('%s\\0%s\\0%s\\n' % (n, s, m))" "h.update(('%s\\0%s\\0%s\\n' % (n, 0, m))" cachekey
  run_mutant "cache key ignores the file list" "for n, s, m in stats:" "for n, s, m in []:" cachekey
  run_mutant "date tail read as a part"        "(?!-\\d{2})" "" datetail
  run_mutant "lines split like splitlines()"   "lines = text.split('\\n')" "lines = text.splitlines()" linesplit
  run_mutant "control characters not cleaned"  "return CTRL.sub('?', s)" "return s" ctrl
  run_mutant "2 MB limit off by one"           "if size > MAX_BYTES:" "if size >= MAX_BYTES:" sizelimit
  run_mutant "internal error exits 1"          "os._exit(2)" "os._exit(1)" crashexit
  run_mutant "broken pipe handler removed"     "except BrokenPipeError:" "except ZeroDivisionError:" brokenpipe
  run_mutant "section filter ignored"          "inbound = [r for r in inbound if r[7] and args.section in r[7]]" "pass" section
  run_mutant "stale index files kept"          "if old.startswith('index-') and old.endswith('.json') and old != os.path.basename(path):" "if False:" stale
  run_mutant "link target run unbounded (F1)"  "{1,300})(?:#[^)]{0,300})?" "+)(?:#[^)]{0,300})?" link
  run_mutant "link fragment run unbounded (F1)" "#[^)]{0,300})?" "#[^)]*)?" link
  run_mutant "reversed-form look-back unbounded" "b = BEFORE.search(line, max(0, m.start() - BEFORE_WINDOW), m.start())" "b = BEFORE.search(line[:m.start()])" linear
  run_mutant "absolute paths no longer resolved (F2)" "rel = repo_relative(idx, a)" "rel = None" target
  run_mutant "relative paths taken from the repo root (F2)" "os.path.join(os.getcwd(), a)" "os.path.join(root, a)" cwd
  run_mutant "symlinks in a path not resolved (F2)" "full = os.path.realpath(a if os.path.isabs(a)" "full = os.path.abspath(a if os.path.isabs(a)" realpath
  run_mutant "folder without a slash not a folder (F2)" "if any(f.startswith(p.rstrip('/') + '/') for f in idx['files']) and p.rstrip('/'):" "if False:" dir
  run_mutant "absolute folder not recognised (F2)" "if rel is not None and any(f.startswith(rel + '/') for f in idx['files']):" "if False:" dir
  run_mutant "folder test loses its slash (F2)" "f.startswith(p.rstrip('/') + '/') for f in" "f.startswith(p.rstrip('/')) for f in" dir
  run_mutant "no pointer rule for look-alikes (F4)" "if undefined and m.group(1) not in SHORTENABLE and house is not None and len(m.group(2)) != house:" "if False:" pointer
  run_mutant "pointer never printed (F4)" "if ttype == 'id' and undefined:" "if False:" pointer
  run_mutant "four-digit ADR target resolves (F4)" "if pfx == DECISION_PREFIX and len(m.group(2)) > 3:" "if False:" adr4
  run_mutant "BUG-0079 target resolves" "if pfx != DECISION_PREFIX and padded_form(pfx, n, len(m.group(2)), idx['widths']):" "if False:" bug0079
  run_mutant "padded BUG form never padded" "return pfx in SHORTENABLE and bool(w) and tw > w and len(str(num)) < tw" "return False" bug0079
  run_mutant "BUG-0079 cited counts as BUG-079" "if pfx not in resolvable or padded_form(pfx, num, tw, widths):" "if pfx not in resolvable or (pfx == DECISION_PREFIX and tw > 3):" bug0079cite
  run_mutant "repo root unknown again" "return ('dir', '.')" "return (None, a)" rootdir
  run_mutant "repo root not recognised by its path" "        return ''                      # the repo root itself" "        return None                    # the repo root itself" rootdir
  run_mutant "'/' counts as the repo root" "    if full == base:" "    if full == base or full == os.sep:" rootdir
  run_mutant "./x.md read from the repo root again" "if not cwd_form and p in idx['file_set']:" "if (a[2:] if cwd_form else p) in idx['file_set']:" cwddot
  run_mutant "extra id families knob ignored"  "TICKET_IDS = env_words('HARNESS_REFS_IDS', 'USER DEC FEAT DOC BIZ SEC TBD')" "TICKET_IDS = 'USER DEC FEAT DOC BIZ SEC TBD'.split()" refsids
  wait
  i=1; while [ "$i" -le "$N" ]; do cat "$MB/$i/result"; grep -q '^  \(FAIL\|ERROR\)' "$MB/$i/result" && BAD=$((BAD+1)); i=$((i+1)); done
  after=$(shasum "$SRC/refs.sh" "$SRC/refs-index.py" | awk '{print $1}' | tr '\n' ' ')
  if [ "$before" = "$after" ]; then echo "  ok    the real refs.sh and refs-index.py are byte-identical after the mutation runs"
  else echo "  FAIL  the real code changed during the mutation runs"; BAD=$((BAD+1)); fi
  echo "refs mutants: $N mutants, $BAD problem(s)"
  [ "$BAD" = 0 ]; exit $?
fi

# ───────────────────────────── helpers ───────────────────────────────────────────────────────────────────────────
P=0; F=0; K=0; S=0
chk() { if [ "$2" = 0 ]; then P=$((P+1)); echo "  ok    $1"; else F=$((F+1)); echo "  FAIL  $1"; [ -n "${3:-}" ] && printf '        %s\n' "$3" | head -12; fi; }
# a row that fails today because of a defect in the code under test; counted apart from passes and failures
known() {
  if [ "$2" = 0 ]; then P=$((P+1)); echo "  ok    $1   (FIXED: this row was a known defect — remove the mark)"
  else K=$((K+1)); echo "  KNOWN-DEFECT  $1"; [ -n "${3:-}" ] && printf '        %s\n' "$3" | head -6; fi
}
skip() { S=$((S+1)); echo "  SKIP  $1 — $2 (unexercised: NOT a pass)"; }
w() { mkdir -p "$(dirname "$1")" && cat > "$1"; }     # w PATH <<'EOF' … EOF
run() { "$REFS" "$@" >"$T/out" 2>"$T/err"; RC=$?; OUT=$(cat "$T/out"); ERR=$(cat "$T/err"); }
has()  { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
hasE() { printf '%s\n' "$ERR" | grep -qF -- "$1"; }
cnt()  { printf '%s\n' "$OUT" | grep -cF -- "$1"; }
ln_of() { grep -nF -- "$2" "$1" | head -1 | cut -d: -f1; }          # ln_of FILE TEXT → first line number
# nocontrol FILE → 0 when the file holds no C0 (except tab/newline), DEL or C1 character
nocontrol() { python3 -I -c '
import sys
t = open(sys.argv[1], "rb").read().decode("utf-8")
bad = [c for c in t if (ord(c) < 32 and c not in "\n\t") or 0x7f <= ord(c) <= 0x9f]
sys.exit(1 if bad else 0)' "$1"; }
# cpu_of CMD ARGS... → the smaller of two CPU times (user+sys, in ms) of the child processes that running the command
# takes. CPU time, not wall time: a loaded machine stretches the clock, not the work (999999999 on a 120 s timeout).
cpu_of() { python3 -I -c '
import resource, subprocess, sys
best = None
for _ in range(2):
    b = resource.getrusage(resource.RUSAGE_CHILDREN)
    try:
        subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    except subprocess.TimeoutExpired:
        print(999999999)
        sys.exit(0)
    a = resource.getrusage(resource.RUSAGE_CHILDREN)
    ms = int(((a.ru_utime - b.ru_utime) + (a.ru_stime - b.ru_stime)) * 1000)
    best = ms if best is None else min(best, ms)
print(best)' "$@"; }
# runin DIR ARGS... → like run, from another working directory
runin() { local d="$1"; shift; ( cd "$d" && "$REFS" "$@" >"$T/out" 2>"$T/err" ); RC=$?; OUT=$(cat "$T/out"); ERR=$(cat "$T/err"); }
# edit_keep_mtime FILE TEXT → rewrite FILE with TEXT but restore its previous mtime to the nanosecond
edit_keep_mtime() { python3 -I -c '
import os, sys
p, text = sys.argv[1], sys.argv[2]
st = os.stat(p)
open(p, "w").write(text)
os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))' "$1" "$2"; }
newrepo() { R="$T/$1"; rm -rf "$R"; mkdir -p "$R"; cd "$R" || exit 2; git init -q . && git config user.email t@t && git config user.name t; }
nfiles() { git ls-files -co --exclude-standard | grep -vc '^\.refs-cache/'; }
# the cache folder, without parsing ls
cachefile() { find .refs-cache -maxdepth 1 -type f -name 'index-*.json' | head -1; }
nindex() { find .refs-cache -maxdepth 1 -type f -name 'index-*.json' | wc -l | tr -d ' '; }
cachels() { find .refs-cache -maxdepth 1 -mindepth 1 | sort; }

# ───────────────────────────── the main fixture ──────────────────────────────────────────────────────────────────
newrepo main
printf '.refs-cache/\n' > .gitignore
w README.md <<'EOF'
Top readme. It names ADR-002 and the file docs/cites.md.
EOF
w docs/adr/ADR-001-grants.md <<'EOF'
# ADR-001 grants

**Status:** Accepted (part 3 superseded by ADR-009)

Exact grants.
EOF
w docs/adr/ADR-002-platform.md <<'EOF'
# ADR-002 platform enforcement

**Status:** Accepted

See ADR-001 §2 and ADR-007 §1 and §2 here.
This ADR-002 mentions itself.
Also ADR 49 and ADR-49 and BUG-79 inline.
EOF
w docs/adr/ADR-007-x.md <<'EOF'
# ADR-007 x

**Status:** Accepted
EOF
w docs/adr/ADR-015-inv.md <<'EOF'
# ADR-015 invariants

**Status:** Accepted
EOF
w docs/adr/ADR-049-failopen.md <<'EOF'
# ADR-049 fail open

**Status:** Accepted
EOF
w docs/cites.md <<'EOF'
# cites
ADR-002 §4 part form
ADR-007 §1 and §2 two parts
ADR-015 rule 1 an invariant
§3 of ADR-001 reversed
ADR-007 §2–§3 range
ADR-001 §3, 2026-10-12 date tail
ADR-49 short and ADR 49 spaced and BUG-79 short
ADR-0130 and ADR-1000 are no adrs
MOD-SUB-03 is one token
UTF-8 SHA-256 ISO-8601 look-alikes
ADR-002 plain whole mention
planted undefined SEC-777 here
house width undefined WEB-06 here
short WIN-1 here
ADR-001 §3, 10-12 day-month tail
EOF
w docs/kinds.md <<'EOF'
# kinds
BUG-079 SEC-001 USER-001 DEC-001 FEAT-001 DOC-001 BIZ-001 T-001 TBD-001 WIN-01 OPS-01 QQQ-01 WEB-01 XX-1 H58 MOD-SUB-03
EOF
w docs/tickets/bug-register.md <<'EOF'
| ID | Sev | Summary | Status | Endpoint |
|---|---|---|---|---|
| BUG-079 | P1 | broke `scripts/foo.sh` and server/test/foo_test.go TestFooBar | open | svc-a, svc-b |
| BUG-080 | P2 | other | open | |

Notes below the table, not part of any row: see `scripts/foo.sh` again.
EOF
w docs/tickets/security.md <<'EOF'
| ID | Endpoint | Title |
|---|---|---|
| SEC-001 | svc-c | a |
| SEC-002 | | defined but never cited |
EOF
w docs/tickets/user.md <<'EOF'
| ID | Title |
|---|---|
| USER-001 | a |
EOF
w docs/tickets/decisions.md <<'EOF'
| ID | Title |
|---|---|
| DEC-001 | a |
EOF
w docs/tickets/features.md <<'EOF'
| ID | Title |
|---|---|
| FEAT-001 | a |
EOF
w docs/tickets/docs.md <<'EOF'
| ID | Title |
|---|---|
| DOC-001 | a |
EOF
w docs/tickets/biz.md <<'EOF'
| ID | Title |
|---|---|
| BIZ-001 | a |
EOF
w docs/backlog-tickets.md <<'EOF'
| ID | Title |
|---|---|
| T-001 | a |
EOF
w docs/tbd-parking-lot.md <<'EOF'
| ID | Title |
|---|---|
| TBD-001 | a |
EOF
w docs/feature-catalog-win.md <<'EOF'
| ID | Feature | Status |
|---|---|---|
| WIN-01 | a | done |
| OPS-01 | b | done |
| WEB-01 | c | done |
| QQQ-01 | invented prefix, nowhere in the script | done |
| XX-1 | one-digit house width | done |
| MOD-SUB-03 | multi-part prefix | done |
EOF
w docs/runner.md <<'EOF'
| ID | Title |
|---|---|
| H58 | wave |
EOF
w server/test/foo_test.go <<'EOF'
package s
func TestFooBar(t *testing.T) {} // harness:allow-uncited test fixture
EOF
w pkg/f.go <<'EOF'
package a
// ADR-002 §4 governs this.
// BUG-079 regression guard.
func F() {}
EOF
w scripts/foo.sh <<'EOF'
# ADR-001 §2 governs this script
echo hi
EOF
w api/openapi.yaml <<'EOF'
# ADR-002 §4 contract
EOF
w api/x.go <<'EOF'
// ADR-002 §4 contract
package api
EOF
w docs/sub/rel.md <<'EOF'
a [link](../adr/ADR-001-grants.md) and `scripts/foo.sh` and bare scripts/foo.sh and README.md here
EOF
MAIN="$R"; NMAIN=$(nfiles)

echo "-- A: every definition kind has a known positive (and a heading naming its kind)"
run ADR-002;   chk "A  ADR-002 is defined by its file, span starting at line 1 (kind adr)" "$([ $RC = 0 ] && has '== ADR-002 (adr) ==' && has 'defines: docs/adr/ADR-002-platform.md:1-'; echo $?)" "rc=$RC $OUT"
chk "A  the span of an ADR file ends at its last line (a 7-line file is shown as ':1-7', not ':1-8')" "$(has 'defines: docs/adr/ADR-002-platform.md:1-7'; echo $?)" "$(printf '%s\n' "$OUT" | grep '^defines')"
run BUG-079;   chk "A  BUG-079 defined at its table row (kind bug)" "$([ $RC = 0 ] && has '== BUG-079 (bug) ==' && has "defines: docs/tickets/bug-register.md:$(ln_of docs/tickets/bug-register.md '| BUG-079')"; echo $?)" "$OUT"
for pair in SEC-001:sec:security USER-001:user:user DEC-001:dec:decisions FEAT-001:feat:features DOC-001:doc:docs BIZ-001:biz:biz; do
  id=${pair%%:*}; rest=${pair#*:}; kind=${rest%%:*}; f=${rest#*:}
  run "$id"; chk "A  $id defined in docs/tickets/$f.md (kind $kind)" "$([ $RC = 0 ] && has "== $id ($kind) ==" && has "defines: docs/tickets/$f.md:3"; echo $?)" "rc=$RC $OUT"
done
run T-001;     chk "A  [G:refsids] T-001 defined in docs/backlog-tickets.md (kind t; the family comes from HARNESS_REFS_IDS)" "$([ $RC = 0 ] && has '== T-001 (t) ==' && has 'defines: docs/backlog-tickets.md:3'; echo $?)" "$OUT"
run TBD-001;   chk "A  TBD-001 defined in docs/tbd-parking-lot.md (kind tbd)" "$([ $RC = 0 ] && has '== TBD-001 (tbd) ==' && has 'defines: docs/tbd-parking-lot.md:3'; echo $?)" "$OUT"
run WIN-01;    chk "A  WIN-01 defined in docs/feature-catalog-win.md (kind catalog)" "$([ $RC = 0 ] && has '== WIN-01 (catalog) ==' && has 'defines: docs/feature-catalog-win.md:3'; echo $?)" "$OUT"
run QQQ-01;    chk "A  a catalog prefix invented by a row (QQQ) is an ID: prefixes are read from rows, never listed" "$([ $RC = 0 ] && has '== QQQ-01 (catalog) ==' && has 'defines: docs/feature-catalog-win.md:6'; echo $?)" "$OUT"
run H58;       chk "A  H58 defined by a runner row (kind runner)" "$([ $RC = 0 ] && has '== H58 (runner) ==' && has 'defines: docs/runner.md:3'; echo $?)" "$OUT"
run MOD-SUB-03; chk "A  MOD-SUB-03 (a three-part prefix MOD-SUB) is defined by a catalog row (kind catalog)" "$([ $RC = 0 ] && has '== MOD-SUB-03 (catalog) ==' && has 'defines: docs/feature-catalog-win.md:8'; echo $?)" "$OUT"
run SEC-002;   chk "A  a defined-but-uncited ID exits 1 and still shows its definition" "$([ $RC = 1 ] && has '== SEC-002 (sec) ==' && has 'defines: docs/tickets/security.md:4' && has 'NO REFERENCES to or from SEC-002 besides its definition'; echo $?)" "rc=$RC $OUT"

echo "-- A: not-IDs and look-alikes"
run UTF-8;     chk "A  UTF-8 is not an ID (exit 1, 'NO REFERENCES', no definition shown)" "$([ $RC = 1 ] && has 'NO REFERENCES' && ! has 'defines:'; echo $?)" "rc=$RC $OUT"
run SHA-256;   chk "A  SHA-256 is not an ID" "$([ $RC = 1 ] && has 'NO REFERENCES' && ! has 'defines:'; echo $?)" "rc=$RC $OUT"
run ISO-8601;  chk "A  ISO-8601 is not an ID" "$([ $RC = 1 ] && has 'NO REFERENCES' && ! has 'defines:'; echo $?)" "rc=$RC $OUT"
run --dangling
D_OUT="$OUT"; D_RC=$RC
chk "A  --dangling never lists UTF-8, SHA-256 or ISO-8601 (while it does list a real planted one)" "$([ $RC = 0 ] && ! has 'UTF-8' && ! has 'SHA-256' && ! has 'ISO-8601' && has 'SEC-777'; echo $?)" "$OUT"
chk "A  MOD-SUB-03 is one token: SUB-03 is neither dangling nor a target" "$(! printf '%s\n' "$OUT" | grep -qE '^  (SUB-03|ST-PAR|ST|PAR) '; echo $?)" "$OUT"
run SUB-03;    chk "A  refs.sh SUB-03 finds nothing (control: MOD-SUB-03 is cited on docs/cites.md)" "$([ $RC = 1 ] && has 'NO REFERENCES'; echo $?)" "rc=$RC $OUT"
run MOD-SUB-03; chk "A  MOD-SUB-03 is cited as one token on docs/cites.md:$(ln_of docs/cites.md 'MOD-SUB-03 is one')" "$(has "docs/cites.md:$(ln_of docs/cites.md 'MOD-SUB-03 is one'):"; echo $?)" "$OUT"
run ADR-0130;  chk "A  ADR-0130 (4 digits) names no ADR" "$([ $RC = 1 ] && has 'NO REFERENCES'; echo $?)" "rc=$RC $OUT"
run ADR-1000;  chk "A  ADR-1000 (4 digits) names no ADR" "$([ $RC = 1 ] && has 'NO REFERENCES'; echo $?)" "rc=$RC $OUT"
chk "A  --dangling lists neither ADR-0130, ADR-130 nor ADR-1000 (control: ADR-009 from a status line IS listed)" "$(printf '%s\n' "$D_OUT" | grep -qE 'ADR-009 ' && ! printf '%s\n' "$D_OUT" | grep -qE 'ADR-0?130|ADR-1000'; echo $?)" "$D_OUT"

echo "-- A: the edge kinds (one known positive each)"
run ADR-001
chk "A  cites-section: 'ADR-001 §2' in ADR-002 is an INBOUND cites-section of ADR-001 with the part" "$([ $RC = 0 ] && has '-- cites-section' && has "docs/adr/ADR-002-platform.md:5: §2"; echo $?)" "$OUT"
chk "A  decision-in-code: ADR-001 cited from scripts/foo.sh" "$(has '-- decision-in-code' && has "scripts/foo.sh:1:"; echo $?)" "$OUT"
chk "A  ... and a .md citation is never decision-in-code" "$(! printf '%s\n' "$OUT" | grep -A3 -- '-- decision-in-code' | grep -q 'docs/'; echo $?)" "$OUT"
run BUG-079
chk "A  code-cites: BUG-079 cited from a comment in pkg/f.go" "$(has '-- code-cites' && has "pkg/f.go:3:"; echo $?)" "$OUT"
chk "A  cites: BUG-079 in kinds.md and as 'BUG-79' in ADR-002 ([as \"BUG-79\"])" "$(has '-- cites' && has 'docs/kinds.md:2:' && has '[as "BUG-79"]'; echo $?)" "$OUT"
chk "A  OUTBOUND of a BUG row: bug-test (TestFooBar)" "$(has '-- test' && has 'TestFooBar'; echo $?)" "$OUT"
run scripts/foo.sh
chk "A  bug-file: scripts/foo.sh named in a BUG row, tagged with the owner BUG-079" "$([ $RC = 0 ] && has '-- bug-file' && has 'BUG-079'; echo $?)" "$OUT"
chk "A  mentions-path: backticks, bare path and markdown link: docs/sub/rel.md:1 (and only mentions-path there)" "$(has '-- mentions-path' && has 'docs/sub/rel.md:1:'; echo $?)" "$OUT"
chk "A  [G:owner] a path mentioned in prose BELOW the table (bug-register.md:6) belongs to no row: mentions-path, not bug-file of BUG-080" "$(printf '%s\n' "$OUT" | sed -n '/^-- mentions-path/,$p' | grep -qF 'docs/tickets/bug-register.md:6:' && ! printf '%s\n' "$OUT" | sed -n '/^-- bug-file/,/^-- /p' | grep -qF 'bug-register.md:6:'; echo $?)" "$OUT"
run BUG-080
chk "A  [G:owner] ... and BUG-080's OUTBOUND does not claim that path (control: BUG-079's does)" "$(! has 'scripts/foo.sh' ; echo $?)" "$OUT"
run BUG-079
chk "A  [G:owner] control: BUG-079's OUTBOUND lists scripts/foo.sh as bug-file and server/test/foo_test.go as bug-test" "$(has 'scripts/foo.sh' && has '-- path' && has 'bug-file' && has 'bug-test'; echo $?)" "$OUT"
run server/test/foo_test.go
chk "A  bug-test: a test path named in a BUG row is bug-test, not bug-file" "$([ $RC = 0 ] && has '-- bug-test' && ! has '-- bug-file'; echo $?)" "$OUT"
run TestFooBar
chk "A  a test name cited in a BUG row: inbound bug-test from the BUG row" "$([ $RC = 0 ] && has '== TestFooBar (test) ==' && has '-- bug-test' && has 'docs/tickets/bug-register.md:3'; echo $?)" "$OUT"
run docs/adr/ADR-001-grants.md
chk "A  mentions-path by markdown link RELATIVE to the file (../adr/ADR-001-grants.md from docs/sub/)" "$([ $RC = 0 ] && has 'docs/sub/rel.md:1:'; echo $?)" "$OUT"
run README.md
chk "A  a bare root file name (README.md) is a mentions-path from docs/sub/rel.md" "$([ $RC = 0 ] && has 'docs/sub/rel.md:1:'; echo $?)" "$OUT"
run MOD-SUB-03
run BUG-080

echo "-- A: part forms and --section"
sec() { local id="$1" n="$2"; shift 2; run "$id" --section "$n"; }
L_TWO=$(ln_of docs/cites.md 'ADR-002 §4'); L_LST=$(ln_of docs/cites.md 'ADR-007 §1 and §2'); L_RULE=$(ln_of docs/cites.md 'ADR-015 rule 1')
L_REV=$(ln_of docs/cites.md '§3 of ADR-001'); L_RNG=$(ln_of docs/cites.md 'ADR-007 §2–§3'); L_DATE=$(ln_of docs/cites.md 'ADR-001 §3, 2026')
run ADR-002 --section 4;  chk "A  'ADR-002 §4' names part 4 (docs/cites.md:$L_TWO)" "$([ $RC = 0 ] && has "docs/cites.md:$L_TWO:" && has 'api/x.go' ; echo $?)" "rc=$RC $OUT"
run ADR-002 --section 5;  chk "A  [G:section] --section 5 on ADR-002 drops the part-4 citations (control: section 4 above) " "$(! has "docs/cites.md:$L_TWO:"; echo $?)" "$OUT"
run ADR-007 --section 1;  chk "A  'ADR-007 §1 and §2' names part 1" "$(has "docs/cites.md:$L_LST:" && ! has "docs/cites.md:$L_RNG:"; echo $?)" "$OUT"
run ADR-007 --section 2;  chk "A  ... and part 2, and the range '§2–§3' names part 2 too" "$(has "docs/cites.md:$L_LST:" && has "docs/cites.md:$L_RNG:"; echo $?)" "$OUT"
run ADR-007 --section 3;  chk "A  [G:section] the range '§2–§3' names part 3, '§1 and §2' does not" "$(has "docs/cites.md:$L_RNG:" && ! has "docs/cites.md:$L_LST:"; echo $?)" "$OUT"
run ADR-015 --section 1;  chk "A  'ADR-015 rule 1' names part 1" "$([ $RC = 0 ] && has "docs/cites.md:$L_RULE:"; echo $?)" "$OUT"
run ADR-001 --section 3;  chk "A  '§3 of ADR-001' names part 3 (reversed form), and so does 'ADR-001 §3, 2026-10-12'" "$(has "docs/cites.md:$L_REV:" && has "docs/cites.md:$L_DATE:"; echo $?)" "$OUT"
run ADR-001 --section 2026; chk "A  [G:datetail] the date tail '§3, 2026-10-12' does not read part 2026 (no citation line, '0 ref(s)')" "$(! has "docs/cites.md:$L_DATE:" && has '0 ref(s) in 0 file(s) (only part 2026)'; echo $?)" "rc=$RC $OUT"
chk "A  --section N with no citation of part N exits 1 even when the ADR itself has outbound refs (as ADR-007 --section 9 below)" "$(if [ $RC = 1 ]; then echo 0; else echo 1; fi)" "rc=$RC"
run ADR-001 --section 20;  chk "A  [G:datetail] ... nor part 20 (the first digits of the year)" "$(! has "docs/cites.md:$L_DATE:"; echo $?)" "$OUT"
run ADR-001 --section 10;  chk "A  [G:datetail] ... nor part 10 (the month of the date)" "$(! has "docs/cites.md:$L_DATE:"; echo $?)" "$OUT"
L_DM=$(ln_of docs/cites.md 'ADR-001 §3, 10-12')
run ADR-001 --section 10;  chk "A  [G:datetail] a day-month tail '§3, 10-12' does not read part 10 (ASSUMPTION: 10-12 is a date, not a range of parts)" "$(if ! has "docs/cites.md:$L_DM:"; then echo 0; else echo 1; fi)" "$OUT"
run ADR-001 --section 3;   chk "A  [G:datetail] ... while it still names part 3 (control)" "$(if has "docs/cites.md:$L_DM:"; then echo 0; else echo 1; fi)" "$OUT"
run ADR-001;               chk "A  the whole-ADR view reports 'N ref(s) name a part of the decision' (not zero)" "$(has 'name a part of the decision'; echo $?)" "$OUT"
run BUG-079 --section 1;   chk "A  --section on a non-ADR target is a usage error (exit 2)" "$([ $RC = 2 ] && hasE '--section only applies to a decision-record target'; echo $?)" "rc=$RC $ERR"
run docs/cites.md --section 1; chk "A  --section on a file target is a usage error (exit 2)" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC"
run ADR-007 --section 9;   chk "A  [G:section] --section with no matching citation: exit 1, no cites lines (control: sections 1-3 match)" "$([ $RC = 1 ] && ! has 'docs/cites.md:'; echo $?)" "rc=$RC $OUT"

echo "-- A: variant forms resolve (and are tagged so)"
run ADR-49;     chk "A  ADR-49 resolves to ADR-049 with the citation tagged [as \"ADR-49\"] in ADR-002" "$([ $RC = 0 ] && has '== ADR-049 (adr) ==' && has '[as "ADR-49"]'; echo $?)" "$OUT"
run "ADR 49";   chk "A  'ADR 49' (one argument with a space) resolves to the same ADR" "$([ $RC = 0 ] && has '== ADR-049 (adr) ==' && has '[as "ADR 49"]'; echo $?)" "$OUT"
run adr-49;     chk "A  lower-case adr-49 resolves too" "$([ $RC = 0 ] && has '== ADR-049 (adr) =='; echo $?)" "$OUT"
run ADR-049;    chk "A  [G:adrspace] ADR-049 inbound includes the spaced citation 'ADR 49' of ADR-002:7" "$(has 'docs/adr/ADR-002-platform.md:7:' && has '[as "ADR 49"]'; echo $?)" "$OUT"
run BUG-79;     chk "A  BUG-79 resolves to BUG-079" "$([ $RC = 0 ] && has '== BUG-079 (bug) =='; echo $?)" "$OUT"
run "BUG 79";   chk "A  'BUG 79' (space) resolves to BUG-079" "$([ $RC = 0 ] && has '== BUG-079 (bug) =='; echo $?)" "$OUT"
run ADR-002;    chk "A  [G:owner] an ADR's own line citing itself ('This ADR-002 mentions itself', line 6) is not INBOUND" "$(! printf '%s\n' "$OUT" | sed -n '/== INBOUND/,/== OUTBOUND/p' | grep -qF 'docs/adr/ADR-002-platform.md:6:'; echo $?)" "$OUT"
chk "A  [G:owner] ... while ADR-002's citations of OTHER ids (ADR-007) are OUTBOUND with its line numbers" "$(has 'ADR-007' && has 'docs/adr/ADR-002-platform.md:5'; echo $?)" "$OUT"
chk "A  [G:owner] ... and the self-citation is neither inbound nor outbound-to-itself" "$(! printf '%s\n' "$OUT" | sed -n '/== OUTBOUND/,$p' | grep -qE '^  ADR-002 '; echo $?)" "$OUT"

echo "-- A: --dangling on the main fixture"
chk "A  --dangling exit 0 when something dangles; planted SEC-777 listed with first file:line" "$([ "$D_RC" = 0 ] && printf '%s\n' "$D_OUT" | grep -qE "SEC-777  1 ref\(s\) in 1 file\(s\), first docs/cites.md:$(ln_of docs/cites.md 'SEC-777')"; echo $?)" "$D_OUT"
chk "A  --dangling groups by kind (a '-- sec' group holds SEC-777)" "$(printf '%s\n' "$D_OUT" | grep -A1 -- '-- sec' | grep -q 'SEC-777'; echo $?)" "$D_OUT"
chk "A  --dangling does not list ids that ARE defined (BUG-079, SEC-001, WIN-01, H58)" "$(! printf '%s\n' "$D_OUT" | grep -qE '^  (BUG-079|SEC-001|WIN-01|H58) '; echo $?)" "$D_OUT"

newrepo clean
w docs/adr/ADR-001-a.md <<'EOF'
# ADR-001 a

**Status:** Accepted
EOF
w docs/cites.md <<'EOF'
cites ADR-001 only
EOF
run --dangling
chk "A  nothing to list: the 'no dangling ids' line and exit 1" "$([ $RC = 1 ] && has 'no dangling ids — scanned 2 files' && has '== DANGLING: 0 id(s)'; echo $?)" "rc=$RC $OUT"
w docs/cites2.md <<'EOF'
cites ADR-002 which does not exist
EOF
run --dangling
chk "A  control: the same repo plus one undefined cite lists it, exit 0" "$([ $RC = 0 ] && has 'ADR-002' && has '== DANGLING: 1 id(s)'; echo $?)" "rc=$RC $OUT"

cd "$MAIN" || exit 2
echo "-- B: exits and usage errors"
run;                         chk "B  no target: exit 2 with usage" "$([ $RC = 2 ] && hasE 'usage: refs.sh'; echo $?)" "rc=$RC $ERR"
run "";                      chk "B  empty target: exit 2" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run "   ";                   chk "B  blank target: exit 2" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run ADR-002 ADR-001;         chk "B  two targets: exit 2" "$([ $RC = 2 ] && hasE 'exactly one'; echo $?)" "rc=$RC $ERR"
run --bogus ADR-002;         chk "B  unknown option: exit 2" "$([ $RC = 2 ] && hasE 'unknown option --bogus'; echo $?)" "rc=$RC $ERR"
run -x;                      chk "B  a lone -x is an unknown option (exit 2)" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run --cap 0 ADR-002;         chk "B  --cap 0: exit 2" "$([ $RC = 2 ] && hasE '--cap needs a positive number'; echo $?)" "rc=$RC $ERR"
run --cap ADR-002;           chk "B  --cap with a non-number: exit 2" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run ADR-002 --cap;           chk "B  --cap with no value (last argument): exit 2" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run --cap -3 ADR-002;        chk "B  --cap -3: exit 2" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run --cap 2.5 ADR-002;       chk "B  --cap 2.5: exit 2" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run ADR-002 --section;       chk "B  --section with no value: exit 2" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run ADR-002 --section x;     chk "B  --section x: exit 2" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run ADR-002 --section 0;     chk "B  --section 0: exit 2" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run --dangling ADR-002;      chk "B  --dangling with a target: exit 2" "$([ $RC = 2 ] && hasE 'takes no target'; echo $?)" "rc=$RC $ERR"
run --dangling --section 1;  chk "B  --dangling with --section: exit 2" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run docs/adr/;               chk "B  a directory target: exit 2 ('is a directory')" "$([ $RC = 2 ] && hasE 'is a directory'; echo $?)" "rc=$RC $ERR"
run -h;                      chk "B  -h prints the usage and exits 0" "$([ $RC = 0 ] && has 'usage: refs.sh'; echo $?)" "rc=$RC"
run ADR-002 -h;              chk "B  --help after the target also exits 0 without running a query" "$([ $RC = 0 ] && ! has '== ADR-002'; echo $?)" "rc=$RC"
run zebra-unicorn;           chk "B  an unknown target: exit 1, says NO REFERENCES and the scanned-file count ($NMAIN)" "$([ $RC = 1 ] && has 'NO REFERENCES for: zebra-unicorn' && has "scanned $NMAIN files (0 skipped"; echo $?)" "rc=$RC $OUT"
run ADR-777;                 chk "B  a well-formed but unknown id (ADR-777): exit 1, the scanned count, never a crash" "$([ $RC = 1 ] && has "scanned $NMAIN files"; echo $?)" "rc=$RC $OUT"
printf 'x\n' > ./-zz.md; printf 'see ADR-002\n' > ./-zz.md
run -- -zz.md;              chk "B  a target starting with '-' goes after '--' (a file named -zz.md is found)" "$([ $RC = 0 ] && has '== -zz.md (file) =='; echo $?)" "rc=$RC $OUT"
"$REFS" -zz.md >/dev/null 2>&1; BARE_DASH_RC=$?
chk "B  ... control: the same name WITHOUT '--' is an option error (exit 2), so the row above proves the escape" "$(if [ "$BARE_DASH_RC" = 2 ]; then echo 0; else echo 1; fi)" "rc=$BARE_DASH_RC"
run -- -nothing-here;        chk "B  '-- -nothing-here' is a target (exit 1, not a usage error)" "$([ $RC = 1 ] && has 'NO REFERENCES for: -nothing-here'; echo $?)" "rc=$RC $OUT $ERR"
rm -f ./-zz.md

echo "-- B: hostile output (a repo line must not drive the terminal)"
newrepo host
printf '.refs-cache/\n' > .gitignore
w docs/adr/ADR-002-x.md <<'EOF'
# ADR-002 x

**Status:** Accepted
EOF
printf 'esc ADR-002 \033[31mRED\033[0m \033]0;title\007 bell \001 del \177 end\n' > docs/esc.md
printf 'c1 ADR-002 \302\233 31m CSI \302\205 NEL end\n' > docs/c1.md
printf 'crlf line one\r\nADR-002 on a CRLF line\r\n' > docs/crlf.md
printf 'a\013b\ncc\014dd\n\034x\035y\036z\n\302\205nel\n\342\200\250ls\n\342\200\251ps\nADR-002 after the odd separators\nlast\n' > docs/sep.md
printf 'lone\rcarriage ADR-002 return\n' > docs/cr.md
printf 'bad \377\376 bytes ADR-002 here \300\200\n' > docs/utf.md
run ADR-002
chk "B  control: the escape-laden file really holds ESC (so the row below proves a replacement)" "$(if [ "$(tr -cd '\033' < docs/esc.md | wc -c | tr -d ' ')" = 3 ]; then echo 0; else echo 1; fi)"
chk "B  ESC, BEL, SOH, DEL in a repo line are replaced: no raw control byte reaches stdout" "$([ $RC = 0 ] && has 'docs/esc.md:1:' && nocontrol "$T/out"; echo $?)" "$(cat -v "$T/out" | grep esc.md)"
chk "B  [G:ctrl] ... the line is still shown, with '?' where the control bytes were" "$(printf '%s\n' "$OUT" | grep 'docs/esc.md:1:' | grep -qF 'ADR-002 ?[31mRED?[0m ?]0;title? bell ? del ? end'; echo $?)" "$(cat -v "$T/out" | grep esc.md)"
chk "B  [G:ctrl] C1 controls (U+009B CSI, U+0085 NEL) are replaced too" "$([ "$(LC_ALL=C grep -c $'\xc2\x9b' "$T/out")" = 0 ] && [ "$(LC_ALL=C grep -c $'\xc2\x85' "$T/out")" = 0 ] && has 'docs/c1.md:1:'; echo $?)" "$(cat -v "$T/out" | grep c1.md)"
run $'\033[31mevil\033[0m'
chk "B  [G:ctrl] ESC in the QUERY is replaced in the 'NO REFERENCES for' echo (exit 1)" "$([ $RC = 1 ] && ! grep -q "$(printf '\033')" "$T/out" && has 'NO REFERENCES for: ?[31mevil?[0m'; echo $?)" "rc=$RC $(cat -v "$T/out")"
run $'ADR-002\n\033]0;pwn\007'
chk "B  a newline plus OSC in the query: nothing raw reaches stdout or stderr" "$(! grep -q "$(printf '\033')" "$T/out" "$T/err"; echo $?)" "$(cat -v "$T/out")"
run ADR-002 --cap 50
chk "B  CRLF: a cite on a CRLF line is found at the right line (docs/crlf.md:2) and no CR is printed" "$(has 'docs/crlf.md:2:' && ! grep -q "$(printf '\r')" "$T/out"; echo $?)" "$(cat -v "$T/out" | grep crlf)"
chk "B  [G:linesplit] \\x0b \\x0c \\x1c-\\x1e U+0085 U+2028 U+2029 in earlier lines do not drift the line number (docs/sep.md:$(grep -n 'ADR-002' docs/sep.md | cut -d: -f1))" "$(has "docs/sep.md:$(grep -n 'ADR-002' docs/sep.md | cut -d: -f1):"; echo $?)" "$(cat -v "$T/out" | grep sep.md)"
chk "B  a lone CR inside a line does not split it: the cite is on docs/cr.md:1" "$(has 'docs/cr.md:1:'; echo $?)" "$(cat -v "$T/out" | grep 'cr.md')"
chk "B  invalid UTF-8 bytes in a file: still scanned, cite found (docs/utf.md:1), exit 0, no traceback" "$([ $RC = 0 ] && has 'docs/utf.md:1:' && ! hasE 'Traceback'; echo $?)" "$(cat -v "$T/out" | grep utf.md) $ERR"
chk "B  stdout stays valid UTF-8 even after invalid input" "$(python3 -I -c 'import sys; open(sys.argv[1],"rb").read().decode("utf-8")' "$T/out" 2>/dev/null; echo $?)"

# a file NAME with a newline or an escape: git ls-files -z carries it, the printout must not let it inject lines
NLN=$'docs/we\nird.md'; ESCN=$'docs/e\033[31mscape.md'
if printf 'cites ADR-002 here\n' > "$NLN" 2>/dev/null && printf 'cites ADR-002 here\n' > "$ESCN" 2>/dev/null; then
  run ADR-002 --cap 50
  chk "B  control: the odd-named files are indexed (their name parts are listed)" "$([ $RC = 0 ] && has 'scape.md:1:' && has 'ird.md:1:'; echo $?)" "rc=$RC"
  chk "B  a file NAME with a newline does not split the output: no fake line starting 'ird.md:1:'" "$(! printf '%s\n' "$OUT" | grep -q '^ird.md'; echo $?)" "$(cat -v "$T/out" | grep -n 'ird\|we')"
  chk "B  a file name with ESC reaches stdout with the control byte replaced" "$(! grep -q "$(printf '\033')" "$T/out"; echo $?)" "$(cat -v "$T/out" | grep scape)"
  rm -f "$NLN" "$ESCN"
else skip "file names with a newline / ESC" "this filesystem refused them"; fi

echo "-- B: scope — binary, large, deleted, symlink"
newrepo scope
printf '.refs-cache/\n' > .gitignore
w docs/adr/ADR-002-x.md <<'EOF'
# ADR-002 x

**Status:** Accepted
EOF
printf 'text cite ADR-002 ok\n' > docs/text.md
printf 'bin\0 cite ADR-002 in binary\n' > docs/bin.md
python3 -I -c '
import sys
head = b"cite ADR-002 in a big file\n"
def mk(path, total): open(path, "wb").write(head + b"x" * (total - len(head)))  # harness:allow-uncited test fixture writer
mk("docs/big.md", 2 * 1024 * 1024 + 1)
mk("docs/exact.md", 2 * 1024 * 1024)
# NUL at byte 8192 is outside the 8 KB probe: still text; NUL at byte 8191 is inside it: binary
open("docs/nul-late.md", "wb").write(b"cite ADR-002 late nul\n" + b"y" * (8192 - 22) + b"\0")
open("docs/nul-early.md", "wb").write(b"cite ADR-002 early nul\n" + b"y" * (8191 - 23) + b"\0")
'
printf 'cite ADR-002 deleted soon\n' > docs/gone.md
ln -s text.md docs/link-file.md
ln -s ../docs docs/link-dir
ln -s nowhere.md docs/link-dangling.md
git add -- docs/gone.md >/dev/null 2>&1; rm -f docs/gone.md   # tracked, then deleted from the work tree
run ADR-002 --all
chk "B  control: the plain text file's cite is found" "$([ $RC = 0 ] && has 'docs/text.md:1:'; echo $?)" "rc=$RC $OUT"
chk "B  a binary file (NUL in the first 8 KB) is not scanned" "$(! has 'docs/bin.md' ; echo $?)" "$OUT"
chk "B  [G:sizelimit] a file over 2 MB is skipped; exactly 2 MB is scanned" "$(! has 'docs/big.md' && has 'docs/exact.md:1:'; echo $?)" "$OUT"
chk "B  a NUL at byte 8192 is outside the probe (scanned); at byte 8191 it is binary (skipped)" "$(has 'docs/nul-late.md:1:' && ! has 'docs/nul-early.md'; echo $?)" "$OUT"
chk "B  a listed-but-deleted file does not crash the run (exit 0, no traceback)" "$([ $RC = 0 ] && ! hasE 'Traceback'; echo $?)" "$ERR"
chk "B  stderr counts the skipped files: binary 2 + too-large 1 + unreadable (deleted + dangling link + dir link)" "$(hasE 'skipped' && [ "$(printf '%s' "$ERR" | sed -n 's/.*, \([0-9]*\) skipped.*/\1/p')" -ge 5 ]; echo $?)" "$ERR"
run zebra-unicorn
chk "B  the 'NO REFERENCES' line reports the skipped count" "$(printf '%s\n' "$OUT" | grep -qE '\([5-9] skipped as binary/too large/unreadable\)'; echo $?)" "$OUT"
run ADR-002 --all
chk "B  a symlink to a file is skipped: docs/link-file.md is not listed as a second citation of the same text" "$(! has 'docs/link-file.md'; echo $?)" "$OUT"
OUTSIDE="$T/outside-target.md"; printf 'secret ADR-002 line from OUTSIDE the repo\n' > "$OUTSIDE"; ln -s "$OUTSIDE" docs/link-out.md
run ADR-002 --all
chk "B  a symlink pointing OUTSIDE the repo is not read: its line is never printed" "$(! has 'link-out.md' && ! has 'OUTSIDE the repo'; echo $?)" "$OUT"
chk "B  a symlink to a directory and a dangling symlink: no crash (control: exit 0 above)" "$([ $RC = 0 ] && ! hasE 'Traceback' && ! has 'link-dir' && ! has 'link-dangling'; echo $?)" "$OUT $ERR"

echo "-- B: running conditions"
cd "$MAIN" || exit 2
run ADR-002; BASEOUT=$(cat "$T/out")
OUTSUB=$(cd "$MAIN/docs/adr" && "$REFS" ADR-002 2>/dev/null); RCSUB=$?
chk "B  run from a subdirectory: same answer as from the root, paths relative to the repo root" "$(if [ $RCSUB = 0 ] && [ "$OUTSUB" = "$BASEOUT" ]; then echo 0; else echo 1; fi)"
OUTNG=$(cd "$T" && "$REFS" ADR-002 2>&1); RCNG=$?
chk "B  outside a git repo: exit 2, 'LOOKUP FAILED — NOT no references'" "$([ $RCNG = 2 ] && printf '%s' "$OUTNG" | grep -q 'LOOKUP FAILED'; echo $?)" "rc=$RCNG $OUTNG"

# a big answer piped into head -1: the reader closes the pipe; no traceback may appear
newrepo pipe
w docs/adr/ADR-002-x.md <<'EOF'
# ADR-002 x

**Status:** Accepted
EOF
python3 -I -c '
with open("docs/many.md", "w") as f:
    for i in range(4000):
        f.write("line %d cites ADR-002 with padding %s\n" % (i, "p" * 40))'
"$REFS" ADR-002 >/dev/null 2>&1
( "$REFS" --all ADR-002 2>"$T/pipe-err" | head -1 >"$T/pipe-out" )
chk "B  control: the answer is big enough to fill a pipe (> 64 KB)" "$(if [ "$("$REFS" --all ADR-002 2>/dev/null | wc -c | tr -d ' ')" -gt 70000 ]; then echo 0; else echo 1; fi)"
chk "B  [G:brokenpipe] '| head -1' leaves no traceback and no 'internal error' on stderr" "$(! grep -qE 'Traceback|BrokenPipe|internal error|Exception' "$T/pipe-err" && [ -s "$T/pipe-out" ]; echo $?)" "$(cat "$T/pipe-err" | head -5)"
"$REFS" --all ADR-002 2>/dev/null | head -1 >/dev/null; chk "B  ... and the first line was delivered" "$(if [ "$(head -c 5 "$T/pipe-out")" = "== AD" ]; then echo 0; else echo 1; fi)" "$(cat "$T/pipe-out")"

# stray modules in the working directory (and next to the script) must never be imported
newrepo stray
w docs/adr/ADR-002-x.md <<'EOF'
# ADR-002 x

**Status:** Accepted
EOF
printf 'cites ADR-002\n' > docs/cites.md
for m in json re os subprocess hashlib bisect fnmatch time traceback; do printf 'import sys\nsys.stderr.write("STRAY %s IMPORTED\\n")\nsys.exit(77)\n' "$m" > "$m.py"; done
run ADR-002
chk "B  stray json.py / re.py / os.py … in the cwd are not imported (exit 0, no STRAY)" "$([ $RC = 0 ] && ! hasE STRAY && has '== ADR-002 (adr) =='; echo $?)" "rc=$RC $ERR"
CP="$T/copy"; mkdir -p "$CP"; cp "$(dirname "$REFS")/refs.sh" "$(dirname "$REFS")/refs-index.py" "$CP/"
for m in json re; do printf 'import sys\nsys.stderr.write("STRAY %s IMPORTED\\n")\nsys.exit(77)\n' "$m" > "$CP/$m.py"; done
OUT=$("$CP/refs.sh" ADR-002 2>"$T/err"); RC=$?; ERR=$(cat "$T/err")
chk "B  ... nor a stray json.py next to the script itself (python3 -I)" "$([ $RC = 0 ] && ! hasE STRAY; echo $?)" "rc=$RC $ERR"
python3 "$CP/refs-index.py" --root "$R" ADR-002 >/dev/null 2>"$T/err"; RC=$?
chk "B  control: WITHOUT -I the same stray module IS imported (exit 77), so the row above proves the isolation" "$(if [ $RC = 77 ]; then echo 0; else echo 1; fi)" "rc=$RC $(cat "$T/err")"
OUT=$(PYTHONPATH="$R" "$REFS" ADR-002 2>"$T/err"); RC=$?; ERR=$(cat "$T/err")
chk "B  PYTHONPATH pointing at stray modules is ignored too" "$([ $RC = 0 ] && ! hasE STRAY; echo $?)" "rc=$RC $ERR"

echo "-- B: an internal error exits 2, never 1"
newrepo crash
w docs/adr/ADR-002-x.md <<'EOF'
# ADR-002 x

**Status:** Accepted
EOF
w docs/cites.md <<'EOF'
cites ADR-002
EOF
run ADR-002; CACHEF=$(cachefile)
python3 -I -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p)); del d["widths"]; json.dump(d, open(p, "w"))' "$CACHEF"
run ADR-002
chk "B  [G:crashexit] a cache that parses but lacks a key crashes the run: exit 2 with 'internal error', NOT 1" "$([ $RC = 2 ] && hasE 'internal error' && hasE 'NOT "no references"'; echo $?)" "rc=$RC $ERR"
run --rebuild ADR-002
chk "B  control: --rebuild heals it (exit 0)" "$([ $RC = 0 ] && has '== ADR-002 (adr) =='; echo $?)" "rc=$RC $ERR"
printf '[]' > "$(cachefile)"
run ADR-002
chk "B  a cache file that is valid JSON of the wrong shape ([]) is rebuilt like a corrupt one, not a crash" "$([ $RC = 0 ] && has '== ADR-002 (adr) =='; echo $?)" "rc=$RC $(printf '%s' "$ERR" | tail -2)"
run --rebuild ADR-002

echo "-- C: the cache"
newrepo cache
w docs/adr/ADR-002-x.md <<'EOF'
# ADR-002 x

**Status:** Accepted
EOF
w docs/cites.md <<'EOF'
cites ADR-002 once
EOF
run ADR-002; C1="$T/c1.out"; cp "$T/out" "$C1"
chk "C  first run builds the index (stderr 'index built')" "$([ $RC = 0 ] && hasE 'index built'; echo $?)" "$ERR"
chk "C  the cache folder holds exactly one index-*.json" "$(if [ "$(nindex)" = 1 ]; then echo 0; else echo 1; fi)" "$(cachels)"
run ADR-002; C2="$T/c2.out"; cp "$T/out" "$C2"
chk "C  second run is a cache hit (stderr 'cache hit')" "$([ $RC = 0 ] && hasE 'cache hit' && ! hasE 'index built'; echo $?)" "$ERR"
chk "C  stdout is byte-identical between the build and the hit" "$(cmp -s "$C1" "$C2"; echo $?)"
run --rebuild ADR-002; cp "$T/out" "$T/c3.out"
chk "C  --rebuild forces a build even though a cache exists" "$(hasE 'index built'; echo $?)" "$ERR"
run --rebuild ADR-002
chk "C  stdout is byte-identical across two --rebuild runs" "$(cmp -s "$T/c3.out" "$T/out" && cmp -s "$T/c3.out" "$C1"; echo $?)"
run --rebuild --dangling; cp "$T/out" "$T/d1.out"; run --dangling; cp "$T/out" "$T/d2.out"
chk "C  --dangling output is identical between a build and a hit" "$(cmp -s "$T/d1.out" "$T/d2.out"; echo $?)"
run ADR-002
touch -t 202001010101 docs/cites.md; run ADR-002
chk "C  [G:cachekey] touching a file (same size, new mtime) rebuilds" "$(hasE 'index built'; echo $?)" "$ERR"
run ADR-002; chk "C  control: the run after that is a hit again" "$(hasE 'cache hit'; echo $?)" "$ERR"
printf 'cites ADR-002 once\nand ADR-002 twice\n' > docs/cites.md; run ADR-002
chk "C  [G:cachekey] a changed file (new size) rebuilds and the new line shows" "$(hasE 'index built' && has 'docs/cites.md:2:'; echo $?)" "$ERR"
run ADR-002
# same size, new content, new mtime: the mtime alone must trigger the rebuild
printf 'cites ADR-002 once\nand ADR-999 twice\n' > docs/cites.md; touch -t 202002020202 docs/cites.md; run ADR-002
chk "C  [G:cachekey] a changed file of the SAME size with a new mtime rebuilds (the old line 2 is gone)" "$(hasE 'index built' && ! has 'docs/cites.md:2:'; echo $?)" "$ERR $OUT"
run ADR-002; chk "C  control: a hit follows" "$(hasE 'cache hit'; echo $?)" "$ERR"
# different size, the very same mtime to the nanosecond: the size alone must trigger the rebuild
MT0=$(python3 -I -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' docs/cites.md)
edit_keep_mtime docs/cites.md $'cites ADR-002 once\nand ADR-002 twice, longer line\n'
MT1=$(python3 -I -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' docs/cites.md)
chk "C  control: the edit kept the mtime to the nanosecond and changed only the size" "$(if [ "$MT0" = "$MT1" ]; then echo 0; else echo 1; fi)" "$MT0 vs $MT1"
run ADR-002
chk "C  [G:cachekey] a different SIZE with the very same mtime still rebuilds (new line 2 shows)" "$(hasE 'index built' && has 'docs/cites.md:2:'; echo $?)" "$ERR"
run ADR-002
printf 'x\n' > docs/new.md; run ADR-002
chk "C  [G:cachekey] adding a file rebuilds" "$(hasE 'index built'; echo $?)" "$ERR"
run ADR-002; rm docs/new.md; run ADR-002
chk "C  [G:cachekey] removing a file rebuilds" "$(hasE 'index built'; echo $?)" "$ERR"
run ADR-002
mv docs/cites.md docs/renamed.md; run ADR-002
chk "C  [G:cachekey] renaming a file (same size, same mtime) rebuilds and the new path shows" "$(hasE 'index built' && has 'docs/renamed.md'; echo $?)" "$ERR $OUT"
run ADR-002
CP2="$T/copy2"; mkdir -p "$CP2"; cp "$(dirname "$REFS")/refs.sh" "$(dirname "$REFS")/refs-index.py" "$CP2/"; printf '\n# a comment that changes nothing but the content\n' >> "$CP2/refs-index.py"
run ADR-002; OUT=$("$CP2/refs.sh" ADR-002 2>"$T/err"); RC=$?; ERR=$(cat "$T/err")
chk "C  [G:cachekey] a changed refs-index.py (same repo, same files) does not reuse the old cache" "$([ $RC = 0 ] && hasE 'index built'; echo $?)" "rc=$RC $ERR"
# the untracked, NOT ignored cache folder is never indexed (else every run would change the key)
rm -f .gitignore; run --rebuild ADR-002; run ADR-002
chk "C  the .refs-cache/ folder itself is never scanned: a hit even when it is untracked and not gitignored" "$(hasE 'cache hit'; echo $?)" "$ERR"
run zebra-unicorn
chk "C  ... and it is not counted in the scanned files ($(nfiles) listed by git minus the cache)" "$(has "scanned $(( $(git ls-files -co --exclude-standard | grep -vc '^\.refs-cache/') )) files"; echo $?)" "$OUT"
# corrupt / empty / truncated index files
CF=$(cachefile)
for variant in "garbage{{{" "" '{"version": 2, "scanned": 1'; do
  printf '%s' "$variant" > "$CF"; run ADR-002
  chk "C  a corrupt index-*.json ('$(printf '%s' "$variant" | cut -c1-18)') is rebuilt, answer still correct" "$([ $RC = 0 ] && hasE 'cache unreadable, rebuilding' && hasE 'index built' && has '== ADR-002 (adr) =='; echo $?)" "rc=$RC $ERR"
done
printf '{"version": 1, "refs": [], "scanned": 0}' > "$CF"; run ADR-002
chk "C  an index of another VERSION is rebuilt, answer still correct" "$([ $RC = 0 ] && hasE 'index built' && has '== ADR-002 (adr) =='; echo $?)" "rc=$RC $ERR"
# stale siblings
mkdir -p .refs-cache/index-adir.json
printf '{}' > .refs-cache/index-stale1.json; printf '{}' > .refs-cache/index-stale2.json
printf 'keep' > .refs-cache/notes.txt; printf 'keep' > .refs-cache/index-x.json.bak; printf 'keep' > .refs-cache/other-index.json
touch docs/adr/ADR-002-x.md; run ADR-002
STALE_LEFT=$(find .refs-cache -maxdepth 1 -name 'index-stale*' | wc -l | tr -d ' '); INDEX_NOW=$(find .refs-cache -maxdepth 1 -type f -name 'index-[0-9a-f]*.json' | wc -l | tr -d ' ')
chk "C  [G:stale] stale index-*.json siblings are removed on write (exactly one real index remains)" "$(if [ "$STALE_LEFT" = 0 ] && [ "$INDEX_NOW" = 1 ]; then echo 0; else echo 1; fi)" "stale=$STALE_LEFT index=$INDEX_NOW"
chk "C  ... and nothing else in the cache folder is deleted (notes.txt, index-x.json.bak, other-index.json, a directory named index-adir.json)" "$(if [ -f .refs-cache/notes.txt ] && [ -f .refs-cache/index-x.json.bak ] && [ -f .refs-cache/other-index.json ] && [ -d .refs-cache/index-adir.json ]; then echo 0; else echo 1; fi)" "$(cachels)"
chk "C  ... and a directory named index-*.json in the cache does not crash the run" "$([ $RC = 0 ] && ! hasE Traceback; echo $?)" "$ERR"
# unwritable cache: the answer is still right, with a warning
rm -rf .refs-cache; printf 'i am a file, not a folder\n' > .refs-cache
run ADR-002
chk "C  a cache path that cannot be created: warning on stderr, correct answer, exit 0" "$([ $RC = 0 ] && hasE 'cache not written' && has '== ADR-002 (adr) =='; echo $?)" "rc=$RC $ERR"
run ADR-002
chk "C  ... and the next run is not a hit (nothing was cached) but still answers" "$([ $RC = 0 ] && ! hasE 'cache hit' && has '== ADR-002 (adr) =='; echo $?)" "$ERR"
rm -f .refs-cache; run ADR-002
if [ "$(id -u)" = 0 ]; then skip "read-only cache folder (chmod 555)" "running as root: chmod does not stop root"
else
  chmod 555 .refs-cache; touch docs/adr/ADR-002-x.md; run ADR-002; chmod 755 .refs-cache
  chk "C  a read-only cache folder: warning, correct answer, exit 0" "$([ $RC = 0 ] && hasE 'cache not written' && has '== ADR-002 (adr) =='; echo $?)" "rc=$RC $ERR"
fi
run --rebuild ADR-002

echo "-- D: yaml/yml as documents, duplicate definitions"
# yaml / yml / json / toml / jsonl are documents
newrepo yml
printf '.refs-cache/\n' > .gitignore
w docs/adr/ADR-002-x.md <<'EOF'
# ADR-002 x

**Status:** Accepted
EOF
mkdir -p api
printf '# ADR-002 §4 in yaml\nk: v\n' > api/openapi.yaml
printf '# ADR-002 §4 in yml\n' > api/other.yml
printf '{"note": "ADR-002 §4 in json"}\n' > api/d.json
printf '# ADR-002 §4 in toml\n' > api/d.toml
printf '{"note": "ADR-002 §4 in jsonl"}\n' > api/d.jsonl
printf '// ADR-002 §4 in go\n' > api/x.go
printf '# ADR-002 §4 in py\n' > api/x.py
printf '# ADR-002 §4 in sh\n' > api/x.sh
run ADR-002 --all
S_DOC=$(printf '%s\n' "$OUT" | sed -n '/^-- cites-section/,/^-- /p')
chk "D  .yaml and .yml cites are cites-section, never decision-in-code" "$(printf '%s\n' "$S_DOC" | grep -q 'api/openapi.yaml:1:' && printf '%s\n' "$S_DOC" | grep -q 'api/other.yml:1:'; echo $?)" "$OUT"
chk "D  .json, .toml and .jsonl are documents too (cites-section)" "$(printf '%s\n' "$S_DOC" | grep -q 'api/d.json:1:' && printf '%s\n' "$S_DOC" | grep -q 'api/d.toml:1:' && printf '%s\n' "$S_DOC" | grep -q 'api/d.jsonl:1:'; echo $?)" "$OUT"
D_CODE=$(printf '%s\n' "$OUT" | sed -n '/^-- decision-in-code/,/^-- /p')
chk "D  control: a .go, .py and .sh citation IS decision-in-code" "$(printf '%s\n' "$D_CODE" | grep -q 'api/x.go:1:' && printf '%s\n' "$D_CODE" | grep -q 'api/x.py:1:' && printf '%s\n' "$D_CODE" | grep -q 'api/x.sh:1:'; echo $?)" "$OUT"
chk "D  ... and the yaml file is not in the decision-in-code group" "$(! printf '%s\n' "$D_CODE" | grep -q 'yaml\|yml\|json\|toml'; echo $?)" "$D_CODE"

# duplicate definitions
newrepo dup
printf '.refs-cache/\n' > .gitignore
w docs/tickets/bug-register.md <<'EOF'
| ID | Sev | Summary | Status | Endpoint |
|---|---|---|---|---|
| BUG-080 | P2 | the open row | open | |
EOF
w docs/tickets/bug-archive.md <<'EOF'
| ID | Sev | Summary | Status | Endpoint |
|---|---|---|---|---|
| BUG-080 | P2 | the archived copy | closed | |
EOF
w docs/cites.md <<'EOF'
cites BUG-080
EOF
run --dangling
chk "D  a duplicate definition is listed in DUPLICATE DEFINITIONS with BOTH locations" "$(has '== DUPLICATE DEFINITIONS: 1 id(s) defined more than once ==' && printf '%s\n' "$OUT" | grep -qE '^  BUG-080  docs/tickets/bug-archive.md:3 · docs/tickets/bug-register.md:3$'; echo $?)" "rc=$RC $OUT"
chk "D  only duplicates (nothing undefined): --dangling exits 0, not 1, and prints no 'no dangling ids' line" "$([ $RC = 0 ] && ! has 'no dangling ids'; echo $?)" "rc=$RC $OUT"
run BUG-080
chk "D  the target view says it is defined twice and lists both definitions" "$(has 'NOTE: defined 2 times' && has 'defines: docs/tickets/bug-archive.md:3' && has 'defines: docs/tickets/bug-register.md:3'; echo $?)" "$OUT"
w docs/runner.md <<'EOF'
| ID | Title |
|---|---|
| H58 | wave |
EOF
w docs/runner-archive.md <<'EOF'
| ID | Title |
|---|---|
| H58 | wave (archived copy) |
EOF
run --dangling
chk "D  [G:generated] a real duplicate across runner.md and runner-archive.md is still listed (H58)" "$(printf '%s\n' "$OUT" | grep -qE '^  H58  docs/runner-archive.md:3 · docs/runner.md:3$'; echo $?)" "$OUT"
rm docs/runner-archive.md docs/runner.md docs/tickets/bug-archive.md
run --dangling
chk "D  control: with the second definitions removed, the duplicate section is gone ('no dangling', exit 1)" "$([ $RC = 1 ] && ! has 'DUPLICATE'; echo $?)" "rc=$RC $OUT"

echo "-- E: generated views cite, they never define"
newrepo gen
printf '.refs-cache/\n' > .gitignore
w docs/feature-catalog-win.md <<'EOF'
| ID | Feature | Status |
|---|---|---|
| WIN-01 | the real row | done |
EOF
w docs/feature-catalog-planned.md <<'EOF'
# planned
> **GENERATED by `scripts/render-catalog.py --render` — do NOT hand-edit; edit the area file and render.**

| ID | Feature | Status |
|---|---|---|
| WIN-01 | the copied row | done |
EOF
run --dangling
chk "E  [G:generated] a file with 'GENERATED … do not edit' in its first lines: its repeated row is not a duplicate (exit 1, nothing dangling)" "$([ $RC = 1 ] && ! has 'DUPLICATE'; echo $?)" "rc=$RC $OUT"
run WIN-01
chk "E  [G:generated] ... it is shown as a CITE of WIN-01 (feature-catalog-planned.md:6), and the real row is the only definition" "$(has 'defines: docs/feature-catalog-win.md:3' && ! has 'defines: docs/feature-catalog-planned.md' && ! has 'NOTE: defined' && has '-- cites' && has 'docs/feature-catalog-planned.md:6:'; echo $?)" "$OUT"
# control: the very same file without the marker IS a duplicate
sed -i.bak 's/GENERATED/MADE/' docs/feature-catalog-planned.md; rm -f docs/feature-catalog-planned.md.bak
run --dangling
chk "E  control: the same repeated row WITHOUT the marker is listed as a duplicate (so the rows above prove the rule)" "$([ $RC = 0 ] && has 'DUPLICATE DEFINITIONS' && has 'WIN-01  docs/feature-catalog-planned.md:6 · docs/feature-catalog-win.md:3'; echo $?)" "rc=$RC $OUT"
# marker in the head window: line 8 counts, line 9 does not
python3 -I -c '
import sys
for n, path in ((8, "docs/feature-catalog-l8.md"), (9, "docs/feature-catalog-l9.md")):
    lines = ["l%d" % i for i in range(1, 12)]
    lines[n - 1] = "GENERATED view - do not edit"
    lines += ["", "| ID | Feature | Status |", "|---|---|---|", "| WIN-01 | copy | done |"]
    open(path, "w").write("\n".join(lines) + "\n")'
rm -f docs/feature-catalog-planned.md
run --dangling
chk "E  [G:generated] the marker on line 8 makes a view; on line 9 it does not (only the line-9 file is a duplicate)" "$(has 'docs/feature-catalog-l9.md' && ! has 'docs/feature-catalog-l8.md'; echo $?)" "$OUT"
rm -f docs/feature-catalog-l8.md docs/feature-catalog-l9.md
# regions
w docs/feature-catalog.md <<'EOF'
# hub
intro
<!-- GENERATED:hub BEGIN — scripts/render-catalog.py --render; do NOT hand-edit this block -->
| ID | Feature | Status |
|---|---|---|
| WIN-01 | copy inside the region | done |
<!-- GENERATED:hub END -->
EOF
run --dangling
chk "E  [G:generated] a row inside <!-- GENERATED:x BEGIN … END --> is not a duplicate" "$([ $RC = 1 ] && ! has 'DUPLICATE'; echo $?)" "rc=$RC $OUT"
run WIN-01; chk "E  [G:generated] ... it is a cite (feature-catalog.md:6)" "$(has 'docs/feature-catalog.md:6:' && has '-- cites'; echo $?)" "$OUT"
w docs/feature-catalog.md <<'EOF'
# hub
<!-- GENERATED:hub BEGIN -->
<!-- GENERATED:hub END -->
| ID | Feature | Status |
|---|---|---|
| WIN-01 | a row AFTER the region ended | done |
EOF
run --dangling
chk "E  [G:generated] a row after the END marker defines again (a real duplicate)" "$([ $RC = 0 ] && has 'WIN-01  docs/feature-catalog-win.md:3 · docs/feature-catalog.md:6'; echo $?)" "$OUT"
w docs/feature-catalog.md <<'EOF'
# hub
Write `<!-- GENERATED:hub BEGIN` to open a region (prose).
`<!-- GENERATED:hub BEGIN -->` quoted at the start of a line.
| ID | Feature | Status |
|---|---|---|
| WIN-01 | a real row: backtick-quoted markers opened nothing | done |
EOF
run --dangling
chk "E  [G:generated] backtick-quoted marker text does not open a region (the row is a duplicate)" "$([ $RC = 0 ] && has 'WIN-01  docs/feature-catalog-win.md:3 · docs/feature-catalog.md:6'; echo $?)" "rc=$RC $OUT"
w docs/feature-catalog.md <<'EOF'
# hub
| ID | Feature | Status |
|---|---|---|
| OPS-01 | before the BEGIN marker: a real definition | done |
<!-- GENERATED:hub BEGIN -->
| ID | Feature | Status |
|---|---|---|
| WIN-01 | after an unterminated BEGIN | done |
| OPS-02 | still inside, to the end of the file | done |
EOF
run --dangling; D1="$OUT"
chk "E  [G:generated] an unterminated BEGIN runs to the end of the file: its rows cite, they do not define" "$(! printf '%s\n' "$D1" | grep -q 'DUPLICATE'; echo $?)" "$D1"
run OPS-01; chk "E  ... and the row BEFORE the BEGIN marker is a real definition" "$(has 'defines: docs/feature-catalog.md:4'; echo $?)" "$OUT"
run OPS-02; chk "E  ... while OPS-02 inside the region is not defined at all (it is only cited)" "$(has 'NOT DEFINED anywhere' || ! has 'defines:'; echo $?)" "$OUT"
w docs/feature-catalog.md <<'EOF'
# hub
This page is GENERATED elsewhere and then pasted here (prose only).

| ID | Feature | Status |
|---|---|---|
| WIN-01 | the word GENERATED alone is no view | done |
EOF
run --dangling
chk "E  [G:generated] the word GENERATED in prose without 'do not edit' does not make a view (duplicate)" "$([ $RC = 0 ] && has 'WIN-01  docs/feature-catalog-win.md:3 · docs/feature-catalog.md:6'; echo $?)" "rc=$RC $OUT"
w docs/feature-catalog.md <<'EOF'
# hub
Please do not edit this by hand, it is precious (no marker word).

| ID | Feature | Status |
|---|---|---|
| WIN-01 | 'do not edit' alone is no view either | done |
EOF
run --dangling
chk "E  [G:generated] ... nor does 'do not edit' without the word GENERATED" "$([ $RC = 0 ] && has 'WIN-01  docs/feature-catalog-win.md:3 · docs/feature-catalog.md:6'; echo $?)" "rc=$RC $OUT"
w docs/feature-catalog.md <<'EOF'
# GENERATED hub - DO NOT HAND-EDIT
| ID | Feature | Status |
|---|---|---|
| WIN-01 | the marker is matched case-insensitively for the edit words | done |
EOF
run --dangling
chk "E  [G:generated] 'do not hand-edit' in capitals is accepted as the marker (not a duplicate)" "$([ $RC = 1 ] && ! has 'DUPLICATE'; echo $?)" "rc=$RC $OUT"
# a generated view must not hide an ID that ONLY it mentions: it still cites (dangling if undefined)
w docs/feature-catalog.md <<'EOF'
# GENERATED hub - do not edit
| ID | Feature | Status |
|---|---|---|
| WIN-09 | only here | done |
EOF
run --dangling
chk "E  a generated view row of an id defined nowhere else is a dangling cite, not a definition (WIN-09)" "$([ $RC = 0 ] && has 'WIN-09' && has 'docs/feature-catalog.md'; echo $?)" "rc=$RC $OUT"
rm -f docs/feature-catalog.md

echo "-- F: short forms resolve only for ADR and BUG"
newrepo short
printf '.refs-cache/\n' > .gitignore
w docs/feature-catalog-win.md <<'EOF'
| ID | Feature | Status |
|---|---|---|
| WIN-01 | a | done |
| WEB-01 | b | done |
| XX-1 | one digit | done |
| XX-2 | one digit | done |
EOF
w docs/adr/ADR-049-x.md <<'EOF'
# ADR-049 x

**Status:** Accepted
EOF
w docs/tickets/bug-register.md <<'EOF'
| ID | Sev | Summary | Status | Endpoint |
|---|---|---|---|---|
| BUG-079 | P1 | a | open | |
EOF
w docs/cites.md <<'EOF'
short WIN-1 here
exact XX-1 here and long XX-01 here
house width WEB-06 here
named kind with no rows DOC-01 here and DOC-001 here
ADR-49 and BUG-79 still resolve
EOF
run --dangling; D2="$OUT"
run WIN-01;  chk "F  [G:shortenable] WIN-1 with only WIN-01 defined is NOT a cite of WIN-01 (docs/cites.md:2 absent)" "$(! has 'docs/cites.md:2:'; echo $?)" "$OUT"
chk "F  [G:shortenable] ... and not dangling either" "$(! printf '%s\n' "$D2" | grep -qE '^  WIN-0?1 '; echo $?)" "$D2"
run WIN-1;   chk "F  [G:shortenable] refs.sh WIN-1 exits 1 and offers 'Did you mean WIN-01?'" "$([ $RC = 1 ] && has 'Did you mean WIN-01?'; echo $?)" "rc=$RC $OUT"
run XX-1;    chk "F  a prefix whose rows really are X-1 matches exactly: XX-1 is defined and its cite found (cites.md:2)" "$([ $RC = 0 ] && has '== XX-1 (catalog) ==' && has 'docs/cites.md:2:'; echo $?)" "$OUT"
run XX-01;   chk "F  ... and XX-01 is a different token: not defined, not a cite" "$([ $RC = 1 ] && ! has 'defines:'; echo $?)" "$OUT"
chk "F  ... XX-01 is not dangling and XX-1 is not dangling" "$(! printf '%s\n' "$D2" | grep -qE '^  XX-0?1 '; echo $?)" "$D2"
chk "F  a house-width undefined token (WEB-06, WEB-01 defined) is dangling" "$(printf '%s\n' "$D2" | grep -qE '^  WEB-06 '; echo $?)" "$D2"
run WEB-06;  chk "F  refs.sh WEB-06 says NOT DEFINED anywhere (it is cited)" "$(has 'NOT DEFINED anywhere'; echo $?)" "$OUT"
chk "F  a named kind with no rows (DOC-01, DOC-001; no DOC table here) is still dangling, grouped under doc" "$(printf '%s\n' "$D2" | grep -A3 -- '-- doc' | grep -q 'DOC-01 ' && printf '%s\n' "$D2" | grep -A3 -- '-- doc' | grep -q 'DOC-001 '; echo $?)" "$D2"
run ADR-49;  chk "F  [G:shortenable] ADR-49 still resolves" "$([ $RC = 0 ] && has '== ADR-049 (adr) ==' && has 'docs/cites.md:5:'; echo $?)" "$OUT"
run BUG-79;  chk "F  [G:shortenable] BUG-79 still resolves" "$([ $RC = 0 ] && has '== BUG-079 (bug) ==' && has 'docs/cites.md:5:'; echo $?)" "$OUT"
chk "F  ADR-49 / BUG-79 resolve to defined ids, so they are not dangling" "$(! printf '%s\n' "$D2" | grep -qE '^  (ADR|BUG)-'; echo $?)" "$D2"
run "wIn-1"; chk "F  lower-case win-1 gets the same Did-you-mean answer (exit 1)" "$(if [ $RC = 1 ]; then echo 0; else echo 1; fi)" "rc=$RC $OUT"

echo "-- X: extra nasty cases (the test author's own)"
newrepo extra
printf '.refs-cache/\n' > .gitignore
w docs/adr/ADR-002-x.md <<'EOF'
# ADR-002 x

**Status:** Accepted
EOF
w docs/tickets/bug-register.md <<'EOF'
| **ID** | Sev | Summary | Status | Endpoint |
|---|---|---|---|---|
| **BUG-010** | P1 | bold id | open | `svc-a` |
| [BUG-011](#x) | P1 | linked id | open | |
EOF
w docs/other.md <<'EOF'
A quoted example row in a doc that is not a definition source:

| ID | Sev | Summary |
|---|---|---|
| BUG-900 | P3 | not a definition |
EOF
w docs/cites.md <<'EOF'
BUG-010 BUG-011 BUG-900 cited
ADR-002 §1,2 and ADR-002 §§2 and 3 and ADR-002 §2 to §3 done
Version-2 and MD5-1 and X-1 are not ids, nor is e-mail A-1
the path docs/adr/ADR-002-x.md. and (docs/adr/ADR-002-x.md) and docs/adr/ADR-002-x.md,
EOF
run BUG-010; chk "X  a bold **BUG-010** id cell defines BUG-010" "$(has '== BUG-010 (bug) ==' && has 'defines: docs/tickets/bug-register.md:3'; echo $?)" "$OUT"
run BUG-011; chk "X  a markdown-linked [BUG-011](#x) id cell defines BUG-011" "$(has '== BUG-011 (bug) =='; echo $?)" "$OUT"
run --dangling; chk "X  a quoted example row outside the definition globs does not define (BUG-900 dangles); header-less look-alikes never dangle" "$(has '  BUG-900 ' && ! has 'Version-2' && ! has 'MD5-1' && ! has ' X-1' && ! has ' A-1'; echo $?)" "$OUT"
run ADR-002 --section 2; chk "X  '§1,2', '§§2 and 3', '§2 to §3' all name part 2 (cites.md:2)" "$(has 'docs/cites.md:2:'; echo $?)" "$OUT"
run ADR-002 --section 3; chk "X  ... and part 3" "$(has 'docs/cites.md:2:'; echo $?)" "$OUT"
run ADR-002 --section 1; chk "X  ... and part 1" "$(has 'docs/cites.md:2:'; echo $?)" "$OUT"
run docs/adr/ADR-002-x.md; chk "X  a path followed by '.', ',' or ')' is still a mentions-path (docs/cites.md:4)" "$([ $RC = 0 ] && has 'docs/cites.md:4:'; echo $?)" "$OUT"
run ./docs/adr/ADR-002-x.md; chk "X  a ./-prefixed path target resolves to the same file" "$([ $RC = 0 ] && has '== docs/adr/ADR-002-x.md (file) =='; echo $?)" "$OUT"
run docs/adr; chk "X  a directory without trailing slash is just unknown (exit 1), not a crash" "$(if [ $RC = 1 ] || [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run ADR-002 --cap 1 --all; chk "X  --all wins over --cap (no TRUNCATED)" "$(! has TRUNCATED; echo $?)" "$OUT"
python3 -I -c '
with open("docs/many.md", "w") as f:
    for i in range(60): f.write("n%d cites ADR-002\n" % i)'
run ADR-002 --cap 5; chk "X  --cap 5: 5 lines of the 60 shown and the rest announced as TRUNCATED (use --all)" "$(has '… 56 more cites line(s) — TRUNCATED (use --all)' || has 'TRUNCATED'; echo $?)" "$OUT"
run ADR-002; chk "X  the default cap (40) truncates 60 lines and says so" "$(has 'TRUNCATED (use --all)'; echo $?)" "$OUT"
run ADR-002 --all; chk "X  --all shows all 60 and no TRUNCATED" "$([ "$(cnt 'docs/many.md:')" = 60 ] && ! has TRUNCATED; echo $?)" "n=$(cnt 'docs/many.md:')"
python3 -I -c '
open("docs/long.md", "w").write("x" * 400 + " ADR-002 " + "y" * 400 + "\n")'
run ADR-002 --all; chk "X  a 800-char line is windowed AROUND the match (the citation is visible in the output)" "$(printf '%s\n' "$OUT" | grep 'docs/long.md:1:' | grep -qF 'ADR-002'; echo $?)" "$(printf '%s\n' "$OUT" | grep 'docs/long.md:1:' | cut -c1-300)"

newrepo parts
printf '.refs-cache/\n' > .gitignore
w docs/adr/ADR-002-x.md <<'EOF'
# ADR-002 x

**Status:** Accepted
EOF
w docs/adr/ADR-003-x.md <<'EOF'
# ADR-003 x

**Status:** Accepted
EOF
w docs/adr/ADR-049-x.md <<'EOF'
# ADR-049 x

**Status:** Accepted
EOF
mkdir -p "docs/my dir"
# shellcheck disable=SC2016  # the backticks are literal fixture text, not a command substitution
printf 'ADR-002 §4.2 and ADR-002 §10 and ADR-002 §1-3 and ADR-002 §2, 4 and 5\n(ADR-002) [ADR-002] `ADR-002` ADR-002. ADR-002, **ADR-002**\nADR-002 §1 and ADR-003 §2\nADR 49 §3 and ADR-49 §4 and ADR-049 invariant 6\nno newline at end ADR-003' > "docs/my dir/é n.md"
P1="docs/my dir/é n.md"
run ADR-002 --section 4;  chk "X  '§4.2' and '§2, 4 and 5' both name part 4 (line 1)" "$(has "$P1:1:"; echo $?)" "$OUT"
run ADR-002 --section 10; chk "X  '§10' names part 10, and only the line holding it (line 1)" "$(has "$P1:1:" && ! has "$P1:3:"; echo $?)" "$OUT"
run ADR-002 --section 1;  chk "X  part 1 is found in '§1-3' and '§1' (lines 1 and 3) but '§10' alone does not make it part 1" "$(has "$P1:3:" && has "$P1:1:"; echo $?)" "$OUT"
run ADR-002 --section 3;  chk "X  the range '§1-3' covers part 3; line 3 (§1 only) does not" "$(has "$P1:1:" && ! has "$P1:3:"; echo $?)" "$OUT"
run ADR-002 --section 7;  chk "X  part 7 is named nowhere: no citation lines (control: parts 1-4 above find some)" "$(! has "$P1:"; echo $?)" "$OUT"
run ADR-002;  chk "X  a cite wrapped in ( ) [ ] backticks ** or followed by . , is still a cite (line 2)" "$(has "$P1:2:"; echo $?)" "$OUT"
run ADR-003;  chk "X  a cite on the last line WITHOUT a trailing newline is found at line 5, in a non-ASCII, space-containing path" "$([ $RC = 0 ] && has "$P1:5:" && has "$P1:3:"; echo $?)" "$OUT"
run ADR-049 --section 3;  chk "X  [G:adrspace] 'ADR 49 §3' (space form with a part) names part 3 of ADR-049" "$([ $RC = 0 ] && has "$P1:4:"; echo $?)" "$OUT"
run ADR-049 --section 4;  chk "X  [G:adrspace] 'ADR-49 §4' names part 4" "$(has "$P1:4:"; echo $?)" "$OUT"
run ADR-049 --section 6;  chk "X  'invariant 6' is a part designator too" "$(has "$P1:4:"; echo $?)" "$OUT"
run " ADR-003 ";  chk "X  a target with surrounding spaces is trimmed" "$([ $RC = 0 ] && has '== ADR-003 (adr) =='; echo $?)" "$OUT"
w docs/runner.md <<'EOF'
| ID | Title |
|---|---|
| H58 | wave |
EOF
printf 'wave H58 mentioned\n' > docs/w.md
run h58;  chk "X  a lower-case runner id (h58) resolves to H58" "$([ $RC = 0 ] && has '== H58 (runner) =='; echo $?)" "$OUT"
run win-1;  chk "X  an unknown lower-case id is just unknown (exit 1)" "$(if [ $RC = 1 ]; then echo 0; else echo 1; fi)" "$OUT"

newrepo guards
printf '.refs-cache/\n' > .gitignore
w docs/adr/ADR-123-x.md <<'EOF'
# ADR-123 x

**Status:** Accepted
EOF
w docs/adr/ADR-049-x.md <<'EOF'
# ADR-049 x

**Status:** Accepted
EOF
w docs/tickets/bug-register.md <<'EOF'
| ID | Sev | Summary | Status | Endpoint |
|---|---|---|---|---|
| BUG-079 | P1 | a | open | |
EOF
w docs/lookalikes.md <<'EOF'
ADR 1234 and ADR 49abc and ADR 49_x are look-alikes
XADR 49 and PADR-49 and _ADR 49 and FOO-ADR 49 and x-ADR-49 are look-alikes too
x_BUG-079 and aBUG-079 and 1BUG-079 and BUG-079x and BUG-079_x and BUG_079 are look-alikes as well
EOF
w docs/clean.md <<'EOF'
control: ADR 49 and ADR-123 and BUG-079 each stand alone here
EOF
run ADR-049;  chk "X  [G:adrspace] 'ADR 49abc', 'ADR 49_x', 'XADR 49', 'PADR-49', '_ADR 49', 'FOO-ADR 49' are not citations of ADR-049 (control: docs/clean.md:1 is)" "$(if [ $RC = 0 ] && has 'docs/clean.md:1:' && ! has 'docs/lookalikes.md'; then echo 0; else echo 1; fi)" "$OUT"
run ADR-123;  chk "X  [G:adrspace] 'ADR 1234' is not a citation of ADR-123 (control: docs/clean.md:1 is)" "$(if [ $RC = 0 ] && has 'docs/clean.md:1:' && ! has 'docs/lookalikes.md'; then echo 0; else echo 1; fi)" "$OUT"
run BUG-079;  chk "X  [G:tok] 'x_BUG-079', 'aBUG-079', '1BUG-079', 'BUG-079x', 'BUG-079_x' are not citations of BUG-079 (control: docs/clean.md:1 is)" "$(if [ $RC = 0 ] && has 'docs/clean.md:1:' && ! has 'docs/lookalikes.md'; then echo 0; else echo 1; fi)" "$OUT"

newrepo bom
printf '.refs-cache/\n' > .gitignore
mkdir -p docs/tickets
printf '\357\273\277| ID | Sev | Summary | Status | Endpoint |\n|---|---|---|---|---|\n| BUG-079 | P1 | a | open | |\n' > docs/tickets/bug-register.md
printf 'cites BUG-079 here\n' > docs/c.md
printf '| ID | Sev | Summary | Status | Endpoint |\n|---|---|---|---|---|\n| BUG-080 | P1 | a | open | |\n' > docs/tickets/other.md
printf 'cites BUG-080 here\n' >> docs/c.md
run BUG-080;  chk "X  control: the same table without a BOM defines BUG-080" "$(if [ $RC = 0 ] && has '== BUG-080 (bug) =='; then echo 0; else echo 1; fi)" "$OUT"
run BUG-079
chk "X  a UTF-8 BOM before the header of the FIRST table of a definition file does not hide the table: BUG-079 is defined, not 'NOT DEFINED anywhere'" "$(if has '== BUG-079 (bug) ==' && ! has 'NOT DEFINED'; then echo 0; else echo 1; fi)" "$OUT"

# unreadable file, long code line, story-block ownership, ./ paths, URL links, outbound cap
newrepo misc
printf '.refs-cache/\n' > .gitignore
w docs/adr/ADR-002-x.md <<'EOF'
# ADR-002 x

**Status:** Accepted
EOF
printf 'cites ADR-002 here\n' > docs/ok.md
printf 'cites ADR-002 but unreadable\n' > docs/secret.md
if [ "$(id -u)" = 0 ]; then skip "an unreadable file (chmod 000)" "running as root: chmod does not stop root"
else
  chmod 000 docs/secret.md; run ADR-002 --all; chmod 644 docs/secret.md
  chk "X  an unreadable file (mode 000) is skipped and counted, never a crash; the readable file is still found" "$(if [ $RC = 0 ] && has 'docs/ok.md:1:' && ! has 'docs/secret.md' && ! hasE Traceback && hasE '1 skipped'; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
fi
python3 -I -c '
long_line = "x" * 25000 + " ADR-002 " + "y" * 10 + "\n"
open("web-min.js", "w").write(long_line)
open("docs/min.md", "w").write(long_line)'
run ADR-002 --all
chk "X  a 25,000-char line is scanned in a document (docs/min.md:1) but skipped in a code file (web-min.js, the 20,000-char minified-code limit; OBSERVATION: the header of refs-index.py does not name this limit and the skip is not counted)" "$(if has 'docs/min.md:1:' && ! has 'web-min.js'; then echo 0; else echo 1; fi)" "$OUT"
w docs/x.md <<'EOF'
target file
EOF
printf 'dotted ./docs/x.md here\nand [a web link](https://example.com/docs/x.md) and [abs](/docs/x.md) here\n' > docs/m.md
run docs/x.md
chk "X  a ./docs/x.md mention counts as a path mention (docs/m.md:1)" "$(if has 'docs/m.md:1:'; then echo 0; else echo 1; fi)" "$OUT"
chk "X  an https:// link and a /-rooted link to that name are not path mentions (docs/m.md:2 absent)" "$(if ! has 'docs/m.md:2:'; then echo 0; else echo 1; fi)" "$OUT"
w docs/outbound.md <<'EOF'
cites ADR-002 and docs/x.md and docs/ok.md and docs/m.md and docs/min.md
EOF
run docs/outbound.md --cap 1
chk "X  --cap 1 on a file with many OUTBOUND targets announces the rest as TRUNCATED (use --all)" "$(if has 'more target(s) — TRUNCATED (use --all)'; then echo 0; else echo 1; fi)" "$OUT"
run docs/outbound.md --all
chk "X  ... and --all lists every one of them (control: the 4 path targets and the ADR)" "$(if ! has TRUNCATED && has 'ADR-002' && has 'docs/x.md' && has 'docs/ok.md' && has 'docs/m.md' && has 'docs/min.md'; then echo 0; else echo 1; fi)" "$OUT"

echo "-- R: review fixes F1-F4 and the CPU-time ratio for long-line rows"
# The long-line rows compare CPU time at size N and 2N (and against a same-size plain line), never seconds: the machine
# may be under heavy load (a gate run holds the test lock) and wall time then proves nothing. Linear work doubles
# (ratio about 2.0, or about 1.0 while process start-up dominates); quadratic work quadruples (about 4.0). The line
# between them is 3.0. The detector itself is proved on a quadratic and a linear Python loop (controls below).
newrepo scale
printf '.refs-cache/\n' > .gitignore
w docs/adr/ADR-001-x.md <<'EOF'
# ADR-001 x

**Status:** Accepted
EOF
SC_FAIL=999999999
Q_LOOP='n = 2500; sum(1 for i in range(n) for j in range(n))'
L_LOOP='n = 1500000; sum(1 for i in range(n))'
q1=$(cpu_of python3 -I -c "$Q_LOOP"); q2=$(cpu_of python3 -I -c "${Q_LOOP/2500/5000}")
l1=$(cpu_of python3 -I -c "$L_LOOP"); l2=$(cpu_of python3 -I -c "${L_LOOP/1500000/3000000}")
QR=$(( 100 * q2 / (q1 > 0 ? q1 : 1) )); LR=$(( 100 * l2 / (l1 > 0 ? l1 : 1) ))
chk "R  control: the CPU-ratio detector sees a quadratic loop (2n vs n = ${QR}%, must be over 300%)" "$(if [ "$QR" -gt 300 ]; then echo 0; else echo 1; fi)" "q1=${q1}ms q2=${q2}ms"
chk "R  control: ... and a linear loop stays under the line (2n vs n = ${LR}%, must be under 300%)" "$(if [ "$LR" -lt 300 ]; then echo 0; else echo 1; fi)" "l1=${l1}ms l2=${l2}ms"
# scale_check LABEL TAG PYTHON-EXPRESSION-IN-n N : CPU(2N)/CPU(N) under 3.0 and CPU(N)/CPU(plain line of the same size) under 25
scale_check() {
  local label="$1" tag="$2" expr="$3" n="$4" t1 t2 tp size ratio vs
  python3 -I -c 'import sys; n = int(sys.argv[2]); open("docs/scale.md", "w", encoding="utf-8").write(eval(sys.argv[1]))' "$expr" "$n"
  size=$(wc -c < docs/scale.md | tr -d ' ')
  t1=$(cpu_of "$REFS" --rebuild ADR-001)
  python3 -I -c 'import sys; n = 2 * int(sys.argv[2]); open("docs/scale.md", "w", encoding="utf-8").write(eval(sys.argv[1]))' "$expr" "$n"
  t2=$(cpu_of "$REFS" --rebuild ADR-001)
  python3 -I -c 'import sys; open("docs/scale.md", "w", encoding="utf-8").write("a" * int(sys.argv[1]) + " /\n")' "$size"
  tp=$(cpu_of "$REFS" --rebuild ADR-001)
  ratio=$(( 100 * t2 / (t1 > 0 ? t1 : 1) )); vs=$(( 100 * t1 / (tp > 0 ? tp : 1) ))
  chk "R  [G:$tag] $label: CPU at 2N is ${ratio}% of CPU at N (limit 300%) and N costs ${vs}% of a same-size plain line (limit 2500%)" "$(if [ "$t1" -lt "$SC_FAIL" ] && [ "$ratio" -lt 300 ] && [ "$vs" -lt 2500 ]; then echo 0; else echo 1; fi)" "N=$n size=$size t1=${t1}ms t2=${t2}ms plain=${tp}ms"
}
# F1: the markdown-link pattern was quadratic on `](a](a...` and on `](a#](a#...` (no closing parenthesis)
scale_check "F1 a '](a' link line (24 KB, and a '/' so the link scan runs)" link '"](a" * n + " /\n"' 8000
scale_check "F1 a '](a#' link-with-fragment line (the fragment run)" link '"](a#" * n + " /\n"' 6000
scale_check "F1 one long unclosed target '](' + a's" link '"x/](" + "a" * (n * 3) + "\n"' 8000
# the class: plain mentions followed by nothing (the reversed-form look-back)
scale_check "a line of plain 'ADR-001 ' mentions" linear '"ADR-001 " * n + "\n"' 3000
scale_check "a line of 'ADR-001 §1 ' mentions" linear '"ADR-001 §1 " * n + "\n"' 3000
scale_check "a line of '§1 of ADR-001 ' reversed-form mentions" linear '"§1 of ADR-001 " * n + "\n"' 3000
rm -f docs/scale.md
# function: the bounded link pattern still finds real links, with and without a fragment
newrepo linkfn
printf '.refs-cache/\n' > .gitignore
w docs/adr/ADR-001-grants.md <<'EOF'
# ADR-001 grants

**Status:** Accepted
EOF
w docs/sub/rel.md <<'EOF'
plain [a](../adr/ADR-001-grants.md) link
with fragment [b](../adr/ADR-001-grants.md#section-2) link
long fragment [c](../adr/ADR-001-grants.md#VERYLONGFRAGMENT) link
EOF
python3 -I -c 'open("docs/sub/rel.md", "a").write("target over 300 chars [d](" + "a/" * 200 + "x.md) and a long fragment [e](../adr/ADR-001-grants.md#" + "f" * 400 + ")\n")'
run docs/adr/ADR-001-grants.md
chk "R  F1 control: a link with and without a fragment is still a mentions-path (rel.md:1, :2, :3)" "$(if [ $RC = 0 ] && has 'docs/sub/rel.md:1:' && has 'docs/sub/rel.md:2:' && has 'docs/sub/rel.md:3:'; then echo 0; else echo 1; fi)" "$OUT"
chk "R  F1 an over-long link target or fragment (> 300 chars) is not matched and does not crash (rel.md:4 absent, exit 0 above)" "$(if ! has 'docs/sub/rel.md:4:' && ! hasE Traceback; then echo 0; else echo 1; fi)" "$OUT $ERR"

# F2: file targets given as absolute or cwd-relative paths, and folders
newrepo tgt
printf '.refs-cache/\nignored.md\n' > .gitignore
w docs/adr/ADR-001-grants.md <<'EOF'
# ADR-001 grants

**Status:** Accepted
EOF
w docs/cites.md <<'EOF'
cites ADR-001 here
EOF
w docs/sub/x.md <<'EOF'
sub x  harness:allow-uncited (fixture text, not code)
EOF
w docs/m.md <<'EOF'
see docs/sub/x.md here
EOF
printf 'root x\n' > x.md
printf 'ignored\n' > ignored.md
printf 'notes\n' > docs/adr-notes.md
TP="$R"
run docs/cites.md; cp "$T/out" "$T/ref.out"; REF_RC=$RC
chk "R  F2 control: the repo-relative answer exists (docs/cites.md, exit 0, outbound ADR-001)" "$(if [ "$REF_RC" = 0 ] && has '== docs/cites.md (file) ==' && has 'ADR-001'; then echo 0; else echo 1; fi)" "$OUT"
run "$TP/docs/cites.md"
chk "R  F2 [G:target] an ABSOLUTE path gives the same answer as the repo-relative one (stdout identical, exit 0)" "$(if [ $RC = 0 ] && cmp -s "$T/ref.out" "$T/out"; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run "$TP//docs//cites.md"
chk "R  F2 [G:target] ... with doubled slashes" "$(if [ $RC = 0 ] && cmp -s "$T/ref.out" "$T/out"; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run "$TP/docs/sub/../cites.md"
chk "R  F2 [G:target] ... with a '..' inside" "$(if [ $RC = 0 ] && cmp -s "$T/ref.out" "$T/out"; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
ln -s "$TP" "$T/linkroot"
run "$T/linkroot/docs/cites.md"
chk "R  F2 [G:realpath] ... through a symlink to the repo root (the root itself is a link)" "$(if [ $RC = 0 ] && cmp -s "$T/ref.out" "$T/out"; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
runin "$TP/docs/sub" ../cites.md
chk "R  F2 [G:cwd] from a SUBFOLDER, a cwd-relative path ('../cites.md') gives the same answer" "$(if [ $RC = 0 ] && cmp -s "$T/ref.out" "$T/out"; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
runin "$TP/docs/sub" ../../docs/cites.md
chk "R  F2 [G:cwd] ... '../../docs/cites.md'" "$(if [ $RC = 0 ] && cmp -s "$T/ref.out" "$T/out"; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
runin "$TP/docs/sub" ./../cites.md
chk "R  F2 [G:cwd] ... './../cites.md'" "$(if [ $RC = 0 ] && cmp -s "$T/ref.out" "$T/out"; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
runin "$TP/docs/sub" "$TP/docs/cites.md"
chk "R  F2 an absolute path typed in a subfolder" "$(if [ $RC = 0 ] && cmp -s "$T/ref.out" "$T/out"; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
runin "$TP/docs/sub" ../adr/ADR-001-grants.md
chk "R  F2 a cwd-relative path to ANOTHER file (the ADR) names that file, not the first one" "$(if [ $RC != 2 ] && has '== docs/adr/ADR-001-grants.md (file) =='; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
runin "$TP/docs/sub" x.md
chk "R  F2 a bare 'x.md' typed in docs/sub: both docs/sub/x.md and the root x.md exist; the repo-relative name wins (documented: an exact repo path wins), so the answer is for the ROOT x.md (no inbound m.md)" "$(if has 'to or from x.md' && ! has 'docs/sub/x.md' && ! has 'docs/m.md:1:'; then echo 0; else echo 1; fi)" "$OUT"
runin "$TP/docs/sub" ./x.md
chk "R  F2 [G:cwddot] ./x.md typed in docs/sub means docs/sub/x.md (the explicit './' is cwd-relative, lead ruling 2026-10-24, fix): the SUB file answers, with its inbound docs/m.md:1, not the root x.md" "$(if has '== docs/sub/x.md (file) ==' && has 'docs/m.md:1:'; then echo 0; else echo 1; fi)" "$OUT"
run docs/sub/x.md
chk "R  F2 control: the repo-relative name of the sub file finds its inbound mention (docs/m.md:1), so the row above can tell the files apart" "$(if has 'docs/m.md:1:'; then echo 0; else echo 1; fi)" "$OUT"
# outside the repo, ignored files, odd shapes: never a crash, never a wrong file
run /etc/hosts
chk "R  F2 an absolute path OUTSIDE the repo is just unknown: exit 1, no crash" "$(if [ $RC = 1 ] && has 'NO REFERENCES for: /etc/hosts' && ! hasE Traceback; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
run ../outside.md
chk "R  F2 a '../' path that leaves the repo is unknown: exit 1" "$(if [ $RC = 1 ] && has 'NO REFERENCES'; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run "$TP/ignored.md"
chk "R  F2 an absolute path to a .gitignored file inside the repo is not indexed: exit 1 (control: the tracked file above is)" "$(if [ $RC = 1 ] && has 'NO REFERENCES'; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run /
chk "R  F2 the target '/' is unknown (exit 1), not a crash and not the repo" "$(if [ $RC = 1 ] && ! hasE Traceback; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
run "$(python3 -I -c 'print("/" + "d/" * 2500 + "f.md")')"
chk "R  F2 a 5,000-character absolute path is unknown (exit 1), no crash" "$(if [ $RC = 1 ] && ! hasE Traceback; then echo 0; else echo 1; fi)" "rc=$RC ${ERR:0:200}"
run $'/tmp/\033[31mevil/x.md'
chk "R  F2 [G:ctrl] an absolute path with ESC outside the repo: the echo of the target has the control byte replaced" "$(if [ $RC = 1 ] && nocontrol "$T/out"; then echo 0; else echo 1; fi)" "$(cat -v "$T/out")"
# folders
run docs/adr
chk "R  F2 [G:dir] 'docs/adr' WITHOUT the slash is a folder: exit 2, 'is a directory'" "$(if [ $RC = 2 ] && hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run docs/adr/
chk "R  F2 'docs/adr/' with the slash: exit 2" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run "$TP/docs/adr"
chk "R  F2 [G:dir] an absolute folder path: exit 2" "$(if [ $RC = 2 ] && hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
runin "$TP/docs/sub" ../adr
chk "R  F2 [G:dir] a cwd-relative folder ('../adr' from docs/sub): exit 2" "$(if [ $RC = 2 ] && hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
runin "$TP/docs/sub" docs/adr
chk "R  F2 [G:dir] from a SUBFOLDER, the repo-relative folder name 'docs/adr' (no slash) is still a folder: exit 2" "$(if [ $RC = 2 ] && hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
runin "$TP/docs/sub" docs/adr/
chk "R  F2 [G:dir] ... with the slash" "$(if [ $RC = 2 ] && hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
runin "$TP/docs/sub" docs/ad
chk "R  F2 [G:dir] ... and a mere prefix of it ('docs/ad') is not a folder: exit 1" "$(if [ $RC = 1 ] && ! hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
runin "$TP/docs/sub" docs/cites.md
chk "R  F2 from a subfolder, a repo-relative FILE name ('docs/cites.md') still names that file (an exact repo path wins)" "$(if [ $RC = 0 ] && cmp -s "$T/ref.out" "$T/out"; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run docs
chk "R  F2 a folder holding sub-folders ('docs'): exit 2" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"
run docs/ad
chk "R  F2 a name that is only a PREFIX of a folder ('docs/ad') is not a folder: exit 1, not 2" "$(if [ $RC = 1 ]; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
run docs/adr/ADR-001-grants.md
chk "R  F2 control: a file under that folder is still a file (exit 0, not 'is a directory')" "$(if [ $RC != 2 ] && ! hasE 'is a directory' && has '== docs/adr/ADR-001-grants.md (file) =='; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
run docs/adr-notes.md
chk "R  F2 control: 'docs/adr-notes.md' (shares the prefix 'docs/adr') is a file, not a folder" "$(if [ $RC = 1 ] && has 'NO REFERENCES to or from docs/adr-notes.md' && ! hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
run --section 1 docs/adr
chk "R  F2 --section with a folder target is still a usage error (exit 2)" "$(if [ $RC = 2 ]; then echo 0; else echo 1; fi)" "rc=$RC $ERR"

# F4: no 'see --dangling' pointer for a look-alike; ADR-0049 is not ADR-049
newrepo ptr
printf '.refs-cache/\n' > .gitignore
w docs/adr/ADR-049-x.md <<'EOF'
# ADR-049 x

**Status:** Accepted
EOF
w docs/tickets/bug-register.md <<'EOF'
| ID | Sev | Summary | Status | Endpoint |
|---|---|---|---|---|
| BUG-079 | P1 | a | open | |
EOF
w docs/feature-catalog-win.md <<'EOF'
| ID | Feature | Status |
|---|---|---|
| WEB-01 | a | done |
EOF
w docs/cites.md <<'EOF'
look-alikes: a real dangling WEB-06 and a short WEB-6
four digits ADR-0049 and BUG-0079 and ADR-1000
EOF
run WEB-6
chk "R  F4 [G:pointer] ... nor WEB-6 (1 digit against the 2-digit house width of WEB)" "$(if ! has 'see --dangling' && ! has 'NOT DEFINED'; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run WEB-06
chk "R  F4 [G:pointer] control: ... and WEB-06 (house width, undefined) too" "$(if has 'NOT DEFINED anywhere' && has 'see --dangling'; then echo 0; else echo 1; fi)" "$OUT"
run --dangling
chk "R  F4 the pointer's promise holds: --dangling lists WEB-06 and not WEB-6" "$(if has '  WEB-06 ' && ! has '  WEB-6 '; then echo 0; else echo 1; fi)" "$OUT"
cd "$T/ptr" || exit 2
run ADR-0049
chk "R  F4 [G:adr4] ADR-0049 is an unknown target (exit 1, 'NO REFERENCES for: ADR-0049'), not ADR-049" "$(if [ $RC = 1 ] && has 'NO REFERENCES for: ADR-0049' && ! has '== ADR-049'; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run "ADR 0049"
chk "R  F4 [G:adr4] ... 'ADR 0049' (space form)" "$(if [ $RC = 1 ] && ! has '== ADR-049'; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run adr-0049
chk "R  F4 [G:adr4] ... adr-0049 (lower case)" "$(if [ $RC = 1 ] && ! has '== ADR-049'; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run ADR-1000
chk "R  F4 ADR-1000 stays unknown too" "$(if [ $RC = 1 ]; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run ADR-49
chk "R  F4 control: ADR-49 still resolves to ADR-049" "$(if [ $RC = 0 ] || has '== ADR-049 (adr) =='; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run ADR-049
chk "R  F4 control: ADR-049 resolves" "$(if has '== ADR-049 (adr) =='; then echo 0; else echo 1; fi)" "$OUT"
run --dangling
chk "R  F4 --dangling does not list ADR-0049 or ADR-049 (a four-digit cite names no record)" "$(if ! has '  ADR-0049' && ! has '  ADR-049 ' && ! has 'ADR-1000'; then echo 0; else echo 1; fi)" "$OUT"
# fix: BUG-0079 (four digits, a padding zero) is unknown like ADR-0049; BUG-79 and BUG-079 still resolve
run BUG-0079
chk "R  F4 [G:bug0079] BUG-0079 is an unknown target (exit 1, 'NO REFERENCES for: BUG-0079'), not BUG-079" "$(if [ $RC = 1 ] && has 'NO REFERENCES for: BUG-0079' && ! has '== BUG-079'; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run bug-0079
chk "R  F4 [G:bug0079] ... bug-0079 (lower case)" "$(if [ $RC = 1 ] && has 'NO REFERENCES for' && ! has '== BUG-079'; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run "BUG 0079"
chk "R  F4 [G:bug0079] ... 'BUG 0079' (space form)" "$(if [ $RC = 1 ] && ! has '== BUG-079'; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run BUG-79
chk "R  F4 [G:bug0079] control: BUG-79 (shortened) still resolves to BUG-079" "$(if has '== BUG-079 (bug) =='; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
run BUG-079
chk "R  F4 [G:bug0079] control: BUG-079 (house width) resolves" "$(if has '== BUG-079 (bug) =='; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
w docs/bugcite.md <<'EOF'
a real citation of BUG-079 here
EOF
run BUG-079
chk "R  F4 [G:bug0079cite] a cited BUG-0079 is no citation of BUG-079: the inbound list names docs/bugcite.md:1 (BUG-079) and not docs/cites.md:2 (BUG-0079)" "$(if has 'docs/bugcite.md:1:' && ! has 'docs/cites.md:2:'; then echo 0; else echo 1; fi)" "rc=$RC $OUT"
rm -f docs/bugcite.md
# fix: the repo root is a folder like any other (exit 2, 'is a directory'); '/' and paths outside the repo stay unknown
run .
chk "R  F2 [G:rootdir] the repo root as '.' (typed at the root) is a folder: exit 2, 'is a directory'" "$(if [ $RC = 2 ] && hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
dot=.; run "$dot/"   # the literal argument ./ built from a variable: shellcheck SC2083 reads a bare ./ as a broken ./file
chk "R  F2 [G:rootdir] ... './' too" "$(if [ $RC = 2 ] && hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
run "$T/ptr"
chk "R  F2 [G:rootdir] ... the repo root by its ABSOLUTE path" "$(if [ $RC = 2 ] && hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
runin "$T/ptr/docs" ..
chk "R  F2 [G:rootdir] ... and by '..' from a subfolder" "$(if [ $RC = 2 ] && hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
run /
chk "R  F2 [G:rootdir] control: '/' stays unknown (exit 1, 'NO REFERENCES for: /'), not a folder" "$(if [ $RC = 1 ] && has 'NO REFERENCES for: /' && ! hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
run "$T"
chk "R  F2 [G:rootdir] control: a folder OUTSIDE the repo (the parent of the repo root) stays unknown: exit 1, not 'is a directory'" "$(if [ $RC = 1 ] && ! hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
run /etc/hosts
chk "R  F2 [G:rootdir] control: a file outside the repo stays unknown: exit 1" "$(if [ $RC = 1 ] && ! hasE 'is a directory'; then echo 0; else echo 1; fi)" "rc=$RC $OUT $ERR"
w docs/long-reversed.md <<'EOF'
filler filler filler filler filler filler filler filler filler filler filler filler filler filler filler filler filler filler §3 of ADR-049
EOF
run ADR-049 --section 3
chk "R  the reversed form '§3 of ADR-049' is still read after 100+ characters of filler on the same line (the look-back window is relative to the token)" "$(if has 'docs/long-reversed.md:1:'; then echo 0; else echo 1; fi)" "$OUT"


echo
if [ "$K" -gt 0 ] || [ "$S" -gt 0 ]; then
  echo "refs matrix: $P pass, $F fail, $K known-defect row(s) (red on purpose, NOT passes), $S skipped (unexercised, NOT passes)"
else echo "refs matrix: $P pass, $F fail"; fi
[ "$F" = 0 ]
