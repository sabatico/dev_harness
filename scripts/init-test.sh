#!/usr/bin/env bash
# init-test.sh — known-answer test for scripts/init.sh: an initialised project must still pass its doc
# gates AFTER the kit's originals are removed, as init's closing advice tells the owner to do.
#
# WHY THIS EXISTS: the kit's docs are gated in the KIT layout (running-files/, ci/, dot-claude/), and init
# copies them into the INSTALLED layout (docs/, docs/ci/, .claude/). A kit-layout path left in a copied
# doc still resolves while the originals sit beside the copies, so init, its fresh baseline and every
# gate all pass, until the owner runs the advised removal. Then the doc-paths gate goes red in a
# project that changed nothing: 11 violations on the first real install (AnyTutor, 2026-10-07). Nothing
# in the kit ran init and then removed the originals, so nothing could see it.
#
# It works on a COPY of this kit's working tree (tracked + untracked, .gitignore respected, so an
# uncommitted edit is tested too), never on the kit itself. Exit 0 all rows pass · 1 a row failed ·
# 3 could not run · 4 not the kit (an installed project has no originals to remove: nothing to test).
#
#   scripts/init-test.sh            # the generic stack
#   scripts/init-test.sh python     # init with a named stack pack
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$HERE/.." && pwd)"
STACK="${1:-generic}"

for d in running-files ci dot-claude; do
  [ -d "$KIT/$d" ] || { echo "init-test: N/A — $d/ is absent, so this is an installed project, not the kit"; exit 4; }
done
command -v git >/dev/null 2>&1 || { echo "init-test: INCOMPLETE — git is not on PATH"; exit 3; }

# macOS `mktemp -d` ignores TMPDIR; the template keeps every kit test on the same temp root.
T="$(mktemp -d "${TMPDIR:-/tmp}/init-test.XXXXXX")" || { echo "init-test: INCOMPLETE — cannot create a temp dir"; exit 3; }
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P"
pass=0; fail=0
ok() { if [ "$2" = 0 ]; then pass=$((pass+1)); echo "  ok    $1"; else fail=$((fail+1)); echo "  FAIL  $1"; [ -n "${3:-}" ] && printf '%s\n' "$3" | sed 's/^/        /'; fi; }
gate() { ( cd "$P" && bash "scripts/$1" 2>&1 ); }

# The copy is what a fresh clone holds: no .git history and no per-machine .claude/ (a maintainer's
# local .claude/ once made `.claude/...` path claims resolve here and nowhere else).
copied=0
while IFS= read -r -d '' f; do
  [ -f "$KIT/$f" ] || continue          # tracked but deleted in the working tree
  mkdir -p "$P/$(dirname "$f")" && cp -p "$KIT/$f" "$P/$f" && copied=$((copied+1))
done < <(git -C "$KIT" ls-files -z --cached --others --exclude-standard)
[ "$copied" -gt 0 ] || { echo "init-test: INCOMPLETE — copied no files from $KIT (is it a git work tree?)"; exit 3; }
git -C "$P" init -q . || { echo "init-test: INCOMPLETE — git init failed in the copy"; exit 3; }

echo "-- init into a copy of the kit ($copied files, stack $STACK)"
OUT="$(cd "$P" && bash scripts/init.sh "Init Test" P3 "$STACK" 2>&1)"; RC=$?
ok "init.sh exits 0" "$RC" "$(printf '%s\n' "$OUT" | tail -5)"
[ "$RC" = 0 ] || { echo "init-test: $pass passed, $fail failed"; exit 1; }
ok "its closing advice names every kit original to remove (running-files ci dot-claude)" \
  "$(printf '%s\n' "$OUT" | grep -q 'git rm -r running-files ci dot-claude'; echo $?)"

OUT="$(gate check-doc-paths.sh)"; ok "doc-paths passes straight after init" $? "$OUT"
BL="$P/.harness/baselines/doc-paths.txt"
FROZEN="$(grep -v '^#' "$BL" 2>/dev/null | grep -c .)"
ok "init's fresh doc-paths baseline freezes nothing (a frozen miss in a new install is a kit doc bug)" \
  "$([ "${FROZEN:-0}" = 0 ]; echo $?)" "$(grep -v '^#' "$BL" 2>/dev/null)"

echo "-- remove the kit originals, as the advice says"
rm -rf "$P/running-files" "$P/ci" "$P/dot-claude"
OUT="$(gate check-doc-paths.sh)"; ok "doc-paths passes with running-files/, ci/ and dot-claude/ gone" $? "$OUT"
OUT="$(gate check-doc-links.sh)"; ok "doc-links passes with the originals gone" $? "$OUT"
OUT="$(gate check-skills.sh)";    ok "skills passes on the installed .claude/ with the originals gone" $? "$OUT"
# The gate sees only paths that fail to resolve; this row sees the rewrite itself, including a kit path
# that happens to resolve by accident in the installed layout.
LEFT="$(grep -rnE '`(running-files|dot-claude|ci)/' "$P/docs" 2>/dev/null | sed "s|^$P/||")"
ok "no copied doc still cites a kit-layout path in backticks" "$([ -z "$LEFT" ]; echo $?)" "$LEFT"

echo "init-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
