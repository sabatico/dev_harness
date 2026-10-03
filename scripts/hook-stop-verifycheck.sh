#!/usr/bin/env bash
# hook-stop-verifycheck.sh — Stop hook: flag a turn that changed code and then finished without running
# anything that checks it. Logic and its WHY: scripts/verify-check.py. This wrapper loads the stack pack
# (for HARNESS_CODE_EXTS / HARNESS_TEST_CMD) and harness.conf, and exports them to the python.
# Advisory by default (HARNESS_VERIFYCHECK_MODE=block makes the model verify or say it did not, once).
# Test: scripts/hook-stop-verifycheck-test.sh (a fast-tier gate).
set -uo pipefail
# HERE before any cd: with a relative $0 (a matrix, a hand run) the cd would orphan it.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${HARNESS_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null)}" || exit 0
cd "$ROOT" || exit 0
set -a
# The pack supplies the language's extensions and test command; harness.conf wins over it.
pack="$(sed -n 's/^[[:space:]]*HARNESS_STACK=["'"'"']\{0,1\}\([A-Za-z0-9_-]\{1,\}\).*/\1/p' harness.conf 2>/dev/null | tail -1)"
[ -f "$HERE/stacks/generic.conf" ] && . "$HERE/stacks/generic.conf"
[ -n "$pack" ] && [ -f "$HERE/stacks/$pack.conf" ] && . "$HERE/stacks/$pack.conf"
[ -f harness.conf ] && . ./harness.conf
set +a
HARNESS_ROOT_OVERRIDE="$ROOT" python3 "$HERE/verify-check.py" 2>/dev/null
exit 0
