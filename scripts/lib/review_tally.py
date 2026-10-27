#!/usr/bin/env python3
"""review_tally.py — the one reader of a reviewer's answer, and the vote count of several answers.

Two callers use it:
    scripts/check-the-work.sh  judge   -> parse(): the finding ids, their tags (important / nit / pre-existing)
    scripts/check-the-work.sh  tally   -> tally(): the vote mode, a finding is kept when 2 voters agree on it

WHY ONE FILE: the judge and the vote must read an answer the same way. If the vote counted a finding the judge does not
see (or the other way), a finding could be confirmed by two voters and then never reach a judgement, or the reverse.
Anything that later measures reviewers (a scorer over a reviewer test set) should import parse() and tally() from here
for the same reason.

WHY THE VOTE: across the first 20 judged reviews of the first adopting project about 3 findings in 10 were judged
REJECTED (noise). Independent reviewers of
different model families rarely invent the SAME wrong finding, so a finding that two of them name at the same place
is far more likely real. A finding only one voter names is kept on record as UNCONFIRMED, never dropped silently.

What "the same finding" means here (mechanical on purpose: no model judges the agreement): the same file (one path
may be the tail of the other, e.g. "a/b.go" and "b.go") and line ranges that come within WINDOW lines of each other.
A finding joins a cluster only when its file is the same file as the file of EVERY member (check-the-work F2
2026-10-24: a bare "config.ts" is the tail of both "web/config.ts" and "api/config.ts", and joined the two
into one finding by way of the bare name); the lines need only be near one member. The merged finding names the longest
path of its members;
a finding with a file but no line agrees with any finding on that file. A finding with no file never agrees with
another (it is kept UNCONFIRMED; a goal not met is voted on its own GOAL line instead).

The goal verdict of a vote is MET only when at least 2 voters saw it MET (with one voter, that voter's verdict): a
minority MET must not close the GOAL question the sub-session would otherwise have to answer.

Exit codes (the kit's vocabulary, scripts/lib/common.sh): 0 ok · 2 bad arguments · 3 could not run (an answer file is unreadable).
Python 3 standard library only. Run with `python3 -I`.
"""
import json
import re
import sys

TAGS = ("important", "nit", "pre-existing")
FINDING = re.compile(r"^\s*F(\d+)\b(.*)$")
ALSO_ASKED = re.compile(r"^===== ALSO-ASKED OPINION: ([A-Za-z0-9._-]+)")
SEV = re.compile(r"\[\s*(P[0-3])\s*\]", re.I)
TAG = re.compile(r"\[\s*(important|nit|pre-?existing)\s*\]", re.I)
# A path with an extension ("x.go", "a/b/c.swift", "scripts/x-test.sh"), then an optional ":line" or ":from-to".
LOC = re.compile(r"(?<![\w/.-])((?:[\w.@+-]+/)*[\w@+-][\w.@+-]*\.[A-Za-z0-9]{1,8})(?::(\d+)(?:\s*[-–]\s*(\d+))?)?")


# Extensions a bare "name.ext" (no "/" and no ":line") may have to count as a location. WHY (cross-author finding
# 2026-10-24): "e.g." or "i.e." or "foo.Bar()" in a file-less finding read as a file, so two voters' file-less findings
# "agreed". A name with a "/" or a ":line" is a location already; a bare one must carry a known source/doc extension.
KNOWN_EXT = frozenset("go py sh ts js mjs swift kt kts cs ps1 sql md json jsonl yaml yml toml txt html css c h m java rb rs "
                      "gradle xml plist conf".split())


def _find_loc(text):
    """The first real location in text: a match of LOC with a '/' or a ':line', or else a known extension."""
    for m in LOC.finditer(text):
        if "/" in m.group(1) or m.group(2) or m.group(1).rsplit(".", 1)[1].lower() in KNOWN_EXT:
            return m
    return None


def _own_tag(rest, sev):
    """The tag that belongs to the finding: the bracket group standing DIRECTLY after the severity, or directly before it
    (only blanks between), or, with no severity, the one at the start of the line. WHY not "anywhere in the line"
    (found by a bug hunt): finding text is the reviewer's, and the reviewer quotes the diff; "reads x[nit] out of
    range" or a trailing "[nit]" in the text decided the tag, and a nit needs no judgement. A tag standing elsewhere is
    ignored, so the finding reads 'untagged' and is judged: the safe direction."""
    if sev:
        after = TAG.match(rest, sev.end() + (len(rest[sev.end():]) - len(rest[sev.end():].lstrip())))
        if after:
            return after
        for m in TAG.finditer(rest[:sev.start()]):
            if not rest[m.end():sev.start()].strip():
                return m
        return None
    return TAG.match(rest, len(rest) - len(rest.lstrip()))


def _path(p):
    """'a/x.go', 'b/x.go' (diff prefixes) and './x.go' name the file x.go; 'a/b/c.py' names b/c.py; './a/x.py' names a/x.py.
    WHY ONE prefix at most (check-the-work F3 2026-10-24): the old loop took off "a/" and then "b/" as well, so the real
    path 'a/b/c.py' became 'c.py' and './a/x.py' became 'x.py'; two different files then read as one. ASSUMPTION: a real
    top-level folder that is itself called 'a' or 'b' loses its name too (a diff prefix cannot be told from it)."""
    if p.startswith("./") and len(p) > 2:
        return p[2:]  # "./" marks a plain relative path, so an "a/" after it is a real folder, not a diff prefix
    for pre in ("a/", "b/"):
        if p.startswith(pre) and len(p) > len(pre):
            return p[len(pre):]
    return p


def parse(answer):
    """Every finding line of an answer, in order: id, severity, tag, path, lines, text.
    The id rule is the judge's since 2026-10-18: a line that starts with F<n> is finding F<n> (its first line only);
    after an '===== ALSO-ASKED OPINION: <name>' header the ids get the prefix '<name>:'. A finding without a tag is
    'untagged' (the judge treats it as important: a missing tag must not let a defect skip its judgement)."""
    out, seen, prefix = [], set(), ""
    for line in answer.splitlines():
        h = ALSO_ASKED.match(line)
        if h:
            prefix = h.group(1) + ":"
            continue
        m = FINDING.match(line)
        if not m:
            continue
        fid = prefix + "F" + m.group(1)
        if fid in seen:
            continue
        seen.add(fid)
        rest = m.group(2)
        sev = SEV.search(rest)
        tag = _own_tag(rest, sev)
        # The location is looked for in the line with every bracketed severity/tag blanked out (same length), so "[P1]"
        # can never read as a path and a tag word standing after the location does not hide it (cross-author finding
        # 2026-10-24: "F1 [P1] src/a.go:5 [nit] naming" lost its location). Since then such a late tag is no longer the
        # finding's TAG (see _own_tag); it is only blanked here so the location stays findable.
        # A location after the last bracket still wins (the earlier rule, kept: a file named BEFORE the tags is a preface);
        # only when there is none there is the whole line searched.
        tail = TAG.sub(lambda x: " " * len(x.group(0)), SEV.sub(lambda x: " " * len(x.group(0)), rest))
        loc = _find_loc(rest[max([0] + [x.end() for x in (sev, tag) if x]):]) or _find_loc(tail)
        lo = hi = None
        if loc and loc.group(2):
            lo = int(loc.group(2))
            hi = int(loc.group(3)) if loc.group(3) else lo
            if hi < lo:
                lo, hi = hi, lo
        t = tag.group(1).lower() if tag else "untagged"
        # A P0 or P1 can never be a nit. The judge skips the judging of a nit, so a defect
        # that breaks something must not be able to reach that skip, whatever the line says. (A P0/P1 may still be
        # "pre-existing": that one is judged and routed to the register.)
        if t == "nit" and sev and sev.group(1).upper() in ("P0", "P1"):
            t = "important"
        out.append({
            "id": fid, "sev": sev.group(1).upper() if sev else None,
            "tag": "pre-existing" if t in ("preexisting", "pre-existing") else t,
            "path": _path(loc.group(1)) if loc else None, "lo": lo, "hi": hi, "text": line.strip(),
        })
    return out


def goal_head(answer):
    """MET / NOT MET / CANNOT TELL / '?' from the answer's GOAL: line ('NOT MET' is tested first: it ends in MET)."""
    m = re.search(r"^GOAL:\s*(.+)$", answer, re.M)
    g = (m.group(1).strip().upper() if m else "")
    for head in ("NOT MET", "CANNOT TELL", "MET"):
        # The head must END there (cross-author finding 2026-10-24: "GOAL: METHODS unclear" was read as MET).
        if re.match(re.escape(head) + r"(?:$|[ \-–—:,.])", g):
            return head
    return "?"


def _same_file(a, b):
    return a == b or a.endswith("/" + b) or b.endswith("/" + a)


def _near(f, g, window):
    if f["lo"] is None or g["lo"] is None:
        return True
    return f["lo"] - window <= g["hi"] and g["lo"] - window <= f["hi"]


def _agrees(cluster, f, window):
    # check-the-work F2 2026-10-24: EVERY member must be the same file (not only one), or a bare name joins two
    # different files of the same name through itself; one member near enough on lines is still enough.
    ms = [m for _, m in cluster["members"]]
    return all(_same_file(m["path"], f["path"]) for m in ms) and any(_near(m, f, window) for m in ms)


def _rank(sev):
    return int(sev[1]) if sev else 9


def tally(votes, window=15):
    """votes: [(voter name, answer text)], only answers in the asked shape. Returns (merged answer text, meta dict).
    Greedy clustering in voter order: each finding joins the first cluster it agrees with that has no finding of the
    same voter yet (a voter cannot confirm itself), else starts a new one."""
    clusters = []
    for name, answer in votes:
        for f in parse(answer):
            home = None
            if f["path"]:
                for c in clusters:
                    if name not in c["voters"] and c["members"][0][1]["path"] and _agrees(c, f, window):
                        home = c
                        break
            if home is None:
                home = {"members": [], "voters": []}
                clusters.append(home)
            home["members"].append((name, f))
            home["voters"].append(name)
    n = len(votes)
    quorum = 2 if n >= 2 else 1
    confirmed = [c for c in clusters if len(c["voters"]) >= quorum]
    single = [c for c in clusters if len(c["voters"]) < quorum]
    # The worst severity named wins; the tag is the members' majority, a tie going to the stricter tag (important,
    # then pre-existing, then nit) so a split vote never turns a defect into a nit.
    order = {"important": 0, "untagged": 0, "pre-existing": 1, "nit": 2}
    lines, meta_c = [], []
    for k, c in enumerate(confirmed, 1):
        sev = min((m["sev"] for _, m in c["members"] if m["sev"]), key=_rank, default=None)
        counts = {}
        for _, m in c["members"]:
            t = "important" if m["tag"] == "untagged" else m["tag"]
            counts[t] = counts.get(t, 0) + 1
        tag = sorted(counts, key=lambda t: (-counts[t], order[t]))[0]
        # The LONGEST path among the members names the place (check-the-work F2 2026-10-24: the first member may hold
        # the bare "config.ts" while another voter named "web/config.ts"); that member's lines go with it.
        first = max((m for _, m in c["members"]), key=lambda m: len(m["path"]))
        loc = first["path"] + (":%d" % first["lo"] if first["lo"] is not None else "") + (
            "-%d" % first["hi"] if first["hi"] not in (None, first["lo"]) else "")
        said = " || ".join("%s: %s" % (v, FINDING.sub(r"\2", m["text"]).strip()) for v, m in c["members"])
        lines.append("F%d [%s] [%s] %s — agreed by %s (%d of %d voters) — %s" % (
            k, sev or "P?", tag, loc, ", ".join(c["voters"]), len(c["voters"]), n, said))
        meta_c.append({"id": "F%d" % k, "voters": c["voters"], "from": [v + ":" + m["id"] for v, m in c["members"]]})
    meta_u = []
    for k, c in enumerate(single, 1):
        v, m = c["members"][0]
        meta_u.append({"id": "U%d" % k, "voter": v, "finding": m["id"], "text": m["text"]})
    heads = {name: goal_head(a) for name, a in votes}
    met = sum(1 for h in heads.values() if h == "MET")
    shown = "; ".join("%s=%s" % kv for kv in heads.items())
    if (n >= 2 and met >= 2) or (n == 1 and met == 1):
        goal = "MET — %d of %d voters saw the goal met (%s)" % (met, n, shown)
    elif any(h == "NOT MET" for h in heads.values()):
        goal = "NOT MET — fewer than 2 voters saw the goal met (%s)" % shown
    else:
        goal = "CANNOT TELL — fewer than 2 voters saw the goal met (%s)" % shown
    unseen = []
    for name, a in votes:
        m = re.search(r"^UNSEEN:\s*(.*)$", a, re.M)
        if m and m.group(1).strip():
            unseen.append("%s: %s" % (name, m.group(1).strip()))
    text = ["VERDICT: " + ("FINDINGS" if lines else "PASS"), "GOAL: " + goal] + lines
    if meta_u:
        text.append("UNCONFIRMED (named by one voter only; on record, no judgement needed):")
        text += ["%s (only %s) %s" % (u["id"], u["voter"], u["text"]) for u in meta_u]
    text.append("UNSEEN: " + ("; ".join(unseen) if unseen else "-"))
    text.append("VOTE: %d voter(s) answered (%s); a finding is kept when %d agree; window %d lines" % (
        n, ", ".join(v for v, _ in votes), quorum, window))
    meta = {"voters": [v for v, _ in votes], "quorum": quorum, "window": window, "confirmed": meta_c,
            "unconfirmed": meta_u, "goal_votes": heads}
    return "\n".join(text) + "\n", meta


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError as e:
        print("review_tally: cannot read %s (%s)" % (path, e.__class__.__name__), file=sys.stderr)
        sys.exit(3)


def main(argv):
    """tally [--window N] [--meta FILE] NAME=FILE ...   -> the merged answer on stdout (and the meta JSON in FILE)
    parse FILE                                         -> the findings of one answer as JSON"""
    if len(argv) >= 2 and argv[0] == "parse":
        print(json.dumps(parse(_read(argv[1])), ensure_ascii=False))
        return 0
    if not argv or argv[0] != "tally":
        print(main.__doc__, file=sys.stderr)
        return 2
    window, meta_path, votes, args = 15, None, [], argv[1:]
    while args:
        a = args.pop(0)
        if a == "--window" and args:
            w = args.pop(0)
            if not w.isdigit() or not 0 <= int(w) <= 500:
                print("review_tally: --window must be 0 to 500 lines (got %r)" % w, file=sys.stderr)
                return 2
            window = int(w)
        elif a == "--meta" and args:
            meta_path = args.pop(0)
        elif "=" in a and re.match(r"^[A-Za-z0-9][A-Za-z0-9._-]*=", a):
            name, path = a.split("=", 1)
            votes.append((name, _read(path)))
        else:
            print("review_tally: unknown argument %r" % a, file=sys.stderr)
            return 2
    if not votes:
        print("review_tally: no vote given (NAME=FILE)", file=sys.stderr)
        return 2
    if len({v for v, _ in votes}) != len(votes):
        print("review_tally: a voter name is given twice", file=sys.stderr)
        return 2
    text, meta = tally(votes, window)
    # The meta file is written BEFORE the answer is printed (cross-author finding 2026-10-24: an unwritable path ended in
    # a traceback after the merged answer was already on stdout); a failure prints nothing on stdout.
    if meta_path:
        try:
            with open(meta_path, "w", encoding="utf-8") as f:
                json.dump(meta, f, ensure_ascii=False)
        except OSError as e:
            print("review_tally: cannot write the meta file %s (%s)" % (meta_path, e.__class__.__name__), file=sys.stderr)
            return 3
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
