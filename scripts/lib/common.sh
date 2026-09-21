#!/usr/bin/env bash
# common.sh — shared plumbing for every gate. Source it; do not execute it.
#
# WHY THIS EXISTS: gates that each invent their own output format, exit codes and
# config loading drift apart within weeks, and then nobody can tell a real red from
# a broken script. One vocabulary, defined once.
#
# ── THE EXIT VOCABULARY (the most important thing in this file) ────────────────
#
#   0  PASS       the check ran, and found nothing wrong
#   1  FAIL       the check ran, and found something wrong
#   3  INCOMPLETE the check could NOT run but SHOULD have — missing tool, unreachable target,
#                 no harness.conf at all. Forces the run verdict to INCOMPLETE.
#   4  N/A        the check is deliberately not configured for this project (its setting is
#                 empty in an existing harness.conf). Reported as `skipped`: never a pass,
#                 always listed, but it does NOT force INCOMPLETE.
#
# 3 vs 4 is the distinction between "this should have run and did not" and "this correctly does
# not apply". Collapsing them either hides a real hole (everything becomes N/A) or trains people
# to ignore the verdict (everything becomes INCOMPLETE). See ci/run-integrity.md R2.
#
# 3 exists because of the failure this whole harness is built around: a check that
# scanned nothing reports zero findings, which is indistinguishable from clean. A
# gate that cannot run must NEVER exit 0. If you add a gate, honour this or you are
# adding a control that lies in the reassuring direction.
#
# Bash 3.2 compatible (stock macOS). No associative arrays, no mapfile, no GNU-only
# flags — the harness must run on the machine the developer actually has.

set -uo pipefail

# ── repo root + config ────────────────────────────────────────────────────────

harness_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

REPO_ROOT="$(harness_repo_root)"
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── LANGUAGE NEUTRALITY, AND HOW IT UNFOLDS BACK INTO SPECIFICS ───────────────
#
# No gate in this kit knows what language you write. Every language-shaped fact — what a function
# declaration looks like, what a comment looks like, which files are tests, what "skip" is called,
# what an error branch looks like, what is vendored or generated — is a VARIABLE, defaulted below
# to a deliberately loose union that matches most C-family and Python-family syntax.
#
# A loose default is a weak gate, though: a union regex matches a lot and therefore proves little
# about YOUR code. So the generality is the shipping state, not the operating state. A **stack
# pack** (`stacks/<name>.conf`) unfolds the union back into exact values for one language, and
# `HARNESS_STACK` in harness.conf selects it:
#
#     generic  ->  DECL_RE matches func|def|fn|function, comments match // # -- *
#     go       ->  DECL_RE matches `func` with receivers, tests are *_test.go, skip is t.Skip
#
# Precedence, deliberately: **defaults < stack pack < harness.conf**. The pack gives you a correct
# starting point for your language; anything you set in harness.conf still wins, because a pack
# cannot know your layout. Packs are data, not rules — write one for a language we do not ship in
# about twenty lines (`stacks/README.md`).
#
# The proof that a pack is right is not that it looks right: `scripts/selftest.sh` builds its
# fixture project FROM THE ACTIVE PACK, so running it proves the gates can see declarations,
# comments, skips and log calls **in your language** — not in the kit author's.

HARNESS_STACK="generic"

# Defaults, so a gate never dereferences an unset var under `set -u`.
HARNESS_DOC_DIRS=""
HARNESS_DOC_INDEX=""
HARNESS_CODE_DIRS=""
HARNESS_CODE_EXTS=""
HARNESS_DECISION_DIR=""
HARNESS_DECISION_PREFIX="ADR"
HARNESS_DECISION_LEDGER=""
HARNESS_BUG_REGISTER=""
HARNESS_MARKERS=""
HARNESS_SECRET_TERMS="password secret token apikey api_key privatekey seed mnemonic otp"
HARNESS_LOG_FUNCS="log logf print println debug info warn error fatal trace"
HARNESS_TEST_CMD=""
HARNESS_COVERAGE_CMD=""
HARNESS_LINT_CMD=""
HARNESS_TEST_ENV_GATES=""
HARNESS_BASELINE_DIR=".harness/baselines"
HARNESS_BASE_REF="origin/main"

# ── the language-shaped vars ──────────────────────────────────────────────────
# Declared empty here ONLY so `set -u` is safe. The authoritative union values live in exactly one
# place — stacks/generic.conf — which is always loaded as the base, so there is no second copy of
# them here to drift. (Two definitions of the same list is the drift this kit exists to prevent;
# it would be a poor look to ship it in the file that explains why.)
HARNESS_DECL_RE=""
HARNESS_DECL_STRIP_RE=""
HARNESS_COMMENT_RE=""
HARNESS_DOC_BELOW=0
HARNESS_TEST_GLOBS=""
HARNESS_SKIP_RE=""
HARNESS_ERROR_RE=""
HARNESS_EXCLUDE_GLOBS=""
HARNESS_SCHEMA_GLOBS=""
HARNESS_CONTRACT_GLOBS=""

# ── config loading ────────────────────────────────────────────────────────────
#
# The pack must load BEFORE harness.conf so harness.conf's values win. But the pack NAME lives in
# harness.conf, so we read that one assignment out first rather than sourcing the file twice —
# sourcing twice would run any side effects twice, and a config that is not idempotent would then
# behave differently for gates than for hooks.
harness_load_config() {
  local cfg="$REPO_ROOT/harness.conf" pack

  # The generic pack is ALWAYS the base, config or not — so a repo with no harness.conf still has
  # working language defaults, and there is only one copy of them anywhere.
  # shellcheck disable=SC1090
  [ -f "$HARNESS_DIR/stacks/generic.conf" ] && . "$HARNESS_DIR/stacks/generic.conf"

  if [ ! -f "$cfg" ]; then HARNESS_CONFIG_FOUND=0; return; fi
  HARNESS_CONFIG_FOUND=1

  # Read the pack NAME out of harness.conf without sourcing it: the pack must load BEFORE
  # harness.conf so harness.conf wins, and sourcing the file twice would run any side effect twice.
  pack="$(sed -n 's/^[[:space:]]*HARNESS_STACK=["'"'"']\{0,1\}\([A-Za-z0-9_-]\{1,\}\).*/\1/p' "$cfg" | tail -1)"
  [ -n "$pack" ] || pack="generic"
  HARNESS_STACK="$pack"
  if [ "$pack" = "generic" ]; then
    HARNESS_STACK_FOUND=1
  elif [ -f "$HARNESS_DIR/stacks/$pack.conf" ]; then
    # shellcheck disable=SC1090
    . "$HARNESS_DIR/stacks/$pack.conf"
    HARNESS_STACK_FOUND=1
  else
    HARNESS_STACK_FOUND=0
  fi

  # shellcheck disable=SC1090
  . "$cfg"
}
HARNESS_STACK_FOUND=1
harness_load_config

# A named pack that does not exist is a CONFIG ERROR, not a silent fallback to the loose union:
# the gates would still run, still print green, and still be checking something other than what the
# project declared. Any gate that cares calls this.
harness_need_stack() {
  [ "${HARNESS_STACK_FOUND:-1}" -eq 1 ] || \
    gate_incomplete "HARNESS_STACK=\"$HARNESS_STACK\" names no pack: $HARNESS_DIR/stacks/$HARNESS_STACK.conf does not exist (see stacks/README.md)"
}

# Turn a space-separated glob list into a case-statement pattern: 'a b' -> 'a|b'.
harness_globs_to_pattern() { printf '%s' "$*" | tr ' ' '|'; }

# True when $1 matches any glob in $2 (a space-separated list).
harness_matches_glob() {
  local f="$1" g
  shift
  for g in $*; do
    # shellcheck disable=SC2254
    case "$f" in $g) return 0 ;; esac
  done
  return 1
}

# ── output ────────────────────────────────────────────────────────────────────

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_DIM=$'\033[2m';  C_B=$'\033[1m';    C_0=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_DIM=""; C_B=""; C_0=""
fi

GATE_NAME="${GATE_NAME:-$(basename "${0%.sh}")}"
_gate_findings=0

gate_head() { printf '%s── %s%s\n' "$C_DIM" "$GATE_NAME" "$C_0"; }

# A single violation. Format is uniform so a human and a model both parse it.
gate_violation() {
  # gate_violation <file> <line-or-dash> <message>
  _gate_findings=$((_gate_findings + 1))
  printf '%s  FAIL%s %s:%s  %s\n' "$C_RED" "$C_0" "$1" "$2" "$3"
}

gate_note() { printf '%s  note%s %s\n' "$C_DIM" "$C_0" "$*"; }

# Use when the gate CANNOT run. Never exit 0 after this.
gate_incomplete() {
  printf '%s  INCOMPLETE%s %s\n' "$C_YEL" "$C_0" "$*"
  printf '%s             (this is NOT a pass — nothing was checked)%s\n' "$C_YEL" "$C_0"
  exit 3
}

# Deliberately not applicable to this project. Still not a pass — it is listed in the manifest
# and the report must account for what went uncovered.
gate_not_applicable() {
  printf '%s  N/A%s %s\n' "$C_DIM" "$C_0" "$*"
  printf '%s      (not a pass — this check covers nothing here)%s\n' "$C_DIM" "$C_0"
  exit 4
}

# Standard ending for a gate that ran to completion.
gate_finish() {
  # gate_finish <what-was-scanned-description>
  if [ "$_gate_findings" -eq 0 ]; then
    printf '%s  PASS%s %s\n' "$C_GRN" "$C_0" "${1:-checked}"
    exit 0
  fi
  printf '%s  %d violation(s)%s — %s\n' "$C_RED" "$_gate_findings" "$C_0" "${1:-checked}"
  exit 1
}

# ── config guards ─────────────────────────────────────────────────────────────

harness_need_config() {
  if [ "$HARNESS_CONFIG_FOUND" -eq 0 ]; then
    gate_incomplete "no harness.conf at $REPO_ROOT (copy harness.conf.example)"
  fi
}

harness_need_var() {
  # harness_need_var VAR_NAME "what it configures"
  # Empty in an EXISTING config = a deliberate opt-out (exit 4, reported as skipped).
  # No config at all is caught earlier by harness_need_config (exit 3).
  local val
  eval "val=\${$1:-}"
  if [ -z "$val" ]; then
    gate_not_applicable "$1 is empty in harness.conf — $2"
  fi
}

harness_need_tool() {
  command -v "$1" >/dev/null 2>&1 || gate_incomplete "required tool '$1' not on PATH"
}

# ── file discovery ────────────────────────────────────────────────────────────

# Emit every markdown file under HARNESS_DOC_DIRS, one per line.
harness_doc_files() {
  local d
  for d in $HARNESS_DOC_DIRS; do
    [ -d "$REPO_ROOT/$d" ] || continue
    find "$REPO_ROOT/$d" -type f -name '*.md' 2>/dev/null
  done
}

# True when at least one configured code dir exists on disk. A gate whose dirs are ABSENT
# could not scan (exit 3); a gate whose dirs exist but matched nothing covers nothing (exit 4).
# Both are distinct from PASS — see gates.md G1.
harness_code_dirs_exist() {
  local d
  for d in $HARNESS_CODE_DIRS; do
    [ -d "$REPO_ROOT/$d" ] && return 0
  done
  return 1
}

# Emit every source file under HARNESS_CODE_DIRS, one per line.
harness_code_files() {
  local d e
  for d in $HARNESS_CODE_DIRS; do
    [ -d "$REPO_ROOT/$d" ] || continue
    for e in $HARNESS_CODE_EXTS; do
      find "$REPO_ROOT/$d" -type f -name "*.$e" 2>/dev/null
    done
  done
}

# Files changed vs the base ref — the ratchet's notion of "what you touched".
# Falls back to the whole tree ONLY when explicitly asked, never silently.
harness_changed_files() {
  local base="$HARNESS_BASE_REF"
  if ! git -C "$REPO_ROOT" rev-parse --verify "$base" >/dev/null 2>&1; then
    # No base ref (fresh repo, no remote). Use the working-tree diff against HEAD.
    if git -C "$REPO_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
      git -C "$REPO_ROOT" diff --name-only HEAD 2>/dev/null
      git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null
    else
      git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null
    fi
    return
  fi
  git -C "$REPO_ROOT" diff --name-only "$base"...HEAD 2>/dev/null
  git -C "$REPO_ROOT" diff --name-only HEAD 2>/dev/null
  git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null
}

# ── the two questions every code gate asks ────────────────────────────────────
#
# "Is this a test file?" and "is this vendored/generated?" are asked by most gates here, and for a
# while each answered them itself. They drifted, which is how a Python repo ended up with every
# test function reported as an uncited declaration. One answer, defined once.
#
# The ANSWER is here; the LIST is config (HARNESS_TEST_GLOBS / HARNESS_EXCLUDE_GLOBS), because what
# a test file looks like is a fact about your language, not about this gate.
#
# ⚠ ANCHOR BASENAME PATTERNS TO A SEPARATOR. `*/test_*` and not `*test_*`: the bare form matches any
# path merely CONTAINING "test_", so a source file named `latest_events.py` is silently exempted
# from every gate that uses this — a hole that reads as a clean scan. The shipped globs are
# anchored; keep yours anchored when you add to them.

harness_is_test_file() {
  # harness_is_test_file <path>  — true (0) when the path is a test file.
  # The LIST lives in HARNESS_TEST_GLOBS (stack pack / harness.conf); the shared ANSWER lives here.
  # Keeping the list out of the code is what makes this kit language-neutral; keeping the answer in
  # one place is what stops three gates disagreeing about it.
  harness_matches_glob "$1" "$HARNESS_TEST_GLOBS"
}

harness_is_vendored() {
  # harness_is_vendored <path>  — true (0) for third-party or generated code. Not ours to annotate,
  # and a gate that demands edits to it teaches people that the gate is noise.
  # List: HARNESS_EXCLUDE_GLOBS (stack pack / harness.conf). Answer: here, once.
  harness_matches_glob "$1" "$HARNESS_EXCLUDE_GLOBS"
}

# ── ratchet baselines ─────────────────────────────────────────────────────────
#
# A baseline lets a rule land on a codebase that already violates it: existing
# violations are frozen and tolerated, NEW ones fail. Without this, every rule is
# a big-bang migration and therefore never gets adopted.

# ── the push receipt (gates.md G4) ────────────────────────────────────────────
#
# "Gates passed" and "gates passed on THIS code" are different claims. The receipt binds them: the
# runner writes a tree hash when everything is green, and anything that re-checks it recomputes the
# same hash and compares.
#
# G4 names two details that decide whether this works, and both are load-bearing:
#   · UNTRACKED-but-not-ignored files are included. A tracked-only hash misses the file you just
#     wrote, which is exactly the code most likely to be unverified.
#   · ONE shared function does the hashing for writer and checker. Two implementations drift, and
#     the first symptom is a check that refuses the very run that created the receipt.
#
# And G1's hashing corollary: a digest over an EMPTY enumeration is not random, it is the stable
# hash of nothing — so a receipt written while enumeration was broken would MATCH a later check
# made while it was still broken, and the whole mechanism would pass having verified no files.
# harness_tree_hash therefore refuses to emit a digest for an empty file list.

harness_tree_hash() {
  # Prints the digest on stdout, or exits 3 (INCOMPLETE) if it enumerated nothing.
  local files n
  files="$( { git -C "$REPO_ROOT" ls-files 2>/dev/null
              git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null; } | sort -u )"
  n="$(printf '%s\n' "$files" | grep -c . || true)"
  if [ "${n:-0}" -eq 0 ]; then
    printf 'tree-hash enumerated ZERO files — the enumeration is broken, not the tree.\n' >&2
    printf 'Refusing to emit a digest: the hash of nothing is STABLE and would verify forever.\n' >&2
    return 3
  fi
  printf '%s\n' "$files" \
    | while IFS= read -r f; do [ -f "$REPO_ROOT/$f" ] && shasum -a 256 "$REPO_ROOT/$f"; done \
    | shasum -a 256 | cut -d' ' -f1
}

harness_receipt_path() { printf '%s/.gate-receipt' "$REPO_ROOT"; }

harness_receipt_write() {
  # harness_receipt_write <what-ran>
  local h; h="$(harness_tree_hash)" || return 3
  {
    printf 'tree-sha256 %s\n' "$h"
    printf 'written-at  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'covered     %s\n' "$1"
    printf 'head        %s\n' "$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo none)"
  } > "$(harness_receipt_path)"
}

harness_receipt_verify() {
  # 0 = receipt matches the tree; 1 = stale; 3 = no receipt / could not hash.
  local rp h rec; rp="$(harness_receipt_path)"
  [ -f "$rp" ] || { printf 'no .gate-receipt — the gates have not been run on this tree.\n' >&2; return 3; }
  h="$(harness_tree_hash)" || return 3
  rec="$(awk '$1=="tree-sha256"{print $2}' "$rp")"
  [ "$h" = "$rec" ] && return 0
  printf 'RECEIPT STALE: the tree changed since the gates passed.\n' >&2
  printf '  receipt: %s\n  now:     %s\n' "$rec" "$h" >&2
  printf 'The green run you are relying on was for different code. Re-run the gates.\n' >&2
  return 1
}

harness_baseline_path() {
  printf '%s/%s/%s.txt' "$REPO_ROOT" "$HARNESS_BASELINE_DIR" "$1"
}

harness_baseline_has() {
  # harness_baseline_has <name> <key>
  local bp; bp="$(harness_baseline_path "$1")"
  [ -f "$bp" ] || return 1
  grep -qxF "$2" "$bp" 2>/dev/null
}

harness_baseline_write() {
  # harness_baseline_write <name>  — reads keys from stdin
  local bp tmp; bp="$(harness_baseline_path "$1")"
  mkdir -p "$(dirname "$bp")"
  tmp="$bp.tmp.$$"
  sort -u > "$tmp"
  {
    printf '# %s baseline — frozen KNOWN violations. New ones still fail.\n' "$1"
    printf '#\n'
    printf '# This is NOT a to-do list and it is NOT permission. Every line was a violation that\n'
    printf '# existed when the gate was adopted. Fix one by DELETING its line — the gate then guards\n'
    printf '# that case forever. A growing baseline is a regression; the run prints the count so it\n'
    printf '# stays visible.\n'
    printf '#\n'
    printf '# TRIAGE BEFORE YOU FREEZE (gates.md G3): freezing without triage buries real findings\n'
    printf '# among false ones. Record the categories here:\n'
    printf '#   «category 1 — why these are acceptable»\n'
    printf '#\n'
    cat "$tmp"
  } > "$bp"
  rm -f "$tmp"
  printf 'baseline written: %s (%d entr(ies))\n' "$bp" "$(grep -cv "^#" "$bp" | tr -d " ")"
}
