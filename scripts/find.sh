#!/usr/bin/env bash
# find.sh — the project's standard search. Searches EVERY file in the repo (tracked + untracked, minus
# what .gitignore excludes; binaries skipped), case-insensitive, for ANY of the given terms. Never
# truncates silently; "no hits" and "search failed" are distinct, loud, and exit differently.
#
# Usage: scripts/find.sh [--regex] [--list] [--max-per-file N] TERM [TERM...]
#   terms are fixed strings by default (no regex/glob surprises); --regex: extended regex
#   --list: the ranked file list only (no match lines) — the cheap first look at a broad term
#   exit 0 = hits · 1 = no hits anywhere (coverage printed) · 2 = usage/search error (NOT "no hits")
#
# WHY (v1.3, from an outside benchmark of v1–v1.2: 270 sessions, two models). Retrieval almost never
# failed because a file could not be READ; it failed because the SEARCH was wrong, and three ways
# recurred on every version and model, all of them silent:
#   1. zsh aborts a grep with an unquoted glob (`--include=*.md`) with one line, "no matches found";
#      piped, the command still exits 0 and the agent reads "no hits". It killed a search in about
#      half of all sessions. → this is its own bash script built on `git grep`: no shell glob anywhere.
#   2. ~80% of hand-written searches named a few guessed folders, then concluded "nothing exists".
#      → always the WHOLE repo, from any cwd, and "no hits" states how many files it covered.
#   3. broad searches piped into `| head` filled the quota with code before reaching the document.
#      → files are RANKED by hit count before any match line, and every per-file cap says TRUNCATED.
# The reference implementation and its acceptance suite came with the benchmark report; this version
# adds a single grep pass with -z output (the reference re-ran git grep once per hit file: ~2 s on 150
# files; and it printed "d\303\251cision.md" for an accented name, then found no lines in it — a silent
# miss; -z prints names raw), a record parser that survives a newline in a file name, options after
# the terms, --list, an empty term refused (it matched every line), cut over-long lines, and a last
# section for the harness's OWN files (HARNESS_FIND_LAST) so they stop crowding the project's answers.
# Tests: scripts/find-test.sh (a fast-tier gate). Requires git, bash, python3 (a harness prerequisite).
set -uo pipefail
mode=-F; per_file=20; list_only=0; terms=()
# Options are recognised ANYWHERE before a `--` (agents write `find.sh x y --list` as often as the
# other order); everything after `--` is a term, so a flag-looking term is searched with `-- -x`.
while [ $# -gt 0 ]; do
  case "$1" in
    --regex) mode=-E; shift ;;
    --list) list_only=1; shift ;;
    --max-per-file) per_file="${2:-}"; shift 2 2>/dev/null || shift ;;
    --) shift; terms+=("$@"); break ;;
    -*) echo "find.sh: unknown option $1 (a term starting with '-' goes after --)" >&2; exit 2 ;;
    *) terms+=("$1"); shift ;;
  esac
done
set -- ${terms[@]+"${terms[@]}"}
for t in "$@"; do
  [ -n "$t" ] || { echo "find.sh: an empty term matches every line — drop it (SEARCH FAILED — NOT 'no hits')" >&2; exit 2; }
done
[ $# -gt 0 ] || { echo "usage: find.sh [--regex] [--list] [--max-per-file N] TERM [TERM...]" >&2; exit 2; }
case "$per_file" in ''|*[!0-9]*) echo "find.sh: --max-per-file needs a number" >&2; exit 2 ;; esac
command -v python3 >/dev/null 2>&1 || { echo "find.sh: python3 is required (SEARCH FAILED — NOT 'no hits')" >&2; exit 2; }
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "find.sh: not inside a git repo (SEARCH FAILED — NOT 'no hits')" >&2; exit 2; }
cd "$root" || exit 2

# The harness's own files go LAST. Read this ONE assignment out of harness.conf without sourcing it (a
# search must not execute config). Unset → the installed-project default; set but empty → none.
last_default="docs/ci/ .claude/ evals/ harness.conf harness.conf.example AGENTS.md TAILORING.md CHEAT-SHEET.md CONVENTIONS.md CONTRIBUTING.md"
last="$last_default"
if [ -f harness.conf ] && grep -qE '^[[:space:]]*(export[[:space:]]+)?HARNESS_FIND_LAST=' harness.conf; then
  last="$(sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}HARNESS_FIND_LAST=["'"'"']\{0,1\}\([^"'"'"'#]*\).*/\2/p' harness.conf | tail -1)"
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/find.XXXXXX")" || { echo "find.sh: cannot create a temp file (SEARCH FAILED — NOT 'no hits')" >&2; exit 2; }
trap 'rm -f "$tmp" "$tmp.err"' EXIT
pats=(); for t in "$@"; do pats+=(-e "$t"); done
G=(git -c core.quotePath=false)
nfiles=$("${G[@]}" ls-files --cached --others --exclude-standard -z | tr -cd '\0' | wc -c | tr -d ' ')
"${G[@]}" grep --untracked -I -i "$mode" -n -z "${pats[@]}" > "$tmp" 2> "$tmp.err"; rc=$?
if [ "$rc" -eq 1 ] && [ ! -s "$tmp" ] && [ ! -s "$tmp.err" ]; then
  echo "NO HITS for: $* — searched all $nfiles files in the repo (case-insensitive; binary files skipped)."
  exit 1
elif [ "$rc" -ne 0 ]; then
  echo "SEARCH FAILED (git grep exit $rc) — this is NOT 'no hits':" >&2
  cat "$tmp.err" >&2
  exit 2
fi

python3 - "$tmp" "$nfiles" "$per_file" "$list_only" "$last" <<'PY'
import sys
path, nfiles, per_file, list_only, last = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4] == "1", sys.argv[5].split()
hits, order = {}, []
# git grep -z -n writes  path \0 lineno \0 text \n . A path may contain a newline (never a NUL) and the
# text never does, so records are read field by field, not split on newlines first.
data = open(path, "rb").read()
i = 0
while i < len(data):
    j = data.find(b"\0", i)
    k = data.find(b"\0", j + 1) if j >= 0 else -1
    if j < 0 or k < 0:
        break
    e = data.find(b"\n", k + 1)
    e = len(data) if e < 0 else e
    p = data[i:j].decode("utf-8", "replace")
    if p not in hits:
        hits[p] = []
        order.append(p)
    hits[p].append((data[j + 1:k].decode(), data[k + 1:e].decode("utf-8", "replace")))
    i = e + 1
last = [g[2:] if g.startswith("./") else g for g in last]
# harness:allow-uncited — plumbing: is this path one of the harness's own files (HARNESS_FIND_LAST)?
def harness(p):
    return any(p == g or (g.endswith("/") and p.startswith(g)) for g in last)
proj = sorted((p for p in order if not harness(p)), key=lambda p: (-len(hits[p]), p))
own = sorted((p for p in order if harness(p)), key=lambda p: (-len(hits[p]), p))
print(f"== {len(order)} file(s) with hits, of {nfiles} searched (most hits first) ==")
for p in proj:
    print(f"{len(hits[p])}\t{p}")
if own:
    print("-- the harness's own files (listed last: HARNESS_FIND_LAST) --")
    for p in own:
        print(f"{len(hits[p])}\t{p}")
if list_only:
    print("\n(--list: file ranking only. Rerun without --list, or read the top files.)")
    sys.exit(0)
print(f"\n== matches (up to {per_file} per file) ==")
for p in proj + own:
    print(f"--- {p}")
    for n, text in hits[p][:per_file]:
        cut = text if len(text) <= 300 else text[:300] + " …[line cut at 300 chars]"
        print(f"{p}:{n}:{cut}")
    extra = len(hits[p]) - per_file
    if extra > 0:
        print(f"    … {extra} more in this file — TRUNCATED, read the file")
PY
# A formatter crash must never exit 1, which means "no hits".
[ $? -eq 0 ] || { echo "find.sh: formatting the results failed (SEARCH FAILED — NOT 'no hits')" >&2; exit 2; }
exit 0
