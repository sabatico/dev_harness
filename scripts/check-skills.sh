#!/usr/bin/env bash
# check-skills.sh — lint every harness skill, agent and path-scoped rule against Anthropic's Agent
# Skills best practices (see dot-claude/skills/authoring-skills/SKILL.md for the rules and WHY).
#
#   scripts/check-skills.sh [ROOT]      # ROOT defaults to the repo root; exit 0 clean, 1 findings
#
# Checks (each finding names file + rule, so the fix is obvious):
#   SKILL.md   frontmatter present · name == folder · name ^[a-z0-9-]{1,64}$ · gerund first word ·
#              no reserved words · description non-empty, ≤1024 chars, third person, has "Use when",
#              no XML tags · body ≤500 lines · relative links resolve · no Windows paths ·
#              reference files: one level deep (no links to other reference .md) · ToC if >100 lines
#              evals/<name>.json with ≥3 scenarios (query + expected_behavior)
#   agents/*.md  frontmatter with name + description (third person, "Use when"/"Use for")
#   rules/*.md   frontmatter with non-empty `paths:` (README.md exempt)
# Dated wording ("as of 2026", "before March") outside a "## History" section is a WARNING only:
# dates also appear legitimately in examples.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
PY="$(command -v python3 || true)"
[ -n "$PY" ] || { echo "check-skills: python3 not found — cannot lint (this is a FAIL, not a skip)"; exit 1; }

"$PY" - "$ROOT" <<'PYEOF'
import os, re, sys
root = os.path.abspath(sys.argv[1])  # absolute: link targets and walked files must compare equal
# an installed project has the platform layer in .claude/ (preferred when it holds skills/agents/rules);
# the kit keeps it in dot-claude/
base = next((os.path.join(root, d) for d in (".claude", "dot-claude")
             if any(os.path.isdir(os.path.join(root, d, x)) for x in ("skills", "agents", "rules"))),
            os.path.join(root, "dot-claude"))
findings, warnings = [], []
NAME_RE = re.compile(r"^[a-z0-9-]{1,64}$")
XML_RE = re.compile(r"<[A-Za-z/][^>]*>")
FIRST_SECOND = re.compile(r"^\s*(I|I'm|I'll|We|We'll|You|You'll|Your|Let me|Use this to)\b")
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)#\s]+)(?:#[^)]*)?\)")
WIN_PATH = re.compile(r"\b[\w.-]+\\[\w.-]+\.(?:md|py|sh|json|js|ts)\b")
DATED = re.compile(r"\b(as of|since|before|after|until)\s+(?:\d{4}|January|February|March|April|May|June|July|August|September|October|November|December)\b", re.I)

def rel(p):  # harness:allow-uncited kit linter governed by the authoring-skills skill; the kit has no ADR log
    """Findings print repo-relative paths so the fix target is obvious."""
    return os.path.relpath(p, root)

def split_frontmatter(text):  # harness:allow-uncited kit linter governed by the authoring-skills skill; the kit has no ADR log
    """Minimal YAML-frontmatter reader (no PyYAML dependency on gate machines)."""
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---", 4)
    if end < 0:
        return None, text
    fm_raw = text[4:end]
    body = text[end + 4:].lstrip("\n")
    fm, key = {}, None
    for line in fm_raw.splitlines():
        m = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if m:
            key = m.group(1); fm[key] = m.group(2).strip().strip('"').strip("'")
        elif key and line.startswith((" ", "\t")):
            fm[key] = (fm[key] + " " + line.strip()).strip()
    return fm, body

def check_description(path, desc, needs_when=True):  # harness:allow-uncited kit linter governed by the authoring-skills skill; the kit has no ADR log
    """The description is all an agent sees before choosing a skill, so its limits and voice are enforced."""
    if not desc:
        findings.append(f"{rel(path)}: description is empty"); return
    if len(desc) > 1024:
        findings.append(f"{rel(path)}: description is {len(desc)} chars (max 1024)")
    if XML_RE.search(desc):
        findings.append(f"{rel(path)}: description contains an XML/HTML tag")
    if FIRST_SECOND.match(desc):
        findings.append(f"{rel(path)}: description must be third person (\"Writes…\", not \"I…\"/\"You…\")")
    if needs_when and not re.search(r"\bUse (when|for|at|before|after|whenever)\b", desc):
        findings.append(f"{rel(path)}: description must say when to use it (\"Use when …\")")

def body_without_history(body):  # harness:allow-uncited kit linter governed by the authoring-skills skill; the kit has no ADR log
    """Dated wording is legitimate inside a ## History section, so it is stripped before the timeless-wording check."""
    out, skip = [], False
    for line in body.splitlines():
        if re.match(r"^##\s+History\b", line): skip = True; continue
        if skip and re.match(r"^##\s", line): skip = False
        if not skip: out.append(line)
    return "\n".join(out)

TICK = re.compile(r"`([^`\n]+)`")
KIT = os.path.basename(base) == "dot-claude"
def resolves(tok, here):  # harness:allow-uncited kit linter governed by the authoring-skills skill; the kit has no ADR log
    """ A backticked path claim resolves at the root, next to the file, or — in the kit, whose docs
    cite INSTALLED-layout paths (.harness/baselines/doc-paths.txt) — after mapping docs/ci/ -> ci/,
    docs/ -> running-files/, .claude/ -> dot-claude/."""
    cands = [os.path.join(root, tok), os.path.join(here, tok)]
    if KIT:
        for pre, kit in (("docs/ci/", "ci/"), ("docs/", "running-files/"), (".claude/", "dot-claude/")):
            if tok.startswith(pre):
                cands.append(os.path.join(root, kit + tok[len(pre):])); break
    return any(os.path.exists(c) for c in cands)

def check_paths(path, text):  # harness:allow-uncited kit linter governed by the authoring-skills skill; the kit has no ADR log
    """ Same claim rule as check-doc-paths.sh (which does not scan the platform layer): a backticked
    token with a slash AND an extension (or a trailing slash) must exist."""
    for m in TICK.finditer(text):
        tok = m.group(1).strip()
        if (" " in tok or "(" in tok or "://" in tok or tok.startswith(("http", "/", "~"))
                or any(c in tok for c in "<>«»*?[$")):
            continue
        if "/" not in tok or not (tok.endswith("/") or re.search(r"/[^/]*\.[A-Za-z0-9]+$", tok)):
            continue
        if not resolves(tok.rstrip("/"), os.path.dirname(path)):
            findings.append(f"{rel(path)}: backticked path `{tok}` does not exist")

def check_md_common(path, text):  # harness:allow-uncited kit linter governed by the authoring-skills skill; the kit has no ADR log
    """Checks shared by skills, references, agents and rules."""
    check_paths(path, text)
    for m in WIN_PATH.finditer(text):
        findings.append(f"{rel(path)}: Windows-style path '{m.group(0)}' (use forward slashes)")
    for m in DATED.finditer(body_without_history(text)):
        warnings.append(f"{rel(path)}: dated wording '{m.group(0)}' outside a ## History section")

skills_dir = os.path.join(base, "skills")
names = set()
if os.path.isdir(skills_dir):
    for d in sorted(os.listdir(skills_dir)):
        sdir = os.path.join(skills_dir, d)
        if not os.path.isdir(sdir): continue
        skill = os.path.join(sdir, "SKILL.md")
        if not os.path.isfile(skill):
            findings.append(f"{rel(sdir)}: folder has no SKILL.md"); continue
        text = open(skill, encoding="utf-8").read()
        fm, body = split_frontmatter(text)
        if fm is None:
            findings.append(f"{rel(skill)}: missing YAML frontmatter (--- name/description ---)"); continue
        name = fm.get("name", "")
        if not NAME_RE.match(name):
            findings.append(f"{rel(skill)}: name '{name}' must be lowercase letters/digits/hyphens, ≤64 chars")
        if name != d:
            findings.append(f"{rel(skill)}: name '{name}' must equal its folder '{d}'")
        if re.search(r"claude|anthropic", name):
            findings.append(f"{rel(skill)}: name contains a reserved word (claude/anthropic)")
        if not name.split("-")[0].endswith("ing"):
            findings.append(f"{rel(skill)}: name '{name}' must start with a gerund (verb-ing) — harness naming convention")
        if XML_RE.search(name):
            findings.append(f"{rel(skill)}: name contains an XML tag")
        names.add(name)
        # evals: ≥3 scenarios per skill (best practices: "at least three evaluations created")
        ev = os.path.join(root, "evals", f"{d}.json")
        if not os.path.isfile(ev):
            findings.append(f"{rel(skill)}: no evals/{d}.json (≥3 scenarios: query + expected_behavior)")
        else:
            import json
            try:
                data = json.load(open(ev, encoding="utf-8"))
                ok = [x for x in data if isinstance(x, dict) and x.get("query") and isinstance(x.get("expected_behavior"), list) and x["expected_behavior"]] if isinstance(data, list) else []
                if len(ok) < 3:
                    findings.append(f"{rel(ev)}: needs ≥3 scenarios each with query + non-empty expected_behavior (found {len(ok)})")
            except ValueError as e:
                findings.append(f"{rel(ev)}: not valid JSON ({e})")
        check_description(skill, fm.get("description", ""))
        n_body = len(body.splitlines())
        if n_body > 500:
            findings.append(f"{rel(skill)}: body is {n_body} lines (max 500 — move detail to reference/)")
        check_md_common(skill, body)
        # links from SKILL.md must resolve; collect the skill's own reference files
        linked = set()
        for m in LINK_RE.finditer(body):
            target = m.group(1)
            if re.match(r"^[a-z]+://", target) or target.startswith("mailto:"): continue
            p = os.path.normpath(os.path.join(sdir, target))
            if not os.path.exists(p):
                findings.append(f"{rel(skill)}: link '{target}' does not resolve")
            elif p.endswith(".md"):
                linked.add(p)
        # every .md in the skill folder besides SKILL.md is a reference file
        for dp, _dn, fn in os.walk(sdir):
            for f in fn:
                if not f.endswith(".md") or os.path.join(dp, f) == skill: continue
                ref = os.path.join(dp, f)
                rtext = open(ref, encoding="utf-8").read()
                if ref not in linked:
                    findings.append(f"{rel(ref)}: reference file is not linked from its SKILL.md (one level deep, or delete it)")
                if len(rtext.splitlines()) > 100 and not re.search(r"^##\s+Contents\b", rtext, re.M):
                    findings.append(f"{rel(ref)}: over 100 lines — add a '## Contents' list at the top")
                for m in LINK_RE.finditer(rtext):
                    t = m.group(1)
                    if re.match(r"^[a-z]+://", t): continue
                    tp = os.path.normpath(os.path.join(dp, t))
                    if tp.endswith(".md") and tp.startswith(sdir + os.sep) and tp != skill:
                        findings.append(f"{rel(ref)}: links to another reference file '{t}' — keep references one level deep from SKILL.md")
                check_md_common(ref, rtext)

agents_dir = os.path.join(base, "agents")
if os.path.isdir(agents_dir):
    for f in sorted(os.listdir(agents_dir)):
        if not f.endswith(".md"): continue
        p = os.path.join(agents_dir, f)
        fm, body = split_frontmatter(open(p, encoding="utf-8").read())
        if fm is None or not fm.get("name"):
            findings.append(f"{rel(p)}: agent needs frontmatter with name + description"); continue
        check_description(p, fm.get("description", ""))
        check_md_common(p, body)

rules_dir = os.path.join(base, "rules")
if os.path.isdir(rules_dir):
    for f in sorted(os.listdir(rules_dir)):
        if not f.endswith(".md") or f == "README.md": continue
        p = os.path.join(rules_dir, f)
        text = open(p, encoding="utf-8").read()
        fm, body = split_frontmatter(text)
        if fm is None or "paths" not in fm:
            findings.append(f"{rel(p)}: path-scoped rule needs frontmatter with `paths:`")
        check_md_common(p, body)

for w in warnings: print("  warn  " + w)
for f in findings: print("  FAIL  " + f)
print(f"check-skills: {len(names)} skills, {len(findings)} finding(s), {len(warnings)} warning(s)")
sys.exit(1 if findings else 0)
PYEOF
