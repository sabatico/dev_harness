#!/usr/bin/env bash
# rotate-bug-register.sh — move long-settled CLOSED rows to the bug-register archive.
# Generalised 2026-09-29 from a live project; paths from harness.conf (HARNESS_BUG_REGISTER,
# HARNESS_BUG_ARCHIVE default <register>-archive.md). Exit: 0 ok · 1 due/violation · 2 usage · 4 N/A.
#
# WHY. On the live project the register reached 336 KB with HALF of it closed rows — and it is one of
# the hottest files in the harness: grepped by gates, swept by the librarian, injected in part by the
# session-start hook, read
# by any agent chasing a bug id. The session log already solved this exact problem with a size
# budget + an archive file (ONBOARDING §9b); this generalises that pattern to the register.
#
# POLICY: a CLOSED row whose NEWEST date is older than the cutoff (default 30 days) moves, verbatim,
# to the archive's table. OPEN rows never move, whatever their age. The newest-date test is the
# right staleness signal because rows accrete dates as they are worked; a row touched recently is
# still in someone's working set even if the bug is old.
#
# 2026-09-29 — THE OPEN TABLE. The live register had grown to 523 KB again,
# and rotation could not help: this script only looked BELOW "## Closed bugs", while 94 rows whose
# status says FIXED/CLOSED/RESOLVED (~288 KB) still sat in the "## Open bugs" table — moving a row
# across when it is fixed was a prose step, so it mostly did not happen (13 genuinely open bugs,
# 145 rows in the open table). Now a row in the OPEN table is CLOSED only on a POSITIVE marker — its
# status cell starts with FIXED / CLOSED / RESOLVED (after markdown/emoji) and says OPEN nowhere; mixed
# cells ("(a) FIXED; (c) OPEN", "PARTLY CLOSED", "FIRST FIX…") stay put. Such a row goes to the archive
# if past the cutoff, else to the Closed table. --check turns the prose step into a GATE: it fails
# while anything is due, so the misfiling can no longer accumulate (run-all-gates.sh, fast tier).
# Cells are split on UNESCAPED pipes: rows carry `\|` inside code spans, and a plain split misreads
# the status column of exactly those rows.
#
# WHAT DOES NOT CHANGE: the row text (verbatim move); the escape-analysis prose blocks under
# "Closed bugs" (only table rows rotate — the analyses are the register's teaching material and are
# already outside the hot grep paths); bug ids (grep finds a given BUG-NNN in exactly one of the two
# files). Anything that COUNTS bugs must read both files, or totals drop when rows move. This kit's
# check-bug-evidence.sh reads only the live register: an archived row already passed it when it closed.
#
# SAFETY: refuses to move a row that says OPEN anywhere in its status cell; writes are staged as a
# whole-file rewrite of both files, so a crash mid-run cannot half-move a row (rerun is idempotent).
# An UNKNOWN ARGUMENT IS AN ERROR (exit 2). Until 2026-09-29 it was silently skipped, so
# `rotate-bug-register.sh --help` performed a real rotation (it did, once — verbatim and lossless,
# but unintended).
#
# Usage:
#   scripts/rotate-bug-register.sh              # rotate with the 30-day cutoff
#   scripts/rotate-bug-register.sh --days 60    # different cutoff
#   scripts/rotate-bug-register.sh --dry-run    # report what would move, touch nothing
#   scripts/rotate-bug-register.sh --check      # gate: exit 1 if anything is due, touch nothing
# Test: scripts/rotate-bug-register-test.sh (a fast-tier gate).
set -euo pipefail
ROOT="${HARNESS_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "$0")/.." && pwd))}"
cd "$ROOT"
[ -f harness.conf ] && . ./harness.conf
REG_PATH="${HARNESS_BUG_REGISTER:-}"
ARC_PATH="${HARNESS_BUG_ARCHIVE:-${REG_PATH%.md}-archive.md}"

DAYS=30; MODE=apply
while [ $# -gt 0 ]; do case "$1" in
  --days) DAYS="$2"; shift 2 ;;
  --dry-run) MODE=dry; shift ;;
  --check) MODE=check; shift ;;
  *) echo "rotate-bug-register.sh: unknown argument '$1' (use --days N, --dry-run, --check)" >&2; exit 2 ;;
esac; done
if [ -z "$REG_PATH" ] || [ ! -f "$REG_PATH" ]; then
  echo "N/A — no bug register configured (HARNESS_BUG_REGISTER) or file missing: ${REG_PATH:-unset}"; exit 4
fi
CUTOFF="$(date -v-"${DAYS}"d +%Y-%m-%d 2>/dev/null || date -d "-${DAYS} days" +%Y-%m-%d)"

python3 - "$CUTOFF" "$MODE" "$REG_PATH" "$ARC_PATH" <<'PY'
import re, sys
cutoff, mode, REG, ARC = sys.argv[1:5]
ROW = re.compile(r'^\| (BUG|SEC)-\d')

lines = open(REG).read().split('\n')
try:
    ci = next(i for i, l in enumerate(lines) if l.startswith('## Closed bugs'))
except StopIteration:
    print("✗ no '## Closed bugs' section found — refusing to touch anything"); sys.exit(1)
oi = next((i for i, l in enumerate(lines) if l.startswith('## Open bugs')), None)

# harness:allow-uncited — plumbing: split on UNESCAPED pipes; rows carry `\|` inside code spans and a
# plain split misreads exactly those rows' status column (matrix row "escaped pipe").
def cells(l):
    return [c.strip() for c in re.split(r'(?<!\\)\|', l)]

# harness:allow-uncited — the POSITIVE closed marker for open-table rows: FIXED/CLOSED/RESOLVED first,
# OPEN nowhere. Open is the default there, so only an explicit marker may move a row.
def status_closed(l):
    c = cells(l)
    if len(c) < 7:
        return False
    s = re.sub(r'[*_`✅⛔✔☑]+', ' ', c[6]).strip().upper()
    return bool(re.match(r'(FIXED|CLOSED|RESOLVED)\b', s)) and not re.search(r'\bOPEN\b', s)

# harness:allow-uncited — staleness = the NEWEST date on the row: rows accrete dates as they are
# worked, so a recently touched row stays in the working set even if the bug is old.
def newest(l):
    d = re.findall(r'20\d\d-\d\d-\d\d', l)
    return max(d) if d else None

to_archive, to_closed, keep = [], [], []
for i, l in enumerate(lines):
    if ROW.match(l) and oi is not None and oi < i < ci and status_closed(l):
        n = newest(l)
        (to_archive if n and n < cutoff else to_closed).append((i, l)); continue
    if ROW.match(l) and i > ci:
        n = newest(l)
        is_open = any(c == 'OPEN' or c.startswith('**OPEN') for c in cells(l))
        if n and n < cutoff and not is_open:
            to_archive.append((i, l)); continue
    keep.append((i, l))

ids = lambda rows: [cells(l)[1] for _, l in rows]
# Misfiled rows join the closed table (recent) or the archive (old) VERBATIM — so only when the closed table has
# the SAME columns (same header names). A template whose closed table uses a different schema (e.g. "Found →
# Closed | Fix | Verified by") needs a human rewrite; moving verbatim would corrupt it. Compare header NAMES, not
# counts: the kit's own template has 7 columns in both tables, differently named. A closed section with NO table
# header cannot prove the schemas match, so it blocks too. Decided BEFORE the dry-run/--check report, so the
# preview says exactly what a real run will do.
hdr = next((l for i, l in enumerate(lines) if i > ci and l.startswith('| ID')), None)
ohdr = next((l for i, l in enumerate(lines) if oi is not None and oi < i < ci and l.startswith('| ID')), None)
schema_differs = bool(ohdr and (hdr is None or [c.lower() for c in cells(hdr)] != [c.lower() for c in cells(ohdr)]))
blocked = []
if schema_differs:
    blocked = to_closed + [(i, l) for i, l in to_archive if i < ci]
    to_archive = [(i, l) for i, l in to_archive if i > ci]
    to_closed = []
    keep = sorted(keep + blocked)

stay = sum(1 for i, l in keep if i > ci and ROW.match(l))
print(f"cutoff {cutoff}: {len(to_archive)} closed row(s) to archive, {len(to_closed)} closed row(s) "
      f"misfiled in the OPEN table to move to the closed table, {stay} stay in the closed table")
if blocked:
    print(f"✗ {len(blocked)} closed row(s) still in the OPEN table ({', '.join(ids(blocked))}): the closed table "
          f"{'has no header' if hdr is None else 'uses a different schema'} — rewrite each as a closed row by hand; "
          "it then rotates normally")
if mode in ('dry', 'check') or not (to_archive or to_closed):
    for tag, rows in (("archive", to_archive), ("closed table", to_closed)):
        if rows: print(f"  → {tag}: {', '.join(ids(rows)[:12])}{' …' if len(rows) > 12 else ''}")
    if mode == 'check' and (to_archive or to_closed):
        print("✗ rotation due — run scripts/rotate-bug-register.sh (verbatim move; ids are conserved)")
    sys.exit(1 if (blocked or (mode == 'check' and (to_archive or to_closed))) else 0)

out = [l for _, l in keep]
if to_closed:
    kept_idx = [i for i, _ in keep]
    last_row = max((k for k, (i, l) in enumerate(keep) if i > ci and ROW.match(l)), default=None)
    if last_row is None:  # empty closed table: insert after its |---| separator
        last_row = next((k for k, (i, l) in enumerate(keep) if i > ci and l.startswith('|---')), None)
        if last_row is None:  # reachable when the open table's header isn't a literal "| ID" (schema then unprovable); never crash
            print("✗ the closed section has no table to move rows into — refusing to touch anything"); sys.exit(1)
    out = out[:last_row + 1] + [l for _, l in to_closed] + out[last_row + 1:]

try:
    arc = open(ARC).read()
except FileNotFoundError:
    arc = (
        "# Bug register — ARCHIVE of long-settled closed rows\n\n"
        "> Rows rotate here from the live bug register by `scripts/rotate-bug-register.sh`\n"
        "> once CLOSED and untouched for the cutoff period. Rows are\n"
        "> VERBATIM — same columns, same ids; a `BUG-NNN` lives in exactly one of the two files.\n"
        "> Anything that counts bugs must read both files. Append-only; never reopen a row\n"
        "> here — a regression is a NEW bug row in the live register citing the old id.\n\n"
        # the archive's columns are the CLOSED table's (that is what rotates here), copied from the register itself
        + ((hdr.rstrip() + "\n" + "|" + "---|" * len([c for c in cells(hdr.strip())[1:] if c or not hdr.strip().endswith('|')]) + "\n") if hdr else
           "| ID | Sev | Found → Closed | Summary | Fix (commit) | Verified by | Escape analysis |\n"
           "|---|---|---|---|---|---|---|\n"))
if to_archive:
    open(ARC, 'w').write(arc.rstrip('\n') + '\n' + '\n'.join(l for _, l in to_archive) + '\n')
open(REG, 'w').write('\n'.join(out))
moved = ids(to_archive) + ids(to_closed)
print(f"moved: {', '.join(moved[:8])}{' …' if len(moved) > 8 else ''}")
sys.exit(1 if blocked else 0)  # rows still waiting for a hand rewrite: same answer as --check and --dry-run
PY
