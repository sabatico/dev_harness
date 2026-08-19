#!/usr/bin/env bash
# check-markers.sh — an inline marker MUST have a row in its registry.
#
# WHY THIS IS THE CORE ANTI-DRIFT MECHANISM:
#
# Every project accumulates deliberately-incomplete things — a stub, a deferred
# test, a known shortcut. The danger is not that they exist. It is that "we will do
# this later" and "we forgot this entirely" look identical six weeks on.
#
# Pairing a marker with a registry row makes the difference machine-checkable, and
# gives the deferred thing a way to RESURFACE: when the blocker lifts, the registry
# is what brings it back. Without the pairing, a TODO is a wish with a timestamp.
#
# Configure pairs in harness.conf:
#   HARNESS_MARKERS="DEFERRED-TEST:docs/registers/deferred-test-registry.md STUB:docs/registers/stub-registry.md"
#
# The rule: for every occurrence of MARKER in the tree, the registry named for that
# marker must mention the FILE the marker lives in. That keeps the registry honest
# without forcing a rigid row format on you.

GATE_NAME="markers"
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

harness_need_config
harness_need_var HARNESS_MARKERS "marker:registry pairs"

gate_head

pairs=0
occurrences=0

for pair in $HARNESS_MARKERS; do
  marker="${pair%%:*}"
  registry="${pair#*:}"

  if [ -z "$marker" ] || [ -z "$registry" ] || [ "$marker" = "$pair" ]; then
    gate_incomplete "malformed HARNESS_MARKERS entry: '$pair' (want MARKER:path/to/registry.md)"
  fi

  reg_abs="$REPO_ROOT/$registry"
  if [ ! -f "$reg_abs" ]; then
    gate_incomplete "registry for marker $marker does not exist: $registry"
  fi
  pairs=$((pairs + 1))

  # Find the marker everywhere except the registry itself and this harness.
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    f="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    rel="${f#$REPO_ROOT/}"

    [ "$rel" = "$registry" ] && continue
    case "$rel" in ai-dev-harness/*) continue ;; esac

    occurrences=$((occurrences + 1))
    if ! grep -qF "$rel" "$reg_abs" 2>/dev/null; then
      gate_violation "$rel" "$lineno" "$marker marker with no row in $registry"
    fi
  done < <(git -C "$REPO_ROOT" grep -n -I -F "$marker" -- . 2>/dev/null | sed "s|^|$REPO_ROOT/|")
done

[ "$pairs" -eq 0 ] && gate_incomplete "no marker/registry pairs configured"

gate_finish "$occurrences marker occurrence(s) across $pairs registry pairing(s)"
