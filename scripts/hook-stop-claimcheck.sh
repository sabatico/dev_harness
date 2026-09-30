#!/usr/bin/env bash
# hook-stop-claimcheck.sh — Stop hook: verify the checkable claims (paths, decision/bug ids, attributed
# quotes) in the reply that just ended. Logic and its WHY: scripts/claim-check.py. This wrapper exports
# harness.conf so the python sees the project's decision dir, bug register, corpus and log dir.
# Advisory by default (HARNESS_CLAIMCHECK_MODE=block makes the model self-correct once).
# Test: scripts/hook-stop-claimcheck-test.sh (a fast-tier gate).
set -uo pipefail
ROOT="${HARNESS_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null)}" || exit 0
cd "$ROOT" || exit 0
HERE="$(cd "$(dirname "$0")" && pwd)"
set -a; [ -f harness.conf ] && . ./harness.conf; set +a
HARNESS_ROOT_OVERRIDE="$ROOT" python3 "$HERE/claim-check.py" 2>/dev/null
exit 0
