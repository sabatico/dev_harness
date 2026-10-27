#!/usr/bin/env python3
"""refs-index.py — the reference index ("what points at X, and what does X point at?"). Run through scripts/refs.sh.

WHY (the owner of the first adopting project asked for "some graph implementation to improve retrieval"; the ruling:
a GENERATED reference index over the exact IDs the repo already writes — not a graph database, not embeddings).
CLAUDE.md requires reading "everything that POINTS AT" a decision before changing it. Agents did that with
`scripts/find.sh <term>` per ID, which misses the variant forms people really write ("ADR-49", "ADR 49", "§3 of
ADR-001") and cannot say which hits are DEFINITIONS, which are plain mentions and which are a code comment's
decision citation. This file walks every repo file once, records each exact-ID reference as a typed edge with
file:line, and answers inbound and outbound in one view.

CONFIG (harness.conf, read by refs.sh and passed in the environment; an env var already set wins, so a test can vary a knob):
  HARNESS_DECISION_PREFIX  the decision-record family (default ADR); its files are HARNESS_DECISION_DIR/PREFIX-NNN-*.md
  HARNESS_DECISION_DIR     where decision files live (default docs/adr)
  HARNESS_BUG_PREFIX       the bug family (default BUG); its rows live in the ticket tables
  HARNESS_BUG_REGISTER     the bug register file (optional; it and its "-archive" sibling also define ids)
  HARNESS_REFS_IDS         the other id families (default "USER DEC FEAT DOC BIZ SEC TBD"), each a table-row family
  HARNESS_DOC_DIRS         the doc roots whose tables define ids (default docs)
The decision and bug prefixes are the ONLY ones that resolve a shortened number ("ADR-12" -> ADR-012).

WHAT IS AN ID. Never a hard-coded list of prefixes ("UTF-8", "SHA-256", "ISO-8601" must never count). A token
`PREFIX-NN` is an ID only when its prefix is DEFINED somewhere:
  decision  a file DECISION_DIR/PREFIX-NNN-*.md (defined at line 1, whole file = its span)
  tickets   a table row `| ID |` in <doc dir>/tickets/*.md, backlog-tickets*.md, tbd-parking-lot*.md and the bug
            register (the bug family, and the families named in HARNESS_REFS_IDS), also its archives
  catalog   a table row in <doc dir>/feature-catalog*.md: the prefixes are whatever the rows start with — read from
            the rows, never listed here
  runner    `| W3 |` rows of <doc dir>/runner*.md (no hyphen; matched in prose files only — too common a shape in code)
Tables are recognised by a header whose first cell is `ID`; the definition files are a glob list (DEFINITION_GLOBS)
because a quoted example row in some other doc must not define an ID.

EDGES (every one carries file:line; owner = the ID whose definition span contains the line):
  defines            the row / file that defines an ID
  cites              a mention of an ID in a document
  cites-section      a decision cited with a part: "ADR-002 §4", "ADR-007 §1 and §2", "ADR-015 rule 1", "§3 of ADR-001"   harness:allow-old-citation shows the citation FORMS refs.sh reads, quoted not claimed
  decision-in-code   a decision cited from a code or script file (doc comments cite "ADR-005 §1"); yaml, json, toml and jsonl are documents, so their cites are cites/cites-section
  code-cites         any other ID cited from code (a bug id in a comment)
  bug-file, bug-test a path / test name inside a bug-register row
  mentions-path      any other mention of a repo path (backticks, bare, markdown link)
This tool only SHOWS each decision's `**Status:**` line verbatim; whether a citation of a superseded part is stale is a
judgement it never makes.

GENERATED VIEWS ARE NOT DEFINITIONS: a file whose first lines say GENERATED ... do not edit, or a region between
`<!-- GENERATED:name BEGIN` and `<!-- GENERATED:name END`, only cites. WHY: a generated copy of a row would otherwise
read as a duplicate definition of the id.

INDEX, BUILT ON DEMAND (no committed index → no stale-index gate, no merge conflicts). Cached in `.refs-cache/`
(gitignored), keyed by sha256(this file's content + the knobs above + every scanned file's path, size, mtime_ns) so ANY
changed, added or removed file — or a changed knob — rebuilds it; stale `index-*.json` siblings are removed on write —
the only deletion this tool makes, inside its own cache folder, of files it can rebuild. An unwritable cache is a stderr
warning, never a wrong answer. Output is sorted and deterministic; progress and timing go to stderr.

SCOPE. `git ls-files -co --exclude-standard` (tracked + untracked, .gitignore respected — the same files scripts/find.sh
searches), minus `.claude/worktrees/`, `.security-scans/` and the cache; binary files (NUL in the first 8 KB), files over
2 MB and symbolic links (never read through: the target may lie outside the repo or double-list a tracked file) are
skipped and COUNTED. A CODE line longer than 20,000 characters (minified code) is not scanned; those lines are counted
and named on stderr when the index is built; a document line is always scanned. A UTF-8 byte-order mark at the start of
a file is ignored. Code vs document is decided by the file extension (DOC_EXT).
Not covered (named, not hidden): bare file names without a directory ("main.go"), directory mentions, ID lists
written as "ADR-001/002", the part numbers of an ID inside a path, where a test function is defined.

Exit: 0 hits · 1 nothing (the scanned-file count is printed) · 2 usage error or crash (an uncaught exception never
leaves exit 1, which means "nothing found" — same convention as scripts/find.sh). Python 3 stdlib only; `python3 -I`.
Matrix: scripts/refs-test.sh.
"""
import bisect
import fnmatch
import hashlib
import json
import os
import re
import stat as stat_mod
import subprocess
import sys
import time
import traceback

VERSION = 4
MAX_BYTES = 2 * 1024 * 1024
LONG_CODE_LINE = 20000     # a CODE line longer than this is skipped (and counted); document lines are always scanned
SKIP_PREFIXES = ('.claude/worktrees/', '.security-scans/', '.refs-cache/')
CACHE_DIR = '.refs-cache'
DEFAULT_CAP = 40

# ── config (harness.conf knobs, passed in the environment by refs.sh) ──────────────────────────────────────────
PREFIX_OK = re.compile(r'[A-Z][A-Z0-9]{0,5}')


def env_words(name, default):
    v = os.environ.get(name)
    return (default if v is None else v).split()


def env_one(name, default):
    return (os.environ.get(name) or default).strip()


DOC_DIRS = [d.strip('/') for d in env_words('HARNESS_DOC_DIRS', 'docs')] or ['docs']
DECISION_PREFIX = env_one('HARNESS_DECISION_PREFIX', 'ADR')
BUG_PREFIX = env_one('HARNESS_BUG_PREFIX', 'BUG')
DECISION_DIR = env_one('HARNESS_DECISION_DIR', 'docs/adr').strip('/')
BUG_REGISTER = env_one('HARNESS_BUG_REGISTER', '')
TICKET_IDS = env_words('HARNESS_REFS_IDS', 'USER DEC FEAT DOC BIZ SEC TBD')
for _p in [DECISION_PREFIX, BUG_PREFIX] + TICKET_IDS:
    if not PREFIX_OK.fullmatch(_p):
        sys.stderr.write('refs.sh: bad id prefix %r in harness.conf (1-6 chars, A-Z0-9, starting with a letter)\n' % _p)
        sys.exit(2)
CONFIG_SIG = repr((DOC_DIRS, DECISION_PREFIX, BUG_PREFIX, DECISION_DIR, BUG_REGISTER, TICKET_IDS))

# Only the decision and bug families resolve a shortened number ("ADR-12" -> ADR-012, "BUG-79" -> BUG-079): those are
# the forms people really shorten. Any other family must match a defined id exactly.
SHORTENABLE = (DECISION_PREFIX, BUG_PREFIX)
DEC_FILE = re.compile(re.escape(DECISION_DIR) + '/' + re.escape(DECISION_PREFIX) + r'-(\d{3})-.*\.md$')

# Where IDs are DEFINED by table rows. A glob list, not "any table": a quoted example row elsewhere must not define.
CATALOG_GLOBS = tuple('%s/feature-catalog*.md' % d for d in DOC_DIRS)
RUNNER_GLOBS = tuple('%s/runner*.md' % d for d in DOC_DIRS)
DEFINITION_GLOBS = tuple(g for d in DOC_DIRS for g in (
    '%s/tickets/*.md' % d, '%s/backlog-tickets*.md' % d, '%s/tbd-parking-lot*.md' % d)) + CATALOG_GLOBS + RUNNER_GLOBS
if BUG_REGISTER:
    DEFINITION_GLOBS += (os.path.splitext(BUG_REGISTER)[0] + '*.md',)    # the register and its "-archive" sibling
# Each configured family has the kind of its lowercased prefix; a prefix found only in a catalog table is 'catalog'.
KIND_BY_PREFIX = {p: p.lower() for p in [DECISION_PREFIX, BUG_PREFIX] + TICKET_IDS}
KIND_ORDER = tuple(dict.fromkeys(list(KIND_BY_PREFIX.values()) + ['catalog', 'runner', 'other']))
DOC_EXT = ('.md', '.markdown', '.txt', '.rst', '.toml', '.jsonl', '.json', '.csv', '.yaml', '.yml')
EDGE_ORDER = ('defines', 'cites-section', 'cites', 'decision-in-code', 'code-cites', 'bug-file', 'bug-test',
              'mentions-path')

# ── patterns ─────────────────────────────────────────────────────────────────────────────────────────────────
# A generic ID token. The lookbehind refuses a '-' so "ST-PAR-03" is ONE token (prefix "ST-PAR"), never "PAR-03".
TOK = re.compile(r'(?<![A-Za-z0-9_-])([A-Z][A-Z0-9]{0,5}(?:-[A-Z][A-Z0-9]{0,5}){0,2})-(\d{1,4})(?![A-Za-z0-9_])')
# "ADR 12" (space form) is a decision citation too — find.sh "ADR-012" cannot see it.
DEC_SPACE = re.compile(r'(?<![A-Za-z0-9_-])' + re.escape(DECISION_PREFIX) + r' (\d{1,3})(?![A-Za-z0-9_])')
RUN = re.compile(r'(?<![A-Za-z0-9_./#-])([A-Z]{1,2})(\d{1,3}[a-z]?)(?![A-Za-z0-9_])')
PATH = re.compile(r'(?<![A-Za-z0-9_@+~./\-])((?:\./)?[A-Za-z0-9_@+~.\-]+(?:/[A-Za-z0-9_@+~.\-]+)+)')
BARE = re.compile(r'(?<![A-Za-z0-9_@+~./\-])([A-Za-z0-9_.\-]+\.[A-Za-z0-9]{1,6})(?![A-Za-z0-9_/])')
LINK = re.compile(r'\]\(([^)\s#]{1,300})(?:#[^)]{0,300})?\)')    # bounded runs: linear on `](a](a...`
TESTNAME = re.compile(r'\bTest[A-Z_][A-Za-z0-9_]*')
# Generated views are NOT definitions: a generated catalog page, a hub block, a by-side view or a board repeats rows
# that live elsewhere, and a repeated row would otherwise read as a duplicate definition. (Owner of the first adopting
# project ruled it so.) A general rule, not a list of files: a file whose first lines say
# GENERATED ... do not edit, or a region between `<!-- GENERATED:name BEGIN` and `<!-- GENERATED:name END`, only cites.
GEN_HEAD = re.compile(r'\bGENERATED\b')
GEN_NOEDIT = re.compile(r'do not (?:hand-)?edit', re.I)
GEN_BEGIN = re.compile(r'^\s*<!--\s*GENERATED:([\w-]+)\s+BEGIN')
GEN_END = re.compile(r'^\s*<!--\s*GENERATED:([\w-]+)\s+END')
CTRL = re.compile(r'[\x00-\x08\x0b-\x1f\x7f\x80-\x9f]')

# Part-citation forms (a superseded-citation gate, if the project has one, should read the same forms). The continuation
# number is limited to 1-2 digits and refuses a date tail so "ADR-001 §3, 2026-10-12" does not read "2026" as a part.  harness:allow-old-citation a form example, not a claim
BEFORE_WINDOW = 80      # characters of look-back for the reversed form "§3 of ADR-001" (keeps the scan linear-time)  harness:allow-old-citation a form example, not a claim
DES = r'(?:§§?|rules?\b|invariants?\b|sections?\b)'
NUM = r'\d+(?:\.\d+)*'
CNUM = r'\d{1,2}(?:\.\d{1,2})*(?!\d)(?!-\d{2})'
LIST = NUM + r'(?:\s*(?:,|/|&|\+|and|–|—|-|to)\s*(?:§§?\s*)?' + CNUM + r')*'
AFTER = re.compile(r'\s*(' + DES + r'\s*(' + LIST + r'))', re.I)
BEFORE = re.compile(r'(' + DES + r'\s*(' + LIST + r'))\s+of\s+(?:the\s+)?$', re.I)


def padded_form(pfx, num, tw, widths):
    """True when a typed ID has more digits than the repo writes it with ("ADR-0049", "BUG-0079"): such a form names no
    record, so it neither resolves to the shorter ID nor counts as a citation of it. One rule for the decision and bug
    families (a decision number is three digits, whatever the digits; a bug number may only gain digits that are not
    padding). WHY a rule at all: "BUG-0079" resolving to BUG-079 answered a question nobody asked, with a real-looking
    result, while the same shape for a decision said "unknown"."""
    if pfx == DECISION_PREFIX:
        return tw > 3
    w = widths.get(pfx)
    return pfx in SHORTENABLE and bool(w) and tw > w and len(str(num)) < tw


def nums_of(text):
    """Top-level section numbers in '1 and 2', '2–3', '4.2' (a dash expands to a range, max 20 wide)."""
    out, prev, sep_range = set(), None, False
    for tok in re.split(r'(\s*(?:,|/|&|\+|and|to|–|—|-)\s*(?:§§?\s*)?)', text):
        if re.fullmatch(NUM, tok.strip() or 'x'):
            n = int(tok.strip().split('.')[0])
            if sep_range and prev is not None and 0 <= n - prev <= 20:
                out.update(range(prev, n + 1))
            out.add(n)
            prev, sep_range = n, False
        else:
            sep_range = bool(re.search(r'[–—-]|\bto\b', tok))
    return out


def clean(s):
    """Strip control characters from anything printed: a repo line must not be able to drive the terminal."""
    return CTRL.sub('?', s)


CTRL_NAME = re.compile(r'[\x00-\x1f\x7f\x80-\x9f]')


def cname(s):
    """A file NAME made printable: unlike a line it may hold a newline or tab, which would forge a second output line, and
    the file list can hold names that are not valid UTF-8 (lone surrogates) that print() cannot encode."""
    return CTRL_NAME.sub('?', s.encode('utf-8', 'replace').decode('utf-8'))


def is_doc(path):
    return path.lower().endswith(DOC_EXT)


def glob_any(path, globs):
    return any(fnmatch.fnmatch(path, g) for g in globs)


def split_cells(line):
    return [c.strip() for c in re.split(r'(?<!\\)\|', line.strip().strip('|'))] if line.lstrip().startswith('|') else []


def id_cell(cell):
    return re.sub(r'[*`]|\[([^\]]*)\]\([^)]*\)', lambda m: m.group(1) or '', cell).strip()


ROW_ID = re.compile(r'^([A-Z][A-Z0-9]{0,5}(?:-[A-Z][A-Z0-9]{0,5}){0,2})-(\d{1,4})[a-z]?$')
ROW_RUN = re.compile(r'^([A-Z]{1,2})(\d{1,3}[a-z]?)$')
ROW_RANGE = re.compile(r'^([A-Z][A-Z0-9]{0,5})-(\d{1,4})\s*(?:–|—|-|to)\s*(?:[A-Z][A-Z0-9]{0,5}-)?(\d{1,4})$')


# ── file list ──────────────────────────────────────────────────────────────────────────────────────────────────
def list_files(root):
    p = subprocess.run(['git', '-c', 'core.quotePath=false', 'ls-files', '-co', '--exclude-standard', '-z'],
                       cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        raise RuntimeError('git ls-files failed: ' + p.stderr.decode('utf-8', 'replace').strip())
    names = sorted({n.decode('utf-8', 'surrogateescape') for n in p.stdout.split(b'\0') if n})
    return [n for n in names if not n.startswith(SKIP_PREFIXES)]


def stat_files(root, names):
    """[(name, size, mtime_ns)], or (name, None, 'symlink') for a symbolic link, or (name, None, None) for a listed-but-
    missing / not-regular file. A link is NOT read through: its target may be outside the repo, or a second copy of a
    tracked file that would list every citation twice."""
    out = []
    for n in names:
        full = os.path.join(root, n)
        try:
            st = os.lstat(full)
            if stat_mod.S_ISLNK(st.st_mode):
                out.append((n, None, 'symlink'))
            elif stat_mod.S_ISREG(st.st_mode):
                out.append((n, st.st_size, st.st_mtime_ns))
            else:
                out.append((n, None, None))
        except OSError:
            out.append((n, None, None))
    return out


def cache_key(stats):
    h = hashlib.sha256()
    h.update(('v%d\0' % VERSION).encode())
    with open(os.path.abspath(__file__), 'rb') as f:
        h.update(f.read())
    h.update(CONFIG_SIG.encode())    # a changed knob changes what is an id: the old index would answer wrongly
    for n, s, m in stats:
        h.update(('%s\0%s\0%s\n' % (n, s, m)).encode('utf-8', 'surrogateescape'))
    return h.hexdigest()[:16]


# ── the one pass ───────────────────────────────────────────────────────────────────────────────────────────────
def build(root, stats):
    files = [n for n, _, _ in stats]
    fidx = {n: i for i, n in enumerate(files)}
    rootfiles = {n for n in files if '/' not in n}
    skipped = {'binary': 0, 'too-large': 0, 'unreadable': 0, 'symlink': 0}
    long_lines = 0     # code lines over LONG_CODE_LINE chars, not scanned
    scanned = 0

    defs = {}          # key (prefix,int) -> list of [file_idx, line, end_line, kind, display-width]
    spans = {}         # file_idx -> list of (start, end, owner (prefix,int)|runner-id-str)
    widths = {}        # prefix -> widest digit string among DEFINITIONS
    dec_status = {}    # int -> (file_idx, line, text)
    raw_ids = []       # [file_idx, line, prefix, num, typed_width, variant, nums|None, section_text, in_code]
    raw_run = []       # [file_idx, line, prefix+digits]
    raw_paths = []     # [file_idx, line, path]
    raw_tests = []     # [file_idx, line, name, ctx]       ctx = 'bug'
    run_defs = {}      # id string -> [[file_idx, line]]

    for name, size, kind in stats:
        fi = fidx[name]
        if size is None:
            skipped['symlink' if kind == 'symlink' else 'unreadable'] += 1
            continue
        if size > MAX_BYTES:
            skipped['too-large'] += 1
            continue
        try:
            with open(os.path.join(root, name), 'rb') as f:
                data = f.read()
        except OSError:
            skipped['unreadable'] += 1
            continue
        if b'\0' in data[:8192]:
            skipped['binary'] += 1
            continue
        scanned += 1
        text = data.decode('utf-8', 'replace')
        if text.startswith('\ufeff'):
            text = text[1:]            # a BOM in front of the first table header would hide the whole table
        lines = text.split('\n')           # NOT splitlines(): it also splits on \x0b \x0c   and drifts line numbers
        code = not is_doc(name)
        gen_file = any(GEN_HEAD.search(l) and GEN_NOEDIT.search(l) for l in lines[:8])
        in_gen = False
        is_def_file = glob_any(name, DEFINITION_GLOBS)
        is_runner = glob_any(name, RUNNER_GLOBS)
        is_catalog = glob_any(name, CATALOG_GLOBS)
        m_dec = DEC_FILE.match(name)
        owner_dec = int(m_dec.group(1)) if m_dec else None
        nlines = len(lines) - (1 if lines and lines[-1] == '' else 0)    # split('\n') leaves '' after the final newline
        if owner_dec is not None:
            defs.setdefault((DECISION_PREFIX, owner_dec), []).append([fi, 1, nlines, KIND_BY_PREFIX[DECISION_PREFIX], 3])
            widths[DECISION_PREFIX] = 3
            spans.setdefault(fi, []).append((1, nlines, (DECISION_PREFIX, owner_dec)))
        in_id_table = False
        for ln, raw in enumerate(lines, 1):
            line = raw.rstrip('\r')
            if not line.strip():
                in_id_table = False             # a blank line ends a table
                continue
            if code and len(line) > LONG_CODE_LINE:
                long_lines += 1           # minified code: named in the header and counted, never silent
                continue
            if line.lstrip().startswith('<!--'):
                if GEN_BEGIN.match(line):
                    in_gen = True
                elif GEN_END.match(line):
                    in_gen = False
            generated_here = gen_file or in_gen    # rows here are copies: they cite, they never define
            row_owner = None      # ('BUG', 5) when this line is a definition row of a BUG
            # --- decision status line
            if owner_dec is not None and owner_dec not in dec_status and line.startswith('**Status:**'):
                dec_status[owner_dec] = (fi, ln, line)
            # --- table definitions
            if is_def_file and line.startswith('|') and not generated_here:
                cells = split_cells(line)
                if cells and id_cell(cells[0]) == 'ID':
                    in_id_table = True
                elif in_id_table and cells:
                    cid = id_cell(cells[0])
                    mm, mr = ROW_ID.match(cid), ROW_RUN.match(cid)
                    if mm:
                        pfx, num = mm.group(1), int(mm.group(2))
                        kind = KIND_BY_PREFIX.get(pfx) or ('catalog' if is_catalog else 'other')
                        w = len(mm.group(2))
                        defs.setdefault((pfx, num), []).append([fi, ln, ln, kind, w])
                        widths[pfx] = max(widths.get(pfx, 0), w)
                        spans.setdefault(fi, []).append((ln, ln, (pfx, num)))
                        row_owner = (pfx, num)
                    elif mr and is_runner:
                        rid = mr.group(1) + mr.group(2)
                        run_defs.setdefault(rid, []).append([fi, ln])
                        spans.setdefault(fi, []).append((ln, ln, rid))
                        row_owner = rid
            elif is_def_file and (not line.startswith('|') or generated_here):
                in_id_table = False

            # --- ID tokens
            if '-' in line or DECISION_PREFIX + ' ' in line:
                for m in TOK.finditer(line):
                    pfx, ns = m.group(1), m.group(2)
                    nums, sect = None, ''
                    if pfx == DECISION_PREFIX:
                        a = AFTER.match(line, m.end())
                        if a:
                            nums, sect = sorted(nums_of(a.group(2))), a.group(1).strip()
                        else:
                            b = BEFORE.search(line, max(0, m.start() - BEFORE_WINDOW), m.start())
                            if b:
                                nums, sect = sorted(nums_of(b.group(2))), b.group(1).strip()
                    raw_ids.append([fi, ln, pfx, int(ns), len(ns), 0, nums, sect, code])
                for m in DEC_SPACE.finditer(line):
                    a = AFTER.match(line, m.end())
                    raw_ids.append([fi, ln, DECISION_PREFIX, int(m.group(1)), len(m.group(1)), 1,
                                    sorted(nums_of(a.group(2))) if a else None, a.group(1).strip() if a else '', code])
            if not code:
                for m in RUN.finditer(line):
                    raw_run.append([fi, ln, m.group(1) + m.group(2)])
            # --- paths
            if '/' in line:
                for m in PATH.finditer(line):
                    p = m.group(1)
                    if p.startswith('./'):
                        p = p[2:]
                    p = p.rstrip('.-')
                    if p in fidx:
                        raw_paths.append([fi, ln, p])
                for m in LINK.finditer(line):
                    t = m.group(1)
                    if '://' in t or t.startswith(('mailto:', '/')):
                        continue
                    p = os.path.normpath(os.path.join(os.path.dirname(name), t))
                    if p in fidx:
                        raw_paths.append([fi, ln, p])
            if rootfiles and '.' in line:
                for m in BARE.finditer(line):
                    if m.group(1) in rootfiles:
                        raw_paths.append([fi, ln, m.group(1)])
            # --- test names inside bug-register rows
            if row_owner is not None and row_owner[0] == BUG_PREFIX:
                for m in TESTNAME.finditer(line):
                    raw_tests.append([fi, ln, m.group(0), 'bug'])
    return dict(files=files, scanned=scanned, skipped=skipped, long_lines=long_lines, defs=defs, spans=spans, widths=widths,
                dec_status=dec_status, raw_ids=raw_ids, raw_run=raw_run, raw_paths=raw_paths,
                raw_tests=raw_tests, run_defs=run_defs)


# ── finalise: raw tokens → typed edges ───────────────────────────────────────────────────────────────────────
def is_test_path(p):
    return bool(re.search(r'(_test\.|\.test\.|-test\.|/tests?/|(^|/)Tests?/|Tests?\.[a-z]+$)', p))


def finalize(raw):
    files = raw['files']
    fidx = {n: i for i, n in enumerate(files)}
    widths = raw['widths']
    defs = raw['defs']

    def canon(pfx, num, typed_w=0):
        w = widths.get(pfx) or (3 if pfx == DECISION_PREFIX else typed_w)
        return '%s-%s' % (pfx, str(num).zfill(w))

    def cite_key(pfx, num, tw):
        """The ID a citation names, or None when it is only a look-alike token. Only the decision and bug families
        resolve a shortened number ("ADR-12" -> ADR-012, "BUG-79" -> BUG-079), because those are the forms people really
        shorten. Anything else must match a defined ID exactly: "WIN-1" is NOT "WIN-01" (a repo may also use WIN-1 for a
        review finding) unless a row `WIN-1` exists. A different-width token with no such row stays a plain token."""
        if pfx in SHORTENABLE:
            return canon(pfx, num, tw)
        typed = '%s-%s' % (pfx, str(num).zfill(tw))
        if typed in defkeys:
            return typed
        if pfx not in widths or tw == widths[pfx]:
            return typed                  # the house width but undefined (WEB-06): a cited-never-defined candidate
        return None

    defkeys = {canon(p, n) for (p, n) in defs}
    def_prefixes = {p for (p, _n) in defs}
    # resolvable = a token with this prefix can be judged defined/dangling
    resolvable = def_prefixes | set(KIND_BY_PREFIX)

    # owner lookup per file
    starts = {}
    for fi, sp in raw['spans'].items():
        sp.sort(key=lambda s: (s[0], s[1]))
        starts[fi] = ([s[0] for s in sp], sp)

    def owner_of(fi, ln):
        # spans never overlap inside one file (one ADR-wide span, single-line rows, disjoint runner rows)
        if fi not in starts:
            return None
        st, sp = starts[fi]
        i = bisect.bisect_right(st, ln) - 1
        return sp[i][2] if i >= 0 and sp[i][0] <= ln <= sp[i][1] else None

    def okey(o):
        if o is None:
            return ''
        if isinstance(o, tuple):
            return canon(o[0], o[1])
        return o

    seen = set()
    refs = []   # [file_idx, line, edge, ttype, tkey, extra, owner, nums]

    def add(fi, ln, edge, ttype, tkey, extra='', nums=None):
        k = (fi, ln, edge, ttype, tkey, extra)
        if k in seen:
            return
        seen.add(k)
        refs.append([fi, ln, edge, ttype, tkey, extra, okey(owner_of(fi, ln)), nums])

    for fi, ln, pfx, num, tw, variant, nums, sect, code in raw['raw_ids']:
        if pfx not in resolvable or padded_form(pfx, num, tw, widths):
            continue                  # "ADR-0130", "ADR-1000", "BUG-0079" name no record (padded_form)
        key = cite_key(pfx, num, tw)
        if key is None:
            continue
        typed = '%s%s%s' % (pfx, ' ' if variant else '-', str(num).zfill(tw))
        extra = sect if nums else ''
        if typed != key:
            # a form `find.sh ADR-012` cannot see: "ADR-12", "ADR 12"
            extra = (extra + ' ' if extra else '') + '[as "%s"]' % typed
        if code:
            edge = 'decision-in-code' if pfx == DECISION_PREFIX else 'code-cites'
        else:
            edge = 'cites-section' if nums else 'cites'
        add(fi, ln, edge, 'id', key, extra, nums)

    runner = set(raw['run_defs'])
    for fi, ln, rid in raw['raw_run']:
        if rid in runner:
            add(fi, ln, 'cites', 'id', rid)

    for fi, ln, p in raw['raw_paths']:
        o = owner_of(fi, ln)
        if isinstance(o, tuple) and o[0] == BUG_PREFIX:
            add(fi, ln, 'bug-test' if is_test_path(p) else 'bug-file', 'path', p)
        else:
            add(fi, ln, 'mentions-path', 'path', p)
    for fi, ln, name, ctx in raw['raw_tests']:
        add(fi, ln, 'bug-test', 'test', name)
    # definitions as `defines` edges are not in `refs`; they live in `defs` (display keys)
    defout = {}
    for (pfx, num), v in defs.items():
        defout[canon(pfx, num)] = [[d[0], d[1], d[2], d[3]] for d in v]
    for rid, v in raw['run_defs'].items():
        defout[rid] = [[d[0], d[1], d[1], 'runner'] for d in v]
    status = {canon(DECISION_PREFIX, n): list(v) for n, v in raw['dec_status'].items()}
    refs.sort(key=lambda r: (files[r[0]], r[1], r[2], r[3], r[4], r[5]))
    return dict(version=VERSION, files=files, scanned=raw['scanned'], skipped=raw['skipped'],
                long_lines=raw['long_lines'], defs=defout,
                refs=refs, status=status,
                kinds={canon(p, n): v[0][3] for (p, n), v in defs.items()},
                resolvable=sorted(resolvable), widths=widths)


# ── cache ─────────────────────────────────────────────────────────────────────────────────────────────────────
def load_or_build(root, rebuild):
    t0 = time.time()
    names = list_files(root)
    stats = stat_files(root, names)
    key = cache_key(stats)
    cdir = os.path.join(root, CACHE_DIR)
    path = os.path.join(cdir, 'index-%s.json' % key)
    if not rebuild and os.path.isfile(path):
        try:
            with open(path, 'r', encoding='utf-8') as f:
                idx = json.load(f)
            if not isinstance(idx, dict):
                raise ValueError('wrong shape')     # [] or a bare string is valid JSON but not an index
            if idx.get('version') == VERSION:
                sys.stderr.write('refs: index cache hit (%d files, %d refs, %.2fs)\n' % (
                    idx['scanned'], len(idx['refs']), time.time() - t0))
                idx['file_set'] = {n: i for i, n in enumerate(idx['files'])}
                idx['files_disp'] = [cname(n) for n in idx['files']]
                return idx
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            sys.stderr.write('refs: cache unreadable, rebuilding\n')
    idx = finalize(build(root, stats))
    dt = time.time() - t0
    try:
        os.makedirs(cdir, exist_ok=True)
        tmp = path + '.%d.tmp' % os.getpid()
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(idx, f, separators=(',', ':'))
        os.replace(tmp, path)
        for old in os.listdir(cdir):
            if old.startswith('index-') and old.endswith('.json') and old != os.path.basename(path):
                try:
                    os.remove(os.path.join(cdir, old))
                except OSError:
                    pass
    except OSError as e:
        sys.stderr.write('refs: warning: cache not written (%s); answer is still correct\n' % e)
    idx['file_set'] = {n: i for i, n in enumerate(idx['files'])}
    idx['files_disp'] = [cname(n) for n in idx['files']]
    sys.stderr.write('refs: index built in %.2fs (%d files scanned, %d skipped, %d refs)\n' % (
        dt, idx['scanned'], sum(idx['skipped'].values()), len(idx['refs'])))
    if idx.get('long_lines'):
        sys.stderr.write('refs: %d code line(s) over %d characters were not scanned (minified code)\n' % (
            idx['long_lines'], LONG_CODE_LINE))
    return idx


# ── query ─────────────────────────────────────────────────────────────────────────────────────────────────────
class Out:
    def __init__(self, root, idx):
        self.root, self.idx, self.cache = root, idx, {}

    def line(self, fi, ln, needle=None):
        """The line's text, cut to a window AROUND the match: a 150-character head would often hide the very citation
        the row is listed for (a rule line can hold five IDs)."""
        if fi not in self.cache:
            try:
                with open(os.path.join(self.root, self.idx['files'][fi]), 'rb') as f:
                    self.cache[fi] = f.read().decode('utf-8', 'replace').split('\n')
            except OSError:
                self.cache[fi] = []
        ls = self.cache[fi]
        t = ls[ln - 1].strip() if 0 < ln <= len(ls) else ''
        t = clean(t)
        if len(t) <= 150:
            return t
        m = needle.search(t) if needle is not None else None
        a = max(0, (m.start() if m else 0) - 60)
        return ('… ' if a else '') + t[a:a + 150] + (' …' if a + 150 < len(t) else '')


def norm_target(idx, arg):
    """('id', key) | ('path', p) | ('test', name) | ('dir', p) | (None, why).

    Paths: a bare name ("x.md", "docs/adr") is repo-relative first (an exact repo path wins over an ID-shaped file name).
    An explicit "./", "../", or "." is the caller's directory, as in every Unix tool :
    `./x.md` typed in docs/sub is docs/sub/x.md, never the root x.md, so the './' is NOT stripped before the repo-relative
    match. The repo root is a folder like any other: exit 2, "is a directory"."""
    a = arg.strip()
    cwd_form = a.startswith('./')                  # explicit current-directory form: only the cwd-relative reading applies
    p = a
    if not cwd_form and p in idx['file_set']:      # an exact file path wins over an ID-shaped file name
        return ('path', p)
    rel = repo_relative(idx, a)                    # absolute, or relative to the caller's directory
    if rel is not None and rel in idx['file_set']:
        return ('path', rel)
    if rel == '':
        return ('dir', '.')                        # the repo root itself
    if rel is not None and any(f.startswith(rel + '/') for f in idx['files']):
        return ('dir', rel)
    if any(f.startswith(p.rstrip('/') + '/') for f in idx['files']) and p.rstrip('/'):
        return ('dir', p)                          # a folder without the slash is a folder too
    m = re.fullmatch(r'([A-Za-z][A-Za-z0-9]{0,5}(?:-[A-Za-z][A-Za-z0-9]{0,5}){0,2})(?:-|\s)(\d{1,4})', a)
    if m:
        pfx, n = m.group(1).upper(), int(m.group(2))
        if pfx == DECISION_PREFIX and len(m.group(2)) > 3:
            return (None, a)                       # decision numbers are three digits: "ADR-0049" names no record
        if pfx != DECISION_PREFIX and padded_form(pfx, n, len(m.group(2)), idx['widths']):
            return (None, a)                       # "BUG-0079" names no record either
        if pfx in SHORTENABLE:             # only the decision and bug families resolve a shortened number
            w = idx['widths'].get(pfx) or (3 if pfx == DECISION_PREFIX else len(m.group(2)))
            return ('id', '%s-%s' % (pfx, str(n).zfill(w)))
        return ('id', '%s-%s' % (pfx, m.group(2)))
    m = re.fullmatch(r'([A-Za-z]{1,2})(\d{1,3}[a-z]?)', a)
    if m:
        rid = m.group(1).upper() + m.group(2).lower()
        if rid in idx['defs'] and idx['defs'][rid][0][3] == 'runner':
            return ('id', rid)
    if p.endswith('/') and any(f.startswith(p) for f in idx['files']):
        return ('dir', p)
    if re.fullmatch(r'Test[A-Z_][A-Za-z0-9_]*', a):
        return ('test', a)
    return (None, a)


def repo_relative(idx, a):
    """The repo-relative form of a path given absolute or relative to the current directory ('' for the repo root), or None
    when it lies outside the repo. WHY: the tool reads the index from the git root but the caller types paths from wherever
    they stand; agents in worktrees pass absolute paths all the time, and an answer of "no references" for the right
    file is a wrong answer that reads as a real one ."""
    root = idx.get('root')
    if not root or not a:
        return None
    try:
        full = os.path.realpath(a if os.path.isabs(a) else os.path.join(os.getcwd(), a))
        base = os.path.realpath(root)
    except (OSError, ValueError):
        return None
    if full == base:
        return ''                      # the repo root itself: a folder 
    if not full.startswith(base + os.sep):
        return None
    return full[len(base) + 1:].replace(os.sep, '/')


def kind_label(idx, key):
    k = idx['kinds'].get(key)
    if k:
        return k
    if key in idx['defs']:
        return idx['defs'][key][0][3]
    m = re.fullmatch(r'(.+)-\d+', key)
    if m:
        return KIND_BY_PREFIX.get(m.group(1)) or ('catalog' if m.group(1) in idx['resolvable'] else 'other')
    return 'other'


def capped(rows, cap):
    return rows if cap is None else rows[:cap]


def render_target(root, idx, ttype, tkey, args):
    """Lines for one target, or None when there is neither a definition nor any edge."""
    files, refs = idx['files_disp'], idx['refs']          # printable names; lookups use idx['files']
    o = Out(root, idx)
    cap = None if args.all else args.cap
    needle = None
    head, own_file, undefined = [], None, False
    if ttype == 'id':
        defs_here = idx['defs'].get(tkey, [])
        kind = idx['kinds'].get(tkey) or (idx['defs'][tkey][0][3] if tkey in idx['defs'] else None)
        m = re.fullmatch(r'(.+)-(\d+)', tkey)
        title = '== %s%s ==' % (tkey, (' (%s)' % kind) if kind else '')
        if m:
            needle = re.compile(r'(?<![A-Za-z0-9_-])%s[- ]0*%d(?!\d)' % (re.escape(m.group(1)), int(m.group(2))))
        for fi, ln, end, k in sorted(defs_here, key=lambda d: (files[d[0]], d[1])):
            head.append('defines: %s:%d%s' % (files[fi], ln, '' if end == ln else '-%d' % end))
        undefined = bool(not defs_here and not head and m and m.group(1) in set(idx['resolvable']))
        house = idx['widths'].get(m.group(1)) if m else None
        if undefined and m.group(1) not in SHORTENABLE and house is not None and len(m.group(2)) != house:
            undefined = False         # a wrong-width look-alike (WEB-6) is never listed by --dangling: no pointer 
        if len(defs_here) > 1:
            head.append('NOTE: defined %d times (a duplicate definition, or a table and its archive)' % len(defs_here))
        st = idx['status'].get(tkey)
        if st:
            head.append('status: %s   [%s:%d; shown verbatim, whether a citation of a superseded part is stale is not judged here]' % (
                clean(st[2])[:300], files[st[0]], st[1]))
        inbound = [r for r in refs if r[3] == 'id' and r[4] == tkey and r[6] != tkey]
        outbound = [r for r in refs if r[6] == tkey and not (r[3] == 'id' and r[4] == tkey)]
    elif ttype == 'path':
        own_file = idx['file_set'][tkey]
        title = '== %s (file) ==' % cname(tkey)
        needle = re.compile(re.escape(tkey))
        ids = sorted(k for k, v in idx['defs'].items() if any(d[0] == own_file for d in v))
        if ids:
            head.append('defines %d id(s) in this file: %s%s   (query an id for who cites it)' % (
                len(ids), ', '.join(ids[:12]), ' …' if len(ids) > 12 else ''))
        inbound = [r for r in refs if r[3] == 'path' and r[4] == tkey]
        outbound = [r for r in refs if r[0] == own_file and r[6] != r[4] and not (r[3] == 'path' and r[4] == tkey)]
        defs_here = [1] if ids else []
    elif ttype == 'test':
        title = '== %s (test) ==' % cname(tkey)
        needle = re.compile(re.escape(tkey))
        defs_here = []
        inbound = [r for r in refs if r[3] == 'test' and r[4] == tkey]
        outbound = []
    if args.section is not None:
        inbound = [r for r in inbound if r[7] and args.section in r[7]]
    if not (defs_here or head or inbound or outbound):
        return None, False
    if ttype == 'id' and undefined:
        head.append('NOT DEFINED anywhere: %s is cited but no row or file defines it (see --dangling)' % tkey)

    lines = [title] + head
    lines.append('')
    lines.append('== INBOUND — what points at %s: %d ref(s) in %d file(s)%s ==' % (
        cname(tkey), len(inbound), len({r[0] for r in inbound}), '' if args.section is None else ' (only part %d)' % args.section))
    if not inbound:
        lines.append('  none')
    for edge in EDGE_ORDER:
        rows = [r for r in inbound if r[2] == edge]
        if not rows:
            continue
        lines.append('-- %s (%d ref(s) in %d file(s)) --' % (edge, len(rows), len({r[0] for r in rows})))
        merged = {}                     # one display line per (file, line); several citations on it join their tags
        for r in rows:
            # the owner (the bug row that holds the link) is the useful part of a path or test hit
            tag = r[5] if r[3] == 'id' else ('[%s]' % r[5] if r[5] else '')
            if r[3] != 'id' and r[6]:
                tag = (r[6] + ' ' + tag).strip()
            merged.setdefault((files[r[0]], r[0], r[1]), []).append(tag)
        mrows = sorted(merged.items())
        for (fname, fi, ln), tags in capped(mrows, cap):
            tag = ' ; '.join(sorted({t for t in tags if t}))
            lines.append('  %s:%d:%s %s' % (fname, ln, (' ' + tag) if tag else '', o.line(fi, ln, needle)))
        if cap is not None and len(mrows) > cap:
            lines.append('  … %d more %s line(s) — TRUNCATED (use --all)' % (len(mrows) - cap, edge))
    if ttype == 'id' and tkey.startswith(DECISION_PREFIX + '-') and inbound:
        part = sum(1 for r in inbound if r[7])
        lines.append('(%d ref(s) name a part of the decision, %d name it whole; `--section N` shows one part)' % (part, len(inbound) - part))

    if ttype in ('id', 'path', 'test'):
        grp = {}
        for r in outbound:
            k = kind_label(idx, r[4]) if r[3] == 'id' else r[3]
            grp.setdefault(k, {}).setdefault((r[3], r[4]), []).append(r)
        lines.append('')
        lines.append('== OUTBOUND — what %s points at: %d ref(s) to %d target(s) ==' % (
            cname(tkey), sum(len(v) for g in grp.values() for v in g.values()), sum(len(g) for g in grp.values())))
        if not grp:
            lines.append('  none')
        for k in list(KIND_ORDER) + ['path', 'test']:
            g = grp.get(k)
            if not g:
                continue
            lines.append('-- %s (%d target(s)) --' % (k, len(g)))
            items = sorted(g.items(), key=lambda kv: (len(kv[0][1]) if False else 0, kv[0][1]))
            for (tt, tk), rs in capped(items, cap):
                locs = sorted({(files[r[0]], r[1]) for r in rs})
                if len({f for f, _ in locs}) == 1:
                    loc = '%s:%s%s' % (locs[0][0], ','.join(str(l) for _, l in locs[:8]), ' …' if len(locs) > 8 else '')
                else:
                    loc = ', '.join('%s:%d' % x for x in locs[:3]) + (' …' if len(locs) > 3 else '')
                parts = sorted({r[5] for r in rs if r[5]})
                lines.append('  %s%s  x%d  %s  (%s)' % (cname(tk), ('  ' + ' | '.join(parts)) if parts else '', len(rs), loc,
                                                       ', '.join(sorted({r[2] for r in rs}))))
            if cap is not None and len(items) > cap:
                lines.append('  … %d more target(s) — TRUNCATED (use --all)' % (len(items) - cap))
    # with --section the question is "who cites part N": a decision's own outbound refs must not turn "none" into success
    return lines, bool(inbound) if args.section is not None else bool(inbound or outbound)


def hint(idx, tkey):
    """A short form is never resolved for a non-ADR/BUG id; say which defined id has the same number instead."""
    m = re.fullmatch(r'(.+)-(\d+)', tkey)
    if not m or tkey in idx['defs']:
        return ''
    near = sorted(k for k in idx['defs'] if re.fullmatch(re.escape(m.group(1)) + r'-0*%d' % int(m.group(2)), k))
    return ('\nDid you mean %s? (only the decision and bug families resolve a shortened number)' % ', '.join(near)) if near else ''


def render_dangling(idx, root):
    files = idx['files_disp']
    defs = idx['defs']
    resolvable = set(idx['resolvable'])
    by_kind = {}
    for r in idx['refs']:
        if r[3] != 'id':
            continue
        key = r[4]
        if key in defs:
            continue
        m = re.fullmatch(r'(.+)-(\d+)', key)
        if not m:
            continue                       # runner ids are only matched when defined
        pfx, n = m.group(1), int(m.group(2))
        if pfx not in resolvable:
            continue
        kind = KIND_BY_PREFIX.get(pfx) or 'catalog'
        by_kind.setdefault(kind, {}).setdefault(key, []).append(r)
    lines = []
    total = sum(len(v) for v in by_kind.values())
    lines.append('== DANGLING: %d id(s) cited but never defined (scanned %d files) ==' % (total, idx['scanned']))
    for kind in list(KIND_ORDER):
        g = by_kind.get(kind)
        if not g:
            continue
        lines.append('-- %s (%d) --' % (kind, len(g)))
        for key in sorted(g, key=lambda k: (re.sub(r'\d+$', '', k), int(re.search(r'(\d+)$', k).group(1)))):
            rs = sorted(g[key], key=lambda r: (files[r[0]], r[1]))
            r = rs[0]
            lines.append('  %s  %d ref(s) in %d file(s), first %s:%d' % (key, len(rs), len({x[0] for x in rs}), files[r[0]], r[1]))
    dups = {k: v for k, v in defs.items() if len(v) > 1}
    if dups:
        # a second row for the same id (a table and its copy, or a catalog row repeated in the planned file): which one
        # is true is a question for whoever owns the register, so both locations are listed
        lines.append('== DUPLICATE DEFINITIONS: %d id(s) defined more than once ==' % len(dups))
        for key in sorted(dups, key=lambda k: (re.sub(r'\d+[a-z]?$', '', k), int(re.search(r'(\d+)[a-z]?$', k).group(1)))):
            lines.append('  %s  %s' % (key, ' · '.join('%s:%d' % (files[d[0]], d[1]) for d in sorted(
                dups[key], key=lambda d: (files[d[0]], d[1])))))
    return lines, total + len(dups)


# ── main ──────────────────────────────────────────────────────────────────────────────────────────────────────
USAGE = ('usage: refs.sh [--all] [--cap N] [--section N] [--rebuild] TARGET\n'
         '       refs.sh [--rebuild] --dangling\n'
         '  TARGET = an ID (ADR-012, "ADR 12", BUG-321, SEC-001, W3), a repo file path\n'
         '           (a name with no ./ is repo-relative; ./x and ../x are relative to where you stand),\n'
         '           or a test name cited in a bug row (TestFoo)\n'
         '  --section N  only decision citations that name part N        --all  no per-group cap (default cap %d)\n'
         '  exit 0 = references found · 1 = none (files scanned printed) · 2 = usage error / crash' % DEFAULT_CAP)


class Args:
    all = False
    cap = DEFAULT_CAP
    section = None
    rebuild = False
    dangling = False
    target = None


def parse(argv):
    a, pos = Args(), []
    i = 0
    while i < len(argv):
        t = argv[i]
        if t == '--':
            pos += argv[i + 1:]
            break
        if t in ('-h', '--help'):
            print(USAGE)
            sys.exit(0)
        elif t == '--all':
            a.all = True
        elif t == '--rebuild':
            a.rebuild = True
        elif t == '--dangling':
            a.dangling = True
        elif t in ('--cap', '--section'):
            i += 1
            v = argv[i] if i < len(argv) else ''
            if not v.isdigit() or int(v) < 1:
                die('%s needs a positive number' % t)
            if t == '--cap':
                a.cap = int(v)
            else:
                a.section = int(v)
        elif t.startswith('-') and len(t) > 1:
            die('unknown option %s (a target starting with "-" goes after --)' % clean(t))
        else:
            pos.append(t)
        i += 1
    if a.dangling:
        if pos or a.section is not None:
            die('--dangling takes no target and no --section')
        return a
    if len(pos) != 1 or not pos[0].strip():
        die('exactly one non-empty TARGET is needed' if pos else 'a TARGET is needed')
    a.target = pos[0]
    return a


def die(msg):
    sys.stderr.write('refs.sh: %s\n%s\n' % (msg, USAGE))
    sys.exit(2)


def crash(t, v, tb):
    traceback.print_exception(t, v, tb)
    sys.stderr.write('refs.sh: internal error (%s) — this is NOT "no references"\n' % t.__name__)
    sys.stderr.flush()
    os._exit(2)


def main():
    sys.excepthook = crash
    try:
        sys.stdout.reconfigure(errors='replace')
    except (AttributeError, ValueError):
        pass
    argv = sys.argv[1:]
    root = None
    if len(argv) >= 2 and argv[0] == '--root':
        root, argv = argv[1], argv[2:]
    if root is None:
        die('internal: run this through scripts/refs.sh')
    args = parse(argv)
    idx = load_or_build(root, args.rebuild)
    idx['root'] = root
    files = idx['files']
    if args.dangling:
        lines, total = render_dangling(idx, root)
        print('\n'.join(lines))
        if total == 0:
            print('no dangling ids — scanned %d files (a known positive is proven by '
                  'the test suite, not by this line)' % idx['scanned'])
            return 1
        return 0
    ttype, tkey = norm_target(idx, args.target)
    if ttype is None:
        print('NO REFERENCES for: %s — it is not a defined or cited ID, a scanned file path or a test name; '
              'scanned %d files (%d skipped as binary/too large/unreadable).' % (
                  clean(args.target), idx['scanned'], sum(idx['skipped'].values())))
        return 1
    if ttype == 'dir':
        die('%s is a directory; give a file (or use scripts/find.sh for a folder)' % clean(tkey))
    if args.section is not None and not (ttype == 'id' and tkey.startswith(DECISION_PREFIX + '-')):
        die('--section only applies to a decision-record target (%s-NNN)' % DECISION_PREFIX)
    lines, has_edges = render_target(root, idx, ttype, tkey, args)
    if lines is None:
        print('NO REFERENCES to or from %s — scanned %d files (%d skipped as binary/too large/unreadable).' % (
            clean(tkey), idx['scanned'], sum(idx['skipped'].values())) + hint(idx, tkey))
        return 1
    print('\n'.join(lines))
    if not has_edges:
        if args.section is not None:
            print('\nNO CITATION of part %d of %s — scanned %d files.' % (args.section, clean(tkey), idx['scanned']))
        else:
            print('\nNO REFERENCES to or from %s besides its definition — scanned %d files.' % (clean(tkey), idx['scanned']))
        return 1
    return 0


if __name__ == '__main__':
    try:
        rc = main()
        sys.stdout.flush()
    except BrokenPipeError:
        # `refs.sh X | head` closes the pipe early: that is the reader's choice, not a crash. Point stdout at /dev/null
        # so the interpreter's exit-time flush does not print a traceback either.
        try:
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        except OSError:
            pass
        rc = 0
    sys.exit(rc)
