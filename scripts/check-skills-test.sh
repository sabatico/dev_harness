#!/usr/bin/env bash
# check-skills-test.sh — known-answer matrix for check-skills.sh: one clean fixture must PASS,
# and every planted defect must FAIL with its specific message. A gate is trusted only after it
# has been watched failing (ci/gates.md, Gate INTEGRITY).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-skills.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/skills-test.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 2; }; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

mk_skill() {  # mk_skill ROOT FOLDER NAME DESCRIPTION [BODY]  — also writes a valid 3-scenario eval
  mkdir -p "$1/dot-claude/skills/$2" "$1/evals"
  printf -- '---\nname: %s\ndescription: %s\n---\n\n%s\n' "$3" "$4" "${5:-# Body}" > "$1/dot-claude/skills/$2/SKILL.md"
  printf '[%s,%s,%s]\n' '{"query":"q","expected_behavior":["a"]}' '{"query":"q","expected_behavior":["b"]}' '{"query":"q","expected_behavior":["c"]}' > "$1/evals/$2.json"
}
GOOD_DESC="Runs the widget procedure end to end. Use when the owner asks for widgets."

expect() {  # expect LABEL WANT(0|1) PATTERN ROOT
  out="$("$CHECK" "$4" 2>&1)"; rc=$?
  if [ "$rc" -eq "$2" ] && { [ -z "$3" ] || printf '%s' "$out" | grep -q -- "$3"; }; then
    pass=$((pass+1)); echo "  ok    $1"
  else
    fail=$((fail+1)); echo "  BAD   $1 (rc=$rc, wanted $2, pattern '$3')"; printf '%s\n' "$out" | sed 's/^/        /'
  fi
}

case_dir() { d="$TMP/$1"; mkdir -p "$d/dot-claude"; echo "$d"; }

# 1. clean fixture passes (with a linked reference file that has a ToC)
R=$(case_dir clean); mk_skill "$R" running-widgets running-widgets "$GOOD_DESC" "See [ref](reference/detail.md)."
mkdir -p "$R/dot-claude/skills/running-widgets/reference"
{ echo "# Detail"; echo "## Contents"; for i in $(seq 1 120); do echo "line $i"; done; } > "$R/dot-claude/skills/running-widgets/reference/detail.md"
expect "clean skill passes" 0 "0 finding" "$R"

R=$(case_dir nofm); mkdir -p "$R/dot-claude/skills/running-x"; echo "# no frontmatter" > "$R/dot-claude/skills/running-x/SKILL.md"
expect "missing frontmatter" 1 "missing YAML frontmatter" "$R"

R=$(case_dir badname); mk_skill "$R" Running_X Running_X "$GOOD_DESC"
expect "bad name characters" 1 "lowercase letters" "$R"

R=$(case_dir mismatch); mk_skill "$R" running-a running-b "$GOOD_DESC"
expect "name != folder" 1 "must equal its folder" "$R"

R=$(case_dir reserved); mk_skill "$R" asking-claude asking-claude "$GOOD_DESC"
expect "reserved word" 1 "reserved word" "$R"

R=$(case_dir gerund); mk_skill "$R" widget-runner widget-runner "$GOOD_DESC"
expect "not a gerund" 1 "must start with a gerund" "$R"

R=$(case_dir firstperson); mk_skill "$R" running-y running-y "I can help you run widgets. Use when needed."
expect "first-person description" 1 "third person" "$R"

R=$(case_dir nowhen); mk_skill "$R" running-z running-z "Runs widgets."
expect "description without 'Use when'" 1 "when to use it" "$R"

R=$(case_dir longdesc); mk_skill "$R" running-l running-l "$(printf 'Runs widgets. Use when asked. %.0s' $(seq 1 60))"
expect "description over 1024" 1 "max 1024" "$R"

R=$(case_dir xml); mk_skill "$R" running-m running-m "Runs <b>widgets</b>. Use when asked."
expect "XML tag in description" 1 "XML/HTML tag" "$R"

R=$(case_dir long); mk_skill "$R" running-n running-n "$GOOD_DESC" "$(for i in $(seq 1 520); do echo "line $i"; done)"
expect "body over 500 lines" 1 "max 500" "$R"

R=$(case_dir deadlink); mk_skill "$R" running-o running-o "$GOOD_DESC" "See [x](reference/missing.md)."
expect "dead link" 1 "does not resolve" "$R"

R=$(case_dir nested); mk_skill "$R" running-p running-p "$GOOD_DESC" "See [a](reference/a.md)."
mkdir -p "$R/dot-claude/skills/running-p/reference"
echo "See [b](b.md)" > "$R/dot-claude/skills/running-p/reference/a.md"; echo "b" > "$R/dot-claude/skills/running-p/reference/b.md"
expect "nested reference" 1 "one level deep" "$R"

R=$(case_dir notoc); mk_skill "$R" running-q running-q "$GOOD_DESC" "See [a](reference/a.md)."
mkdir -p "$R/dot-claude/skills/running-q/reference"; for i in $(seq 1 130); do echo "l$i"; done > "$R/dot-claude/skills/running-q/reference/a.md"
expect "long reference without ToC" 1 "Contents" "$R"

R=$(case_dir win); mk_skill "$R" running-r running-r "$GOOD_DESC" 'Run scripts\helper.py now.'
expect "Windows path" 1 "Windows-style path" "$R"

R=$(case_dir agent); mkdir -p "$R/dot-claude/agents"; printf -- '---\nname: helper\ndescription: You help.\n---\nbody\n' > "$R/dot-claude/agents/helper.md"
expect "agent description voice" 1 "third person" "$R"

R=$(case_dir rule); mkdir -p "$R/dot-claude/rules"; printf '# no frontmatter\n' > "$R/dot-claude/rules/x.md"
expect "rule without paths" 1 "paths:" "$R"

R=$(case_dir badpath); mk_skill "$R" running-v running-v "$GOOD_DESC" 'Read `docs/nowhere/missing.md` first.'
expect "dead backticked path" 1 "does not exist" "$R"

R=$(case_dir kitpath); mk_skill "$R" running-w running-w "$GOOD_DESC" 'See `docs/ci/gates.md`.'
mkdir -p "$R/ci"; echo "# gates" > "$R/ci/gates.md"
expect "installed-layout path resolves in the kit" 0 "0 finding" "$R"

# A bare folder claim with its trailing slash: the slash was stripped before the prefix test, so this
# resolved only where a local .claude/ happened to exist (a fresh clone has none; neither has $R).
R=$(case_dir kitbare); mk_skill "$R" running-z running-z "$GOOD_DESC" 'Lives under `.claude/` once installed.'
expect "a bare installed-layout folder (\`.claude/\`) resolves in the kit" 0 "0 finding" "$R"

R=$(case_dir relroot); mk_skill "$R" running-x running-x "$GOOD_DESC" "See [ref](reference/r.md)."
mkdir -p "$R/dot-claude/skills/running-x/reference"; echo "# r" > "$R/dot-claude/skills/running-x/reference/r.md"
out="$(cd "$R" && "$CHECK" . 2>&1)"; if printf '%s' "$out" | grep -q "0 finding"; then pass=$((pass+1)); echo "  ok    relative ROOT ('.') still matches linked references"; else fail=$((fail+1)); echo "  BAD   relative ROOT"; printf '%s\n' "$out"; fi

R=$(case_dir installed); mk_skill "$R" running-y running-y "$GOOD_DESC"; mkdir -p "$R/.claude/skills"; cp -R "$R/dot-claude/skills/running-y" "$R/.claude/skills/"
printf -- '---\nname: broken\n---\n' > "$R/dot-claude/skills/running-y/SKILL.md"
expect "installed .claude/ is preferred over the kit copy" 0 "0 finding" "$R"

R=$(case_dir noevals); mk_skill "$R" running-t running-t "$GOOD_DESC"; rm "$R/evals/running-t.json"
expect "missing evals file" 1 "no evals/" "$R"

R=$(case_dir fewevals); mk_skill "$R" running-u running-u "$GOOD_DESC"; echo '[{"query":"q","expected_behavior":["a"]}]' > "$R/evals/running-u.json"
expect "fewer than 3 evals" 1 "needs ≥3 scenarios" "$R"

R=$(case_dir dated); mk_skill "$R" running-s running-s "$GOOD_DESC" "As of 2026 do X."
expect "dated wording is only a warning" 0 "warn" "$R"

echo "check-skills-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
