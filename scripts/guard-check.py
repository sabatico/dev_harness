#!/usr/bin/env python3
"""guard-check.py — the judge behind hook-pretooluse-guard.sh. Reads the PreToolUse payload on stdin,
prints ONE line: a rule id (deny), nothing (no opinion), or ERROR (could not judge → the hook denies).

WHY A PARSER, NOT REGEXES OVER THE STRING (2026-09-30). The first guard matched exact text anchored to
command position. A probe of 14 everyday disguises of commands it existed to stop let ALL 14 through:
split flags (rm -r -f), capital R, a bash -c / eval wrapper, a command/env/sudo prefix, $HOME instead of
~, and whole destructive families it never named (reset --hard, clean -f, branch -D, a +refspec force
push, stash clear, find -delete). The harness-engineering source study (Barbaste et al. 2026, arXiv
2609.00006, §10.7/§10.9) names the fix the strongest permission layers converged on: match on a
DEOBFUSCATED command, not on its spelling. So this file normalises first and judges second:

  1. SPLIT into simple commands on the shell's separators (; & | && || newline backtick paren brace),
     QUOTE-BLIND on purpose — exactly the old anchor's separator set, so nothing the old guard denied
     can pass now. (Quote-aware splitting is a bypass: one apostrophe in a heredoc body, "don't",
     would swallow every later separator into a fake string.)
  2. TOKENISE each piece with shlex (whitespace fallback when the quoting is unbalanced).
  3. STRIP what only wraps the real command: VAR=val, sudo/doas/env/command/exec/nohup/time/nice/
     xargs/timeout and their options, shell keywords (then/do/if …), a leading backslash, a /bin/ path.
  4. UNWRAP what runs a string as code — bash/sh/zsh -c '…' and eval … — and judge the inner text.
  5. JUDGE argv semantically: flags as SETS (-rf == -r -f == -fr == -R -f), git's global options
     skipped (-C dir, -c k=v), targets checked one by one (an excluded temp path no longer excuses a
     protected path in the same command).

Prose stays prose: a commit MESSAGE is one argv token of `git commit`, never judged as a command — the
original false positive this guard was born with (ci/platform-layer.md P2) stays fixed. Heredoc bodies
are still judged line by line, deliberately: an interpreter fed a heredoc runs what is in it.

ALSO GUARDS ITS OWN OFF-SWITCH (the "floor beneath YOLO", same study §10.7): Write/Edit/mv/rm/sed -i/
redirect onto the hook wiring, the hook scripts or harness.conf is denied unless the OWNER launched the
session with HARNESS_ALLOW_CONTROL_EDITS=1. That flag is read by the hook from its LAUNCH environment
(argv[2] here), before harness.conf is sourced — nothing the agent writes mid-session can turn it on.

SECOND ROUND (same day, from the cross-author test matrix's invent-nastier pass — all reproduced before
fixing): a quoted argument holding a separator (`"x;y"`) broke tokenising and hid the target; `..` climbed
out of an excluded folder (`~/build/..`); `RM` runs rm on a case-insensitive filesystem; `${HOME}` was cut
by a brace separator; `~user`; system folders below the top level; unknown wrappers (caffeinate, setsid,
watch, `env -S`, `bash -c --`); here-strings and `echo … | bash`; git switch/mirror/delete-of-main and
infra spellings (`pulumi -C`, `run-all destroy`, `-destroy=true`); and the control floor was steppable by
copying INTO a folder, by case (`Harness.conf`), by symlink, by rsync/ditto, by `>|`. So now:
  · TWO passes, and a command found by EITHER is judged: the quote-blind split (strict, as before) AND a
    quote-aware shlex pass that also yields redirects, here-strings and pipe-into-shell. If the
    quote-aware pass cannot parse (unbalanced quotes), the quote-blind pass still runs — never weaker.
  · targets are NORMALISED ($HOME/${HOME}/~/~user expanded, relative paths joined to the payload's cwd,
    `..` folded) before they are judged; a relative path that stays INSIDE the repo is the repo's own
    business (as before), one that escapes it is judged like any absolute path.
  · command names and control paths compare case-insensitively; control paths also through symlinks.

NOT COVERED (and said so in CLAUDE.md's enforced/unenforced table): a write performed by an interpreter
(python -c, node -e, awk/sed scripts that write files, a script file), a command or target held in a
variable or a git alias, a remote shell, alternating calls. Known-answer matrix:
scripts/hook-pretooluse-guard-test.sh — run it after ANY edit here.
"""
import fnmatch
import json
import os
import re
import shlex
import sys

# Real paths: `..` is resolved by the kernel PHYSICALLY, so a symlinked cwd must be judged by where it
# really is (a symlink to the repo, then ../<repo>, deletes the real repo).
ROOT = os.path.realpath(sys.argv[1] if len(sys.argv) > 1 else os.getcwd())
ALLOW_CONTROL = (sys.argv[2] if len(sys.argv) > 2 else "") == "1"
EXTRA_CONTROL = (sys.argv[3] if len(sys.argv) > 3 else "").split()
BASE_BRANCH = (sys.argv[4] if len(sys.argv) > 4 else "").split("/")[-1]
PROTECTED_BRANCHES = {"main", "master"} | ({BASE_BRANCH} if BASE_BRANCH else set())
HOMEDIR = os.path.expanduser("~")
CWD = ROOT  # replaced by the payload's (real) cwd in main()

# The enforcement machinery itself. A pattern with a slash matches the repo-relative path; the
# settings patterns also match ANY .claude/settings*.json, including the user-level one in ~/.claude
# (disableAllHooks there switches off every hook in every project). Compared case-insensitively: on a
# case-insensitive filesystem Harness.conf IS harness.conf.
CONTROL = [g.lower() for g in [".claude/settings.json", ".claude/settings.local.json", "harness.conf",
           "scripts/hook-*.sh", "scripts/guard-check.py", "scripts/claim-check.py",
           "scripts/verify-check.py"] + EXTRA_CONTROL]
SETTINGS_ANYWHERE = re.compile(r"(^|/)\.claude/settings[^/]*\.json$", re.I)

# Quote-blind separators. NOT braces: `${HOME}` and `stash@{0}` must stay whole; `{`/`}` as a group
# keyword is stripped as a wrapper instead.
SEP = re.compile(r"\|\||&&|[;&|`\n()]")
OPS = set(";&|()<>\n")
WRAPPERS = {"sudo", "doas", "command", "builtin", "exec", "nohup", "time", "nice", "env", "xargs",
            "stdbuf", "timeout", "caffeinate", "setsid", "watch", "ionice", "flock", "unbuffer", "chronic",
            "then", "do", "else", "elif", "if", "while", "until", "!", "{", "}"}
# Wrapper options that consume the NEXT token as their value.
WRAPPER_ARGOPTS = {
    "sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U"}, "doas": {"-u", "-C"},
    "env": {"-u", "-C"}, "nice": {"-n"}, "stdbuf": {"-i", "-o", "-e"},
    "xargs": {"-I", "-n", "-P", "-L", "-s", "-d", "-E", "-a"}, "timeout": {"-s", "-k"},
    "caffeinate": {"-t", "-w"}, "watch": {"-n", "-d"}, "ionice": {"-c", "-n", "-p"}, "flock": {"-w", "-E"},
}
WRAPPER_POSITIONALS = {"timeout": 1, "flock": 1}  # the duration; the lock file
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish"}


def unquote(t):
    return t[1:-1] if len(t) >= 2 and t[0] == t[-1] and t[0] in "'\"" else t


def tokens(seg):
    try:
        return shlex.split(seg, comments=False, posix=True)
    except ValueError:  # unbalanced quotes: whitespace split, but never leave the quotes ON the target
        return [unquote(t.strip("\"'") if t.count('"') + t.count("'") == 1 else t) for t in seg.split()]


def short_flags(args):
    """-rf -R → {'r','f','R'}; long options are returned separately by long_flags()."""
    s = set()
    for a in args:
        if re.fullmatch(r"-[A-Za-z]+", a):
            s.update(a[1:])
    return s


def long_flags(args):
    return {a.split("=", 1)[0] for a in args if a.startswith("--")}


def strip_prefix(argv):
    """→ (argv without wrappers, [command strings a wrapper will run — env -S])."""
    argv, inner = list(argv), []
    while argv:
        a = argv[0]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", a):
            argv.pop(0)
            continue
        base = os.path.basename(a.lstrip("\\")).lower()
        if base not in WRAPPERS:
            break
        argv.pop(0)
        while argv and argv[0].startswith("-") and argv[0] != "--":
            opt = argv.pop(0)
            if base == "env" and opt in ("-S", "--split-string") and argv:
                inner.append(argv.pop(0))
            elif base == "env" and opt.startswith("--split-string="):
                inner.append(opt.split("=", 1)[1])
            elif base == "env" and opt.startswith("-S") and len(opt) > 2:
                inner.append(opt[2:])
            elif opt in WRAPPER_ARGOPTS.get(base, ()) and argv:
                argv.pop(0)
        if argv and argv[0] == "--":
            argv.pop(0)
        for _ in range(WRAPPER_POSITIONALS.get(base, 0)):
            if argv:
                argv.pop(0)
    if argv:
        argv[0] = os.path.basename(argv[0].lstrip("\\")).lower()
    return argv, inner


# ── targets ───────────────────────────────────────────────────────────────────────────────────
EXCLUDED = re.compile(r"(node_modules|(^|/)tmp(/|$)|/private/tmp|/var/folders/|scratchpad|"
                      r"(^|/)(target|dist|build|\.next|\.cache|coverage|__pycache__)(/|$))")
SYSTEM = ("/usr", "/system", "/etc", "/bin", "/sbin", "/library", "/applications", "/opt", "/var",
          "/private", "/volumes", "/cores", "/dev", "/boot", "/lib", "/lib64", "/root", "/srv", "/snap")


def expand(t):
    t = unquote(t.strip())
    t = re.sub(r"^(\$HOME|\$\{HOME\})(?=/|$)", lambda m: HOMEDIR, t)
    if t.startswith("~"):
        t = os.path.expanduser(t)
    return t


def under(p, d):
    return p == d or p.startswith(d.rstrip("/") + "/")


def protected_target(raw):
    t = unquote(raw.strip())
    if t in ("/", "/*", "~", "$HOME", "${HOME}", "*", ".*", ".", "./", "./*", "..", "../"):
        return True
    e = expand(t)
    relative = not e.startswith("/")
    p = os.path.normpath(os.path.join(CWD, e))
    if re.search(r"(^|/)\.git(/|$)", p):
        return True
    if under(ROOT, p):            # the repo root itself, or a folder that contains it
        return True
    if relative and under(p, ROOT):
        return False              # stays inside the repo: the repo's own business, as before
    low = p.lower()
    if p == "/" or (re.fullmatch(r"/[^/]+", p) and low != "/tmp"):
        return True
    if any(under(low, s) for s in SYSTEM):
        return not EXCLUDED.search(low)
    if under(HOMEDIR, p) or re.fullmatch(r"/(Users|home)/[^/]+", p):
        return True
    if under(p, HOMEDIR) or re.match(r"^/(Users|home)/[^/]+/", p):
        return not EXCLUDED.search(p)
    return False


def is_control(path):
    if not path:
        return False
    e = expand(path)
    ap = os.path.normpath(os.path.join(CWD, e))
    for cand in {ap, os.path.realpath(ap)}:
        if SETTINGS_ANYWHERE.search(cand):
            return True
        for root in {ROOT, os.path.realpath(ROOT)}:
            rel = os.path.relpath(cand, root)
            if not rel.startswith("..") and any(fnmatch.fnmatch(rel.lower(), g) for g in CONTROL):
                return True
    return False


# ── the judge ─────────────────────────────────────────────────────────────────────────────────
DEST_WRITERS = {"cp", "install", "rsync", "ditto", "scp"}   # only the destination is written
WRITERS = DEST_WRITERS | {"rm", "mv", "ln", "tee", "truncate", "chmod", "chown", "unlink", "dd", "sed",
                          "perl", "awk", "gawk"}


def dest_candidates(ops):
    """cp/mv INTO a folder writes <folder>/<basename of each source>."""
    if not ops:
        return []
    dest, srcs = ops[-1], ops[:-1]
    cands = [dest]
    d = os.path.join(CWD, expand(dest))
    if dest.endswith("/") or os.path.isdir(d):
        cands += [os.path.join(dest, os.path.basename(unquote(s).rstrip("/"))) for s in srcs]
    return cands


def judge_control(argv):
    if ALLOW_CONTROL or not argv:
        return None
    cmd, args = argv[0], argv[1:]
    ops = [a for a in args if not a.startswith("-")]
    if cmd == "git" and args[:1] and args[0] in ("rm", "mv", "checkout", "restore"):
        if args[0] == "rm" and "--cached" in args:
            return None   # touches the staging area only
        ops = [a for a in args[1:] if not a.startswith("-")]
        if args[0] == "mv":
            ops = ops + dest_candidates(ops)
    elif cmd not in WRITERS:
        return None
    if cmd == "sed" and not ({"i"} & short_flags(args) or "--in-place" in long_flags(args)
                             or any(a.startswith("-i") for a in args)):
        return None
    if cmd == "perl" and not any(re.fullmatch(r"-\w*i\S*", a) for a in args):
        return None
    if cmd in ("awk", "gawk") and not ("inplace" in args or "--inplace" in args):
        return None
    if cmd in DEST_WRITERS:
        ops = dest_candidates(ops)
    if cmd == "mv":
        ops = ops + dest_candidates(ops)
    if cmd == "dd":
        ops = [a[3:] for a in args if a.startswith("of=")]
    return "control-edit" if any(is_control(o) for o in ops) else None


def infra(cmd, args):
    if cmd in ("terraform", "tofu", "terragrunt", "pulumi"):
        pos = [a for a in args if not a.startswith("-")]
        if "destroy" in pos or (cmd == "pulumi" and "down" in pos):
            return "infra-destroy"
        if "apply" in pos and any(re.fullmatch(r"--?destroy(=(true|1))?", a) for a in args):
            return "infra-destroy"
    return None


def judge(argv):
    if not argv:
        return None
    cmd, args = argv[0], argv[1:]
    sf, lf = short_flags(args), long_flags(args)

    if cmd == "rm" and ({"r", "R"} & sf or "--recursive" in lf):
        after_ddash = False
        for a in args:
            if a == "--":
                after_ddash = True
                continue
            if (after_ddash or not a.startswith("-")) and protected_target(a):
                return "rm-recursive"

    if cmd == "find" and ("-delete" in args or any(
            a in ("-exec", "-execdir", "-ok") and i + 1 < len(args) and os.path.basename(args[i + 1]).lower() == "rm"
            for i, a in enumerate(args))):
        paths = []
        for a in args:
            if a.startswith("-") or a in ("(", "!", "\\("):
                break
            paths.append(a)
        # A name/path filter makes it targeted cleanup (find . -name '*.pyc' -delete); unfiltered over a
        # protected root, or over the cwd, it is rm -r by another spelling.
        filtered = any(a in ("-name", "-iname", "-path", "-ipath", "-regex", "-iregex", "-wholename") for a in args)
        if not filtered and any(protected_target(p) for p in (paths or ["."])):
            return "find-delete"

    rule = infra(cmd, args)
    if rule:
        return rule

    if cmd == "git":
        i = 0
        while i < len(args) and args[i].startswith("-"):
            i += 2 if args[i] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace") else 1
        if i >= len(args):
            return None
        sub, rest = args[i].lower(), args[i + 1:]
        rsf, rlf = short_flags(rest), long_flags(rest)
        ops = [a for a in rest if not a.startswith("-")]
        if sub == "push":
            if ({"f"} & rsf or rlf & {"--force", "--force-with-lease", "--force-if-includes", "--mirror"}
                    or any(o.startswith("+") for o in ops)):
                return "force-push"
            deleting = {"d"} & rsf or "--delete" in rlf
            refs = ops[1:] if len(ops) > 1 else []
            if any(re.sub(r"^refs/heads/", "", r.lstrip(":")) in PROTECTED_BRANCHES for r in refs
                   if deleting or r.startswith(":")):
                return "push-delete"
        if sub == "add" and ({"A"} & rsf or "--all" in rlf or any(o in (".", "./", ":/", ":") for o in ops)):
            return "broad-add"
        if sub == "checkout" and (("--" in rest and rest.index("--") < len(rest) - 1)
                                  or "." in ops or {"f"} & rsf or "--force" in rlf):
            return "checkout-discard"
        if sub == "switch" and ({"f"} & rsf or rlf & {"--force", "--discard-changes"}):
            return "checkout-discard"
        if sub == "restore" and not (({"S"} & rsf or "--staged" in rlf) and not ({"W"} & rsf or "--worktree" in rlf)):
            return "checkout-discard"
        if sub == "reset" and "--hard" in rlf:
            return "reset-hard"
        if sub == "clean" and ({"f"} & rsf or "--force" in rlf) and not ({"n"} & rsf or "--dry-run" in rlf):
            return "git-clean"
        if sub == "branch" and ({"D"} & rsf or (({"d"} & rsf or "--delete" in rlf) and ({"f"} & rsf or "--force" in rlf))):
            return "branch-force-delete"
        if sub == "stash" and ops[:1] == ["clear"]:
            return "stash-clear"
    return None


def judge_argv(argv, depth):
    """Judge one simple command, then anything it runs as a string (bash -c, eval, env -S)."""
    argv, inner = strip_prefix(argv)
    rule = judge(argv) or judge_control(argv)
    if rule:
        return rule
    if argv and argv[0] in SHELLS:
        for j, a in enumerate(argv[1:], 1):
            if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", a):
                rest = argv[j + 1:]
                if rest[:1] == ["--"]:
                    rest = rest[1:]
                inner += rest[:1]
                break
    elif argv and argv[0] == "eval":
        inner.append(" ".join(argv[1:]))
    for text in inner:
        rule = scan(text, depth + 1)
        if rule:
            return rule
    return None


def quote_aware(text):
    """→ [(argv, sep_before, redirect_targets, herestrings)] or None when the quoting is unbalanced."""
    lex = shlex.shlex(text, posix=True, punctuation_chars=";&|()<>\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    try:
        toks = list(lex)
    except ValueError:
        return None
    cmds, cur, redirs, here, sep, i = [], [], [], [], "", 0
    while i < len(toks):
        t = toks[i]
        if t and set(t) <= OPS and not set(t) <= set("<>"):
            if ">" in t and i + 1 < len(toks):   # >| and &> arrive glued to their separator chars
                redirs.append(toks[i + 1]); i += 1
            cmds.append((cur, sep, redirs, here)); cur, redirs, here, sep = [], [], [], t
        elif t and set(t) <= set("<>|&") and ">" in t:
            if i + 1 < len(toks):
                redirs.append(toks[i + 1]); i += 1
        elif t == "<<<":
            if i + 1 < len(toks):
                here.append(toks[i + 1]); i += 1
        elif t and set(t) <= set("<"):
            i += 1  # an input redirect / heredoc marker and its operand: not a write
        else:
            cur.append(t)
        i += 1
    cmds.append((cur, sep, redirs, here))
    return cmds


def scan(text, depth=0):
    if depth > 4 or not text:
        return None
    # Pass 1 — quote-blind: strict, exactly the old anchor's separator set.
    for seg in SEP.split(text):
        if seg.strip():
            rule = judge_argv(tokens(seg), depth)
            if rule:
                return rule
    # Pass 2 — quote-aware: real argument boundaries, redirects, here-strings, pipe-into-shell.
    cmds = quote_aware(text)
    if cmds is None:
        if not ALLOW_CONTROL and any(is_control(m.group(1)) for m in
                                     re.finditer(r">{1,2}\|?\s*([^\s;&|<>]+)", text)):
            return "control-edit"
        return None
    prev = []
    for argv, sep, redirs, here in cmds:
        if not ALLOW_CONTROL and any(is_control(r) for r in redirs):
            return "control-edit"
        rule = judge_argv(argv, depth)
        if rule:
            return rule
        for h in here:
            rule = scan(h, depth + 1)
            if rule:
                return rule
        stripped, _ = strip_prefix(argv)
        if sep == "|" and stripped and stripped[0] in SHELLS and not [a for a in stripped[1:] if not a.startswith("-")]:
            p, _ = strip_prefix(prev)
            if p and p[0] in ("echo", "printf"):
                rule = scan(" ".join(p[1:]), depth + 1)
                if rule:
                    return rule
        prev = argv
    return None


def main():
    global CWD
    d = json.load(sys.stdin)
    if isinstance(d.get("cwd"), str) and os.path.isabs(d["cwd"]):
        CWD = os.path.realpath(d["cwd"])
    tool = d.get("tool_name", "")
    ti = d.get("tool_input") or {}
    if tool == "Bash":
        return scan(ti.get("command", "") or "")
    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        fp = ti.get("file_path") or ti.get("notebook_path") or ""
        if not ALLOW_CONTROL and is_control(fp):
            return "control-edit"
    return None


if __name__ == "__main__":
    try:
        print(main() or "")
    except Exception:  # never a silent allow: the hook turns ERROR into a fail-closed deny
        print("ERROR")
