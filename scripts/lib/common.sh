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

# Defaults, so a gate never dereferences an unset var under `set -u`.
HARNESS_DOC_DIRS=""
HARNESS_DOC_INDEX=""
HARNESS_CODE_DIRS=""
HARNESS_CODE_EXTS="go ts tsx js rs py java rb"
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

harness_load_config() {
  local cfg="$REPO_ROOT/harness.conf"
  if [ -f "$cfg" ]; then
    # shellcheck disable=SC1090
    . "$cfg"
    HARNESS_CONFIG_FOUND=1
  else
    HARNESS_CONFIG_FOUND=0
  fi
}
harness_load_config

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

# ── ratchet baselines ─────────────────────────────────────────────────────────
#
# A baseline lets a rule land on a codebase that already violates it: existing
# violations are frozen and tolerated, NEW ones fail. Without this, every rule is
# a big-bang migration and therefore never gets adopted.

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
