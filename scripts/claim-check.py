#!/usr/bin/env python3
"""claim-check.py — verify the CHECKABLE claims in the assistant's last reply (Stop hook).

Generalised 2026-09-29 from a live project (its CLAUDE.md the recall-is-not-a-source rule: "recall is not a source").
Config comes from harness.conf via hook-stop-claimcheck.sh: HARNESS_DECISION_DIR/PREFIX, HARNESS_BUG_REGISTER
(+ HARNESS_BUG_PREFIX, default BUG), HARNESS_CORPUS_DIRS + HARNESS_DOC_DIRS, HARNESS_SIBLING_REPOS,
HARNESS_LOG_DIR, HARNESS_CLAIMCHECK_MODE=advise|block, HARNESS_ROOT_OVERRIDE (tests).


WHY (harness-review-2026-08-24 §11, owner 2026-09-29: "even opus level main agent misses things a lot
and hallucinates 'from memory' instead of every time researching"). Every existing control fires on a
FILE: check-doc-links caught 5 of 5 invented filenames in docs (harness-review §4), while the prose rule
caught 0 of 5. But answers-from-memory land in CHAT, where nothing looked. the recall-is-not-a-source rule names four shapes that
always get a lookup — path, quantity, ruling, result. Three have a mechanically checkable form:

  PATH    a markdown link [x](path) or a backticked `file.ext:line` asserts the file (and the line)
          exists. Resolved exactly (repo root, cwd) and then by SUFFIX against
          every file in the repo and HARNESS_SIBLING_REPOS — chat routinely says `handlers.go:120`
          or `cmd/x/main.go` without the full path, and that is a true claim. Bare backticked paths
          with no line are NOT checked: "create `scripts/new.sh`" names a file that does not exist yet.
  ID      ADR-NNN / BUG-NNN at or below the highest number that exists, appearing NOWHERE in the corpus.
          Above the max is a proposal ("ADR-118 will…"); a historic id mentioned anywhere passes.
  QUOTE   text presented as a quotation (a > blockquote, or "…"/“…” of 6+ words with clean
          boundaries) in a paragraph that cites a repo file or ADR must have been SEEN: present in a
          cited file, anywhere in the corpus, or in a tool result / user message of THIS session.
          That is the recall-is-not-a-source rule's own test — recall is not a source. A quote that exists nowhere the agent
          could have read it was produced from memory, whatever it is attributed to. Last resort
          before a flag: the word sequence is searched across the whole repo, code comments included.

DESIGN RULE — SILENT UNLESS DEFINITELY FALSE (the hook-stop-statecheck.sh principle: a false flag
teaches everyone to ignore you). Calibrated 2026-09-29 against 673 real assistant turns from the 20
most recent sessions: the first version (quotes checked against the cited file only; paths resolved
exactly) raised 50 flags, nearly all false — the owner's own words in quotes, text quoted from tool
output, a quote from a different file than the one linked, quote marks paired across code spans,
bare filenames, an IP:port read as a file. Each is now a PASS row in the test matrix.

MODES: advise (default) → a systemMessage the owner sees + a log line. block → a Stop "decision:block"
that makes the model correct itself before finishing (once: never when stop_hook_active). Every run
logs to .harness-logs/claim-check.log — checked counts too, so the two-week review has a hit RATE, not
anecdotes. Any internal error is LOGGED, never raised: a Stop hook must not break a turn, and a hook
that fails silently is the failure this review found twice.

Usage: hook-stop-claimcheck.sh pipes the Stop payload here. Test: scripts/hook-stop-claimcheck-test.sh.
Env: see the config list at the top of this docstring (all set from harness.conf by the wrapper).
"""
import glob
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
def _git_root():
    try:
        return subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                              timeout=5, cwd=HERE).stdout.strip()
    except Exception:
        return ""
ROOT = os.environ.get("HARNESS_ROOT_OVERRIDE") or _git_root() or os.path.dirname(HERE)
PROJ = ROOT
E = os.environ.get
LOGDIR = os.path.join(ROOT, E("HARNESS_LOG_DIR") or ".harness-logs")
MODE = E("HARNESS_CLAIMCHECK_MODE", "advise")
DEC_DIR = os.path.join(ROOT, E("HARNESS_DECISION_DIR") or "docs/decisions")
DEC_PREFIX = E("HARNESS_DECISION_PREFIX") or "ADR"
BUG_PREFIX = E("HARNESS_BUG_PREFIX") or "BUG"
CORPUS_DIRS = [os.path.join(ROOT, d) for d in dict.fromkeys(((E("HARNESS_CORPUS_DIRS") or "docs") + " " + (E("HARNESS_DOC_DIRS") or "")).split())]
# HARNESS_SIBLING_REPOS is relative to the repo root's PARENT (harness.conf.example), like librarian-sweep.sh.
SIBLINGS = [p if os.path.isabs(p) else os.path.join(os.path.dirname(ROOT), p) for p in (E("HARNESS_SIBLING_REPOS") or "").split()]
MIN_QUOTE_WORDS = 6
MIN_FRAGMENT_WORDS = 5
SKIP_DIRS = {".git", "node_modules", "target", "dist", ".harness-logs", ".gate-logs", "build", ".next"}


# ── the transcript: the last reply, and everything the agent could have SEEN ─────────────────
def _is_user_prompt(d):
    if d.get("type") != "user" or d.get("isSidechain") or d.get("isMeta"):
        return False
    c = (d.get("message") or {}).get("content")
    if isinstance(c, str):
        return True
    if isinstance(c, list):
        kinds = {b.get("type") for b in c if isinstance(b, dict)}
        return "tool_result" not in kinds and "text" in kinds
    return False


def _flatten(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(_flatten(b.get("content") if b.get("type") == "tool_result" else b.get("text", ""))
                         for b in c if isinstance(b, dict))
    return ""


def read_transcript(payload):
    """→ (last reply text, everything user- or tool-supplied this session)."""
    tp = payload.get("transcript_path") or ""
    entries = []
    for attempt in range(2):  # the final entry can land a beat after Stop fires
        entries = []
        if os.path.isfile(tp):
            with open(tp, encoding="utf-8", errors="replace") as f:
                for line in f:
                    try:
                        entries.append(json.loads(line))
                    except ValueError:
                        pass
        if entries and entries[-1].get("type") == "assistant" or attempt:
            break
        time.sleep(0.4)
    seen, texts = [], []
    for d in entries:
        if d.get("type") == "user":
            seen.append(_flatten((d.get("message") or {}).get("content")))
            if isinstance(d.get("toolUseResult"), (dict, str)):
                seen.append(json.dumps(d["toolUseResult"]) if isinstance(d["toolUseResult"], dict) else d["toolUseResult"])
    for d in reversed(entries):
        if _is_user_prompt(d):
            break
        if d.get("type") == "assistant" and not d.get("isSidechain"):
            for b in reversed((d.get("message") or {}).get("content") or []):
                if isinstance(b, dict) and b.get("type") == "text":
                    texts.append(b.get("text", ""))
    reply = "\n\n".join(reversed(texts))
    if isinstance(payload.get("last_assistant_message"), str):
        reply = payload["last_assistant_message"]
    return reply, "\n".join(seen)


# ── helpers ───────────────────────────────────────────────────────────────────────────────────
def strip_fences(text):
    # Fenced code is commands and proposals, not claims: blank it but keep paragraph structure.
    return re.sub(r"```.*?```", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)


_file_index = []


def file_index():
    """Every file in the repo + sibling repos, as absolute paths (built once, lazily)."""
    if _file_index:
        return _file_index
    roots = [ROOT] + [s for s in SIBLINGS if os.path.isdir(s)]
    for r in roots:
        listed = None
        if os.path.isdir(os.path.join(r, ".git")):
            try:
                out = subprocess.run(["git", "-C", r, "ls-files", "-co", "--exclude-standard"],
                                     capture_output=True, text=True, timeout=10).stdout
                listed = [os.path.join(r, p) for p in out.splitlines() if p]
            except Exception:
                listed = None
        if listed is None:
            listed = []
            for dp, dns, fns in os.walk(r):
                dns[:] = [d for d in dns if d not in SKIP_DIRS]
                listed += [os.path.join(dp, fn) for fn in fns]
        _file_index.extend(listed)
    return _file_index


def resolve(target):
    """→ (list of matching files, line or None, shown). Empty list = exists nowhere."""
    t = target.split("#", 1)[0]
    try:
        from urllib.parse import unquote
        t = unquote(t)
    except Exception:
        pass
    line = None
    m = re.match(r"^(.*?):(\d+)(?:-\d+)?$", t)
    if m:
        t, line = m.group(1), int(m.group(2))
    t = t.rstrip("/")
    if not t:
        return [], None, t
    if os.path.isabs(t):
        return ([t] if os.path.exists(t) else []), line, t
    for c in (os.path.join(ROOT, t), os.path.join(os.getcwd(), t)):
        if os.path.exists(c):
            return [c], line, t
    suffix = "/" + t.lstrip("./")
    hits = [p for p in file_index() if p.endswith(suffix)]
    if not hits:  # a directory named by suffix
        hits = [os.path.dirname(p) for p in file_index() if (os.path.dirname(p) + "/").endswith(suffix + "/")][:1]
    return hits, line, t


def count_lines(p):
    try:
        with open(p, "rb") as f:
            return sum(1 for _ in f)
    except OSError:
        return None


def norm(s):
    s = s.replace("“", '"').replace("”", '"').replace("‘", "'").replace("’", "'")
    s = s.replace("—", "-").replace("–", "-")
    s = re.sub(r"[*_`]", "", s)
    s = re.sub(r"\\(.)", r"\1", s)            # JSON/markdown escapes in tool output
    s = re.sub(r"\s+", " ", s).strip().lower()
    return s.strip(" .,;:!?\"'()[]")


_corpus_cache = {}


def corpus_text():
    if "all" not in _corpus_cache:
        chunks = []
        for base in CORPUS_DIRS:
            for dp, dns, fns in os.walk(base):
                dns[:] = [d for d in dns if d not in SKIP_DIRS]
                for fn in fns:
                    if fn.endswith(".md"):
                        try:
                            with open(os.path.join(dp, fn), encoding="utf-8", errors="replace") as f:
                                chunks.append(f.read())
                        except OSError:
                            pass
        for extra in [os.path.join(ROOT, "CLAUDE.md"), os.path.join(ROOT, "CONVENTIONS.md")] + (
                [os.path.join(ROOT, E("HARNESS_ONBOARDING"))] if E("HARNESS_ONBOARDING") else []):
            if os.path.isfile(extra):
                with open(extra, encoding="utf-8", errors="replace") as f:
                    chunks.append(f.read())
        _corpus_cache["all"] = "\n".join(chunks)
        _corpus_cache["norm"] = norm(_corpus_cache["all"])
    return _corpus_cache["all"]


def repo_contains(fragment):
    """Last resort before a quote flag: does the fragment's WORD SEQUENCE appear anywhere in the repo
    or its siblings — code comments included? (Calibration: `WithKeyring` says "active MUST be in the
    ring" is a true quote of a Go comment; docs-only search flagged it.) Punctuation/markup-tolerant."""
    words = re.findall(r"[A-Za-z0-9]+", fragment)
    if len(words) < MIN_FRAGMENT_WORDS:
        return True
    pat = "[^[:alnum:]]+".join(words)
    roots = [ROOT] + [s for s in SIBLINGS if os.path.isdir(s)]
    for r in roots:
        if os.path.isdir(os.path.join(r, ".git")):
            try:
                rc = subprocess.run(["git", "-C", r, "grep", "-q", "-i", "-E", "--untracked", "-e", pat],
                                    capture_output=True, timeout=10).returncode
                if rc == 0:
                    return True
                continue
            except Exception:
                return True  # cannot look ⇒ cannot say "definitely false"
        rx = re.compile(r"[^A-Za-z0-9]+".join(words), re.I)
        for fp in file_index():
            if fp.startswith(r):
                try:
                    with open(fp, encoding="utf-8", errors="ignore") as f:
                        if rx.search(f.read()):
                            return True
                except OSError:
                    pass
    return False


def adr_files():
    d = DEC_DIR
    out = {}
    if os.path.isdir(d):
        for fn in os.listdir(d):
            m = re.match(r"%s-(\d+)" % re.escape(DEC_PREFIX), fn)
            if m:
                out.setdefault(int(m.group(1)), os.path.join(d, fn))
    return out


def id_mentioned(prefix, n):
    return re.search(r"\b%s-0*%d(?![0-9])" % (prefix, n), corpus_text()) is not None


def max_bug():
    ids = [int(x) for x in re.findall(r"\b%s-(\d+)" % re.escape(BUG_PREFIX), corpus_text())]
    return max(ids) if ids else 0


# ── the checks ────────────────────────────────────────────────────────────────────────────────
LINK_RE = re.compile(r"\[[^\]\n]*\]\(([^)\s]+)\)")
# The extension must start with a letter: `192.168.65.1:5432` is an address, not a file.
TICK_LINE_RE = re.compile(r"`([^`\s]+\.[A-Za-z][A-Za-z0-9]*):(\d+)(?:-\d+)?`")
TICK_PATH_RE = re.compile(r"`([^`\s]+\.[A-Za-z][A-Za-z0-9]*)(?::\d+(?:-\d+)?)?`")
ID_RE = re.compile(r"\b(%s|%s)-(\d{1,4})(?![0-9])" % (re.escape(DEC_PREFIX), re.escape(BUG_PREFIX)))
URL_RE = re.compile(r"https?://")
# A quotation needs clean boundaries — an opening mark after start/space/bracket/dash/colon, a closing
# mark before space/punctuation/end — and no code span or bold marker inside. Without that, prose like
# the `"login"`-purpose … the "security" pairs the WRONG marks and invents a "quote".
# ATTRIBUTED only (second calibration, same day): in chat, quote marks do many jobs — proposed UI copy
# ("I've told this person / you may contact them"), the owner's words from OTHER sessions (with his
# typos), emphasis. 19 of 32 checked quotes flagged, none a verbatim claim. The one form that
# unambiguously asserts verbatim text is a quotation ATTRIBUTED to a repo source on the same line:
# a citation, at most a few words, then a verb or colon, then the quote — `ADR-051 says "…"`,
# `[doc](path): "…"`, `§4 reads "…"`. That is the the recall-is-not-a-source rule "what a ruling says" shape exactly.
ATTRIB_TAIL = re.compile(
    r"(?:\]\([^)\s]+\)|\b" + re.escape(DEC_PREFIX) + r"-\d+(?:\s*\u00a7\s?[\d.]+[a-z]?)?|\u00a7\s?[\d.]+[a-z]?|`[^`\n]+`)"
    r"[^\"\u201c\n]{0,30}?(?:\bsays?|\bsaid|\breads?|\bstates?|\brules?|\bruled|\bputs it|\bverbatim|\bquotes?|:)"
    r"\s*[*_]*$", re.I)
QUOTE_RES = [
    re.compile(r'(?:^|(?<=[\s(\[—:]))"([^"`\n]{20,}?)"(?=[\s.,;:!?)\]—]|$)', re.M),
    re.compile(r"(?:^|(?<=[\s(\[—:]))“([^”`\n]{20,}?)”(?=[\s.,;:!?)\]—]|$)", re.M),
]


def check(text, seen="", seen_normed=None):
    flags, stats = [], {"links": 0, "lines": 0, "ids": 0, "quotes": 0}
    body = strip_fences(text)
    adrs = adr_files()
    adr_max = max(adrs) if adrs else 0
    seen_norm = seen_normed if seen_normed is not None else (norm(seen) if seen else "")

    def path_claim(target, kind):
        if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target) or target.startswith("#"):
            return  # URL / mailto / in-page anchor
        stats["links"] += 1
        hits, line, shown = resolve(target)
        if not hits:
            flags.append("%s does not exist anywhere in the repo: %s" % (kind, shown))
        elif line is not None:
            files = [h for h in hits if os.path.isfile(h)]
            if files:
                stats["lines"] += 1
                longest = max((count_lines(h) or 0) for h in files)
                if line > longest:
                    flags.append("line %d is past the end of %s (%d lines)" % (line, shown, longest))

    for m in LINK_RE.finditer(body):
        path_claim(m.group(1), "linked file")
    for m in TICK_LINE_RE.finditer(body):
        path_claim("%s:%s" % (m.group(1), m.group(2)), "file:line reference")

    seen_ids = set()
    for m in ID_RE.finditer(body):
        prefix, n = m.group(1), int(m.group(2))
        if (prefix, n) in seen_ids:
            continue
        seen_ids.add((prefix, n))
        stats["ids"] += 1
        if prefix == DEC_PREFIX:
            if n <= adr_max and n not in adrs and not id_mentioned(DEC_PREFIX, n):
                flags.append("%s-%03d does not exist and is mentioned nowhere in the corpus" % (DEC_PREFIX, n))
        elif n <= max_bug() and not id_mentioned(BUG_PREFIX, n):
            flags.append("%s-%03d is not in the bug register or anywhere in the corpus" % (BUG_PREFIX, n))

    # Quotes: only in a paragraph that cites repo files (or right under one), never next to a web source.
    prev_refs = []
    for para in re.split(r"\n\s*\n", body):
        refs = []
        for m in LINK_RE.finditer(para):
            hits, _, _ = resolve(m.group(1))
            refs += [h for h in hits if os.path.isfile(h)][:1]
        for m in TICK_PATH_RE.finditer(para):
            hits, _, _ = resolve(m.group(1))
            refs += [h for h in hits if os.path.isfile(h)][:1]
        for m in ID_RE.finditer(para):
            if m.group(1) == DEC_PREFIX and int(m.group(2)) in adrs:
                refs.append(adrs[int(m.group(2))])
        quotes = []
        for rx in QUOTE_RES:
            for m in rx.finditer(para):
                q = m.group(1)
                prefix = para[para.rfind("\n", 0, m.start()) + 1:m.start()]
                if "**" not in q and ATTRIB_TAIL.search(prefix):
                    quotes.append(q)
        bq = [re.sub(r"^\s*>\s?", "", l) for l in para.splitlines() if l.lstrip().startswith(">")]
        if bq:
            quotes.append(" ".join(bq))
        use_refs = refs or prev_refs
        if quotes and use_refs and not URL_RE.search(para):
            texts = []
            for r in dict.fromkeys(use_refs):
                try:
                    with open(r, encoding="utf-8", errors="replace") as f:
                        texts.append(norm(f.read()))
                except OSError:
                    pass
            for q in quotes:
                if len(q.split()) < MIN_QUOTE_WORDS:
                    continue
                stats["quotes"] += 1
                for frag in re.split(r"\s*(?:…|\.\.\.|\[\.\.\.\])\s*", q):
                    if len(frag.split()) < MIN_FRAGMENT_WORDS:
                        continue
                    nf = norm(frag)
                    if any(nf in t for t in texts) or nf in seen_norm:
                        continue
                    corpus_text()
                    if nf in _corpus_cache["norm"] or repo_contains(frag):
                        continue
                    names = ", ".join(os.path.relpath(r, ROOT) for r in dict.fromkeys(use_refs))
                    flags.append('quote appears nowhere you could have read it (cited: %s): "%s"'
                                 % (names, frag.strip()[:90]))
                    break
        prev_refs = refs
    return flags, stats


def log(line):
    try:
        os.makedirs(LOGDIR, exist_ok=True)
        with open(os.path.join(LOGDIR, "claim-check.log"), "a") as f:
            f.write(line.replace("\n", " ") + "\n")
    except OSError:
        pass


def main():
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return
    sid = (payload.get("session_id") or "nosession")[:8]
    try:
        text, seen = read_transcript(payload)
        if not text.strip():
            log("%s session=%s event=empty-turn" % (ts, sid))
            return
        flags, st = check(text, seen)
    except Exception as e:  # never break a turn — but never fail silently either
        log("%s session=%s event=error error=%r" % (ts, sid, e))
        return
    log("%s session=%s links=%d lines=%d ids=%d quotes=%d flagged=%d%s" % (
        ts, sid, st["links"], st["lines"], st["ids"], st["quotes"], len(flags),
        (" :: " + " | ".join(flags))[:900] if flags else ""))
    if not flags:
        return
    listed = "; ".join(flags[:5]) + (" (+%d more)" % (len(flags) - 5) if len(flags) > 5 else "")
    if MODE == "block" and not payload.get("stop_hook_active"):
        print(json.dumps({"decision": "block", "reason": (
            "claim-check: %d claim(s) in your last reply cannot be true as written — %s. Correct or retract "
            "each one in a short follow-up (look it up first, the recall-is-not-a-source rule), then finish." % (len(flags), listed))}))
    else:
        print(json.dumps({"systemMessage": (
            "claim-check (advisory): %d claim(s) in the last reply could not be verified against the repo — %s"
            % (len(flags), listed))}))


if __name__ == "__main__":
    main()
