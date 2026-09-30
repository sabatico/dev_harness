#!/usr/bin/env bash
# hook-stop-claimcheck-test.sh — known-answer matrix for claim-check.py (S1 self-proof pattern).
#
# Two halves, both mandatory, because the checker's whole value rests on its DESIGN RULE ("silent
# unless definitely false"): the FLAG rows are hallucination shapes it exists to catch (invented file,
# line past EOF, invented ADR/BUG id, fabricated quote); the PASS rows are the legitimate replies
# nearest each rule (proposals, historic ids, web-sourced quotes, the user's own words, code blocks,
# emphasis/curly-quote differences). A change that flips ANY row is a regression, either direction.
# Runs against a fake project root in a temp dir, so the real repo can never mask a row.
# Gated in run-all-gates.sh (fast tier).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CC="$HERE/claim-check.py"
T="$(mktemp -d "${TMPDIR:-/tmp}/cc-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
R="$T/root"; P="$R"
mkdir -p "$P/docs/decisions" "$P/docs/ai" "$P/docs/registers" "$P/scripts"
printf 'HARNESS_DECISION_DIR="docs/decisions"\nHARNESS_DECISION_PREFIX="ADR"\nHARNESS_BUG_REGISTER="docs/registers/bug-register.md"\nHARNESS_CORPUS_DIRS="docs"\n' > "$R/harness.conf"
echo "# fake CLAUDE.md" > "$R/CLAUDE.md"
printf 'ADR-001 alpha\n\nThe release requires two KeyKeepers to approve before any key material leaves the enclave.\n' > "$P/docs/decisions/ADR-001-alpha.md"
printf 'ADR-005 epsilon\n' > "$P/docs/decisions/ADR-005-epsilon.md"
printf '# ADR log\n- ADR-002 was withdrawn in the spike and never re-filed.\n' > "$P/docs/decisions/README.md"
{ echo '| id | title |'; for i in 001 002 003 005 006 007 008 009 010; do echo "| BUG-$i | a bug |"; done; } > "$P/docs/registers/bug-register.md"
printf 'line one\nA vector store returns the *plausible neighbour*. That is the same output distribution as the failure.\nline three\nline four\nline five\n' > "$P/docs/ai/notes.md"
mkdir -p "$P/src/internal/http" "$P/src/cmd/pii-rotate"
seq 1 200 | sed 's/^/l/' > "$P/src/internal/http/release_handlers.go"
printf 'package main\n// WithKeyring: active MUST be in the ring, or sign() uses an empty key.\n' > "$P/src/cmd/pii-rotate/main.go"
printf 'Owners may name up to three KeyKeepers and never fewer than two at any time.\n' > "$P/docs/ai/other.md"
export HARNESS_ROOT_OVERRIDE="$R" HARNESS_LOG_DIR="$T/logs" HARNESS_DECISION_DIR="docs/decisions" HARNESS_BUG_REGISTER="docs/registers/bug-register.md" HARNESS_CORPUS_DIRS="docs"
pass=0; fail=0; n=0

# transcript <file> <last-reply-text> [user-prompt] [tool-output] — an older turn with a BAD link,
# then the turn under test (its prompt and one tool result are what the agent has SEEN).
transcript() { python3 - "$1" "$2" "${3:-new question}" "${4:-ok}" <<'PY'
import json, sys
path, reply, prompt, toolout = sys.argv[1:5]
E = [
  {"type": "user", "message": {"role": "user", "content": "old question"}},
  {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "old answer [x](docs/ai/OLD-MISSING.md)"}]}},
  {"type": "user", "message": {"role": "user", "content": prompt}},
  {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {}}]}},
  {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": toolout}]}},
  {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": reply}]}},
]
with open(path, "w") as f:
    for e in E: f.write(json.dumps(e) + "\n")
PY
}

# row <label> <want: regex-in-message | NONE> <reply-text> [extra env...]
row() {
  local label="$1" want="$2" reply="$3"; shift 3
  n=$((n+1)); local tp="$T/t$n.jsonl"
  transcript "$tp" "$reply" "${ROW_PROMPT:-new question}" "${ROW_TOOL:-ok}"
  local out; out="$(cd "$R" && printf '{"session_id":"s%s","transcript_path":"%s"}' "$n" "$tp" | env "$@" python3 "$CC")"
  local ok=1
  if [ "$want" = NONE ]; then [ -z "$out" ] || ok=0
  else printf '%s' "$out" | grep -qE "$want" || ok=0; fi
  if [ "$ok" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  $label"; echo "      out: ${out:-<silent>}"; fi
}
L='docs/ai/notes.md'

# ── must FLAG: the hallucination shapes ───────────────────────────────────────
row 'invented linked file'            'linked file does not exist'        "See [notes]($P/docs/ai/missing.md) for detail."
row 'line past end of file'           'line 99 is past the end'           "See [notes]($L:99)."
row 'invented file:line in backticks' 'file:line reference does not exist' 'The fix is in `scripts/nope.sh:12`.'
row 'invented ADR in the numbered range' 'ADR-003 does not exist'         'Per ADR-003 the release is gated.'
row 'invented BUG id inside the range'   'BUG-004 is not'                 'BUG-004 was fixed last week.'
row 'fabricated quote, cited file'    'quote appears nowhere'                   "The [notes]($L) say \"a vector index always improves recall on small corpora\"."
row 'fabricated fragment after an ellipsis' 'quote appears nowhere'             "The [notes]($L) say \"A vector store returns the plausible neighbour … and embeddings are always cheaper than grep here\"."
row 'fabricated blockquote under a cited line' 'quote appears nowhere'          "As [notes]($L) put it:
> embeddings are the right tool for fabricated specifics every time"

row 'attributed via § + verb, fabricated' 'quote appears nowhere'          "§4 of [notes]($L) reads \"embeddings are the right tool for this failure mode\"."
row 'attributed via a colon, fabricated'   'quote appears nowhere'          "[notes]($L): \"embeddings are the right tool for this failure mode\""
row 'invented bare filename:line'     'file:line reference does not exist' 'The check lives in `nonexistent_handlers.go:40`.'
row 'real bare filename, line past its end' 'line 900 is past the end'      'See `release_handlers.go:900`.'

# ── must PASS: the legitimate replies nearest each rule ───────────────────────
row 'real link with a real line'      NONE "See [notes]($L:3)."
row 'real link with an #anchor'       NONE "See [ADR-001](docs/decisions/ADR-001-alpha.md#decision)."
row 'web link'                        NONE "Source: [study](https://example.com/study.html)."
row 'ADR above the max is a proposal' NONE 'This becomes ADR-006 once written.'
row 'historic ADR mentioned in the log' NONE 'ADR-002 was withdrawn long ago.'
row 'BUG above the max is a proposal' NONE 'I will file this as BUG-011.'
row 'verbatim quote with markdown/curly/space differences' NONE "The [notes]($L) say “A vector store  returns the plausible neighbour. That is the same output distribution as the failure.”"
row 'verbatim quote across an ellipsis' NONE "The [notes]($L) say \"A vector store returns the plausible neighbour … That is the same output distribution as the failure\"."
row 'verbatim blockquote under a cited line' NONE "As [notes]($L) put it:
> A vector store returns the *plausible neighbour*. That is the same output distribution as the failure."
row 'quote from an ADR cited by id'   NONE 'ADR-001 says "The release requires two KeyKeepers to approve before any key material leaves the enclave."'
row 'fabricated quote but a web source in the paragraph' NONE "The [notes]($L) and [the study](https://example.com) say \"embeddings always win on recall for any corpus size\"."
row 'quote with no repo citation (user words)' NONE 'You said "implement it all here and then generalize it one level up".'
row 'short quote under the word floor' NONE "The [notes]($L) say \"always cheaper\"."
row 'invented path inside a code fence' NONE 'Run this:
```
bash scripts/not-yet-written.sh:4
cat [x](docs/nope.md)
```'
row 'bare backticked path (a proposal)' NONE 'I will create `scripts/new-thing.sh` next.'
row 'bad link in an EARLIER turn is not re-judged' NONE 'All clear now.'
# The false-positive classes found by the live project's 2026-09-29 audit of 1,093 real turns — each must stay silent.
row 'bare filename:line that exists in a subdir' NONE 'See `release_handlers.go:120`.'
row 'partial path that exists by suffix'  NONE 'See `cmd/pii-rotate/main.go:1`.'
row 'IP:port is not a file'               NONE 'The DB is at `192.168.65.1:5432`.'
row 'real quote from a DIFFERENT corpus file than the one cited' NONE "The [notes]($L) and the register agree: \"Owners may name up to three KeyKeepers and never fewer than two\"."
ROW_PROMPT='please do all as recommended except five and eight, thanks' \
row "the owner's own words, quoted"       NONE "Per [notes]($L) and your ruling \"all as recommended except five and eight\" I will proceed."
ROW_TOOL='Opting out removes any existing stored knowledge base data for this repository.' \
row 'text quoted from a tool result this session' NONE "The [notes]($L) aside, the docs said \"Opting out removes any existing stored knowledge base data\"."
row 'unattributed quote near a citation (proposed UI copy)' NONE "The [notes]($L) matter here, and separately the new consent button label will read \"I have told this person and you may contact them\"."
row 'attributed quote of a CODE comment (not in any doc)' NONE "Per [notes]($L), \`WithKeyring\` says \"active MUST be in the ring, or sign() uses an empty key\"."
row 'quote marks paired across code spans' NONE "The [notes]($L) name the \`\"login\"\`-purpose session, while the function below states the \"security\" purpose is never reused anywhere."

# ── modes, payload shapes, logging ────────────────────────────────────────────
row 'block mode makes the model self-correct' '"decision": "block"' 'BUG-004 was fixed.' HARNESS_CLAIMCHECK_MODE=block
n=$((n+1)); tp="$T/t$n.jsonl"; transcript "$tp" 'BUG-004 was fixed.'
out="$(cd "$R" && printf '{"session_id":"s%s","transcript_path":"%s","stop_hook_active":true}' "$n" "$tp" | HARNESS_CLAIMCHECK_MODE=block python3 "$CC")"
if printf '%s' "$out" | grep -q systemMessage && ! printf '%s' "$out" | grep -q '"decision"'; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  block mode never re-blocks when stop_hook_active"; echo "      out: $out"; fi
n=$((n+1))
out="$(cd "$R" && printf '{"session_id":"s%s","last_assistant_message":"Per ADR-003 it is done."}' "$n" | python3 "$CC")"
if printf '%s' "$out" | grep -q 'ADR-003'; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  last_assistant_message in the payload is used"; fi
if grep -qE 'session=s1 links=1 lines=0 ids=0 quotes=0 flagged=1' "$T/logs/claim-check.log" && grep -qE 'links=1 lines=1 ids=0 quotes=0 flagged=0' "$T/logs/claim-check.log"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  every run logs its counts (flagged and clean)"; fi
n=$((n+1)); tp="$T/t$n.jsonl"; transcript "$tp" "See [x](docs/ai/claimcheck-wrapper-probe-missing.md)."
out="$(printf '{"session_id":"s%s","transcript_path":"%s"}' "$n" "$tp" | bash "$HERE/hook-stop-claimcheck.sh")"
if printf '%s' "$out" | grep -q 'linked file does not exist'; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  the hook wrapper delivers the verdict"; echo "      out: ${out:-<silent>}"; fi

echo "claim-check matrix: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
