#!/usr/bin/env bash
# harness-eval.sh — task-embedded retrieval eval: does the MAIN agent look a fact up, or answer from
# memory? Generalised 2026-09-29 from a live project (it extended that project's librarian eval).
#
# WHY: the librarian eval proved accuracy WHEN CALLED (6/6). The live owner's 2026-09-29 complaint is the
# other half — "even opus level main agent misses things a lot and hallucinates 'from memory' instead of
# every time researching". A direct question ("what does migration 12 say?") always triggers a lookup,
# so it cannot measure that. Each probe in harness-eval-probes.json is an ordinary planning task in which
# one repo fact is INCIDENTAL, with its truth read from code (file:line recorded per probe).
#
# Each probe runs as a FRESH headless session (`claude -p`, plan mode = read-only, bounded turns) from the
# repo root, so CLAUDE.md, the hooks and the session brief load exactly as they do for a real session.
# The scorer then reads that session's transcript:
#   RETRIEVED  a tool input (Read path, Bash/Grep command, librarian delegation) touched the fact's source
#              BEFORE the final answer — the §1.4b behaviour under test;
#   CORRECT    the truth appears in the answer;  WRONG  a plausible wrong value appears;
#   CLAIMS     what claim-check.py flags in the answer (the Stop hook's verdict, recomputed).
# Results append to .harness-logs/harness-eval.log (one JSON line per probe) — rerun after a harness
# change and compare; a single run is an anecdote, the log is the measurement.
#
# COST: every probe is a real model session (~$0.3–1.5 each at Opus prices, bounded by --max-turns).
# Owner-triggered, never gated — same rule as --live: it spends money and depends on a provider.
#
# Usage: scripts/harness-eval.sh [probe-id ...]     (default: all probes)
#        EVAL_MODEL=<model> EVAL_MAX_TURNS=15 scripts/harness-eval.sh
set -uo pipefail
ROOT="${HARNESS_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "$0")/.." && pwd))}"; PROJ="$ROOT"
[ -f "$ROOT/harness.conf" ] && . "$ROOT/harness.conf"
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || ls -d "$HOME/Library/Application Support/Claude/claude-code/"*/claude.app/Contents/MacOS/claude 2>/dev/null | sort -V | tail -1)}"
[ -x "$CLAUDE_BIN" ] || { echo "harness-eval: no claude CLI found (set CLAUDE_BIN)"; exit 2; }
PROBES="$PROJ/scripts/harness-eval-probes.json"
OUT="$ROOT/${HARNESS_LOG_DIR:-.harness-logs}"; mkdir -p "$OUT"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ids=("$@"); [ ${#ids[@]} -gt 0 ] || ids=($(python3 -c 'import json,sys; print(" ".join(p["id"] for p in json.load(open(sys.argv[1]))["probes"]))' "$PROBES"))

for id in "${ids[@]}"; do
  prompt="$(python3 -c 'import json,sys; print(next(p["prompt"] for p in json.load(open(sys.argv[1]))["probes"] if p["id"]==sys.argv[2]))' "$PROBES" "$id")" || { echo "unknown probe: $id"; continue; }
  res="$OUT/eval-$id-${STAMP//:/}.json"
  args=(-p "$prompt" --permission-mode plan --output-format json --max-turns "${EVAL_MAX_TURNS:-15}")
  [ -n "${EVAL_MODEL:-}" ] && args+=(--model "$EVAL_MODEL")
  (cd "$ROOT" && "$CLAUDE_BIN" "${args[@]}" > "$res" 2>"$res.err" < /dev/null)
  python3 - "$PROBES" "$id" "$res" "$STAMP" "$OUT/harness-eval.log" "$PROJ/scripts/claim-check.py" <<'PY'
import glob, importlib.util, json, os, re, sys
probes, pid, res, stamp, logf, ccpath = sys.argv[1:7]
P = next(p for p in json.load(open(probes))["probes"] if p["id"] == pid)
try:
    r = json.load(open(res))
except Exception as e:
    print(f"{pid:22} ERROR: no JSON result ({e}); see {res}.err"); sys.exit(0)
answer, sid = r.get("result") or "", r.get("session_id", "")
# A session that never ran is NOT a measurement (first pilot, 2026-09-29: the bundled CLI was not
# logged in — every probe returned "Not logged in · Please run /login" at $0.00 and was scored
# "NO-VALUE-GIVEN"). Refuse to log it; say what to do.
if r.get("is_error") or not r.get("num_turns") or re.search(r"not logged in|/login|invalid api key", answer, re.I):
    print(f"{pid:22} RUN-ERROR (not logged as a measurement): {' '.join(answer.split())[:100]!r}"
          f" — if it says 'Not logged in', run `claude` once in a terminal and /login, then rerun.")
    sys.exit(0)
tp = next(iter(glob.glob(os.path.expanduser(f"~/.claude/projects/*/{sid}.jsonl"))), None) if sid else None
inputs = []
if tp:
    for line in open(tp, errors="replace"):
        try: d = json.loads(line)
        except ValueError: continue
        if d.get("type") == "assistant":
            for b in (d.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    inputs.append((b.get("name"), json.dumps(b.get("input") or {})))
rx = re.compile(P["retrieval"], re.I)
retrieved = any(rx.search(i) for _, i in inputs)
delegated = any(n in ("Agent", "Task", "Skill") and "librarian" in i for n, i in inputs)
correct = bool(re.search(P["correct"], answer, re.I))
wrong = bool(re.search(P["wrong"], answer, re.I))
spec = importlib.util.spec_from_file_location("cc", ccpath); cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
flags, _ = cc.check(answer)
verdict = ("LOOKED-UP+RIGHT" if retrieved and correct and not wrong else
           "RIGHT-UNVERIFIED" if correct and not wrong and not retrieved else
           "FROM-MEMORY-WRONG" if wrong and not retrieved else
           "WRONG-DESPITE-LOOKUP" if wrong else "NO-VALUE-GIVEN")
row = {"at": stamp, "probe": pid, "verdict": verdict, "retrieved": retrieved, "delegated": delegated,
       "correct": correct, "wrong": wrong, "claim_flags": len(flags), "tool_calls": len(inputs),
       "turns": r.get("num_turns"), "cost_usd": r.get("total_cost_usd"), "session": sid[:8],
       "truth": P["truth"], "source": P["source"], "answer_head": " ".join(answer.split())[:240]}
open(logf, "a").write(json.dumps(row) + "\n")
print(f"{pid:22} {verdict:20} retrieved={retrieved!s:5} delegated={delegated!s:5} tools={len(inputs):2} "
      f"cost=${(r.get('total_cost_usd') or 0):.2f}  truth: {P['truth']}")
PY
done
echo "log: $OUT/harness-eval.log"
