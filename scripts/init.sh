#!/usr/bin/env bash
# init.sh — turn a fresh clone of this boilerplate into a working project skeleton.
#
#   scripts/init.sh "My Project" P3 [go|typescript|python|generic]
#
# What it does:
#   1. Lays down docs/  ← running-files/,  docs/sops/ ← sops/,  docs/ci/ ← ci/
#   2. Installs the platform layer: .claude/ ← dot-claude/ (hooks, guard, rules, librarian)
#   3. Substitutes «PROJECT NAME» throughout the copies
#   4. Writes harness.conf pointing at the new layout, so the gates run immediately
#   5. Generates docs/documentation-index.md from what it actually copied
#   6. Regenerates the doc-paths baseline against the real layout
#   7. PRINTS what your profile does not need — it never deletes
#
# ⛔ IT DELETES NOTHING. Pruning is a judgement call with a blast radius, so it prints a `git rm`
# list and stops. That is the same standing rule the harness applies to every destructive action:
# explain what it removes, then let a human decide. See TAILORING.md for the profiles.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

NAME="${1:-}"
PROFILE="${2:-P3}"
STACK="${3:-generic}"

if [ -z "$NAME" ]; then
  echo "usage: scripts/init.sh \"<Project Name>\" [P1|P2|P3|P4|P5] [stack]" >&2
  echo "       stacks: $(cd "$HERE/stacks" 2>/dev/null && ls *.conf 2>/dev/null | sed 's/\.conf$//' | tr '\n' ' ')" >&2
  echo "       see TAILORING.md — pick the SMALLEST profile that fits, then promote later." >&2
  exit 2
fi

case "$PROFILE" in P1|P2|P3|P4|P5) ;; *) echo "unknown profile: $PROFILE (want P1..P5)" >&2; exit 2 ;; esac
if [ ! -f "$HERE/stacks/$STACK.conf" ]; then
  echo "unknown stack: $STACK" >&2
  echo "available: $(cd "$HERE/stacks" && ls ./*.conf | sed 's|.*/||; s|\.conf$||' | tr '\n' ' ')" >&2
  echo "a language we do not ship is ~20 lines of config — see scripts/stacks/README.md" >&2
  exit 2
fi

if [ -e docs ]; then
  echo "refusing to run: docs/ already exists." >&2
  echo "This looks like an already-initialised project. Move or remove docs/ first if you" >&2
  echo "really mean to re-init — that is your call to make, not this script's." >&2
  exit 1
fi

echo "── initialising '$NAME' at profile $PROFILE, stack $STACK"

# ── 1. layout ────────────────────────────────────────────────────────────────
mkdir -p docs/sops docs/ci
cp -R running-files/. docs/
cp -R sops/.          docs/sops/
cp -R ci/.            docs/ci/

# ── 2. the platform layer ────────────────────────────────────────────────────
# NOT optional and NOT a later step. Hooks, the destructive-action guard, the path-scoped rules and
# the librarian are the controls that hold the rules prose cannot (docs/ci/platform-layer.md). This
# used to be a manual instruction buried in TAILORING.md, and the result was that a fresh project
# had no .claude/ at all while CLAUDE.md asserted the rules auto-loaded — an invisible hole, which
# is the one kind this kit refuses to ship.
# Merge PER FILE, never all-or-nothing. A .claude/ directory already exists more often than not —
# one prior session writing a settings.local.json is enough — and an all-or-nothing check would
# then skip the whole platform layer over a file that collides with nothing. That is how the hole
# this step exists to close comes straight back, silently.
PLATFORM_NEW=0; PLATFORM_KEPT=""
mkdir -p .claude
# No pipelines here, deliberately: under `set -euo pipefail` a grep that matches nothing exits 1
# and takes the whole script with it — which is exactly how this block silently stopped installing
# anything the first time it was written. A plain loop cannot fail that way.
for rel in $( cd dot-claude && find . -type f | sed 's|^\./||' ); do
  if [ -e ".claude/$rel" ]; then
    PLATFORM_KEPT="$PLATFORM_KEPT $rel"
  else
    mkdir -p ".claude/$(dirname "$rel")"
    cp "dot-claude/$rel" ".claude/$rel"
    PLATFORM_NEW=$((PLATFORM_NEW + 1))
  fi
done
PLATFORM_NOTE="installed $PLATFORM_NEW file(s) into .claude/ (hooks, guard, rules, librarian)"
if [ -n "$PLATFORM_KEPT" ]; then
  PLATFORM_NOTE="$PLATFORM_NOTE
    ⚠ KEPT YOURS, not overwritten: $PLATFORM_KEPT
      If settings.json is in that list, its hooks block may be missing the harness hooks —
      compare it against dot-claude/settings.json by hand. The banner is the proof either way."
fi

# ── 3. project name ──────────────────────────────────────────────────────────
# BSD sed needs the -i backup arg; GNU does not. Write to a temp file to stay portable.
subst() {
  # Two statements, deliberately: bash expands ALL words of a single `local` before any of its
  # assignments take effect, so `local f="$1" tmp="$f..."` sees an unset $f and dies under `set -u`.
  local f="$1"
  local tmp="$f.init.$$"
  sed -e "s/«PROJECT NAME»/$NAME/g" -e "s/«PROJECT»/$NAME/g" "$f" > "$tmp" && mv "$tmp" "$f"
}
find docs -name '*.md' -type f | while IFS= read -r f; do subst "$f"; done
[ -f CLAUDE.md ] && subst CLAUDE.md

# ── 4. config ────────────────────────────────────────────────────────────────
cat > harness.conf <<CONF
# harness.conf — $NAME (profile $PROFILE). Generated by scripts/init.sh.
# Every option + what it does: harness.conf.example

# The stack pack supplies every language-shaped value — what a declaration, a comment, a test file,
# a skip and a log call look like — so no gate here hardcodes a language. Anything you set BELOW
# overrides the pack. Swap packs or write your own: scripts/stacks/README.md.
HARNESS_STACK="$STACK"

HARNESS_DOC_DIRS="docs"
HARNESS_DOC_INDEX="docs/documentation-index.md"

# ⚠ SET THIS — the gates cover nothing until they point at real source.
HARNESS_CODE_DIRS="src"
# HARNESS_CODE_EXTS comes from the '$STACK' pack; uncomment to override.
# HARNESS_CODE_EXTS=""

HARNESS_DECISION_DIR="docs/adr"
HARNESS_DECISION_PREFIX="ADR"
HARNESS_DECISION_LEDGER=""

HARNESS_BUG_REGISTER="docs/tickets/bug-register.md"
HARNESS_MARKERS="DEFERRED-TEST:docs/deferred-test-registry.md"

HARNESS_SECRET_TERMS="password passwd secret token apikey api_key privatekey private_key seed mnemonic otp pin ssn"
# HARNESS_LOG_FUNCS comes from the '$STACK' pack.

# The '$STACK' pack proposes these; CONFIRM THEM against how this project actually builds. An
# empty value means the suite reports NOT RUN, which is a gap, not a pass.
# HARNESS_TEST_CMD=""
# HARNESS_COVERAGE_CMD=""
# HARNESS_LINT_CMD=""
HARNESS_TEST_ENV_GATES=""

HARNESS_BASELINE_DIR=".harness/baselines"
HARNESS_BASE_REF="origin/main"

# ── platform layer (the .claude/ hooks — see docs/ci/platform-layer.md) ──────
# Empty is a valid, honest state: the guard still blocks the universal destructive commands.
# Each var below switches ON an additional guard branch, so filling one is how you get the
# protection — and scripts/hook-pretooluse-guard-test.sh reports the rows it could not exercise.
HARNESS_PROTECTED_DBS=""        # dev DBs whose data must survive; "<name>_*" clones stay allowed
HARNESS_ARCHIVED_PATHS=""       # globs that are history — never edited
HARNESS_GENERATED_PATHS=""      # glob=regen-command pairs — never hand-edited
HARNESS_CORPUS_DIRS="docs"      # what the read-budget advisory and librarian-sweep consider corpus
HARNESS_READ_BUDGET_BYTES="61440"
HARNESS_SIBLING_REPOS=""        # repos beside this one that belong to the same product
CONF

# ── 5. doc index ─────────────────────────────────────────────────────────────
{
  echo "# Documentation index — $NAME"
  echo
  echo "> Every living doc is registered here, with its update trigger. A doc nobody registered"
  echo "> is a doc nobody will update — and it will still be read. Gated by \`scripts/check-doc-index.sh\`."
  echo
  echo "| Doc | What it holds | Update when |"
  echo "|---|---|---|"
  find docs -name '*.md' -type f | sort | while IFS= read -r f; do
    [ "$f" = "docs/documentation-index.md" ] && continue
    title="$(head -1 "$f" | sed 's/^#[[:space:]]*//')"
    echo "| \`$f\` | ${title:-«what it holds»} | «trigger» |"
  done
} > docs/documentation-index.md

# ── 6. baseline against the REAL layout ──────────────────────────────────────
rm -rf .harness/baselines
bash "$HERE/check-doc-paths.sh" --write-baseline >/dev/null 2>&1 || true

# ── 7. what this profile does not need ───────────────────────────────────────
echo
echo "── profile $PROFILE: review these for removal (NOTHING was deleted)"
prune() { [ -e "$1" ] && echo "   git rm -r $1   # $2"; }

case "$PROFILE" in
  P1)
    prune docs/tickets              "P1: no ticket taxonomy for a throwaway"
    prune docs/adr                  "P1: decisions can be a section in ONBOARDING.md"
    prune docs/runner.md            "P1: no wave runner"
    prune docs/feature-catalog.md   "P1"
    prune docs/use-case-runbook.md  "P1"
    prune docs/sops                 "P1: core only"
    ;;
  P2)
    prune docs/tickets                          "P2: until something needed from a human gets lost"
    prune docs/runner.md                        "P2: until >1 workstream is in flight"
    prune docs/use-case-runbook.md              "P2: no end-user flows in a library"
    prune docs/sops/ui-development-guardrails.md "P2: no UI"
    prune docs/sops/mockup-implementation.md    "P2: no designs"
    prune docs/sops/security-properties.md      "P2: no network surface / multi-user"
    prune docs/sops/owner-communication.md      "P2: no non-technical stakeholder"
    ;;
  P3)
    prune docs/sops/security-properties.md "P3: keep ONLY if multi-user, network surface, or untrusted input"
    prune docs/ci/run-integrity.md         "P3: keep once any job has >1 stage"
    ;;
  P4) echo "   (P4 keeps nearly everything — prune only what plainly does not apply)" ;;
  P5) echo "   (P5 keeps everything)" ;;
esac
[ "$PROFILE" != "P3" ] && [ "$PROFILE" != "P4" ] && [ "$PROFILE" != "P5" ] && \
  prune docs/ci/run-integrity.md "no multi-stage jobs yet"

cat <<NEXT

── platform layer: $PLATFORM_NOTE

── next, in order (TAILORING.md has the detail)

  1. RESTART YOUR SESSION AND SEE THE ⚡ SESSION BRIEF BANNER. Hook config loads at session
     start, so the session that ran this script does NOT have the hooks it just installed —
     and an unprotected session looks identical to a protected one (docs/ci/control-timing.md
     C3). No banner means nothing below step 4 is real yet. Do this first because every other
     step is cheaper to verify once the controls are live.
  2. Fill every «SLOT» in CLAUDE.md — ESPECIALLY the invariants and the ENFORCED-vs-UNENFORCED
     table (control-timing.md C5). If you cannot name 1-3 things that must never break, you are
     not ready to set coverage targets or write guardrail tests.
  3. Set HARNESS_CODE_DIRS and HARNESS_TEST_CMD in harness.conf. Until then the gates cover
     nothing, and they will say so rather than reporting green. Fill the platform vars too —
     each one switches on a guard branch that is otherwise unexercised.
  4. Cut CLAUDE.md's standing rules to the ones you will actually enforce. A rule nobody
     enforces teaches the agent that rules here are decorative.
  5. Run:  scripts/run-all-gates.sh
     Expect INCOMPLETE until src/ exists and HARNESS_TEST_CMD is set — that is the suite being
     honest about covering nothing, not a failure of the install.
  6. VERIFY THE CONTROLS before trusting any of them:
        scripts/selftest.sh                   — G7 (logic): plants a violation per gate, asserts
                                                each goes red, then recovers.
        scripts/hook-pretooluse-guard-test.sh — the guard's known-answer matrix; it reports the
                                                rows your harness.conf leaves unexercised.
        G8 (wiring)                           — do this half yourself: edit a doc through the
                                                agent with a bad link and watch the block arrive.
                                                Calling the script proves only the script.
  7. After the first week, read .gate-logs/ (stop-advisory, read-budget) and tune or delete what
     never fires. Keep the C5 table current as gates land.

  This kit's own meta files (README.md, TAILORING.md, running-files/, sops/, ci/, harness.conf.example)
  are now duplicated under docs/. Remove the originals when you are ready:  git rm -r running-files sops ci
  (CLAUDE.md's pointers are written for the post-init docs/ layout, so they survive that removal.)

  Starting a NEW project rather than a fork of the harness? Drop its history too:
      rm -rf .git && git init && git add -A && git commit -m "«project»: initial harness install"

NEXT
