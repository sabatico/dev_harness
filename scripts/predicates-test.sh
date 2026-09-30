#!/usr/bin/env bash
# predicates-test.sh — known-answer matrix for the shared file predicates.
#
# WHY THIS EXISTS: harness_is_test_file / harness_is_vendored decide what every
# gate SKIPS. An exclusion is the one kind of change that makes a gate quieter
# and more confident at the same time, so a mistake here does not announce
# itself — the gate goes green because it stopped looking. selftest.sh proves
# each gate still fires on a violation it CAN see; this proves the predicates
# have not quietly moved violations out of view.
#
# The rows that matter most are the NEGATIVE ones: a source file that merely
# contains the substring "test" must stay in scope. The pattern these replaced
# was `*test_*`, unanchored, which exempted `latest_events.py`.
#
#   scripts/predicates-test.sh      # exits non-zero on any mismatch

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE_NAME="predicates-test"
. "$REPO_ROOT/scripts/lib/common.sh" 2>/dev/null || . "$(dirname "$0")/lib/common.sh"

pass=0; fail=0

t() { # t <path> <TEST|src>
  local got; if harness_is_test_file "$1"; then got=TEST; else got=src; fi
  if [ "$got" = "$2" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); printf 'FAIL  is_test_file(%s) want=%s got=%s\n' "$1" "$2" "$got"; fi
}
v() { # v <path> <VENDOR|ours>
  local got; if harness_is_vendored "$1"; then got=VENDOR; else got=ours; fi
  if [ "$got" = "$2" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); printf 'FAIL  is_vendored(%s) want=%s got=%s\n' "$1" "$2" "$got"; fi
}

# ── test files, across the ecosystems this kit gets copied into ──────────────
t /r/tests/test_receipt.py            TEST   # pytest — the case that was missing
t /r/tests/test_ws_route.py           TEST
t /r/app/tests_helpers.py             TEST
t /r/src/handler_test.go              TEST   # Go
t /r/lib/thing_tests.exs              TEST   # Elixir
t /r/web/button.test.tsx              TEST   # JS/TS
t /r/web/button.spec.ts               TEST
t /r/spec/models/user_spec.rb         TEST   # Ruby
t /r/pkg/test/fixture.go              TEST   # by directory
t /r/web/__tests__/render.js          TEST

# ── source that must STAY IN SCOPE (the rows an over-broad pattern breaks) ───
t /r/sampleapp/lib/latest_events.py    src    # contains "test_" — the anchoring bug
t /r/src/contest_scoring.go           src    # contains "test"
t /r/src/attestation.py               src
t /r/src/protest.rb                   src
t /r/sampleapp/lib/wsprobe.py          src
t /r/sampleapp/blueprints/ws.py        src
t /r/src/testimony.ts                 src    # starts with "test" but is not test_

# ── vendored / generated ─────────────────────────────────────────────────────
v /r/web/node_modules/lodash/index.js VENDOR
v /r/vendor/github.com/x/y.go         VENDOR
v /r/api/thing.pb.go                  VENDOR
v /r/proto/thing_pb2.py               VENDOR
v /r/web/dist/bundle.min.js           VENDOR
v /r/.venv/lib/site-packages/flask.py VENDOR

# ── ours, and must stay ours ─────────────────────────────────────────────────
v /r/sampleapp/lib/receipt.py          ours
v /r/src/vendors/supplier.py          ours   # "vendors", not "vendor" — not third-party
v /r/src/build_plan.py                ours   # "build_" is not a build/ directory

printf '\n%s: %d passed, %d failed\n' "$GATE_NAME" "$pass" "$fail"
[ "$fail" -eq 0 ] || { printf 'A predicate that over-matches makes gates go QUIET, not loud. Fix before trusting any run.\n'; exit 1; }
