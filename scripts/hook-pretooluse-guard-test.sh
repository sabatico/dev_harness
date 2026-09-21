#!/usr/bin/env bash
# hook-pretooluse-guard-test.sh — the guard's KNOWN-ANSWER matrix (the self-proof pattern applied
# to the guard itself). Run after ANY edit to hook-pretooluse-guard.sh.
#
# Every row is a payload with a KNOWN verdict. The DENY rows are the incidents the guard exists to
# prevent; the ALLOW rows are the false positives it has actually produced (a commit MESSAGE naming
# forbidden commands blocked the commit shipping the source project's guard) plus the legitimate
# workflows nearest each pattern. A change that flips any row is a regression either way.
#
# WHY A SEPARATE FILE, not inline test calls: the guard hot-reloads and scans every Bash command
# string. Inline payloads containing e.g. a semicolon followed by a forbidden command are
# indistinguishable-by-grep from real chained commands, so the LIVE guard blocks the test run
# itself. From a file, the executed command is just this script's name. (Found live, twice.)
set -uo pipefail
cd "$(dirname "$0")"

GUARD=./hook-pretooluse-guard.sh
pass=0; fail=0

t() { # want tool cmd fp label
  local want="$1" tool="$2" cmd="$3" fp="$4" label="$5" out got
  out="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"command":sys.argv[2],"file_path":sys.argv[3]}}))' "$tool" "$cmd" "$fp" | bash "$GUARD")"
  if printf '%s' "$out" | grep -q '"deny"'; then got=DENY; else got=ALLOW; fi
  if [ "$got" = "$want" ]; then pass=$((pass+1));
  else fail=$((fail+1)); echo "FAIL  want=$want got=$got  $label"; fi
}

# ── must DENY: the incidents ──────────────────────────────────────────────────
t DENY Bash 'terraform destroy -auto-approve' '' 'tf destroy at start'
t DENY Bash 'cd infra; terraform destroy' '' 'tf destroy after ;'
t DENY Bash 'true | pulumi destroy' '' 'pulumi destroy after pipe'
t DENY Bash 'sudo rm -rf ~/Documents/x' '' 'sudo rm -rf home'
t DENY Bash 'rm -rf ../myrepo/.git' '' 'rm -rf a .git'
t DENY Bash 'git add -A && git commit -m x' '' 'git add -A'
t DENY Bash 'git add .' '' 'git add dot'
t DENY Bash 'git restore docs/x.md' '' 'git restore path'
t DENY Bash 'git checkout -- docs/x.md' '' 'git checkout --'
t DENY Bash 'git push --force origin main' '' 'force push'

# ── must ALLOW: the near-misses and real workflows ────────────────────────────
t ALLOW Bash 'git commit -m "guard denies terraform destroy and git add -A misuse"' '' 'triggers in commit msg'
t ALLOW Bash 'echo never run rm -rf on the repo' '' 'triggers in echo prose'
t ALLOW Bash 'rm -rf /tmp/scratch/x' '' 'rm -rf temp'
t ALLOW Bash 'rm -rf web/node_modules' '' 'rm -rf node_modules'
t ALLOW Bash 'git add docs/x.md scripts/y.sh' '' 'scoped add'
t ALLOW Bash 'git restore --staged docs/x.md' '' 'restore --staged'
t ALLOW Bash 'git push origin main' '' 'normal push'
t ALLOW Bash 'git checkout main' '' 'checkout branch'
t ALLOW Bash 'terraform plan' '' 'terraform plan'
t ALLOW Bash 'terraform apply -var enable_x=false' '' 'targeted toggle'

# ── must DENY: the guard CANNOT RUN (fail-closed) ────────────────────────────
# The guard's own empty-scan case. Without these rows the fail-closed branches are exactly the kind
# of never-watched code path this matrix exists to catch — and their failure mode is a silent ALLOW.
nopy="${TMPDIR:-/tmp}/harness-guardtest-nopy.$$"
mkdir -p "$nopy" && printf '#!/bin/sh\nexit 127\n' > "$nopy/python3" && chmod +x "$nopy/python3"
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"terraform destroy"}}' \
       | PATH="$nopy:$PATH" bash "$GUARD" 2>/dev/null)"
if printf '%s' "$out" | grep -q '"deny"'; then pass=$((pass+1));
else fail=$((fail+1)); echo "FAIL  want=DENY got=ALLOW  no python3 must fail CLOSED"; fi
rm -rf "$nopy"

out="$(printf 'not json at all' | bash "$GUARD" 2>/dev/null)"
if printf '%s' "$out" | grep -q '"deny"'; then pass=$((pass+1));
else fail=$((fail+1)); echo "FAIL  want=DENY got=ALLOW  unparseable payload must fail CLOSED"; fi

# ── conf-dependent rows (exercised only when harness.conf sets the vars) ─────
skipped=0
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# shellcheck disable=SC1091
[ -f "$ROOT/harness.conf" ] && . "$ROOT/harness.conf"
if [ -n "${HARNESS_PROTECTED_DBS:-}" ]; then
  db="${HARNESS_PROTECTED_DBS%% *}"
  t DENY  Bash "psql -d ${db} -c \"TRUNCATE t\"" '' 'psql TRUNCATE protected db'
  t DENY  Bash "psql -c \"DROP DATABASE ${db}\"" '' 'drop protected db'
  t ALLOW Bash "psql -c \"DROP DATABASE ${db}_clone1\"" '' 'drop clone'
  t ALLOW Bash "echo TRUNCATE ${db} prose" '' 'sql words no client'
else
  skipped=$((skipped+4)); echo "  SKIP  4 protected-DB rows — HARNESS_PROTECTED_DBS is empty in harness.conf"
fi
if [ -n "${HARNESS_ARCHIVED_PATHS:-}" ]; then
  g="${HARNESS_ARCHIVED_PATHS%% *}"
  t DENY Edit '' "/x/${g#\*}" 'edit archived path'
else
  skipped=$((skipped+1)); echo "  SKIP  1 archived-path row — HARNESS_ARCHIVED_PATHS is empty in harness.conf"
fi

# A skip is not a pass (common.sh's exit vocabulary, applied to this matrix). Printing only
# "N pass, 0 fail" over silently-unexercised rows is the same lie the gates refuse to tell.
echo "guard-test: $pass pass, $fail fail, $skipped skipped (unexercised — NOT passes)"
[ "$skipped" -gt 0 ] && echo "  those rows cover the guard branches your harness.conf does not configure; set the vars to exercise them"
[ "$fail" -eq 0 ] && echo "self-proof: OK ($pass known-answer verdicts correct)" || exit 1
exit 0
