#!/usr/bin/env bash
# rotate-onboarding-test.sh — known-answer matrix for rotate-onboarding.sh (S1 self-proof).
#
# WHY: the rotation moves text out of the file every session reads first. Both halves of the owner's
# instruction are pinned here — "doesn't keep growing" (old, unmarked, beyond-the-floor items DO move,
# the diet IS enforced) and "don't cut too much" (the newest-N floor and the age floor BOTH have to be
# crossed; a <!-- keep --> block never moves; nothing is lost or reworded on the way).
# Fixture tree in a temp dir, fixed --today; the real ONBOARDING is untouched. Gated (fast tier).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/ro-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/docs/ai"
cp "$HERE/rotate-onboarding.sh" "$T/scripts/"
printf 'HARNESS_ONBOARDING="ONBOARDING.md"\nHARNESS_ONB_LOG_HEADING="## 10."\nHARNESS_ONB_NEXT_HEADING="## 6b."\nHARNESS_ONB_ARCHIVE="docs/ai/session-log-archive.md"\n' > "$T/harness.conf"
export HARNESS_ROOT_OVERRIDE="$T"
ONB="$T/ONBOARDING.md"; ARC="$T/docs/ai/session-log-archive.md"
fixture() {
cat > "$ONB" <<'EOF'
# Onboarding

## 6b. What happens NEXT

Intro line that is not a dated block.

> **2026-09-20 — newest handover.** keep by floor.

> **2026-09-10 — second.** keep by floor.

> **2026-09-01 — third.** keep by floor even though it is old.

> **2026-08-15 — standing pack, still open.** <!-- keep: pre-launch pack still in work -->
> second line of the standing block.

> **2026-08-01 — old handover, done.** should move.
> its second line.

## 7. Next section

Untouched text.

## 10. Session log

### 2026-09-25 — e1
body e1

### 2026-09-20 — e2
body e2

### 2026-09-18 — e3
body e3

### 2026-09-10 — e4
body e4

### 2026-09-05 — e5
body e5

### 2026-09-04 — e6 young beyond floor
body e6

### 2026-08-01 — e7 old beyond floor
body e7
> ⚠ section footer note stays.
EOF
printf '# Archive\n\n> intro\n\n## Older entries\n\n### 2026-07-01 — ancient\nold body\n' > "$ARC"
}
pass=0; fail=0
chk() { if eval "$2"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  $1"; fi; }
RO() { bash "$T/scripts/rotate-onboarding.sh" --today 2026-09-29 "$@"; }
sec() { awk -v h="$2" 'index($0,h)==1{f=1;next} /^## /{f=0} f' "$1"; }

fixture; cp "$ONB" "$T/onb.orig"; cp "$ARC" "$T/arc.orig"
RO --bogus >/dev/null 2>&1; rc=$?
chk "unknown flag is an error (exit 2)"       "[ $rc -eq 2 ] && cmp -s '$ONB' '$T/onb.orig'"
RO --limits >/dev/null 2>&1; rc=$?
chk "--limits passes: diet ok, order ok"       "[ $rc -eq 0 ]"
RO --check >/dev/null 2>&1; rc=$?
chk "--check fails while rotation is due"      "[ $rc -eq 1 ] && cmp -s '$ONB' '$T/onb.orig'"
RO --dry-run >/dev/null 2>&1
chk "--dry-run touches nothing"                "cmp -s '$ONB' '$T/onb.orig' && cmp -s '$ARC' '$T/arc.orig'"

RO >/dev/null 2>&1
chk "§10 old AND beyond the floor → archive"   "grep -q 'e7 old beyond floor' '$ARC' && ! grep -q 'e7 old' '$ONB'"
chk "§10 beyond the floor but YOUNG stays"     "grep -q 'e6 young beyond floor' '$ONB'"
chk "§10 newest-5 floor stays"                 "( for e in e1 e2 e3 e4 e5; do grep -q \"— \$e\$\" '$ONB' || exit 1; done )"
chk "§10 footer note stays in §10"             "sec '$ONB' '## 10.' | grep -q 'section footer note stays'"
chk "§6b old unmarked beyond floor → archive"  "grep -q 'old handover, done' '$ARC' && ! grep -q 'old handover, done' '$ONB'"
chk "§6b block moved with ALL its lines"       "grep -q 'its second line' '$ARC' && ! grep -q 'its second line' '$ONB'"
chk "§6b <!-- keep --> block never moves"      "grep -q 'standing pack, still open' '$ONB' && ! grep -q 'standing pack' '$ARC'"
chk "§6b newest-3 floor holds even when old"   "grep -q 'third.' '$ONB'"
chk "§6b non-dated intro stays"                "grep -q 'Intro line that is not a dated block' '$ONB'"
chk "other sections untouched"                 "grep -q 'Untouched text' '$ONB'"
chk "archive: rotated chunk goes above older entries" "awk '/Rotated from ONBOARDING/{r=NR} /## Older entries/{o=NR} END{exit !(r && r<o)}' '$ARC'"
chk "archive: existing entries unchanged"      "grep -q 'ancient' '$ARC' && grep -q 'old body' '$ARC'"
ml() { grep -hv '^$' "$@" | grep -v '^## Rotated\|^### §6b handover blocks retired\|^> §10 session-log entries beyond' | sort; }
chk "nothing lost, nothing reworded (line multiset conserved)" "[ \"\$(ml '$T/onb.orig' '$T/arc.orig')\" = \"\$(ml '$ONB' '$ARC')\" ]"
RO --check >/dev/null 2>&1; rc=$?
chk "--check passes after rotating"            "[ $rc -eq 0 ]"

# The newest-N floor ALONE: with a 1-day age limit everything is "old", so only the floor protects.
# (Mutation-found 2026-09-29: in the run above every floor-protected item was also young, so deleting
# the floor changed nothing and no row noticed.)
fixture; RO --log-days 1 --handover-days 1 >/dev/null 2>&1
chk "floor alone: §10 newest 5 stay when all are old"  "( for e in e1 e2 e3 e4 e5; do grep -q \"— \$e\$\" '$ONB' || exit 1; done )"
chk "floor alone: §10 6th newest moves when old"       "grep -q 'e6 young beyond floor' '$ARC'"
chk "floor alone: §6b newest 3 stay when all are old"  "grep -q 'newest handover' '$ONB' && grep -q 'second.' '$ONB' && grep -q 'third.' '$ONB'"

# diet + order violations
fixture
python3 - "$ONB" <<'EOF'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("body e3\n", "".join(f"line {i}\n" for i in range(12)))       # 12 lines > 10
open(p,"w").write(s)
EOF
RO --limits >/dev/null 2>&1; rc=$?
chk "--limits fails on an over-long §10 entry" "[ $rc -eq 1 ]"
cp "$ONB" "$T/onb.fat"; RO >/dev/null 2>&1; rc=$?
chk "apply refuses to archive a diet violation" "[ $rc -eq 1 ] && cmp -s '$ONB' '$T/onb.fat'"
fixture
python3 - "$ONB" <<'EOF'
import sys; p=sys.argv[1]; s=open(p).read()
a="### 2026-09-25 — e1\nbody e1\n\n"; b="### 2026-09-20 — e2\nbody e2\n\n"
s=s.replace(a+b, b+a); open(p,"w").write(s)
EOF
RO --limits >/dev/null 2>&1; rc=$?
chk "--limits fails when §10 is not newest-first" "[ $rc -eq 1 ]"
RO --log-days 99999 --handover-days 99999 >/dev/null 2>&1
chk "apply re-sorts §10 newest-first"          "awk '/— e1\$/{a=NR} /— e2\$/{b=NR} END{exit !(a<b)}' '$ONB'"

# ── kit-only: archive created on first rotation; unconfigured → N/A ──
fixture; rm -f "$ARC"; RO >/dev/null 2>&1
chk "missing archive is created, with the rotated entry" "grep -q 'e7 old beyond floor' '$ARC' && grep -q 'Append-only' '$ARC'"
printf 'HARNESS_ONBOARDING=""\n' > "$T/harness.conf"
RO --check >/dev/null 2>&1; rc=$?
chk "no onboarding configured → N/A (exit 4)" "[ $rc -eq 4 ]"

echo "rotate-onboarding matrix: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
