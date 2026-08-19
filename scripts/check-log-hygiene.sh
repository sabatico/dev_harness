#!/usr/bin/env bash
# check-log-hygiene.sh — no secret material may reach a logging call.
#
# WHY: logs are the most-copied, least-guarded artifact a system produces. They get
# pasted into chats, shipped to third-party aggregators, attached to bug reports and
# handed to models. A secret in a log is a secret in all of those places, and unlike
# a leaked commit you cannot rewrite history to remove it.
#
# This is a NAME-BASED heuristic: it flags a logging call whose arguments mention an
# identifier that looks like a secret. It cannot see a secret flowing through a
# neutrally-named variable, so it is a floor and not a proof.
#
# Suppress a verified-safe case with a trailing
#     # harness:allow-log  <reason>
# comment, so every exception is visible and greppable rather than silently deleted.
# ⚠ The annotation must sit on the SAME LINE as the offending call — the gate reads line by line,
# so a comment on the line above is silently ignored. (This tripped its own author.)

GATE_NAME="log-hygiene"
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

harness_need_config
harness_need_var HARNESS_CODE_DIRS    "which directories hold your source"
harness_need_var HARNESS_SECRET_TERMS "identifiers that must never be logged"
harness_need_var HARNESS_LOG_FUNCS    "function-name fragments that count as logging"

gate_head

# Build alternations from config.
log_alt=""
for t in $HARNESS_LOG_FUNCS; do
  [ -n "$log_alt" ] && log_alt="$log_alt|"
  log_alt="$log_alt$t"
done
sec_alt=""
for t in $HARNESS_SECRET_TERMS; do
  [ -n "$sec_alt" ] && sec_alt="$sec_alt|"
  sec_alt="$sec_alt$t"
done

LOG_RE="[A-Za-z_.]*($log_alt)[A-Za-z_]*[[:space:]]*\("
SEC_RE="($sec_alt)"

scanned=0
calls=0

while IFS= read -r f; do
  case "$f" in *_test.*|*.test.*|*.spec.*|*/vendor/*|*/node_modules/*) continue ;; esac
  scanned=$((scanned + 1))
  rel="${f#$REPO_ROOT/}"

  # -i is REQUIRED, not cosmetic: the overwhelmingly common shapes are capitalised
  # (`log.Printf`, `logger.Warn`, `console.Error`, `Log.Debug`). A case-sensitive match
  # sees none of them, and the gate reports a confident zero. Found by scripts/selftest.sh.
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    lineno="${hit%%:*}"
    text="${hit#*:}"
    calls=$((calls + 1))

    case "$text" in *harness:allow-log*) continue ;; esac

    # Case-insensitive secret-term match on the same line.
    if printf '%s' "$text" | tr 'A-Z' 'a-z' | grep -qE "$SEC_RE"; then
      term="$(printf '%s' "$text" | tr 'A-Z' 'a-z' | grep -oE "$SEC_RE" | head -1)"
      gate_violation "$rel" "$lineno" "logging call references '$term' — redact it, or annotate '# harness:allow-log <reason>'"
    fi
  done < <(grep -niE "$LOG_RE" "$f" 2>/dev/null)

done < <(harness_code_files)

if [ "$scanned" -eq 0 ]; then
  harness_code_dirs_exist || gate_incomplete "no source directories exist yet: $HARNESS_CODE_DIRS (set HARNESS_CODE_DIRS in harness.conf once you have code)"
  gate_not_applicable "source dirs exist but no files matched HARNESS_CODE_EXTS ($HARNESS_CODE_EXTS)"
fi

gate_finish "$calls logging call(s) across $scanned file(s)"
