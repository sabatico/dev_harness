#!/usr/bin/env python3
"""verify-check.py — Stop hook: did this turn change code and then finish without running anything that
checks it? (Wrapper: hook-stop-verifycheck.sh exports harness.conf + the stack pack.)

WHY (2026-09-30). "Verify before you report" sat in the constitution's held-only-by-attention column,
and the kit's own measurement says what that column is worth: of ten escaped defects on the source
project, a rule being read and complied with caught zero (README, "Why so much of this is
mechanised"). The harness-engineering source study (Barbaste et al. 2026, arXiv 2609.00006, §6.2)
found one harness (Hermes) that moves the reflection loop's job into the STOP condition: a turn that
mutated code without producing fresh verification evidence is not allowed to end as a plain answer.
That is cheap, mechanical, and checkable — so it moves this rule partly into the enforced column.

WHAT COUNTS, decided from the session transcript (the same reader claim-check.py uses — the format is
internal to Claude Code and may change between releases; a parse failure is logged, never raised):
  CODE CHANGE   an Edit/Write/MultiEdit/NotebookEdit in THIS turn (since the last human prompt) to a file
                under HARNESS_CODE_DIRS with an extension in HARNESS_CODE_EXTS (any extension if empty).
  VERIFICATION  a Bash call that RUNS (at command position, after wrappers/runners are stripped)
                HARNESS_TEST_CMD / HARNESS_LINT_CMD / HARNESS_COVERAGE_CMD, the gate runner, a *-test.sh
                matrix, or a common test/build/typecheck command — or matches HARNESS_VERIFY_RE there.
                Running it counts even if it FAILED: the point is that the agent saw the result before
                reporting, not that the result was green. A call that was refused (permission, hook) or
                sent to the background does not count.
  FLAG          the last code change comes AFTER the last verification (or there was none).

MODES (HARNESS_VERIFYCHECK_MODE): advise (default) → a systemMessage the owner sees + a log line.
block → a Stop "decision:block" that makes the model run the checks or say plainly it did not — once
per stop (never when stop_hook_active). off → nothing. Same promotion rule as claim-check: start in
advise, read .harness-logs/verify-check.log for two weeks, switch to block on evidence.

KNOWN BLIND SPOTS: edits made by a subagent (they live in its own transcript), code changed through
Bash (sed -i, a generator), a verification command spelled in a way no pattern matches (add it to
HARNESS_VERIFY_RE). Matrix: scripts/hook-stop-verifycheck-test.sh.
"""
import json
import os
import re
import sys
import time

E = os.environ.get
ROOT = E("HARNESS_ROOT_OVERRIDE") or os.getcwd()
MODE = (E("HARNESS_VERIFYCHECK_MODE") or "advise").strip()
CODE_DIRS = (E("HARNESS_CODE_DIRS") or "src").split()
CODE_EXTS = (E("HARNESS_CODE_EXTS") or "").split()
LOGDIR = E("HARNESS_LOG_DIR") or ".harness-logs"
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}

# A verification RUNS at command position. Matching the words anywhere counted `echo skipping pytest`,
# `grep -rn pytest`, `cat scripts/run-all-gates.sh` and `vim src/a_test.sh` as a test run (found by the
# cross-author matrix, 2026-09-30) — so each simple command is stripped of wrappers and runners, then
# the pattern must match at its START.
VERIFY_HEAD = (
    r"(?:pytest|jest|vitest|mocha|rspec|phpunit|ctest|tox|nox|tsc|mypy|pyright|eslint|ruff|shellcheck"
    r"|go (?:test|vet|build)|cargo (?:test|check|build|clippy|nextest)"
    r"|(?:npm|pnpm|yarn|bun)(?: run)? (?:test|build|lint|check|typecheck)"
    r"|make (?:test|check|build|lint)|mvn (?:test|verify)|(?:\./)?gradlew? (?:test|check|build)"
    r"|dotnet (?:test|build)|python3? -m (?:pytest|unittest)"
    r"|(?:\S*/)?run-all-gates\.sh|(?:\S*/)?selftest\.sh|(?:\S*/)?[^\s/]+[-_]test\.sh)(?:\s|$)")
PREFIX = re.compile(r"^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+|(?:env|time|sudo|command|exec|nohup|xargs)(?:\s+-[A-Za-z]+)*\s+"
                    r"|nice(?:\s+-n\s*-?\d+)?\s+|timeout\s+\S+\s+|(?:bash|sh|zsh)\s+(?:-[a-z]+\s+)*['\"]?"
                    r"|npx\s+|bunx\s+|uv run\s+|poetry run\s+|pnpm exec\s+|[({]\s*)+")


def verify_patterns():
    pats = [VERIFY_HEAD]
    for k in ("HARNESS_TEST_CMD", "HARNESS_LINT_CMD", "HARNESS_COVERAGE_CMD"):
        v = (E(k) or "").strip()
        if v:
            pats.append(re.escape(v.split("&&")[0].strip()))
    if E("HARNESS_VERIFY_RE"):
        pats.append(E("HARNESS_VERIFY_RE"))
    out = []
    for p in pats:
        try:
            out.append(re.compile(p))
        except re.error:   # a bad project regex must not switch the whole check off
            log(f"error=bad-HARNESS_VERIFY_RE pattern={p[:40]!r}")
    return out


def runs_verification(cmd, pats):
    for seg in re.split(r"\|\||&&|[;|\n&]", cmd or ""):
        seg = PREFIX.sub("", seg.strip())
        # (cd src && pytest) ends glued to a paren — but a configured command may itself end in one
        # ("covr run (all)"), so try the segment both as written and with the closers trimmed.
        for form in (seg, seg.rstrip(")}'\" ")):
            if form and not form.startswith("#") and any(p.match(form) for p in pats):
                return True
    return False


def _norm_dir(d):
    d = os.path.normpath(d)
    return "" if d == "." else d


def is_code(path):
    if not path:
        return False
    rel = os.path.relpath(os.path.abspath(os.path.join(ROOT, path)), ROOT)
    if rel.startswith(".."):
        return False
    dirs = [_norm_dir(d) for d in CODE_DIRS]
    if not any(d == "" or rel == d or rel.startswith(d + "/") for d in dirs):
        return False
    return not CODE_EXTS or rel.rsplit(".", 1)[-1].lower() in {x.lower() for x in CODE_EXTS}


def _msg(d):
    m = d.get("message")
    return m if isinstance(m, dict) else {}


def _is_user_prompt(d):
    if d.get("type") != "user" or d.get("isSidechain") or d.get("isMeta") or d.get("isCompactSummary"):
        return False
    c = _msg(d).get("content")
    if isinstance(c, str):
        return True
    if isinstance(c, list):
        kinds = {b.get("type") for b in c if isinstance(b, dict)}
        return "tool_result" not in kinds and "text" in kinds
    return False


def _text(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(b.get("text", "") for b in c if isinstance(b, dict))
    return ""


def turn_tool_calls(tp):
    """→ (the tool_use blocks of the current turn, oldest first; {tool_use_id: (is_error, text)})."""
    entries = []
    for attempt in range(2):  # the final entry can land a beat after Stop fires
        entries = []
        if os.path.isfile(tp):
            with open(tp, encoding="utf-8", errors="replace") as f:
                for line in f:
                    try:
                        d = json.loads(line)
                    except ValueError:
                        continue
                    if isinstance(d, dict):
                        entries.append(d)
        if entries and entries[-1].get("type") == "assistant" or attempt:
            break
        time.sleep(0.4)
    calls, results = [], {}
    for d in reversed(entries):
        if _is_user_prompt(d):
            break
        content = _msg(d).get("content")
        if d.get("type") == "user" and isinstance(content, list):
            for b in content:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    results[b.get("tool_use_id")] = (bool(b.get("is_error")), _text(b.get("content")))
        if d.get("type") == "assistant" and not d.get("isSidechain") and isinstance(content, list):
            for b in reversed(content):
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    calls.append(b)
    return list(reversed(calls)), results


def did_run(b, results):
    """A refused call (permission denied, hook-blocked) never ran; a background run's result was never
    read in this turn. A command that ran and FAILED still counts — its result starts 'Exit code N'."""
    if (b.get("input") or {}).get("run_in_background"):
        return False
    r = results.get(b.get("id"))
    if r is None:
        return True   # no result entry to judge by: give the benefit of the doubt (advisory check)
    is_error, text = r
    return not is_error or text.lstrip().startswith("Exit code")


def log(line):
    try:
        os.makedirs(os.path.join(ROOT, LOGDIR), exist_ok=True)
        with open(os.path.join(ROOT, LOGDIR, "verify-check.log"), "a") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) + " " + line + "\n")
    except OSError:
        pass


def main():
    if MODE == "off":
        return
    payload = json.load(sys.stdin)
    sid = re.sub(r"[^A-Za-z0-9-]", "", str(payload.get("session_id", "?")))[:8] or "?"
    pats = verify_patterns()
    last_edit, last_verify, changed = -1, -1, []
    calls, results = turn_tool_calls(payload.get("transcript_path") or "")
    for i, b in enumerate(calls):
        name, ti = b.get("name", ""), b.get("input") or {}
        if name in EDIT_TOOLS:
            fp = ti.get("file_path") or ti.get("notebook_path") or ""
            if is_code(fp):
                last_edit = i
                rel = os.path.relpath(os.path.abspath(os.path.join(ROOT, fp)), ROOT)
                if rel not in changed:
                    changed.append(rel)
        elif name == "Bash" and runs_verification(ti.get("command", ""), pats) and did_run(b, results):
            last_verify = i
    if last_edit < 0:
        return
    if last_verify > last_edit:
        log(f"session={sid} verdict=verified code_files={len(changed)}")
        return
    log(f"session={sid} verdict=UNVERIFIED code_files={len(changed)} mode={MODE}")
    names = ", ".join(changed[:4]) + (f" (+{len(changed) - 4} more)" if len(changed) > 4 else "")
    what = "ran no test, build or gate command afterwards" if last_verify < 0 else \
        "changed code again after the last test, build or gate run"
    if MODE == "block" and not payload.get("stop_hook_active"):
        print(json.dumps({"decision": "block", "reason": (
            f"verify-check: this turn changed {len(changed)} code file(s) ({names}) and {what}. "
            "Before reporting the work, run the project's checks (HARNESS_TEST_CMD, or "
            "scripts/run-all-gates.sh) and report what they printed - or, if they cannot run here, say "
            "plainly in your reply that the change is UNVERIFIED and why.")}))
    else:
        print(json.dumps({"systemMessage": (
            f"verify-check (advisory): this turn changed {len(changed)} code file(s) ({names}) and {what}. "
            "Treat any 'done' in the reply as unverified until the checks have run.")}))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # a Stop hook must never break a turn
        log(f"error={type(e).__name__}")
