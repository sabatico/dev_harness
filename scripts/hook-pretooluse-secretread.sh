#!/usr/bin/env bash
# hook-pretooluse-secretread.sh — keep secrets out of the AGENT'S CONTEXT (security baseline item 26:
# "keep production credentials out of your agent's reach"). Generalised 2026-09-29 from a live project.
#
# WHY: on the source project the constitution said creds live in `.env`, and nothing stopped an
# agent from `cat .env` or a Read of it — which copies every secret into the model's context, the
# session transcript on disk, and anything the transcript is later shared with. The existing guard
# (hook-pretooluse-guard.sh) covers DESTRUCTION; this is the separate EXPOSURE rule (hardening-security skill, door #26).
#
# WHAT IS DENIED: showing secret material to the model —
#   · Read of `.env` / `.env.<name>` (not .env.example/.sample/.template: those hold no values);
#   · a Bash viewer on such a file (cat/less/more/head/tail/bat/nl/strings/xxd/od/vi/vim/nano/open);
#   · grep/sed/awk/cut on it OUTSIDE a `$( … )` substitution (inside one, the value feeds a variable
#     and is never printed — the sanctioned way to load a credential into an env var);
#   · a bare environment dump (`env`, `printenv`, `env | …`, `set` alone) — it prints exported secrets.
# WHAT STAYS ALLOWED: sourcing (`set -a; . ./.env; set +a`), `$(grep KEY= .env | cut -d= -f2)`,
#   `grep -q`/`-c`/`-l` (a yes/no or a count prints no value), `ls`/`git check-ignore`/`stat` on it,
#   `env VAR=x cmd`, and any prose that merely NAMES the file (commit messages, echo "add .env …").
# A script that needs a credential sources the file ITSELF; the agent never needs to see the value.
# Self-test: scripts/hook-pretooluse-secretread-test.sh (known-answer matrix, gated).
set -uo pipefail
pf="$(mktemp "${TMPDIR:-/tmp}/sr-payload.XXXXXX")" || exit 0
cat > "$pf"
python3 - "$pf" > "$pf.out" 2>/dev/null <<'PY'
import json, re, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
tool, ti = d.get("tool_name", ""), d.get("tool_input") or {}
SAFE = r"(?:example|sample|template|dist|defaults)"
ENVFILE = r"(?:[\w./~-]*/)?\.env(?:\.(?!%s\b)[\w-]+)?" % SAFE      # .env, x/.env, .env.local; not .env.example

# harness:allow-uncited — plumbing: one JSON deny with the sanctioned alternative in the reason,
# so a blocked agent learns the safe way to load a credential instead of retrying the unsafe one.
def deny(why):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": "BLOCKED (secret exposure, security baseline 26): " + why +
        " A script that needs a credential sources the file itself (set -a; . ./.env; set +a) or loads one"
        " value into a variable with $(grep KEY= .env | cut -d= -f2) — the value never reaches the model."}}))
    sys.exit(0)

if tool == "Read":
    fp = ti.get("file_path", "") or ""
    base = fp.rsplit("/", 1)[-1]
    if re.fullmatch(r"\.env(?:\.[\w-]+)?", base) and not re.fullmatch(r"\.env\.%s" % SAFE, base):
        deny("reading %s would copy every secret in it into this context and the transcript." % base)
    sys.exit(0)

if tool != "Bash":
    sys.exit(0)
cmd = ti.get("command", "") or ""

# harness:allow-uncited — plumbing: a value read INSIDE $( ) feeds a variable and is never printed,
# which is the sanctioned way to load a credential; only reads outside one are exposure.
def outside_subst(text, pos):
    # True when position `pos` is NOT inside a $( … ) span (a value there feeds a variable, unprinted).
    depth, i = 0, 0
    while i < pos:
        if text.startswith("$(", i):
            depth += 1; i += 2; continue
        if text[i] == ")" and depth:
            depth -= 1
        i += 1
    return depth == 0

SEG = r"(?:^|[;&|(\n]|\bthen\b|\bdo\b)\s*"          # command position
VIEW = r"(?:cat|less|more|head|tail|bat|nl|strings|xxd|od|vi|vim|nano|view|open|tac)"
for m in re.finditer(SEG + VIEW + r"\b[^;&|\n]*?(?<![\w.])(" + ENVFILE + r")(?=$|[\s;&|)\"'])", cmd):
    if outside_subst(cmd, m.start(1)):
        deny("`%s` would print %s into this context." % (m.group(0).strip()[:60], m.group(1)))
for m in re.finditer(SEG + r"(grep|egrep|rg|sed|awk|cut)\b([^;&|\n]*?)(?<![\w.])(" + ENVFILE + r")(?=$|[\s;&|)\"'])", cmd):
    flags = m.group(2)
    if m.group(1) in ("grep", "egrep", "rg") and re.search(r"(^|\s)-[a-zA-Z]*[qcl]", flags):
        continue                                           # -q / -c / -l print no value
    if outside_subst(cmd, m.start(3)):
        deny("`%s` would print values from %s; wrap it in $( … ) to load one into a variable instead."
             % (m.group(0).strip()[:60], m.group(3)))
if re.search(SEG + r"(printenv|env|set)\s*($|[;&|\n])", cmd):
    deny("an environment dump prints every exported secret; print the ONE variable name you need to check "
         "with ${VAR:+set} instead of its value.")
PY
cat "$pf.out" 2>/dev/null
rm -f "$pf" "$pf.out"
exit 0
