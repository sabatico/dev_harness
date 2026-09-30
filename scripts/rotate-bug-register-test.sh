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
printf 'HARNESS_BUG_REGISTER=""\n' > "$T/harness.conf"
bash "$T/scripts/rotate-bug-register.sh" --check >/dev/null 2>&1; rc=$?
chk "no register configured → N/A (exit 4), not a pass" "[ $rc -eq 4 ]"

echo "rotate-bug-register matrix: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
