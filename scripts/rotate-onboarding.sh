#!/usr/bin/env bash
# rotate-onboarding.sh — keep the onboarding file a HANDOVER, not an archive: rotate old session-log
# entries and old dated handover blocks, VERBATIM, into the session-log archive.
# Generalised 2026-09-29 from a live project. Config (harness.conf): HARNESS_ONBOARDING (the file),
# HARNESS_ONB_LOG_HEADING (default "## 8."), HARNESS_ONB_NEXT_HEADING (default "## 6."),
# HARNESS_ONB_ARCHIVE (default <dir>/session-log-archive.md, created on first rotation).
# In the notes below, "§10" = the session-log section and "§6b" = the what-happens-next section.
# Exit: 0 ok · 1 due/violation · 2 usage · 4 N/A (not configured).
#
# WHY (the live project's owner, 2026-09-29: "make sure our onboarding file has good cleaning procedures and doesnt stuck
# growing with all old handovers, but we must be careful to not cut too much of history so that the
# handovers be meaningful"). ONBOARDING is the file every session is told to read first; §9b already
# sets a 120 KB budget and says "archive by the calendar, not when it hurts" — but archiving was a
# PROSE step, and the librarian pass of 2026-09-29 found what prose steps become:
#   · §10's two retirement rules contradict each other — "CAPPED AT THE THREE NEWEST ENTRIES
#     (owner-directed 2026-08-01)" vs §9b rule 3 "at each month's end, move that month's entries";
#     §10 held 9 entries, not newest-first.
#   · CLAUDE.md says the §10 per-entry diet (≤10 lines AND ≤2 KB) is "gated". Nothing checked it.
#   · NOTHING retires §6b: dated handover blocks back to 2026-07-31 (14.6 KB), one of them 70 lines.
#
# POLICY — two floors, so history is never cut thin (the owner's "careful" half):
#   §10  an entry rotates only if it is BOTH beyond the newest --log-keep (default 5) AND older than
#        --log-days (default 30). A busy fortnight keeps everything; a quiet month still keeps 5.
#   §6b  a dated block ("> **YYYY-MM-DD…") rotates only if BOTH beyond the newest --handover-keep
#        (default 3) AND older than --handover-days (default 30) AND it carries no <!-- keep --> marker.
#        The marker is for STANDING items (an open owner call, a pack still being worked) — age alone
#        cannot tell a stale handover from a live one, so the author says which, once.
# Nothing is deleted: moved text is byte-identical in the archive, under a dated "Rotated from
# ONBOARDING" heading, newest first, the way the 2026-08-01 and 2026-08-28 rotations were done
# (session-log-archive.md: "Nothing was edited on the way").
#
# --check is the GATE: fails if a §10 entry breaks the diet, §10 is not newest-first, or anything is
# due. --limits only checks the diet + order (safe to gate before a retention policy is ratified).
# Unknown arguments are an ERROR (a sibling script's silent skip once ran a real rotation).
#
# Usage:
#   scripts/rotate-onboarding.sh --dry-run          # show what would move; touch nothing
#   scripts/rotate-onboarding.sh                    # rotate (and re-sort §10 newest-first)
#   scripts/rotate-onboarding.sh --check            # gate: diet + order + nothing due
#   scripts/rotate-onboarding.sh --limits           # gate: diet + order only
#   options: --log-keep N --log-days D --handover-keep N --handover-days D --today YYYY-MM-DD
# Test: scripts/rotate-onboarding-test.sh (a fast-tier gate).
set -euo pipefail
ROOT="${HARNESS_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "$0")/.." && pwd))}"
cd "$ROOT"
[ -f harness.conf ] && . ./harness.conf
ONB_PATH="${HARNESS_ONBOARDING:-}"
LOG_H="${HARNESS_ONB_LOG_HEADING:-## 8.}"; NEXT_H="${HARNESS_ONB_NEXT_HEADING:-## 6.}"
ARC_PATH="${HARNESS_ONB_ARCHIVE:-$(dirname "${ONB_PATH:-x}")/session-log-archive.md}"

MODE=apply; LOG_KEEP=5; LOG_DAYS=30; HO_KEEP=3; HO_DAYS=30; TODAY="$(date +%Y-%m-%d)"
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) MODE=dry; shift ;;
  --check) MODE=check; shift ;;
  --limits) MODE=limits; shift ;;
  --log-keep) LOG_KEEP="$2"; shift 2 ;;
  --log-days) LOG_DAYS="$2"; shift 2 ;;
  --handover-keep) HO_KEEP="$2"; shift 2 ;;
  --handover-days) HO_DAYS="$2"; shift 2 ;;
  --today) TODAY="$2"; shift 2 ;;
  *) echo "rotate-onboarding.sh: unknown argument '$1'" >&2; exit 2 ;;
esac; done

if [ -z "$ONB_PATH" ] || [ ! -f "$ONB_PATH" ]; then
  echo "N/A — no onboarding file configured (HARNESS_ONBOARDING) or file missing: ${ONB_PATH:-unset}"; exit 4
fi
python3 - "$MODE" "$LOG_KEEP" "$LOG_DAYS" "$HO_KEEP" "$HO_DAYS" "$TODAY" "$ONB_PATH" "$ARC_PATH" "$LOG_H" "$NEXT_H" <<'PY'
import os, re, sys
from datetime import date, timedelta
mode, log_keep, log_days, ho_keep, ho_days, today = sys.argv[1], *map(int, sys.argv[2:6]), sys.argv[6]
ONB, ARC, LOG_H, NEXT_H = sys.argv[7:11]
DATE = re.compile(r"20\d\d-\d\d-\d\d")
t = date.fromisoformat(today)
log_cut = (t - timedelta(days=log_days)).isoformat()
ho_cut = (t - timedelta(days=ho_days)).isoformat()

L = open(ONB, encoding="utf-8").read().split("\n")

# harness:allow-uncited — plumbing: [start, end) of the section whose heading starts with prefix;
# a missing section REFUSES (exit 1) rather than rotating nothing and reporting success.
def section(prefix):
    s = next((i for i, l in enumerate(L) if l.startswith(prefix)), None)
    if s is None:
        print(f"✗ no '{prefix}' section in {ONB} — refusing to touch anything"); sys.exit(1)
    e = next((i for i in range(s + 1, len(L)) if L[i].startswith("## ")), len(L))
    return s, e

# ── §10: entries = ### blocks; a trailing run of '>' lines at section end is the section footer ──
s10, e10 = section(LOG_H)
foot = e10
while foot - 1 > s10 and (L[foot - 1].startswith(">") or not L[foot - 1].strip()):
    foot -= 1
heads = [i for i in range(s10 + 1, foot) if L[i].startswith("### ")]
pre10 = L[s10 + 1:heads[0]] if heads else L[s10 + 1:foot]
entries = []
for k, h in enumerate(heads):
    j = heads[k + 1] if k + 1 < len(heads) else foot
    m = DATE.search(L[h])
    entries.append({"lines": L[h:j], "date": m.group(0) if m else "0000-00-00", "head": L[h][4:80]})

problems = []
for en in entries:
    body = [x for x in en["lines"][1:] if x.strip()]
    nb = sum(len(x.encode()) + 1 for x in body)
    if len(body) > 10 or nb > 2048:
        problems.append(f"§10 diet: '{en['head']}' is {len(body)} lines / {nb} B (limit 10 lines AND 2048 B)")
    if en["date"] == "0000-00-00":
        problems.append(f"§10: entry heading has no YYYY-MM-DD date: '{en['head']}'")
order = sorted(range(len(entries)), key=lambda k: entries[k]["date"], reverse=True)  # stable
if order != list(range(len(entries))):
    problems.append("§10 is not newest-first (" + " → ".join(entries[k]["date"] for k in range(len(entries))) + ")")
entries_sorted = [entries[k] for k in order]
log_move = [en for n, en in enumerate(entries_sorted) if n >= log_keep and en["date"] < log_cut]
log_stay = [en for en in entries_sorted if en not in log_move]

# ── §6b: dated blockquote blocks ─────────────────────────────────────────────────────────────
s6, e6 = section(NEXT_H)
starts = [i for i in range(s6 + 1, e6) if re.match(r"^>\s*\*\*20\d\d-\d\d-\d\d", L[i])]
blocks = []
for k, b in enumerate(starts):
    j = starts[k + 1] if k + 1 < len(starts) else e6
    while j - 1 > b and not L[j - 1].strip():   # trailing blank lines belong to the gap, not the block
        j -= 1
    txt = L[b:j]
    blocks.append({"start": b, "end": j, "lines": txt, "date": DATE.search(L[b]).group(0),
                   "keep": any("<!-- keep" in x for x in txt), "head": re.sub(r"[>*\s]+", " ", L[b])[:90].strip()})
by_new = sorted(blocks, key=lambda b: b["date"], reverse=True)
ho_move = [b for n, b in enumerate(by_new) if n >= ho_keep and b["date"] < ho_cut and not b["keep"]]

due = bool(log_move or ho_move)
print(f"ONBOARDING {sum(len(x.encode()) + 1 for x in L)} B · §10 {len(entries)} entries (keep ≥{log_keep}, "
      f"rotate only if older than {log_cut}) · §6b {len(blocks)} dated blocks (keep ≥{ho_keep}, rotate only "
      f"if older than {ho_cut} and unmarked; {sum(b['keep'] for b in blocks)} marked keep)")
for p in problems: print("  ✗", p)
for en in log_move: print(f"  → §10 to archive: {en['head']}")
for b in ho_move: print(f"  → §6b to archive: {b['head']} ({len(b['lines'])} lines)")
if mode == "limits":
    sys.exit(1 if problems else 0)
if mode == "check":
    if due: print("✗ rotation due — run scripts/rotate-onboarding.sh (verbatim move to the archive)")
    sys.exit(1 if problems or due else 0)
if mode == "dry" or (not due and order == list(range(len(entries)))):
    sys.exit(0)
if any(p.startswith("§10 diet") or "no YYYY" in p for p in problems):
    print("✗ fix the §10 diet problems first — rotating an over-size entry would archive the violation")
    sys.exit(1)

# ── write: ONBOARDING first computed in full, then the archive, each as one whole-file write ─────
drop = set()
for b in ho_move:
    drop.update(range(b["start"], b["end"]))
    k = b["end"]
    while k < e6 and not L[k].strip():   # take the blank separator with the block
        drop.add(k); k += 1
new6 = [L[i] for i in range(s6 + 1, e6) if i not in drop]
new10 = pre10 + [x for en in log_stay for x in en["lines"]] + L[foot:e10]
out = L[:s6 + 1] + new6 + L[e6:s10 + 1] + new10 + L[e10:]

if os.path.isfile(ARC):
    arc = open(ARC, encoding="utf-8").read().split("\n")
else:
    arc = ["# Session log ARCHIVE", "", "> Append-only. Entries rotate here VERBATIM from the onboarding file",
           "> (scripts/rotate-onboarding.sh), newest first; never edit an existing entry.", ""]
ins = next((i for i, l in enumerate(arc) if i > 0 and (l.startswith("## ") or l.startswith("### "))), len(arc))
chunk = [f"## Rotated from ONBOARDING on {today} (scripts/rotate-onboarding.sh — verbatim, newest first)", ""]
if log_move:
    chunk += [f"> §10 session-log entries beyond the newest {log_keep} and older than {log_cut}.", ""]
    for en in log_move: chunk += en["lines"] + ([""] if en["lines"][-1].strip() else [])
if ho_move:
    chunk += [f"### §6b handover blocks retired {today} (beyond the newest {ho_keep}, older than {ho_cut}, not marked keep)", ""]
    for b in sorted(ho_move, key=lambda b: b["date"], reverse=True): chunk += b["lines"] + [""]
open(ONB, "w", encoding="utf-8").write("\n".join(out))
if log_move or ho_move:
    open(ARC, "w", encoding="utf-8").write("\n".join(arc[:ins] + chunk + arc[ins:]))
print(f"rotated: {len(log_move)} §10 entr(y/ies), {len(ho_move)} §6b block(s)"
      + ("; §10 re-sorted newest-first" if order != list(range(len(entries))) else ""))
PY
