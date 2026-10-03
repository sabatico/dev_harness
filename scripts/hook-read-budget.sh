#!/usr/bin/env bash
# hook-read-budget.sh — the librarian tripwire: measure how much corpus the MAIN session pulls into
# its own context, advise delegation past a budget, and LOG it so "do we actually delegate?" is a
# number, not a feeling. (Wire on PostToolUse, matcher Read|Bash|Agent|Task|Skill.)
#
# WHY IT CANNOT BE A HARD GATE: targeted reads of a cited decision record are correct and often
# mandatory; "this read should have been delegated" is a judgment no script can make. VOLUME is
# decidable, so volume is what this measures — advisory, never blocking.
#
# WHAT IT COUNTS (generalised 2026-09-29 from a live project, where the first version measured the
# wrong thing for five weeks and nobody could tell):
#   Read   the bytes Claude Code actually returned (tool_response.file.content) — NOT the file size.
#          A 3-line targeted Read of a 523 KB register returned 138 bytes; counting the file made every
#          correct, targeted read trip the wire, which teaches everyone to ignore it.
#   Bash   commands naming a corpus path (cat/sed/grep of it) count their stdout, capped at what the
#          agent receives: BASH_MAX_OUTPUT_LENGTH (default 30000 chars); past it the output becomes a
#          file + a 2 KB preview. In auto mode agents read through Bash, so a Read-only matcher is blind.
#   Agent/Task (subagent_type librarian) and Skill (consulting-the-librarian) are logged as DELEGATIONS, so the
#          log answers "corpus read directly vs. delegated", per session.
# Subagents are exempt (reading is their job). Logs go to $HARNESS_LOG_DIR (default .harness-logs/),
# NEVER a directory a gate run clears — the live project lost five weeks of data that way.
# The python runs from a QUOTED heredoc over a temp file, and writes its output to a second temp file:
# a single apostrophe inside a `python3 -c '…'` block makes the script fail to PARSE, and so does one
# inside a heredoc nested in $( ) on macOS bash 3.2 — and a hook that fails to parse is silent.
# Test: scripts/hook-read-budget-test.sh (a fast-tier gate).
set -uo pipefail
ROOT="${HARNESS_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null)}" || exit 0
cd "$ROOT" || exit 0
[ -f harness.conf ] && . ./harness.conf
CORPUS="${HARNESS_CORPUS_DIRS:-docs}"
STEP="${HARNESS_READ_BUDGET_BYTES:-61440}"
LOGDIR="${HARNESS_LOG_DIR:-.harness-logs}"

pf="$(mktemp "${TMPDIR:-/tmp}/rb-payload.XXXXXX")" || exit 0
cat > "$pf"
python3 - "$pf" "$ROOT" "$CORPUS" > "$pf.vars" 2>/dev/null <<'PY'
import json, os, re, shlex, sys
try: d = json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
root, corpus = sys.argv[2], sys.argv[3].split()
out = {"SID": d.get("session_id", "nosession"), "AGENT": d.get("agent_type", ""), "KIND": "", "BYTES": "0", "WHAT": ""}
tool, ti, tr = d.get("tool_name", ""), d.get("tool_input") or {}, d.get("tool_response")
# harness:allow-uncited — plumbing: is a Read inside HARNESS_CORPUS_DIRS (relative to the root, so
# an absolute path and a relative one agree)? Code reads are normal work and must not count.
def in_corpus_file(p):
    if not p: return False
    rel = os.path.relpath(os.path.abspath(p), root)
    return not rel.startswith("..") and any(rel == c or rel.startswith(c.rstrip("/") + "/") for c in corpus)
# harness:allow-uncited — plumbing: does a Bash command name a corpus PATH token? Start-anchored so
# a docs URL never counts (mutation-verified by the matrix's URL row).
def names_corpus(cmd):
    # A path TOKEN under a corpus dir (relative, $VAR/…, or absolute under the root). START anchoring
    # is what keeps a docs URL (https://host/docs/…) out.
    for tok in re.split(r"[\s\x27\"<>|;&()=]+", cmd):
        if not tok: continue
        for c in corpus:
            c = re.escape(c.rstrip("/"))
            if re.match(r"(\./)?%s(/|$)" % c, tok) or re.match(r"\$\{?\w+\}?/%s(/|$)" % c, tok): return True
            if tok.startswith(root + "/") and re.match(r"%s(/|$)" % c, tok[len(root) + 1:]): return True
    return False
if tool == "Read" and in_corpus_file(ti.get("file_path", "")):
    content = tr["file"].get("content") if isinstance(tr, dict) and isinstance(tr.get("file"), dict) else None
    if isinstance(content, str): n = len(content.encode("utf-8"))
    else:
        try: n = os.path.getsize(ti["file_path"])   # unknown response shape: conservative fallback
        except OSError: n = 0
    out.update(KIND="read", BYTES=str(n), WHAT=ti.get("file_path", ""))
elif tool == "Bash" and names_corpus(ti.get("command", "") or ""):
    so = ((tr.get("stdout") or "") + (tr.get("stderr") or "")) if isinstance(tr, dict) else (tr if isinstance(tr, str) else "")
    n = len(so)
    if n > 30000: n = 2048
    if n: out.update(KIND="bash", BYTES=str(n), WHAT=" ".join(ti.get("command", "").split())[:140])
elif tool in ("Agent", "Task") and (ti.get("subagent_type") or "") == "librarian":
    out.update(KIND="delegate", WHAT="agent:librarian")
elif tool == "Skill" and "librarian" in (ti.get("skill") or ti.get("name") or ""):
    out.update(KIND="delegate", WHAT="skill:consulting-the-librarian")
for k, v in out.items(): print(k + "=" + shlex.quote(str(v)))
PY
vars="$(cat "$pf.vars" 2>/dev/null)"
rm -f "$pf" "$pf.vars"
eval "$vars" || exit 0
[ -n "${KIND:-}" ] || exit 0
[ -z "${AGENT:-}" ] || exit 0

mkdir -p "$LOGDIR" 2>/dev/null || exit 0
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ "$KIND" = delegate ]; then
  echo "$ts session=${SID:0:8} event=delegate via=$WHAT" >> "$LOGDIR/read-budget.log"; exit 0
fi
STATE="${TMPDIR:-/tmp}/harness-readbudget-${SID}.count"
total=$(( $(cat "$STATE" 2>/dev/null || echo 0) + BYTES ))
printf '%s' "$total" > "$STATE"
echo "$ts session=${SID:0:8} event=$KIND bytes=$BYTES session_total=$total what=$WHAT" >> "$LOGDIR/read-budget.log"
if [ $(( total / STEP )) -gt $(( (total - BYTES) / STEP )) ]; then
  python3 - "$total" <<'PY'
import json, sys
kb = int(sys.argv[1]) // 1024
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": (
  f"read-budget (advisory): this session has now pulled ~{kb} KB of project corpus directly into its own "
  "context (Read + Bash). A targeted read of a record you cite is correct; if you are SEARCHING or "
  "SURVEYING (\"what does the repo say about X\"), that is the librarian's job — /consulting-the-librarian returns "
  "verbatim quotes with file:line from its own window. Delegate the next sweep.")}}))
PY
fi
exit 0
