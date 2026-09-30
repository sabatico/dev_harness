#!/usr/bin/env bash
# hook-pretooluse-secretread-test.sh — known-answer matrix for hook-pretooluse-secretread.sh.
# DENY rows = the ways a secret reaches the model; ALLOW rows = the legitimate workflows nearest each
# pattern (sourcing, loading one value into a variable, yes/no greps, prose naming the file). A change
# that flips any row is a regression, either direction. Gated (fast tier). Payloads only — no real .env.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")" && pwd)/hook-pretooluse-secretread.sh"
pass=0; fail=0
t() { # want tool value label   (value = command for Bash, file_path for Read)
  local want="$1" tool="$2" val="$3" label="$4" out got
  out="$(python3 -c 'import json,sys; t,v=sys.argv[1],sys.argv[2]; print(json.dumps({"tool_name":t,"tool_input":({"command":v} if t=="Bash" else {"file_path":v})}))' "$tool" "$val" | bash "$HOOK")"
  if printf '%s' "$out" | grep -q '"deny"'; then got=DENY; else got=ALLOW; fi
  if [ "$got" = "$want" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  want=$want got=$got  $label"; fi
}
# ── DENY: a secret would enter the model's context ─────────────────────────────
t DENY  Read '/repo/app/.env'                'Read .env'
t DENY  Read '/repo/.env.production'                          'Read .env.production'
t DENY  Bash 'cat .env'                                       'cat .env'
t DENY  Bash 'cat app/.env | head'           'cat path/.env piped'
t DENY  Bash 'head -5 ../.env'                                'head ../.env'
t DENY  Bash 'cd x && less .env.local'                        'less .env.local after &&'
t DENY  Bash 'grep AWS .env'                                  'grep prints values'
t DENY  Bash 'sed -n 1,5p app/.env'          'sed prints lines'
t DENY  Bash "awk -F= '{print \$2}' .env"                     'awk prints values'
t DENY  Bash 'printenv'                                       'bare printenv'
t DENY  Bash 'env | grep AWS'                                 'env dump piped'
t DENY  Bash 'set'                                            'bare set dumps vars'
# ── ALLOW: the legitimate workflows nearest each pattern ───────────────────────
t ALLOW Read '/repo/.env.example'                             'Read .env.example'
t ALLOW Read '/repo/src/environment.ts'                       'Read a file merely named env*'
t ALLOW Bash 'cat .env.example'                               'cat .env.example'
t ALLOW Bash 'set -a; . ./.env; set +a; aws s3 ls'            'source .env in-process'
t ALLOW Bash 'export AWS_ACCESS_KEY_ID=$(grep "^AWS_S3_KEY=" .env | cut -d= -f2)'  'load one value via $( )'
t ALLOW Bash 'grep -q STRIPE_KEY .env && echo present'        'grep -q yes/no'
t ALLOW Bash 'grep -c KEY .env'                               'grep -c count'
t ALLOW Bash 'ls -la .env && git check-ignore -v .env'        'ls + check-ignore'
t ALLOW Bash 'git commit -m "never cat .env into chat"'       'prose in a commit message'
t ALLOW Bash 'echo "add .env to .gitignore"'                  'prose in echo'
t ALLOW Bash 'env FOO=1 bash scripts/x.sh'                    'env VAR=x cmd'
t ALLOW Bash 'set -euo pipefail; make build'                  'set with options'
t ALLOW Bash 'cat docs/environment.md'                        'cat of a non-secret file'
echo "secret-read matrix: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
