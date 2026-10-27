#!/usr/bin/env python3
"""log-agent-run.py — append ONE checked row to the agent run log (HARNESS_AGENT_DIR/runs.jsonl) from named arguments.

WHY (owner of the first adopting project: the run log was lacking data and "we expect this data to be collected from each
subsession"). The log was written by hand: 0 of 596 rows named a sub-session or a branch, 184 had no minutes, 208 no
tokens, and model names drifted. The facts are in every subagent's task notification — `<usage><subagent_tokens>N
</subagent_tokens><tool_uses>N</tool_uses><duration_ms>N</duration_ms></usage>` — so this helper takes that block as it
is, converts it, and refuses a row that breaks the row schema below. It is the ONLY way a row should enter the log: the
validator (row_errors) lives in this file, so the helper and any later reader of the log (a dashboard, a gate) can
share one definition of a valid row by importing it.

Usage (one row per agent run; the lead or the sub-session runs it at integration time):
  scripts/log-agent-run.py --model mid-5 --role tester --task "wave 8 export cross-author tests" \\
      --outcome ok --session export --branch feature/wave8-export --wave W8 \\
      --usage '<usage><subagent_tokens>412000</subagent_tokens><tool_uses>88</tool_uses><duration_ms>2712000</duration_ms></usage>' \\
      --findings 3 --accepted 3 --rejected 0
  --usage may be given more than once (a resumed agent: the blocks are summed). Instead of --usage: --minutes N or
  --duration-ms N, plus --tokens / --tool-uses; or --not-timed "<why>" when no time exists (written to source as
  "minutes not timed: <why>"). Testers, reviewers and hunters must give --findings (0 is a number).
  Other options: --kind run|judgement|correction|infra (default run), --restarts (old field, kept for history),
  --failure-reason (required when the outcome is not ok), --fault model|ours|config|unknown, --corrections, --source,
  --date YYYY-MM-DD (default today), --log PATH, --dry-run (print the row, write nothing).

  A run that did not finish is its own row: --outcome stopped (the lead or a session stopped it), killed (its process
  ended from outside, e.g. an app restart) or restarted (the attempt that was resumed; the resumed attempt gets its own
  row). It needs --failure-reason, --fault model|ours|config ("provider" is "model": it failed after the request was sent
  and our side was fine; "unknown" is refused) and the minutes LOST (--usage, --minutes or --duration-ms, above 0;
  --not-timed is refused: the lost time is the point of the row).

  A machine problem that cost time is --kind infra, with no model:
  scripts/log-agent-run.py --kind infra --what "container runtime hung" --minutes 60 --cause "the runtime stopped answering;
      restarted" --affected "the push gate run" --session lead --branch main --wave W62
  All of --what --minutes (or --duration-ms) --cause --affected --session --branch --wave are required; the run-only
  options (--model --role --task --outcome --usage --tokens ...) are refused, so nothing is dropped without a word.

PROOF AUDIT (owner of the first adopting project): every agent claim without its proof — no raw output line, a bug closed
without a red run, a "passes" that was never run — is logged as a `--kind correction` row (`--corrections N` = how many
errors were found in the output) whose task starts with a label saying what kind of claim it was:
  "UNPROVEN: <claim>"          the claim had no proof (a FINAL report without the gates run; a test never watched red)
  "WRONG CLAIM: <claim>"       a stated fact that was false (e.g. a reported count that the tool's own count contradicted)
  "WRONG DIAGNOSIS: <claim>"   a cause named without reproducing it, which turned out to be another one
The claim is then fixed or reopened. The labels are a convention for whoever reads the log (grep the task), not enforced here.

THE ROW SCHEMA (stable: a project can build a dashboard on it). One JSON object per line, UTF-8, append-only, never
rewritten. Run / judgement / correction rows:
  date (YYYY-MM-DD) · family (text|null) · model · kind · role · task (one line, <=600) · session · branch · wave ·
  minutes (number|null) · tokens · tool_uses (whole|null) · outcome · restarts (whole, 0) · findings · accepted · rejected
  (whole|null) · corrections (whole|null) · failure_reason (text|null) · source (text|null) · logged_by · fault (only
  when given)
Infra rows (kind "infra"; no model or family): date · kind · session · branch · wave · what (<=120) · minutes (>0) ·
  cause (<=600) · affected (<=600) · source · logged_by
Knobs (harness.conf; an environment variable wins): HARNESS_AGENT_DIR (default docs/agents) · HARNESS_RUNLOG (a full log
path, overrides the folder; the matrix uses it) · HARNESS_RUNLOG_MODELS (space-separated model names, each optionally
"name:family"; EMPTY = any model name is accepted, lower-cased) · HARNESS_RUNLOG_MODEL_ALIASES ("alias=name ..."; WHY: names
drift — "mid" vs "mid-5" — and a log with two spellings of one model cannot be summed) · HARNESS_RUNLOG_ROLES
(default: the roles below) · HARNESS_RUNLOG_WAVE_RE (default: a runner-row id such as W63 or EX1, or "none").

Exit: 0 appended (or printed with --dry-run) · 1 refused, nothing written · 3 could not run (log folder missing, crash).
Writes: appends one line to the log under an exclusive lock; never rewrites a line. Standard library only.
Matrix: scripts/log-agent-run-test.sh.
"""
import argparse
import datetime
import fcntl
import importlib.util
import json
import os
import re
import sys
import unicodedata

import math    # noqa: E402 — the validator below uses it

HERE = os.path.dirname(os.path.abspath(__file__))


def _root():
    try:
        import subprocess
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             cwd=os.getcwd(), check=True).stdout.decode("utf-8", "replace").strip()
        return out or os.path.abspath(os.path.join(HERE, ".."))
    except Exception:  # noqa: BLE001 — not in a git repo: the folder above scripts/ is the best root there is
        return os.path.abspath(os.path.join(HERE, ".."))


ROOT = _root()


def conf(name, default):
    """A knob: the environment's value if set, else the last assignment in harness.conf (read with a regex, never
    sourced — a logger must not execute config), else the default."""
    if name in os.environ:
        return os.environ[name]
    try:
        with open(os.path.join(ROOT, "harness.conf"), encoding="utf-8") as f:
            found = re.findall(r"^[ \t]*(?:export[ \t]+)?" + name + r"=[\"']?([^\"'#\n]*)", f.read(), re.M)
        if found:
            return found[-1].strip()
    except OSError:
        pass
    return default


def default_log():
    full = conf("HARNESS_RUNLOG", "")
    if full:
        return full
    return os.path.join(ROOT, conf("HARNESS_AGENT_DIR", "docs/agents").strip() or "docs/agents", "runs.jsonl")


# stopped / killed / restarted: a run that did not finish.
INTERRUPTED = {"stopped", "killed", "restarted"}
OUTCOMES = {"ok", "timeout", "truncated", "empty", "error", "too-large", "unknown"} | INTERRUPTED
KINDS = {"run", "judgement", "correction", "infra"}
# Whose fault a failed call was. WHY: the first adopting project's slowest model looked worst until it turned out that
# most of its lost minutes were stuck in OUR script before anything was sent, or cut off by OUR token budget.
#   model    it failed after the request was sent and our side was fine
#   ours     our script or our brief (a wait before the request left, a brief that was too big)
#   config   our limits (a token budget or time limit set too low)
#   unknown  not judged; the default for a row without the field
FAULTS = {"model", "ours", "config", "unknown"}
# An interrupted run must say whose fault it was: "unknown" would count it against the model without anyone judging it.
JUDGED_FAULTS = FAULTS - {"unknown"}
INFRA_TEXT = ("what", "cause", "affected")
INFRA_TEXT_MAX = {"what": 120, "cause": 600, "affected": 600}
# Session = the sub-session's name ([a-z0-9-]); the lead's own work is session "lead".
SESSION_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,47}$")
# Branch = a git branch name: no spaces, no "..", no leading "-" or "/" ("main" for the lead's own work).
BRANCH_RE = re.compile(r"^(?!.*\.\.)[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$")
# Wave = the runner row of the wave (the id column of the runner file), or the literal "none" for side work outside any wave.
WAVE_RE = re.compile("^(" + conf("HARNESS_RUNLOG_WAVE_RE", "[A-Z]{1,2}[0-9]{1,4}[a-z]?") + "|none)$")
# Roles whose time is the cost a dashboard compares: a row needs minutes > 0, or says why not ("minutes not timed").
TIMED_ROLES = {"builder", "tester", "test-author", "reviewer", "hunter", "ui-builder"}
NOT_TIMED = "minutes not timed"
# Roles whose output is findings: a row without a findings number is a data gap.
FINDING_ROLES = {"tester", "test-author", "reviewer", "hunter"}
# Every role in use; the helper refuses another, so a typo cannot start a new role line.
ROLES = set(conf("HARNESS_RUNLOG_ROLES", "builder tester test-author reviewer hunter lead sub-session analyst researcher "
                 "writer scribe architect librarian designer ui-builder").split())
# The model table: canonical name -> family (or None). EMPTY = any model name is accepted (free text, lower-cased).
MODELS = {}
for _entry in conf("HARNESS_RUNLOG_MODELS", "").split():
    _name, _, _fam = _entry.partition(":")
    MODELS[_name.lower()] = _fam or None
MODEL_ALIASES = {}
for _entry in conf("HARNESS_RUNLOG_MODEL_ALIASES", "").split():
    _al, _, _name = _entry.partition("=")
    if _al and _name:
        MODEL_ALIASES[_al.lower()] = _name.lower()


def canon_model(name):
    """The canonical model name for a logged one (aliases, lower-case), and whether it names several models at once ("a+b")."""
    if not isinstance(name, str):
        return name, False
    if "+" in name:
        return name, True
    low = name.strip().lower()
    return MODEL_ALIASES.get(low, low), False


def _whole(v):
    return isinstance(v, int) and not isinstance(v, bool)


# One row holds less than this many minutes (about 69 days). WHY a cap at all: json.loads reads a 401-digit whole number,
# math.isfinite() then raises OverflowError and a median divides it into "integer division result too large"; and two
# rows of 1e308 summed to infinity, which json.dumps writes as the bare word Infinity, so a page built on the log rendered
# EMPTY while the gate said PASS.
MINUTES_CAP = 100000


def minutes_ok(m, above_zero=False):
    """A minutes value a reader can add up: a number (not a bool), finite, 0 or more (above 0 when asked), below
    MINUTES_CAP. Compared without float(): a huge whole number is refused here instead of overflowing math.isfinite()."""
    if isinstance(m, bool) or not isinstance(m, (int, float)):
        return False
    if isinstance(m, float) and not math.isfinite(m):
        return False
    return (m > 0 if above_zero else m >= 0) and m < MINUTES_CAP


def visible_text(v):
    """True when v is text with at least one character a reader can see: a reason made of spaces or of U+200B and other
    format characters is blank."""
    return isinstance(v, str) and any(not ch.isspace() and unicodedata.category(ch) not in INVISIBLE for ch in v)


def real_date(v):
    """True when v is text of the shape YYYY-MM-DD naming a day that exists (2026-13-45 and 2026-02-30 do not)."""
    if not isinstance(v, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", v):
        return False
    try:
        datetime.date.fromisoformat(v)
    except ValueError:
        return False
    return True


def row_errors(r, n):
    """The per-row detector: every field a reader compares, groups by or adds up is type-checked HERE, so the helper
    cannot write a row that crashes a later reader."""
    errs = []
    if not isinstance(r, dict):
        return [f"line {n}: a log row must be a JSON object"]
    if r.get("kind") == "infra":
        return infra_errors(r, n)
    for k in ("date", "model", "kind", "task"):
        if not r.get(k):
            errs.append(f"line {n}: missing '{k}'")
        elif not isinstance(r.get(k), str):
            errs.append(f"line {n}: '{k}' must be text")   # a reader builds a set and sorts on these: a list crashes it
    if isinstance(r.get("date"), str) and r["date"] and not real_date(r["date"]):
        errs.append(f"line {n}: 'date' {r['date']!r} is not a real day as YYYY-MM-DD")
    for k in ("family", "role", "failure_reason", "outcome", "fault", "session", "branch", "wave", "source"):
        if r.get(k) is not None and not isinstance(r.get(k), str):
            errs.append(f"line {n}: '{k}' must be text")
    for k in ("restarts", "corrections"):
        if r.get(k) is not None and (isinstance(r.get(k), bool) or not isinstance(r.get(k), int)):
            errs.append(f"line {n}: '{k}' must be a whole number")
    # Per-session sums add these up: a string or a negative count would corrupt every total it joins.
    for k in ("tokens", "tool_uses", "findings", "accepted", "rejected"):
        v = r.get(k)
        if v is not None and (not _whole(v) or v < 0):
            errs.append(f"line {n}: '{k}' must be a whole number, 0 or more")
    m = r.get("minutes")
    if m is not None and (isinstance(m, bool) or not isinstance(m, (int, float))):
        errs.append(f"line {n}: 'minutes' must be a number")
    elif isinstance(m, float) and not math.isfinite(m):
        errs.append(f"line {n}: 'minutes' must be a finite number (NaN and Infinity are not valid JSON)")
    elif m is not None and not m < MINUTES_CAP:
        errs.append(f"line {n}: 'minutes' must be below {MINUTES_CAP} (one row; a bigger number breaks the sums)")
    # `in KINDS` / `in OUTCOMES` hash the value: only text may reach them.
    if isinstance(r.get("kind"), str) and r.get("kind") not in KINDS:
        errs.append(f"line {n}: kind must be one of {sorted(KINDS)}")
    if isinstance(r.get("fault"), str) and r.get("fault") not in FAULTS:
        errs.append(f"line {n}: fault must be one of {sorted(FAULTS)}")
    if r.get("kind") == "run" and (not isinstance(r.get("outcome"), str) or r.get("outcome") not in OUTCOMES):
        errs.append(f"line {n}: outcome must be one of {sorted(OUTCOMES)}")
    # A run that states why it has no time ("minutes not timed: <why>" in source) passes with minutes null — before,
    # such runs were written as 0.0, which a reader cannot tell from a measured zero.
    stated = isinstance(r.get("source"), str) and NOT_TIMED in r["source"].lower()
    if r.get("kind") == "run" and (isinstance(m, bool) or not isinstance(m, (int, float))) and not (m is None and stated):
        errs.append(f"line {n}: a run needs 'minutes' (take it from the usage block), or '{NOT_TIMED}: <why>' in source")
    # A run that did not finish: what went wrong and whose fault, or the lost minutes cannot be placed.
    if r.get("kind") == "run" and isinstance(r.get("outcome"), str) and r["outcome"] in INTERRUPTED:
        need_reason = f"line {n}: outcome {r['outcome']!r} needs 'failure_reason' (what stopped it, in a few words)"
        if not (isinstance(r.get("failure_reason"), str) and r["failure_reason"].strip()):
            errs.append(need_reason)
        elif not visible_text(r["failure_reason"]):
            errs.append(need_reason)
        # The lost time is the point of the row, so a "not timed" reason does not excuse it.
        if not minutes_ok(m, above_zero=True):
            errs.append(f"line {n}: outcome {r['outcome']!r} needs 'minutes' lost, above 0 and below {MINUTES_CAP}")
        if not isinstance(r.get("fault"), str) or r["fault"] not in JUDGED_FAULTS:
            errs.append(f"line {n}: outcome {r['outcome']!r} needs 'fault' {' | '.join(sorted(JUDGED_FAULTS))} "
                        "(whose fault the lost time was; 'unknown' is not a judgement)")
    if r.get("kind") == "judgement":
        f, a, j = r.get("findings"), r.get("accepted"), r.get("rejected")
        if not all(isinstance(x, int) and not isinstance(x, bool) for x in (f, a, j)) or a + j > f:
            errs.append(f"line {n}: judgement needs integers findings ≥ accepted + rejected")
    for k, rx, hint in (("session", SESSION_RE, "the sub-session name, [a-z0-9-], or 'lead'"),
                        ("branch", BRANCH_RE, "the git branch, or 'main' for the lead"),
                        ("wave", WAVE_RE, "the runner row of the wave, or 'none' outside any wave")):
        v = r.get(k)
        if not isinstance(v, str) or not v:
            errs.append(f"line {n}: a row needs '{k}' ({hint}) — append it with scripts/log-agent-run.py")
        elif not rx.fullmatch(v):   # fullmatch: with match, "$" also matches before a final newline ("H62\n" passed)
            errs.append(f"line {n}: '{k}' {v!r} is not {hint}")
    model = r.get("model")
    if isinstance(model, str) and MODELS and model not in MODELS:
        want, mixed = canon_model(model)
        if mixed:
            errs.append(f"line {n}: model {model!r} names several models — log one row per model")
        elif want in MODELS:
            errs.append(f"line {n}: model {model!r} is an alias — log it as {want!r}")
        else:
            errs.append(f"line {n}: model {model!r} is not in HARNESS_RUNLOG_MODELS — add it there")
    elif isinstance(model, str) and MODELS and r.get("family") != MODELS[model]:
        errs.append(f"line {n}: family {r.get('family')!r} is wrong for {model} — it is {MODELS[model]!r}")
    if r.get("kind") == "run" and r.get("role") in TIMED_ROLES:
        timed = isinstance(m, (int, float)) and not isinstance(m, bool) and m > 0
        why = isinstance(r.get("source"), str) and NOT_TIMED in r["source"].lower()
        if not timed and not why:
            errs.append(f"line {n}: a {r['role']} run needs minutes > 0 (from the usage block's duration_ms), or "
                        f"'{NOT_TIMED}: <why>' in source")
    return errs


def infra_errors(r, n):
    """A machine-problem row (kind "infra"): the time a machine problem cost (Docker hung, disk full). Every field is
    required and it names no model or family, so its minutes can never be added to a model's numbers."""
    errs = []
    if not real_date(r.get("date")):
        errs.append(f"line {n}: an infra row needs 'date' as YYYY-MM-DD")
    for k, rx, hint in (("session", SESSION_RE, "the session that lost the time, [a-z0-9-], or 'lead'"),
                        ("branch", BRANCH_RE, "the git branch, or 'main' for the lead"),
                        ("wave", WAVE_RE, "the runner row of the wave, or 'none'")):
        v = r.get(k)
        if not isinstance(v, str) or not rx.fullmatch(v):
            errs.append(f"line {n}: an infra row needs '{k}' ({hint})")
    for k in INFRA_TEXT:
        if not visible_text(r.get(k)):
            errs.append(f"line {n}: an infra row needs '{k}' as text")
    m = r.get("minutes")
    # minutes_ok() first: it refuses a non-number and a huge whole number before math.isfinite() could overflow on one.
    if not minutes_ok(m) or not math.isfinite(m) or m <= 0:
        errs.append(f"line {n}: an infra row needs 'minutes' lost, a number above 0 and below {MINUTES_CAP}")
    for k in ("model", "family"):
        if k in r:
            errs.append(f"line {n}: an infra row names no '{k}' — machine time never counts against a model")
    if r.get("source") is not None and not isinstance(r.get("source"), str):
        errs.append(f"line {n}: 'source' must be text")
    return errs


USAGE_TAGS = {"subagent_tokens": "tokens", "tool_uses": "tool_uses", "duration_ms": "duration_ms"}
# Control characters break a markdown table row and can hide text in a terminal; a task is one line of plain text.
CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")
# Unicode categories refused in free text: Cc controls beyond ASCII (U+0080-U+009F), Cf format and bidi marks, Zl/Zp line
# and paragraph separators (some renderers break a table row on them), Co private use, Cs lone surrogates, Cn unassigned.
INVISIBLE = {"Cc", "Cf", "Zl", "Zp", "Co", "Cs", "Cn"}
TASK_MAX = 600  # the longest task in the log on 2026-10-19 was under 300 characters; a pasted report is not a task


def refuse(msg):
    print(f"REFUSED: {msg} — nothing was written")
    sys.exit(1)


def clean_text(name, v, limit=TASK_MAX):
    """Normalise a free-text field (every input normalised and validated): trim, one line, no control chars."""
    if v is None:
        return None
    if "\n" in v or "\r" in v:
        refuse(f"--{name} must be one line")
    v = " ".join(v.split())
    if CONTROL.search(v):
        refuse(f"--{name} holds a control character")
    # Unicode format and bidi characters (category Cf: U+202E right-to-left override, U+200B zero-width space, ...) and the
    # other invisible kinds reorder or hide what a reader sees in a terminal, in a rendered table, so two tasks
    # can look identical or one can read backwards (proposed by the cross-author tester, approved by the lead).
    # A byte that is not UTF-8 reaches argv as a lone surrogate (Python's surrogateescape); it is bad input, so it is a
    # refusal (exit 1) like any other, not "could not run".
    if any(unicodedata.category(ch) == "Cs" for ch in v):
        refuse(f"--{name} is not valid UTF-8 text")
    bad = next((ch for ch in v if unicodedata.category(ch) in INVISIBLE), None)
    if bad is not None:
        refuse(f"--{name} holds the invisible or direction character U+{ord(bad):04X} "
               f"({unicodedata.name(bad, 'unnamed')})")
    if not v or not visible_text(v):
        refuse(f"--{name} is empty")
    if len(v) > limit:
        refuse(f"--{name} is {len(v)} characters; at most {limit}")
    return v


def parse_usage(blocks):
    """Sum the numbers of one or more pasted usage blocks. Each block must carry all three tags: a block missing
    duration_ms would otherwise log a run as untimed without anyone choosing that."""
    total = {"tokens": 0, "tool_uses": 0, "duration_ms": 0}
    for b in blocks:
        for tag, key in USAGE_TAGS.items():
            found = re.findall(rf"<{tag}>\s*(\d+)\s*</{tag}>", b)
            if len(found) != 1:
                refuse(f"a --usage block needs exactly one <{tag}>N</{tag}> (found {len(found)}); paste the whole "
                       "<usage>…</usage> block of one task notification per --usage")
            total[key] += int(found[0])
    return total


def whole(name, v):
    if v is None:
        return None
    if v < 0:
        refuse(f"--{name} must be 0 or more")
    return v


class Parser(argparse.ArgumentParser):
    """argparse exits 2 on a usage error; the harness exit vocabulary is closed (0 · 1 · 3 · 4), and a missing required
    field is a refusal like any other: exit 1, nothing written."""
    def error(self, message):
        self.print_usage(sys.stderr)
        refuse(message)


def main():
    p = Parser(prog="log-agent-run.py", description="Append one checked row to the agent run log.")
    p.add_argument("--model")
    p.add_argument("--role")
    p.add_argument("--task")
    p.add_argument("--outcome")
    p.add_argument("--session", required=True)
    p.add_argument("--branch", required=True)
    p.add_argument("--wave", required=True)
    p.add_argument("--kind", default="run")
    p.add_argument("--usage", action="append", default=[])
    p.add_argument("--minutes", type=float)
    p.add_argument("--duration-ms", type=int)
    p.add_argument("--not-timed")
    p.add_argument("--tokens", type=int)
    p.add_argument("--tool-uses", type=int)
    p.add_argument("--findings", type=int)
    p.add_argument("--accepted", type=int)
    p.add_argument("--rejected", type=int)
    p.add_argument("--corrections", type=int)
    p.add_argument("--restarts", type=int)
    p.add_argument("--what")
    p.add_argument("--cause")
    p.add_argument("--affected")
    p.add_argument("--failure-reason")
    p.add_argument("--fault")
    p.add_argument("--source")
    p.add_argument("--date")
    p.add_argument("--log", default=default_log())
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()
    if a.kind == "infra":
        return infra(a)
    # The run options are not argparse-required since --kind infra has none of them; a missing one is refused here, exit 1.
    missing = [f"--{k}" for k in ("model", "role", "task", "outcome") if getattr(a, k) is None]
    if missing:
        refuse(f"the following arguments are required: {', '.join(missing)}")
    for k in ("what", "cause", "affected"):
        if getattr(a, k) is not None:
            refuse(f"--{k} belongs to a machine-problem row (--kind infra), not a {a.kind} row")

    model, mixed = canon_model(a.model)
    if mixed:
        refuse(f"--model {a.model!r} names several models; log one row per model")
    if MODELS and model not in MODELS:
        refuse(f"--model {a.model!r} is not a known model ({', '.join(sorted(MODELS))}); a new model is one more name in "
               "HARNESS_RUNLOG_MODELS")
    if not model:
        refuse("--model is empty")
    if model != a.model:
        print(f"note: model {a.model!r} logged as {model!r} (lower-cased, or HARNESS_RUNLOG_MODEL_ALIASES)")
    role = a.role.strip().lower()
    if role not in ROLES:
        refuse(f"--role {a.role!r} is not one of {', '.join(sorted(ROLES))}")
    if a.kind not in KINDS:
        refuse(f"--kind must be one of {', '.join(sorted(KINDS))}")
    outcome = a.outcome.strip().lower()
    if outcome not in OUTCOMES:
        refuse(f"--outcome must be one of {', '.join(sorted(OUTCOMES))}")
    if a.kind == "correction" and not a.corrections:
        refuse("a correction row needs --corrections N (how many errors were found in the model's own output)")
    session, branch, wave = a.session.strip(), a.branch.strip(), a.wave.strip()
    for name, v, rx in (("session", session, SESSION_RE), ("branch", branch, BRANCH_RE), ("wave", wave, WAVE_RE)):
        if not rx.fullmatch(v):   # fullmatch: "$" with match also accepts a final newline
            refuse(f"--{name} {v!r} does not match {rx.pattern}")

    # Time: exactly one source of it — the usage block, an explicit number, or a stated reason why there is none.
    usage = parse_usage(a.usage) if a.usage else None
    given = [x for x in ("usage" if usage else None, "minutes" if a.minutes is not None else None,
                         "duration-ms" if a.duration_ms is not None else None,
                         "not-timed" if a.not_timed is not None else None) if x]
    if len(given) > 1:
        refuse(f"give the time once: --{' and --'.join(given)} were both given")
    minutes = None
    if usage:
        ms = usage["duration_ms"]
    else:
        ms = whole("duration-ms", a.duration_ms)
    if ms is not None:
        minutes = ms_to_minutes(ms)
    elif a.minutes is not None:
        if not (a.minutes >= 0 and a.minutes < MINUTES_CAP):
            refuse("--minutes must be a finite number, 0 or more")
        minutes = round(a.minutes, 2)
    tokens = usage["tokens"] if usage else whole("tokens", a.tokens)
    tool_uses = usage["tool_uses"] if usage else whole("tool-uses", a.tool_uses)
    if usage and (a.tokens is not None or a.tool_uses is not None):
        refuse("--tokens / --tool-uses come from the --usage block; do not give them as well")

    findings, accepted, rejected = whole("findings", a.findings), whole("accepted", a.accepted), whole("rejected", a.rejected)
    if a.kind == "run" and role in FINDING_ROLES and findings is None:
        refuse(f"a {role} run needs --findings (0 is a number): a tester or reviewer row without it is a data gap")
    if (accepted or 0) + (rejected or 0) > (findings or 0) and (accepted is not None or rejected is not None):
        refuse("--accepted + --rejected is more than --findings")
    if a.kind == "judgement" and None in (findings, accepted, rejected):
        refuse("a judgement row needs --findings, --accepted and --rejected")
    if a.kind == "run" and outcome != "ok" and not a.failure_reason:
        refuse(f"outcome {outcome!r} needs --failure-reason (what went wrong, in a few words)")
    fault = a.fault.strip().lower() if a.fault else None
    if outcome in INTERRUPTED:
        # Owner 2026-10-19: a stopped, killed or restarted run says whose fault the lost time was and how long it was.
        if fault not in JUDGED_FAULTS:
            refuse(f"outcome {outcome!r} needs --fault {' | '.join(sorted(JUDGED_FAULTS))} (whose fault the lost time "
                   "was; a provider's failure is 'model'; 'unknown' is not a judgement)")
        if a.not_timed is not None:
            refuse(f"outcome {outcome!r} needs the minutes lost (--usage, --minutes or --duration-ms), not --not-timed")
        if not (minutes and minutes > 0):
            refuse(f"outcome {outcome!r} needs the minutes lost, above 0 (from the start to the stop, or the wasted part)")

    source_parts = []
    if usage:
        n = len(a.usage)
        source_parts.append("harness task notification usage block" + (f"s summed over {n} runs" if n > 1 else ""))
    if a.not_timed is not None:
        source_parts.append(f"{NOT_TIMED}: {clean_text('not-timed', a.not_timed, 300)}")
    if a.source:
        source_parts.append(clean_text("source", a.source))
    date = check_date(a.date)

    row = {"date": date, "family": MODELS.get(model) or None, "model": model, "kind": a.kind, "role": role,
           "task": clean_text("task", a.task), "session": session, "branch": branch, "wave": wave,
           "minutes": minutes, "tokens": tokens, "tool_uses": tool_uses, "outcome": outcome,
           # restarts: the old field, still written as 0 so older readers see the same row shape; a resumed run is now
           # its own row with outcome "restarted".
           "restarts": whole("restarts", a.restarts if a.restarts is not None else 0),
           "findings": findings, "accepted": accepted, "rejected": rejected,
           "corrections": whole("corrections", a.corrections),
           "failure_reason": clean_text("failure-reason", a.failure_reason) if a.failure_reason else None,
           "source": "; ".join(source_parts) or None, "logged_by": "scripts/log-agent-run.py"}
    if fault:
        row["fault"] = fault
    append(a, row)


def infra(a):
    """A machine-problem row (--kind infra, owner 2026-10-19): no model, its own required fields, never a model's cost."""
    run_only = [f"--{k.replace('_', '-')}" for k in ("model", "role", "task", "outcome", "not_timed", "tokens", "tool_uses",
                                                    "findings", "accepted", "rejected", "corrections", "restarts",
                                                    "failure_reason", "fault") if getattr(a, k) is not None]
    run_only += ["--usage"] if a.usage else []
    if run_only:
        refuse(f"a machine-problem row (--kind infra) names no model and no run: {', '.join(run_only)} not allowed")
    missing = [f"--{k}" for k in ("what", "cause", "affected", "session", "branch", "wave") if getattr(a, k) is None]
    if a.minutes is None and a.duration_ms is None:
        missing.append("--minutes")
    if missing:
        refuse(f"a machine-problem row needs {', '.join(missing)}")
    if a.minutes is not None and a.duration_ms is not None:
        refuse("give the time once: --minutes and --duration-ms were both given")
    if a.duration_ms is not None:
        minutes = ms_to_minutes(whole("duration-ms", a.duration_ms))
    else:
        if not (a.minutes >= 0 and a.minutes < MINUTES_CAP):
            refuse("--minutes must be a finite number, 0 or more")
        minutes = round(a.minutes, 2)
    if minutes <= 0:
        refuse("a machine-problem row needs the minutes lost, above 0")
    session, branch, wave = a.session.strip(), a.branch.strip(), a.wave.strip()
    for name, v, rx in (("session", session, SESSION_RE), ("branch", branch, BRANCH_RE), ("wave", wave, WAVE_RE)):
        if not rx.fullmatch(v):
            refuse(f"--{name} {v!r} does not match {rx.pattern}")
    row = {"date": check_date(a.date), "kind": "infra", "session": session, "branch": branch, "wave": wave,
           "what": clean_text("what", a.what, INFRA_TEXT_MAX["what"]), "minutes": minutes,
           "cause": clean_text("cause", a.cause, INFRA_TEXT_MAX["cause"]),
           "affected": clean_text("affected", a.affected, INFRA_TEXT_MAX["affected"]),
           "source": clean_text("source", a.source) if a.source else None, "logged_by": "scripts/log-agent-run.py"}
    append(a, row)


def ms_to_minutes(ms):
    """Milliseconds to minutes, under the per-row cap (MINUTES_CAP): compared before dividing, so a
    huge number is a refusal (exit 1), never an OverflowError ("integer division result too large")."""
    if ms >= MINUTES_CAP * 60000:
        refuse(f"--duration-ms {ms} is {MINUTES_CAP} minutes or more; one row holds less (MINUTES_CAP)")
    return round(ms / 60000, 2)


def check_date(v):
    """--date as YYYY-MM-DD naming a real day (real_date), not in the future; today
    when not given."""
    date = (v or datetime.date.today().isoformat()).strip()
    if not real_date(date):
        refuse(f"--date {date!r} is not YYYY-MM-DD")
    if datetime.date.fromisoformat(date) > datetime.date.today():
        refuse(f"--date {date} is in the future")
    return date


def append(a, row):
    """Validate the row with row_errors() on the line it will land on, then append it under a lock."""
    log = os.path.abspath(a.log)
    if not os.path.isdir(os.path.dirname(log)):
        print(f"INCOMPLETE: the log folder {os.path.dirname(log)} does not exist")
        sys.exit(3)
    if a.dry_run:
        n = next_line(log)
        errs = row_errors(row, n)
        if errs:
            refuse("; ".join(errs))
        print(json.dumps(row, ensure_ascii=False))
        print(f"dry run: valid as line {n} of {log}; nothing was written")
        return
    # Append under an exclusive lock: two sessions sharing a checkout must not interleave half lines. The line number is
    # read under the same lock, so the new-row rule judges the line the row really lands on.
    # The lock stays although no test can see it: one O_APPEND write of a short line already lands whole, so a race test
    # passes with or without it; it guards the read-count-validate-write sequence, which only a real overlap would break.
    fd = os.open(log, os.O_RDWR | os.O_CREAT | os.O_APPEND, 0o644)
    with os.fdopen(fd, "r+b") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        data = f.read()
        lead = b"\n" if data and not data.endswith(b"\n") else b""   # a last line without its newline would swallow ours
        n = data.count(b"\n") + (1 if lead else 0) + 1
        errs = row_errors(row, n)
        if errs:
            refuse("; ".join(errs))
        f.write(lead + (json.dumps(row, ensure_ascii=False) + "\n").encode("utf-8"))
        f.flush()
        os.fsync(f.fileno())
    print(json.dumps(row, ensure_ascii=False))
    print(f"appended as line {n} of {os.path.relpath(log, ROOT) if log.startswith(ROOT) else log}")


def next_line(log):
    if not os.path.isfile(log):
        return 1
    data = open(log, "rb").read()
    return data.count(b"\n") + (1 if data and not data.endswith(b"\n") else 0) + 1


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 — a helper that crashes must say "nothing was written", never a bare traceback
        print(f"INCOMPLETE: log-agent-run.py crashed ({type(exc).__name__}: {exc}); nothing was written")
        sys.exit(3)
