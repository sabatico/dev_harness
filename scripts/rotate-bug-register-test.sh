#!/usr/bin/env bash
# rotate-bug-register-test.sh — known-answer matrix for rotate-bug-register.sh (S1 self-proof).
#
# WHY: the rotation moves rows between a home-of-record and its archive. Its failure modes are all
# silent — a row lost, a genuinely OPEN row archived, a misfiled FIXED row never noticed (which is how
# the register reached 523 KB), an unknown flag running a real rotation (it did, 2026-09-29). Each row
# of this matrix pins one of them. Runs on a fixture register in a temp tree; the real one is untouched.
# Gated in run-all-gates.sh (fast tier).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/rbr-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/docs/registers"
cp "$HERE/rotate-bug-register.sh" "$T/scripts/"
printf 'HARNESS_BUG_REGISTER="docs/registers/bug-register.md"\n' > "$T/harness.conf"
export HARNESS_ROOT_OVERRIDE="$T"
OLD=2020-01-01; NEW="$(date +%Y-%m-%d)"
cat > "$T/docs/registers/bug-register.md" <<EOF
# Bug register

## Open bugs

| ID | Sev | Found | Where/how found | Summary | Status | Detail |
|---|---|---|---|---|---|---|
| BUG-001 | P2 | $OLD | x | genuinely open, old | **OPEN.** nobody fixed it | d |
| BUG-002 | P2 | $OLD | x | fixed long ago, misfiled | **FIXED $OLD.** done | d |
| BUG-003 | P2 | $NEW | x | fixed today, misfiled | **FIXED $NEW.** done | d |
| BUG-004 | P2 | $OLD | x | mixed cell stays | **(a) FIXED $OLD; (b) OPEN.** half | d |
| BUG-005 | P2 | $OLD | x | pipe \`a \\| b\` inside a code span | **CLOSED $OLD.** ok | d |
| BUG-006 | P2 | $OLD | x | status mentions OPEN later | **FIXED $OLD** but follow-up still OPEN as BUG-009 | d |
| BUG-007 | P2 | $OLD | x | partly closed stays | **PARTLY CLOSED $OLD.** rest pending | d |

## Closed bugs (append-only)

| ID | Sev | Found | Where/how found | Summary | Status | Detail |
|---|---|---|---|---|---|---|
| BUG-008 | P3 | $OLD | x | closed long ago | FIXED | d |

### Escape analysis prose stays here.
EOF
printf '# Archive\n\n| ID | Sev | Found | Where/how found | Summary | Status | Detail |\n|---|---|---|---|---|---|---|\n' > "$T/docs/registers/bug-register-archive.md"
cp "$T/docs/registers/bug-register.md" "$T/reg.orig"
pass=0; fail=0
chk() { if eval "$2"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  $1"; fi; }
REG="$T/docs/registers/bug-register.md"; ARC="$T/docs/registers/bug-register-archive.md"
sec() { awk -v h="$2" 'index($0,h)==1{f=1;next} /^## /{f=0} f' "$1"; }   # rows of one section

bash "$T/scripts/rotate-bug-register.sh" --help >/dev/null 2>&1; rc=$?
chk "unknown flag is an error (exit 2)"          "[ $rc -eq 2 ]"
chk "unknown flag touched nothing"                "cmp -s '$REG' '$T/reg.orig'"
bash "$T/scripts/rotate-bug-register.sh" --check >/dev/null 2>&1; rc=$?
chk "--check fails while rotation is due"         "[ $rc -eq 1 ]"
chk "--check touched nothing"                     "cmp -s '$REG' '$T/reg.orig'"
bash "$T/scripts/rotate-bug-register.sh" --dry-run >/dev/null 2>&1
chk "--dry-run touched nothing"                   "cmp -s '$REG' '$T/reg.orig'"

bash "$T/scripts/rotate-bug-register.sh" >/dev/null 2>&1
chk "OPEN row never moves"                        "sec '$REG' '## Open' | grep -q 'BUG-001'"
chk "old FIXED row in the open table → archive"   "grep -q 'BUG-002' '$ARC' && ! grep -q 'BUG-002' '$REG'"
chk "recent FIXED row → the CLOSED table"         "sec '$REG' '## Closed' | grep -q 'BUG-003' && ! sec '$REG' '## Open' | grep -q 'BUG-003'"
chk "mixed FIXED/OPEN cell stays open"            "sec '$REG' '## Open' | grep -q 'BUG-004'"
chk "escaped pipe: status read correctly → moves" "grep -q 'BUG-005' '$ARC'"
chk "OPEN anywhere in the status cell stays"      "sec '$REG' '## Open' | grep -q 'BUG-006'"
chk "PARTLY CLOSED stays"                         "sec '$REG' '## Open' | grep -q 'BUG-007'"
chk "old closed-table row → archive (R11 policy)" "grep -q 'BUG-008' '$ARC'"
chk "moved rows are VERBATIM"                     "grep -qxF \"\$(grep '^| BUG-002' '$T/reg.orig')\" '$ARC'"
chk "escape-analysis prose stays"                 "grep -q 'Escape analysis prose stays here' '$REG'"
chk "recent row lands BEFORE the prose"           "awk '/BUG-003/{r=NR} /Escape analysis/{p=NR} END{exit !(r<p)}' '$REG'"
ids() { grep -ohE '^\| BUG-[0-9]+' "$@" | sort; }
chk "every id conserved, none duplicated"         "[ \"\$(ids '$T/reg.orig')\" = \"\$(ids '$REG' '$ARC')\" ]"
bash "$T/scripts/rotate-bug-register.sh" --check >/dev/null 2>&1; rc=$?
chk "--check passes once rotated"                 "[ $rc -eq 0 ]"

# ── kit-only: a closed table with a DIFFERENT schema (the kit's own template) ──
cat > "$REG" <<EOF2
## Open bugs

| ID | Sev | Found | Where/how found | Summary | Status | Detail |
|---|---|---|---|---|---|---|
| BUG-010 | P2 | $NEW | x | fixed today, misfiled | **FIXED $NEW.** done | d |

## Closed bugs (append-only)

| ID | Sev | Found → Closed | Summary | Fix (commit) | Verified by | Escape |
|---|---|---|---|---|---|---|
EOF2
bash "$T/scripts/rotate-bug-register.sh" >/dev/null 2>&1; rc=$?
chk "schema mismatch: recent misfiled row is NOT moved verbatim" "[ $rc -eq 1 ] && awk '/^## Open/{f=1} /^## Closed/{f=0} f && /BUG-010/{ok=1} END{exit !ok}' '$REG'"

# ── a NEW archive file takes the CLOSED table's columns (2026-10-03 fix) ──
# The archive receives closed-table rows, so a freshly created archive must carry the closed table's
# header — until the fix it was hard-coded to the OPEN-table schema. A 5-column closed table makes a
# wrong header AND a wrong separator width visible at once.
rm -f "$ARC"
cat > "$REG" <<EOF3
## Open bugs

| ID | Sev | Found | Where/how found | Summary | Status | Detail |
|---|---|---|---|---|---|---|
| BUG-019 | P2 | $OLD | x | genuinely open | **OPEN.** pending | d |

## Closed bugs (append-only)

| ID | Sev | Closed | Summary | Fix (commit) |
|---|---|---|---|---|
| BUG-020 | P3 | $OLD | closed long ago | abc123 |
EOF3
bash "$T/scripts/rotate-bug-register.sh" >/dev/null 2>&1; rc=$?
chk "new archive: created, the old closed row rotated (positive control)" "[ $rc -eq 0 ] && grep -q '^| BUG-020' '$ARC' && ! grep -q 'BUG-020' '$REG'"
chk "new archive: header == the register's CLOSED-table header" "[ \"\$(grep -m1 '^| ID' '$ARC')\" = '| ID | Sev | Closed | Summary | Fix (commit) |' ]"
chk "new archive: separator width == closed-table column count" "awk '/^\\| ID/{h=NR} h && NR==h+1{print; exit}' '$ARC' | grep -qx '|---|---|---|---|---|'"
chk "new archive: the row sits directly under that header"     "awk '/^\\| ID/{h=NR} h && NR==h+2{print; exit}' '$ARC' | grep -q '^| BUG-020'"

# ── an OLD closed row misfiled in the OPEN table, schemas DIFFER → not archived verbatim ──
# Archiving it would land open-table cells under closed-table columns; it must wait for the same hand
# rewrite as a recent misfiled row, and the message must name it.
rm -f "$ARC"
cat > "$REG" <<EOF4
## Open bugs

| ID | Sev | Found | Where/how found | Summary | Status | Detail |
|---|---|---|---|---|---|---|
| BUG-030 | P2 | $OLD | x | fixed long ago, misfiled | **FIXED $OLD.** done | d |

## Closed bugs (append-only)

| ID | Sev | Found → Closed | Summary | Fix (commit) | Verified by | Escape |
|---|---|---|---|---|---|---|
EOF4
cp "$REG" "$T/reg.b1"
bash "$T/scripts/rotate-bug-register.sh" >"$T/out.b1" 2>&1; rc=$?
chk "schema mismatch, OLD misfiled row alone: refused (exit 1)"   "[ $rc -eq 1 ]"
chk "schema mismatch, OLD misfiled row: NOT archived"             "[ ! -e '$ARC' ] || ! grep -q 'BUG-030' '$ARC'"
chk "schema mismatch, OLD misfiled row: register untouched"       "cmp -s '$REG' '$T/reg.b1'"
chk "schema mismatch, OLD misfiled row: the message names it"     "grep -q 'BUG-030' '$T/out.b1' && grep -q 'different schema' '$T/out.b1'"

# same, mixed with a legitimately rotating closed-table row: that one still moves, the misfit stays
rm -f "$ARC"
cat > "$REG" <<EOF5
## Open bugs

| ID | Sev | Found | Where/how found | Summary | Status | Detail |
|---|---|---|---|---|---|---|
| BUG-030 | P2 | $OLD | x | fixed long ago, misfiled | **FIXED $OLD.** done | d |
| BUG-032 | P2 | $NEW | x | fixed today, misfiled | **FIXED $NEW.** done | d |

## Closed bugs (append-only)

| ID | Sev | Found → Closed | Summary | Fix (commit) | Verified by | Escape |
|---|---|---|---|---|---|---|
| BUG-031 | P3 | $OLD → $OLD | closed long ago | abc123 | test | n/a |
EOF5
cp "$REG" "$T/reg.b2"
bash "$T/scripts/rotate-bug-register.sh" >"$T/out.b2" 2>&1
chk "schema mismatch, mixed: the closed-table row still archives (positive control)" "grep -q '^| BUG-031' '$ARC' && ! grep -q 'BUG-031' '$REG'"
chk "schema mismatch, mixed: OLD misfiled row stays in the OPEN table, not archived" "sec '$REG' '## Open' | grep -q 'BUG-030' && ! grep -q 'BUG-030' '$ARC'"
chk "schema mismatch, mixed: RECENT misfiled row stays in the OPEN table"           "sec '$REG' '## Open' | grep -q 'BUG-032' && ! grep -q 'BUG-032' '$ARC'"
chk "schema mismatch, mixed: the message names both blocked rows"                   "grep 'different schema' '$T/out.b2' | grep -q 'BUG-030' && grep 'different schema' '$T/out.b2' | grep -q 'BUG-032'"
chk "schema mismatch, mixed: every id conserved, none duplicated"                   "[ \"\$(ids '$T/reg.b2')\" = \"\$(ids '$REG' '$ARC')\" ]"

# ── SAME schema: an OLD misfiled row still archives (no regression from the fix) ──
rm -f "$ARC"
cat > "$REG" <<EOF6
## Open bugs

| ID | Sev | Found | Where/how found | Summary | Status | Detail |
|---|---|---|---|---|---|---|
| BUG-040 | P2 | $OLD | x | fixed long ago, misfiled | **FIXED $OLD.** done | d |

## Closed bugs (append-only)

| ID | Sev | Found | Where/how found | Summary | Status | Detail |
|---|---|---|---|---|---|---|
| BUG-041 | P3 | $OLD | x | closed long ago | FIXED | d |
EOF6
bash "$T/scripts/rotate-bug-register.sh" >/dev/null 2>&1; rc=$?
chk "same schema: OLD misfiled row → archive (as before)"  "[ $rc -eq 0 ] && grep -q '^| BUG-040' '$ARC' && ! grep -q 'BUG-040' '$REG'"
chk "same schema: OLD closed-table row → archive"          "grep -q '^| BUG-041' '$ARC' && ! grep -q 'BUG-041' '$REG'"
chk "same schema: new archive header == the shared header" "[ \"\$(grep -m1 '^| ID' '$ARC')\" = '| ID | Sev | Found | Where/how found | Summary | Status | Detail |' ]"

# ── the PREVIEW tells the truth: --dry-run / --check say what a real run will do ──
# Until 2026-10-03 the schema check ran after the preview, so --dry-run promised "→ archive: BUG-030" and
# --check said "run rotate-bug-register.sh" for a row the real run then refused.
rm -f "$ARC"
cat > "$REG" <<EOF7
## Open bugs

| ID | Sev | Found | Where/how found | Summary | Status | Detail |
|---|---|---|---|---|---|---|
| BUG-030 | P2 | $OLD | x | fixed long ago, misfiled | **FIXED $OLD.** done | d |

## Closed bugs (append-only)

| ID | Sev | Found → Closed | Summary | Fix (commit) | Verified by | Escape |
|---|---|---|---|---|---|---|
EOF7
cp "$REG" "$T/reg.p"
bash "$T/scripts/rotate-bug-register.sh" --dry-run >"$T/out.dry" 2>&1
bash "$T/scripts/rotate-bug-register.sh" --check >"$T/out.chk" 2>&1; rc=$?
chk "preview: --dry-run does NOT promise to archive a row the real run refuses" "! grep -q 'archive: BUG-030' '$T/out.dry' && grep -q ' 0 closed row(s) to archive' '$T/out.dry'"
chk "preview: --dry-run names the blocked row and why"                           "grep 'different schema' '$T/out.dry' | grep -q 'BUG-030'"
chk "preview: --check still fails (the row needs a hand rewrite)"                "[ $rc -eq 1 ] && grep 'different schema' '$T/out.chk' | grep -q 'BUG-030'"
chk "preview: --check does not tell you to run a rotation that would refuse"     "! grep -q 'rotation due' '$T/out.chk'"
chk "preview: the advice is the hand rewrite, not 'wait for the cutoff'"         "grep -q 'it then rotates normally' '$T/out.dry' && ! grep -q 'once past the cutoff' '$T/out.dry'"
chk "preview: --dry-run and --check touched nothing"                             "cmp -s '$REG' '$T/reg.p' && [ ! -e '$ARC' ]"

# ── a closed section with NO table header cannot prove the schemas match → an OLD misfiled row is blocked ──
rm -f "$ARC"
cat > "$REG" <<EOF8
## Open bugs

| ID | Sev | Found | Where/how found | Summary | Status | Detail |
|---|---|---|---|---|---|---|
| BUG-050 | P2 | $OLD | x | fixed long ago, misfiled | **FIXED $OLD.** done | d |

## Closed bugs (append-only)

(none yet)
EOF8
cp "$REG" "$T/reg.nh"
bash "$T/scripts/rotate-bug-register.sh" >"$T/out.nh" 2>&1; rc=$?
chk "header-less closed section, OLD misfiled row: refused (exit 1), not archived" "[ $rc -eq 1 ] && { [ ! -e '$ARC' ] || ! grep -q 'BUG-050' '$ARC'; }"
chk "header-less closed section, OLD misfiled row: register untouched"            "cmp -s '$REG' '$T/reg.nh'"
chk "header-less closed section, OLD misfiled row: message says why, names it"    "grep 'has no header' '$T/out.nh' | grep -q 'BUG-050'"

# ── a closed section with NO table and a RECENT misfiled row: a clean refusal, never a traceback ──
sed "s/| BUG-050 | P2 | $OLD |/| BUG-060 | P2 | $NEW |/; s/\*\*FIXED $OLD\.\*\*/**FIXED $NEW.**/" "$T/reg.nh" > "$REG"
cp "$REG" "$T/reg.nt"
bash "$T/scripts/rotate-bug-register.sh" >"$T/out.nt" 2>&1; rc=$?
chk "no closed table, RECENT misfiled row: fixture really holds a recent row (positive control)" "grep -q \"^| BUG-060 | P2 | $NEW\" '$T/reg.nt' && ! grep -q '$OLD' '$T/reg.nt'"
chk "no closed table, RECENT misfiled row: no Python traceback"         "! grep -q 'Traceback' '$T/out.nt'"
chk "no closed table, RECENT misfiled row: refused (exit 1), untouched" "[ $rc -eq 1 ] && cmp -s '$REG' '$T/reg.nt'"
chk "no closed table, RECENT misfiled row: message names it"            "grep -q 'BUG-060' '$T/out.nt' && grep -q 'has no header' '$T/out.nt'"
# the same with an OPEN header the script does not recognise ("| Bug", not "| ID"): schema_differs cannot fire,
# so this reaches the separator-less insert path — it must refuse, not crash.
sed 's/^| ID | Sev | Found | Where/| Bug | Sev | Found | Where/' "$T/reg.nt" > "$REG"
cp "$REG" "$T/reg.nt2"
bash "$T/scripts/rotate-bug-register.sh" >"$T/out.nt2" 2>&1; rc=$?
chk "no closed table, unrecognised open header: fixture has no '| ID' header (positive control)" "! grep -q '^| ID' '$T/reg.nt2' && grep -q '^| BUG-060' '$T/reg.nt2'"
chk "no closed table, unrecognised open header: no traceback, refused, untouched" "! grep -q 'Traceback' '$T/out.nt2' && [ $rc -eq 1 ] && cmp -s '$REG' '$T/reg.nt2'"

# ── a real run with one BLOCKED row and one archivable row: moves the good row, then exits 1 naming the blocked
# one (until 2026-10-03 it exited 0 here while --check/--dry-run said 1 — the run looked clean with a row stuck) ──
rm -f "$ARC"
cat > "$REG" <<EOF10
## Open bugs

| ID | Sev | Found | Where/how found | Summary | Status | Detail |
|---|---|---|---|---|---|---|
| BUG-030 | P2 | $OLD | x | fixed long ago, misfiled | **FIXED $OLD.** done | d |

## Closed bugs (append-only)

| ID | Sev | Found → Closed | Summary | Fix (commit) | Verified by | Escape |
|---|---|---|---|---|---|---|
| BUG-031 | P3 | $OLD → $OLD | closed long ago | abc123 | test | n/a |
EOF10
bash "$T/scripts/rotate-bug-register.sh" >"$T/out.mix" 2>&1; rc=$?
chk "blocked + archivable, real run: the archivable row IS archived"            "grep -q '^| BUG-031' '$ARC' && ! grep -q 'BUG-031' '$REG'"
chk "blocked + archivable, real run: the blocked row stays in the OPEN table"   "sec '$REG' '## Open' | grep -q 'BUG-030' && ! grep -q 'BUG-030' '$ARC'"
chk "blocked + archivable, real run: exits 1 (same answer as --check/--dry-run)" "[ $rc -eq 1 ]"
chk "blocked + archivable, real run: the message names the blocked row"         "grep 'different schema' '$T/out.mix' | grep -q 'BUG-030'"

# ── a closed-table header WITHOUT a trailing pipe: the new archive's separator must still match its column count ──
# (until 2026-10-03 it was built as len(cells)-2, which assumes a trailing pipe: one column short, table broken)
rm -f "$ARC"
cat > "$REG" <<EOF9
## Open bugs

| ID | Sev | Found | Where/how found | Summary | Status | Detail |
|---|---|---|---|---|---|---|

## Closed bugs (append-only)

| ID | Sev | Closed | Summary | Fix (commit)
|---|---|---|---|---
| BUG-070 | P3 | $OLD | closed long ago | abc123
EOF9
bash "$T/scripts/rotate-bug-register.sh" >/dev/null 2>&1
chk "no trailing pipe: the old closed row still archives (positive control)" "grep -q '^| BUG-070' '$ARC'"
chk "no trailing pipe: new archive separator has as many columns as its header (5)" \
    "awk '/^\\| ID/{h=NR} h && NR==h+1{print; exit}' '$ARC' | grep -qx '|---|---|---|---|---|\\{0,1\\}'"
printf 'HARNESS_BUG_REGISTER=""\n' > "$T/harness.conf"
bash "$T/scripts/rotate-bug-register.sh" --check >/dev/null 2>&1; rc=$?
chk "no register configured → N/A (exit 4), not a pass" "[ $rc -eq 4 ]"

echo "rotate-bug-register matrix: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
