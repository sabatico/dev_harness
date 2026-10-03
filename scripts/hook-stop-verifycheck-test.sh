#!/usr/bin/env bash
# hook-stop-verifycheck-test.sh — known-answer matrix for hook-stop-verifycheck.sh + verify-check.py.
#
# Each row builds a synthetic session transcript (JSONL, the shape verify-check.py's turn_tool_calls()
# reads: user / assistant entries, tool_use blocks inside assistant messages, tool_result blocks inside
# user entries) and runs the REAL wrapper against a temp git repo (HARNESS_ROOT_OVERRIDE) with its own
# harness.conf, so the kit's own repo and config can never mask a row. Two halves, both mandatory:
# FLAG rows (code changed, nothing checked it afterwards) and SILENT rows (the nearest legitimate
# turns: verified, doc-only, outside the code dirs, a previous turn's edits, subagent entries).
# A change that flips ANY row is a regression, either direction.
#
# Cross-authored 2026-09-30 (not by the builder of verify-check.py). Cases the checker currently gets
# WRONG are not rows; they went to the lead in the test author's report. Fast-tier gate.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/hook-stop-verifycheck.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/vc-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P/src" "$P/lib" "$P/docs" "$P/scripts"; git -C "$P" init -q
LOGF="$T/logs/verify-check.log"
# The caller's own knobs must not leak into the rows.
unset HARNESS_VERIFYCHECK_MODE HARNESS_VERIFY_RE HARNESS_TEST_CMD HARNESS_LINT_CMD HARNESS_COVERAGE_CMD \
      HARNESS_CODE_DIRS HARNESS_CODE_EXTS HARNESS_STACK HARNESS_LOG_DIR
export HARNESS_ROOT_OVERRIDE="$P"
pass=0; fail=0; n=0

# conf [extra lines] — the temp repo's harness.conf. harness.conf is sourced AFTER the stack pack, so
# the pack-owned knobs (HARNESS_TEST_CMD …) must be set here, not in the environment.
conf() {
  printf 'HARNESS_CODE_DIRS="src lib"\n%s\nHARNESS_LOG_DIR="%s"\n' "${ROW_BASE_EXTS-HARNESS_CODE_EXTS=\"py go\"}" "$T/logs" > "$P/harness.conf"
  [ -n "${1:-}" ] && printf '%s\n' "$1" >> "$P/harness.conf"
  return 0
}

# transcript <file> <event>... — a tiny DSL so each row reads as the turn it models:
#   U:text   human prompt (string content)       UL:text  human prompt as a [text] block list
#   E:/W:/M:path   Edit / Write / MultiEdit       N:path   NotebookEdit (notebook_path)
#   B:cmd    Bash call                            T:text   assistant text
#   SE:path / SB:cmd / SU:text   the same, but isSidechain (a subagent's entries)
#   META:text  an isMeta user entry               RAW:line   a raw transcript line, verbatim
#   BE:/BH:cmd  a Bash call refused before it ran (permission denied / hook-blocked: is_error, no exit code)
#   BX:/BXL:cmd a Bash call that ran and FAILED (is_error, "Exit code N" as a string / as a text block)
#   BG:cmd   run_in_background:true (result never read)   BGF:cmd  run_in_background:false
#   CS:text  an isCompactSummary user entry
# Every tool call is followed by its tool_result user entry, as Claude Code writes it, and the
# transcript ends with an assistant text entry unless the last event is RAW/U, or NOEND (which leaves
# the last tool_result as the final entry: Stop firing before the reply line is flushed).
transcript() {
  python3 - "$@" <<'PY'
import json, sys
path, evs = sys.argv[1], sys.argv[2:]
out, k = [], 0
# harness:allow-uncited — test fixture: builds one tool_use + tool_result pair for a synthetic transcript
def tool(name, inp, side=False, result="ok", is_error=False):
    global k
    k += 1
    a = {"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": "tu%d" % k, "name": name, "input": inp}]}}
    tr = {"type": "tool_result", "tool_use_id": "tu%d" % k, "content": result}
    if is_error:
        tr["is_error"] = True
    r = {"type": "user", "message": {"role": "user", "content": [tr]}}
    if side:
        a["isSidechain"] = r["isSidechain"] = True
    out.extend([a, r])
for ev in evs:
    kind, _, v = ev.partition(":")
    base = kind[1:] if kind in ("SE", "SB", "SU") else kind
    if base == "U":
        e = {"type": "user", "message": {"role": "user", "content": v}}
        if kind == "SU": e["isSidechain"] = True
        out.append(e)
    elif base == "UL":
        out.append({"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": v}]}})
    elif base in ("E", "W", "M"):
        tool({"E": "Edit", "W": "Write", "M": "MultiEdit"}[base], {"file_path": v}, kind == "SE")
    elif base == "N":
        tool("NotebookEdit", {"notebook_path": v, "new_source": "x"})
    elif base == "B":
        tool("Bash", {"command": v}, kind == "SB")
    elif base == "BE":   # refused before it ran (permission denied / hook blocked)
        tool("Bash", {"command": v}, result="Permission to use Bash with command %s has been denied." % v, is_error=True)
    elif base == "BH":   # blocked by a PreToolUse hook
        tool("Bash", {"command": v}, result="PreToolUse:Bash hook error: BLOCKED", is_error=True)
    elif base == "BX":   # ran and FAILED (string content)
        tool("Bash", {"command": v}, result="Exit code 1\nFAILED tests/test_a.py", is_error=True)
    elif base == "BXL":  # ran and FAILED (content as a text-block list)
        tool("Bash", {"command": v}, result=[{"type": "text", "text": "Exit code 2\nerror"}], is_error=True)
    elif base == "BG":   # started in the background; its result was never read this turn
        tool("Bash", {"command": v, "run_in_background": True}, result="Command running in background with ID: b1")
    elif base == "BGF":  # run_in_background explicitly false = a normal run
        tool("Bash", {"command": v, "run_in_background": False})
    elif base == "CS":   # an auto-compact summary written as a user entry
        out.append({"type": "user", "isCompactSummary": True, "message": {"role": "user", "content": v}})
    elif base == "T":
        out.append({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": v}]}})
    elif base == "META":
        out.append({"type": "user", "isMeta": True, "message": {"role": "user", "content": v}})
    elif base == "RAW":
        out.append(v)
if evs and evs[-1] == "NOEND":
    pass
elif not evs or evs[-1].split(":")[0] not in ("RAW", "U"):
    out.append({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "Done."}]}})
with open(path, "w") as f:
    for e in out:
        f.write((e if isinstance(e, str) else json.dumps(e)) + "\n")
PY
}

# row <label> <want: FLAG|BLOCK|SILENT> <event>...
#   env knobs: ROW_CONF (extra harness.conf lines), ROW_BASE_EXTS (replaces the base CODE_EXTS line;
#   empty = let the stack pack decide), ROW_ENV (VAR=val for the hook), ROW_RE (a regex
#   the output must also match), ROW_EXTRA (extra JSON fields for the Stop payload, e.g. ,"x":1).
row() {
  local label="$1" want="$2"; shift 2
  n=$((n+1)); local tp="$T/t$n.jsonl" out rc ok=1
  conf "${ROW_CONF:-}"
  transcript "$tp" "$@"
  out="$(printf '{"session_id":"vrow%04d","transcript_path":"%s"%s}' "$n" "$tp" "${ROW_EXTRA:-}" \
         | env ${ROW_ENV:-} bash "$HOOK" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || ok=0
  case "$want" in
    SILENT) [ -z "$out" ] || ok=0 ;;
    FLAG)   printf '%s' "$out" | grep -q '"systemMessage"' && printf '%s' "$out" | grep -q 'verify-check (advisory)' \
              && ! printf '%s' "$out" | grep -q '"decision"' || ok=0 ;;
    BLOCK)  printf '%s' "$out" | grep -q '"decision": "block"' || ok=0 ;;
  esac
  if [ "$ok" = 1 ] && [ "$want" != SILENT ] && ! printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then ok=0; fi
  if [ "$ok" = 1 ] && [ -n "${ROW_RE:-}" ] && ! printf '%s' "$out" | grep -qE "$ROW_RE"; then ok=0; fi
  if [ "$ok" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  want=$want rc=$rc  $label"; echo "      out: ${out:-<silent>}"; fi
}

# ── must FLAG: code changed this turn, nothing checked it afterwards ──────────
ROW_RE='1 code file\(s\) \(src/a.py\) and ran no test' \
row 'code edit, no verification'                 FLAG  U:fix it E:src/a.py
row 'Write to code counts'                       FLAG  U:x W:lib/b.go
row 'MultiEdit to code counts'                   FLAG  U:x M:src/a.py
row 'NotebookEdit notebook_path counts'          FLAG  U:x N:src/nb.py
row 'absolute path inside the root counts'       FLAG  U:x "E:$P/src/a.py"
row 'dot-dot path that stays inside the root'    FLAG  U:x E:docs/../src/a.py
ROW_RE='changed code again after the last test' \
row 'verify THEN edit is flagged'                FLAG  U:x B:pytest E:src/a.py
ROW_RE='changed code again' \
row 'edit, verify, edit again is flagged'        FLAG  U:x E:src/a.py B:pytest E:src/a.py
row 'edit again via a ./ spelling of the same file' FLAG U:x E:src/a.py B:pytest E:src/./a.py
row 'previous turn verified, this turn edits'    FLAG  U:one E:src/a.py B:pytest T:ok U:two E:src/a.py
row 'a non-verifying Bash after the edit'        FLAG  U:x E:src/a.py B:'git status' B:'ls src'
ROW_RE='1 code file\(s\)' \
row 'the same file edited twice counts once'     FLAG  U:x E:src/a.py E:src/a.py
ROW_RE='6 code file\(s\) .*\(\+2 more\)' \
row 'many files: the first four, then +N more'   FLAG  U:x E:src/a.py E:src/b.py E:src/c.py E:src/d.py E:src/e.py E:lib/f.go
row 'tool_result entries are not turn boundaries' FLAG U:x E:src/a.py B:'echo hi' B:'echo there'
row 'an isMeta user entry is not a turn boundary' FLAG U:x E:src/a.py META:caveat
row 'a SIDECHAIN user prompt is not a boundary'  FLAG  U:x E:src/a.py SU:subagent-task
row 'a subagent (sidechain) test run does not verify the main turn' FLAG U:x E:src/a.py SB:pytest
row 'a prompt given as a [text] block list is a boundary' FLAG U:old B:pytest UL:new E:src/a.py
row 'a corrupt line mid-transcript is skipped, not fatal' FLAG U:x 'RAW:{not json' E:src/a.py
row 'transcript whose LAST entry is a tool_result (Stop fired early)' FLAG U:x E:src/a.py NOEND
ROW_CONF='HARNESS_CODE_EXTS=""' \
row 'empty HARNESS_CODE_EXTS: any extension counts' FLAG U:x E:src/a.md
ROW_CONF='HARNESS_STACK="python"' ROW_BASE_EXTS='' \
row 'the stack pack supplies extensions (python: .pyi)' FLAG U:x E:src/a.pyi
# negative controls for the knob rows below: without the knob the same turn IS flagged
row 'control: a custom runner is not known by default' FLAG U:x E:src/a.py B:'./run_suite --fast'
row 'control: a custom checker is not known by default' FLAG U:x E:src/a.py B:'my-checker all'

# ── must stay SILENT: verified, or not a code change, or not this turn ────────
row 'edit then pytest'                           SILENT U:x E:src/a.py B:'pytest -q'
row 'a FAILING test run still counts as seen'    SILENT U:x E:src/a.py B:'pytest -q || true'
row 'edit then go test'                          SILENT U:x E:lib/b.go B:'go test ./...'
row 'edit then npm run build'                    SILENT U:x E:src/a.py B:'npm run build'
row 'edit then make check'                       SILENT U:x E:src/a.py B:'make check'
row 'edit then cargo clippy'                     SILENT U:x E:src/a.py B:'cargo clippy'
row 'edit then python -m unittest'               SILENT U:x E:src/a.py B:'python3 -m unittest discover'
row 'edit then tsc'                              SILENT U:x E:src/a.py B:'npx tsc --noEmit'
row 'edit then a *-test.sh matrix'               SILENT U:x E:src/a.py B:'bash scripts/hook-x-test.sh'
row 'edit then the gate runner'                  SILENT U:x E:src/a.py B:'scripts/run-all-gates.sh --fast'
row 'edit then selftest.sh'                      SILENT U:x E:src/a.py B:'bash scripts/selftest.sh'
row 'chained: cd then the test'                  SILENT U:x E:src/a.py B:'cd src && pytest'
row 'edit and verify in ONE assistant message (verify last)' SILENT U:x \
  'RAW:{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"m1","name":"Edit","input":{"file_path":"src/a.py"}},{"type":"tool_use","id":"m2","name":"Bash","input":{"command":"pytest"}}]}}'
row 'doc-only edit'                              SILENT U:x E:docs/x.md
row 'edit outside the code dirs'                 SILENT U:x E:scripts/a.py
row 'dir-name prefix is not the dir (src2/)'     SILENT U:x E:src2/a.py
row 'wrong extension inside a code dir'          SILENT U:x E:src/notes.md
row 'path escaping the root'                     SILENT U:x E:../outside/src/a.py
row 'edits from a PREVIOUS turn only'            SILENT U:one E:src/a.py T:done U:two B:ls
row 'edits from a previous turn, this turn reads only' SILENT U:one E:src/a.py U:two
row 'a sidechain (subagent) edit is not this turn' SILENT U:x SE:src/a.py
row 'no tool calls at all'                       SILENT U:x T:'just talking'
ROW_CONF='HARNESS_TEST_CMD="./run_suite --fast && echo ok"' \
row 'HARNESS_TEST_CMD recognised (first command of a chain)' SILENT U:x E:src/a.py B:'./run_suite --fast'
ROW_CONF='HARNESS_LINT_CMD="lintr check"' \
row 'HARNESS_LINT_CMD recognised'                SILENT U:x E:src/a.py B:'lintr check src'
ROW_CONF='HARNESS_COVERAGE_CMD="covr run (all)"' \
row 'HARNESS_COVERAGE_CMD recognised, regex chars escaped' SILENT U:x E:src/a.py B:'covr run (all)'
ROW_ENV='HARNESS_VERIFY_RE=^my-checker.all' \
row 'HARNESS_VERIFY_RE recognised'               SILENT U:x E:src/a.py B:'my-checker all'
ROW_CONF='HARNESS_STACK="python"' ROW_BASE_EXTS='' \
row 'the stack pack extensions exclude other langs (python: .go)' SILENT U:x E:src/a.go

# ══ round 2 (2026-09-30): the invent-nastier cases the builder fixed ═════════
# ── naming a check is not running it: the command must be at command position ─
row 'echo naming pytest'                         FLAG  U:x E:src/a.py B:'echo skipping pytest for now'
row 'grep for pytest'                            FLAG  U:x E:src/a.py B:'grep -rn pytest .'
row 'commit message naming pytest'               FLAG  U:x E:src/a.py B:'git commit -m "tests: run pytest later"'
row 'a shell comment naming pytest'              FLAG  U:x E:src/a.py B:'# pytest'
# A loose project regex is the one way a comment line could match: the comment skip must still hold.
ROW_ENV='HARNESS_VERIFY_RE=.*pytest' \
row 'a comment line does not count even under a loose HARNESS_VERIFY_RE' FLAG U:x E:src/a.py B:'# pytest later'
ROW_ENV='HARNESS_VERIFY_RE=.*pytest' \
row 'control: the loose HARNESS_VERIFY_RE does match a real run' SILENT U:x E:src/a.py B:'CI=1 pytest'
row 'cat the gate runner'                        FLAG  U:x E:src/a.py B:'cat scripts/run-all-gates.sh'
row 'ls the test matrices'                       FLAG  U:x E:src/a.py B:'ls scripts/*-test.sh'
row 'opening a _test.sh in an editor'            FLAG  U:x E:src/a.py B:'vim src/a_test.sh'
row 'pytest as an argument of another tool'      FLAG  U:x E:src/a.py B:'pip install pytest'
row 'mypytest is not pytest'                     FLAG  U:x E:src/a.py B:'mypytest'
# ── …and the wrappers in front of a real run are stripped ────────────────────
row 'VAR=val prefix'                             SILENT U:x E:src/a.py B:'CI=1 pytest'
row 'two VAR=val prefixes'                       SILENT U:x E:src/a.py B:'PYTHONPATH=. CI=1 python3 -m pytest'
row 'env VAR=val prefix'                         SILENT U:x E:src/a.py B:'env CI=1 pytest'
row 'time prefix'                                SILENT U:x E:src/a.py B:'time pytest -q'
row 'sudo prefix'                                SILENT U:x E:src/a.py B:'sudo make test'
row 'timeout N prefix'                           SILENT U:x E:src/a.py B:'timeout 300 pytest'
row 'sh -e matrix'                               SILENT U:x E:src/a.py B:'sh -e scripts/x-test.sh'
row 'npx runner'                                 SILENT U:x E:src/a.py B:'npx vitest run'
row 'uv run runner'                              SILENT U:x E:src/a.py B:'uv run pytest'
row 'poetry run runner'                          SILENT U:x E:src/a.py B:'poetry run pytest'
row 'pnpm exec runner'                           SILENT U:x E:src/a.py B:'pnpm exec jest'
row 'a check after ; in a chain'                 SILENT U:x E:src/a.py B:'cd src; python -m pytest'
row 'a check piped into tee'                     SILENT U:x E:lib/b.go B:'go test ./... | tee /tmp/out'
row './gradlew test'                             SILENT U:x E:src/a.py B:'./gradlew test'
row 'a check inside a brace group'               SILENT U:x E:src/a.py B:'{ pytest; }'
# round 3: the spellings that still read as "not run"
row 'a check inside a subshell: (cd src && pytest)' SILENT U:x E:src/a.py B:'(cd src && pytest)'
row 'env -i prefix'                              SILENT U:x E:src/a.py B:'env -i pytest'
row 'nice -n N prefix'                           SILENT U:x E:src/a.py B:'nice -n 5 pytest'
row "bash -c 'pytest'"                           SILENT U:x E:src/a.py B:"bash -c 'pytest'"
row 'xargs prefix'                               SILENT U:x E:src/a.py B:'xargs pytest'
row 'negative control: echo pytest) is still prose' FLAG U:x E:src/a.py B:'echo pytest)'
row 'negative control: a paren-glued name is not pytest' FLAG U:x E:src/a.py B:'(mypytest)'
# ── a check that never ran does not count; one that ran and failed does ─────
row 'test call DENIED by permissions (never ran)' FLAG U:x E:src/a.py BE:pytest
row 'test call BLOCKED by a hook (never ran)'    FLAG  U:x E:src/a.py BH:pytest
row 'test ran and FAILED (Exit code 1) still counts' SILENT U:x E:src/a.py BX:pytest
row 'failed run with a text-block result still counts' SILENT U:x E:src/a.py BXL:'make test'
row 'denied run AFTER a real run: the real run still counts' SILENT U:x E:src/a.py B:pytest BE:pytest
row 'background test run never counts'           FLAG  U:x E:src/a.py BG:pytest
row 'run_in_background:false is a normal run'    SILENT U:x E:src/a.py BGF:pytest
# ── code-dir and extension spellings ─────────────────────────────────────────
ROW_CONF='HARNESS_CODE_DIRS="."' \
row 'HARNESS_CODE_DIRS="." covers the whole repo' FLAG U:x E:scripts/a.py
ROW_CONF='HARNESS_CODE_DIRS="."' \
row 'HARNESS_CODE_DIRS="." still filters by extension' SILENT U:x E:docs/x.md
ROW_CONF='HARNESS_CODE_DIRS="./src"' \
row 'HARNESS_CODE_DIRS="./src"'                  FLAG  U:x E:src/a.py
ROW_CONF='HARNESS_CODE_DIRS="./src"' \
row 'HARNESS_CODE_DIRS="./src" does not cover lib/' SILENT U:x E:lib/b.go
row 'upper-case extension src/A.PY'              FLAG  U:x E:src/A.PY
ROW_CONF='HARNESS_CODE_EXTS="PY"' \
row 'upper-case configured extension matches a.py' FLAG U:x E:src/a.py
# ── transcript shapes that used to blind the whole check ─────────────────────
row 'a JSON-array line is skipped'               FLAG  U:x E:src/a.py 'RAW:[]' T:ok
row 'a JSON-string / null / number line is skipped' FLAG U:x E:src/a.py 'RAW:"x"' 'RAW:null' 'RAW:42' T:ok
row 'an entry whose message is a string is skipped' FLAG U:x E:src/a.py 'RAW:{"type":"user","message":"x"}' T:ok
row 'an assistant entry whose message is a string' FLAG U:x E:src/a.py 'RAW:{"type":"assistant","message":"x"}' T:ok
row 'an auto-compact summary is not a turn boundary' FLAG U:x E:src/a.py CS:'This session is being continued from a previous conversation' T:ok
row 'compact summary between edit and test: still verified' SILENT U:x E:src/a.py CS:summary B:pytest
# ── a bad HARNESS_VERIFY_RE drops only itself, and says so ───────────────────
ROW_ENV='HARNESS_VERIFY_RE=(' \
row 'bad HARNESS_VERIFY_RE: the check still flags' FLAG U:x E:src/a.py
ROW_ENV='HARNESS_VERIFY_RE=(' \
row 'bad HARNESS_VERIFY_RE: the default patterns still verify' SILENT U:x E:src/a.py B:pytest
if grep -q 'error=bad-HARNESS_VERIFY_RE' "$LOGF"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  a bad HARNESS_VERIFY_RE must be logged"; fi

# ── modes ─────────────────────────────────────────────────────────────────────
ROW_ENV='HARNESS_VERIFYCHECK_MODE=block' ROW_RE='UNVERIFIED' \
row 'block mode: decision block'                 BLOCK  U:x E:src/a.py
ROW_ENV='HARNESS_VERIFYCHECK_MODE=block' ROW_EXTRA=',"stop_hook_active":true' \
row 'block mode + stop_hook_active: advisory only, never a second block' FLAG U:x E:src/a.py
ROW_ENV='HARNESS_VERIFYCHECK_MODE=block' \
row 'block mode, verified turn: silent'          SILENT U:x E:src/a.py B:pytest
ROW_ENV='HARNESS_VERIFYCHECK_MODE=off' \
row 'off mode: silent even when unverified'      SILENT U:x E:src/a.py
ROW_CONF='HARNESS_VERIFYCHECK_MODE="block"' \
row 'mode set in harness.conf is honoured'       BLOCK  U:x E:src/a.py

# ── broken inputs: silent, exit 0, never a crash ──────────────────────────────
broken() { # label payload
  n=$((n+1)); conf; local out rc
  out="$(printf '%s' "$2" | bash "$HOOK" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  $1 (rc=$rc)"; echo "      out: ${out:-<silent>}"; fi
}
broken 'missing transcript file'          "{\"session_id\":\"b1\",\"transcript_path\":\"$T/nope.jsonl\"}"
broken 'transcript path is a directory'   "{\"session_id\":\"b2\",\"transcript_path\":\"$T\"}"
broken 'no transcript_path at all'        '{"session_id":"b3"}'
printf 'garbage\n\x00\xff\xfe not json\n{{{\n' > "$T/corrupt.jsonl"
broken 'fully corrupt transcript'         "{\"session_id\":\"b4\",\"transcript_path\":\"$T/corrupt.jsonl\"}"
broken 'payload not JSON'                 'this is not json'
broken 'empty stdin'                      ''
: > "$T/empty.jsonl"
broken 'empty transcript file'            "{\"session_id\":\"b5\",\"transcript_path\":\"$T/empty.jsonl\"}"

# ── the log: one line per judged turn, verdict + counts, no file names ────────
if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z session=vrow0001 verdict=UNVERIFIED code_files=1 mode=advise$' "$LOGF" \
   && grep -qE ' session=vrow[0-9]{4} verdict=verified code_files=1$' "$LOGF"; then pass=$((pass+1))
else fail=$((fail+1)); echo "FAIL  log lines for UNVERIFIED and verified turns"; sed 's/^/      /' "$LOGF" 2>/dev/null | head -5; fi
if grep -q 'src/a.py' "$LOGF"; then fail=$((fail+1)); echo "FAIL  the log must carry counts, not file names"; else pass=$((pass+1)); fi
# a silent non-code turn writes nothing (doc-only row): no line may mention a doc verdict
cnt_before="$(wc -l < "$LOGF" | tr -d ' ')"
row 'log probe: doc-only turn' SILENT U:x E:docs/y.md
if [ "$(wc -l < "$LOGF" | tr -d ' ')" -eq "$cnt_before" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  a turn with no code change must not log"; fi
ROW_ENV='HARNESS_VERIFYCHECK_MODE=off' row 'log probe: off mode' SILENT U:x E:src/a.py
if [ "$(wc -l < "$LOGF" | tr -d ' ')" -eq "$cnt_before" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  off mode must not log"; fi
[ ! -d "$P/.harness-logs" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL  wrote to the default log dir instead of HARNESS_LOG_DIR"; }

echo "verify-check matrix: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
