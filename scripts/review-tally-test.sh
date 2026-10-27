#!/usr/bin/env bash
# review-tally-test.sh — known-answer matrix for scripts/lib/review_tally.py (cross-author: written by a model that did not
# build the script, from its header and code, and from its docstring).
#
# review_tally.py is the ONE reader of a reviewer's answer (parse: finding ids, severity, tag, file, lines) and the vote
# count of several answers (tally: a finding is kept when 2 voters name the same place). check-the-work.sh (judge, tally)
# leans on it, so a wrong reading here silently changes what a sub-session must judge. Every row runs the CLI on answer files written here, with oracles written BY HAND
# (the expected tag, the expected window boundary, the expected goal verdict), never computed by the script under test.
# Each negative assertion has a positive control beside it (T2 of the writing-tests skill).
#
# Rows that FAIL against the script are findings, not mistakes in the row: they keep their expectation and say "FINDING" in
# their name until the script is fixed. Do not weaken them to make the matrix green.
# TALLY_UNDER_TEST=<path> runs the matrix against a mutated copy of review_tally.py (used to prove each row red).
# Exit: 0 every row passed · 1 any row failed · 3 could not run (python3 missing, script missing).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="${TALLY_UNDER_TEST:-$HERE/lib/review_tally.py}"
[ -f "$SUT" ] || { echo "review-tally-test: INCOMPLETE - the script under test is missing: $SUT"; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "review-tally-test: INCOMPLETE - python3 is missing"; exit 3; }

T="$(mktemp -d "${TMPDIR:-/tmp}/rtally-test.XXXXXX")" || { echo "review-tally-test: INCOMPLETE - mktemp failed"; exit 3; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/a"

# ── the framework (the same shape as scripts/check-the-work-test.sh) ─────────────────────────────────────────────────
N=0; PASSED=0; WHY=""; NAME=""
fail() { WHY="$WHY | $*"; }
begin() { WHY=""; N=$((N + 1)); NAME="$1"; }
finish() {
  if [ -z "$WHY" ]; then PASSED=$((PASSED + 1)); echo "PASS  $NAME"; else echo "FAIL  $NAME -- ${WHY# | }"; fi
}
OUTF="$T/out"; ERRF="$T/err"; META="$T/meta.json"; RC=0
want_rc() { [ "$RC" = "$1" ] || fail "exit $RC, wanted $1 (stderr: $(head -c 300 "$ERRF" | tr '\n' '~'))"; }
has() { grep -qF -- "$2" "$1" 2>/dev/null || fail "${3:-$(basename "$1")}: missing '$2'"; }
lacks() { ! grep -qF -- "$2" "$1" 2>/dev/null || fail "${3:-$(basename "$1")}: must not contain '$2'"; }
eq() { [ "$1" = "$2" ] || fail "${3:-value}: got '$1', wanted '$2'"; }

tly() { python3 -I "$SUT" "$@" >"$OUTF" 2>"$ERRF" </dev/null; RC=$?; }
A() { local n="$1"; shift; printf '%s\n' "$@" >"$T/a/$n"; }   # A <name> <lines...>: an answer file
pj() { python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
print(eval(sys.argv[2]))' "$@"; }
# parse_of <name>: run `parse` on an answer file; the JSON stays in $OUTF
parse_of() { tly parse "$T/a/$1"; }
V='VERDICT: FINDINGS'; G='GOAL: MET — ok'

# ══ parse: tags ═══════════════════════════════════════════════════════════════════════════════════════════════════════
r_parse_tags() {
  A tags "$V" "$G" \
    'F1 [P1] [important] a.go:1 — x' 'F2 [P3] [nit] a.go:2 — x' 'F3 [P2] [pre-existing] a.go:3 — x' \
    'F4 [P2] [preexisting] a.go:4 — x' 'F5 [P2] [Pre-Existing] a.go:5 — x' 'F6 [P2] a.go:6 — no tag at all' \
    'F7 [P3] [NIT] a.go:7 — x' 'F8 [P2] [Important] a.go:8 — x' 'F9 [P2] [pre existing] a.go:9 — a space is no tag' \
    'F10 [P2] nit a.go:10 — an unbracketed word is no tag'
  parse_of tags; want_rc 0
  eq "$(pj "$OUTF" "[f['tag'] for f in d]")" "['important', 'nit', 'pre-existing', 'pre-existing', 'pre-existing', 'untagged', 'nit', 'important', 'untagged', 'untagged']" "tags in order"
  eq "$(pj "$OUTF" "[f['id'] for f in d]")" "['F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10']" "ids in order"
}
r_parse_severity() {
  A sev "$V" 'F1 [P0] [important] a.go:1' 'F2 [p1] [important] a.go:2' 'F3 [ P2 ] [important] a.go:3' 'F4 [important] a.go:4' 'F5 [P4] [important] a.go:5'
  parse_of sev; want_rc 0
  eq "$(pj "$OUTF" "[f['sev'] for f in d]")" "['P0', 'P1', 'P2', None, None]" "severities (lower case and padded read; no severity / P4 is None)"
}
r_parse_severity_never_a_path() {
  # "[P1]" and the tags must never be read as the file; the file comes after them
  A sevpath "$V" 'F1 [P1] [important] pkg/x/y.go:10 — d'
  parse_of sevpath; want_rc 0
  eq "$(pj "$OUTF" "d[0]['path']")" "pkg/x/y.go" "path"; eq "$(pj "$OUTF" "(d[0]['lo'], d[0]['hi'])")" "(10, 10)" "lines"
}

# ══ parse: locations ══════════════════════════════════════════════════════════════════════════════════════════════════
r_parse_locations() {
  A loc "$V" \
    'F1 [P1] [important] pkg/x/y.go:10-20 — a' 'F2 [P1] [important] y.go:20-10 — reversed' 'F3 [P1] [important] y.go:10–20 — en dash' \
    'F4 [P1] [important] y.go — no line' 'F5 [P1] [important] a/y.go:3 — diff prefix' 'F6 [P1] [important] b/y.go:3 — diff prefix' \
    'F7 [P1] [important] ./y.go:3 — dot prefix' 'F8 [P1] [important] no file at all — text' 'F9 [P1] [important] y.go:5 — see also z.go:99' \
    'F10 [P1] [important] y.go:7 - 9 — spaced range' 'F11 earlier.go [P1] [important] y.go:7 — the location is looked for after the tags'
  parse_of loc; want_rc 0
  eq "$(pj "$OUTF" "[(f['path'], f['lo'], f['hi']) for f in d]")" \
    "[('pkg/x/y.go', 10, 20), ('y.go', 10, 20), ('y.go', 10, 20), ('y.go', None, None), ('y.go', 3, 3), ('y.go', 3, 3), ('y.go', 3, 3), (None, None, None), ('y.go', 5, 5), ('y.go', 7, 9), ('y.go', 7, 7)]" \
    "(path, from, to) of each finding"
}
r_parse_huge_line_numbers() {
  A huge "$V" 'F1 [P1] [important] x.go:99999999999999999999999 — a' 'F2 [P1] [important] x.go:0 — zero'
  parse_of huge; want_rc 0
  eq "$(pj "$OUTF" "d[0]['lo']")" "99999999999999999999999" "a very large line number is read, not a crash"
  eq "$(pj "$OUTF" "d[1]['lo']")" "0" "line 0"
}

# ══ parse: ids ════════════════════════════════════════════════════════════════════════════════════════════════════════
r_parse_ids() {
  A ids "$V" '  F1 [P1] [important] a.go:1 — indented' $'\tF2 [P1] [important] a.go:2 — tab' 'F12 [P1] [important] a.go:3 — twelve' \
    'F5x [P1] [important] a.go:4 — glued, not an id' 'F 5 [P1] [important] a.go:5 — spaced, not an id' 'f6 [P1] [important] a.go:6 — lower case' \
    'see F7 [P1] a.go:7 — mid-line' 'F1 [P3] [nit] a.go:8 — the second F1 is ignored' 'UNSEEN: F9 was cut'
  parse_of ids; want_rc 0
  eq "$(pj "$OUTF" "[f['id'] for f in d]")" "['F1', 'F2', 'F12']" "only a line that STARTS with F<n> is a finding; the first F1 wins"
  eq "$(pj "$OUTF" "d[0]['tag']")" "important" "the duplicate F1 did not replace the first"
}
r_parse_also_asked_prefix() {
  A also "$V" 'F1 [P1] [important] a.go:1 — main' '===== ALSO-ASKED OPINION: other' 'VERDICT: FINDINGS' 'F1 [P1] [important] b.go:2 — other' 'F2 [P3] [nit] b.go:3 — other nit'
  parse_of also; want_rc 0
  eq "$(pj "$OUTF" "[f['id'] for f in d]")" "['F1', 'other:F1', 'other:F2']" "ids after an ALSO-ASKED header carry the model name"
  eq "$(pj "$OUTF" "d[1]['path']")" "b.go" "path of the prefixed finding"
}
r_parse_empty_and_binary() {
  : >"$T/a/empty"; tly parse "$T/a/empty"; want_rc 0; eq "$(cat "$OUTF")" "[]" "an empty answer has no findings"
  printf 'VERDICT: FINDINGS\nF1 [P1] [important] a.go:1 \xff\xc3 bad bytes\n' >"$T/a/bin"; tly parse "$T/a/bin"; want_rc 0
  eq "$(pj "$OUTF" "d[0]['id']")" "F1" "invalid UTF-8 is replaced, the finding is still read"
}

# ══ parse / CLI: exit codes ═══════════════════════════════════════════════════════════════════════════════════════════
r_cli_exit_codes() {
  tly; want_rc 2; has "$ERRF" "tally" "usage on stderr"
  tly frobnicate; want_rc 2
  tly parse; want_rc 2
  tly parse "$T/a/no-such-file"; want_rc 3; has "$ERRF" "cannot read" "stderr"; lacks "$ERRF" "Traceback" "stderr"
  tly parse "$T/a"; want_rc 3   # a directory
  A okfile "$V" 'F1 [P1] [important] a.go:1 — x'; tly parse "$T/a/okfile"; want_rc 0   # positive control
}

# ══ tally: the same place ═════════════════════════════════════════════════════════════════════════════════════════════
fa() { printf '%s\n' "$V" "$G" "F1 [P1] [important] $1 — defect A"; }   # fa <loc> → one-finding answer text
agree() { # agree <window or ""> <locA> <locB>: run a two-voter tally; RC 0; echo "yes" when the finding is kept
  fa "$2" >"$T/a/ag-A"; fa "$3" >"$T/a/ag-B"
  if [ -n "$1" ]; then tly tally --window "$1" --meta "$META" A="$T/a/ag-A" B="$T/a/ag-B"; else tly tally --meta "$META" A="$T/a/ag-A" B="$T/a/ag-B"; fi
  [ "$RC" = 0 ] || { fail "tally exit $RC for $2 / $3 (stderr: $(head -c 200 "$ERRF"))"; echo err; return; }
  if grep -q '^F1 ' "$OUTF"; then echo yes; else echo no; fi
}
r_two_voters_agree() {
  fa x.go:10 >"$T/a/A"; fa x.go:12 >"$T/a/B"; tly tally --meta "$META" A="$T/a/A" B="$T/a/B"; want_rc 0
  has "$OUTF" "VERDICT: FINDINGS"; has "$OUTF" "F1 [P1] [important] x.go:10 — agreed by A, B (2 of 2 voters)"; lacks "$OUTF" "UNCONFIRMED" "output (nothing is single)"
  eq "$(pj "$META" "d['confirmed']")" "[{'id': 'F1', 'voters': ['A', 'B'], 'from': ['A:F1', 'B:F1']}]" "meta confirmed"
  eq "$(pj "$META" "d['unconfirmed']")" "[]" "meta unconfirmed"
}
r_window_boundary_default() {
  # the default window is 15 lines: a gap of exactly 15 agrees, 16 does not (hand-computed from "within WINDOW lines")
  eq "$(agree "" x.go:10 x.go:25)" yes "gap 15, B after A"
  eq "$(agree "" x.go:10 x.go:26)" no "gap 16, B after A"
  eq "$(agree "" x.go:40 x.go:25)" yes "gap 15, B before A"
  eq "$(agree "" x.go:40 x.go:24)" no "gap 16, B before A"
  eq "$(agree "" x.go:10-20 x.go:35)" yes "range end 20 to 35 is a gap of 15"
  eq "$(agree "" x.go:10-20 x.go:36)" no "range end 20 to 36 is a gap of 16"
  eq "$(agree "" x.go:10-20 x.go:15)" yes "inside the range"
}
r_window_flag() {
  eq "$(agree 0 x.go:10 x.go:10)" yes "window 0, same line"
  eq "$(agree 0 x.go:10 x.go:11)" no "window 0, next line"
  eq "$(agree 500 x.go:10 x.go:510)" yes "window 500, gap 500"
  eq "$(agree 500 x.go:10 x.go:511)" no "window 500, gap 501"
  eq "$(agree 3 x.go:10 x.go:13)" yes "window 3, gap 3"; eq "$(agree 3 x.go:10 x.go:14)" no "window 3, gap 4"
  eq "$(pj "$META" "d['window']")" "3" "the window is recorded in the meta"
  has "$OUTF" "window 3 lines" "VOTE line"
}
r_not_agreed_is_unconfirmed() {
  fa x.go:10 >"$T/a/A"; fa x.go:90 >"$T/a/B"; tly tally --meta "$META" A="$T/a/A" B="$T/a/B"; want_rc 0
  has "$OUTF" "VERDICT: PASS" "no finding kept → PASS"; lacks "$OUTF" "agreed by" "output"
  has "$OUTF" "UNCONFIRMED (named by one voter only; on record, no judgement needed):"; has "$OUTF" "U1 (only A) F1 [P1]"; has "$OUTF" "U2 (only B) F1 [P1]"
  eq "$(pj "$META" "[(u['id'], u['voter'], u['finding']) for u in d['unconfirmed']]")" "[('U1', 'A', 'F1'), ('U2', 'B', 'F1')]" "meta unconfirmed"
  eq "$(pj "$META" "d['confirmed']")" "[]" "meta confirmed"
}
r_file_matching() {
  eq "$(agree "" a/b.go:5 b.go:5)" yes "a path that is the tail of the other (diff prefix style)"
  eq "$(agree "" b.go:5 src/b.go:5)" yes "the tail match works both ways"
  eq "$(agree "" pkg/b.go:5 b.go:5)" yes "a folder in front"
  eq "$(agree "" src/b.go:5 xb.go:5)" no "xb.go is not src/b.go"
  eq "$(agree "" b.go:5 xb.go:5)" no "xb.go is not b.go (the tail must start at a folder boundary)"
  eq "$(agree "" xb.go:5 b.go:5)" no "b.go is not xb.go (either direction)"
  eq "$(agree "" src/b.go:5 xsrc/b.go:5)" no "xsrc/b.go is not src/b.go"
  eq "$(agree "" x/b.go:5 y/b.go:5)" no "same name in two folders"
  eq "$(agree "" src/a/b.go:5 other/a/b.go:5)" no "two longer paths that end alike are not the same file"
  eq "$(agree "" x.go:5 y.go:5)" no "different files"
  eq "$(agree "" x.go:5 x.go:6)" yes "positive control: the same file, next line"
}
r_file_without_line_agrees_on_that_file() {
  # header: "a finding with a file but no line agrees with any finding on that file"
  eq "$(agree "" x.go:900 x.go)" yes "one side has no line"
  eq "$(agree "" x.go x.go)" yes "both sides have no line"
  eq "$(agree "" x.go y.go)" no "no line, different files"
}
r_finding_without_file_never_agrees() {
  printf '%s\n' "$V" "$G" 'F1 [P1] [important] the check is missing — no file named here' >"$T/a/A"
  cp "$T/a/A" "$T/a/B"; tly tally --meta "$META" A="$T/a/A" B="$T/a/B"; want_rc 0
  has "$OUTF" "VERDICT: PASS" "two voters with the same file-less words do not confirm each other"; has "$OUTF" "U1 (only A)"; has "$OUTF" "U2 (only B)"
  # a file-less finding next to a finding with a file
  fa x.go:5 >"$T/a/C"; tly tally --meta "$META" A="$T/a/A" C="$T/a/C"; want_rc 0; has "$OUTF" "VERDICT: PASS" "file-less vs a file"
  # positive control: with a file, the same two voters agree
  fa x.go:5 >"$T/a/D"; fa x.go:5 >"$T/a/E"; tly tally --meta "$META" D="$T/a/D" E="$T/a/E"; want_rc 0; has "$OUTF" "agreed by D, E"
}
r_voter_never_confirms_itself() {
  # A names the same place twice; B names nothing: A's two findings must stay single (quorum 2)
  printf '%s\n' "$V" "$G" 'F1 [P1] [important] x.go:10 — first' 'F2 [P1] [important] x.go:11 — second' >"$T/a/A"
  printf '%s\n' 'VERDICT: PASS' "$G" >"$T/a/B"
  tly tally --meta "$META" A="$T/a/A" B="$T/a/B"; want_rc 0
  has "$OUTF" "VERDICT: PASS" "output (nobody else saw it)"; lacks "$OUTF" "agreed by" "output"
  eq "$(pj "$META" "len(d['unconfirmed'])")" "2" "both of A's findings are on record as unconfirmed"
  # positive control: B names the place once → exactly ONE cluster is kept, the other of A's findings stays single
  printf '%s\n' "$V" "$G" 'F1 [P1] [important] x.go:10 — B sees it' >"$T/a/B2"
  tly tally --meta "$META" A="$T/a/A" B="$T/a/B2"; want_rc 0
  eq "$(grep -c '^F[0-9]' "$OUTF")" "1" "one kept finding"; eq "$(pj "$META" "len(d['unconfirmed'])")" "1" "A's second finding stays single"
  has "$OUTF" "agreed by A, B (2 of 2 voters)"
}
r_output_order_follows_clusters() {
  printf '%s\n' "$V" "$G" 'F1 [P1] [important] x.go:300 — far' 'F2 [P1] [important] x.go:10 — near' >"$T/a/A"
  printf '%s\n' "$V" "$G" 'F1 [P1] [important] x.go:10 — near' >"$T/a/B"
  tly tally --meta "$META" A="$T/a/A" B="$T/a/B"; want_rc 0
  has "$OUTF" "F1 [P1] [important] x.go:10 — agreed by A, B"; has "$OUTF" "U1 (only A) F1 [P1] [important] x.go:300"
}

# ══ tally: quorum ═════════════════════════════════════════════════════════════════════════════════════════════════════
r_quorum() {
  fa x.go:10 >"$T/a/A"
  tly tally --meta "$META" A="$T/a/A"; want_rc 0
  has "$OUTF" "F1 [P1] [important] x.go:10 — agreed by A (1 of 1 voters)" "one voter: its finding is kept"; has "$OUTF" "a finding is kept when 1 agree"
  eq "$(pj "$META" "d['quorum']")" "1" "quorum with one voter"
  fa x.go:10 >"$T/a/B"; fa x.go:11 >"$T/a/C"; fa x.go:500 >"$T/a/D"
  tly tally --meta "$META" A="$T/a/A" B="$T/a/B" D="$T/a/D"; want_rc 0
  has "$OUTF" "agreed by A, B (2 of 3 voters)" "2 of 3 is enough (quorum 2, not all)"; has "$OUTF" "U1 (only D)"; eq "$(pj "$META" "d['quorum']")" "2" "quorum with three voters"
  tly tally --meta "$META" A="$T/a/A" B="$T/a/B" C="$T/a/C"; want_rc 0; has "$OUTF" "agreed by A, B, C (3 of 3 voters)"
}
r_third_voter_cannot_double_a_cluster() {
  # C names the place twice: its first joins the cluster of A and B, its second must not join (C is in it already)
  fa x.go:10 >"$T/a/A"; fa x.go:10 >"$T/a/B"
  printf '%s\n' "$V" "$G" 'F1 [P1] [important] x.go:10 — one' 'F2 [P1] [important] x.go:11 — two' >"$T/a/C"
  tly tally --meta "$META" A="$T/a/A" B="$T/a/B" C="$T/a/C"; want_rc 0
  has "$OUTF" "(3 of 3 voters)"; lacks "$OUTF" "(4 of 3" "output"; has "$OUTF" "U1 (only C) F2"
}

# ══ tally: tag, severity, goal ════════════════════════════════════════════════════════════════════════════════════════
# tag_of <tagA> <tagB> [<tagC>]: the tag of the kept finding when voters name x.go:10 with those tags ("none" = no tag)
# A voter may carry its own severity as <tag>@<Pn>; the default is P2 on purpose: since then a [P1] or [P0] finding is never a nit,
# so a "[P1] [nit]" voter reads important and would break the tie rows below, which are about the vote, not about that rule.
tag_of() {
  local i=0 n args=() t line sv
  for t in "$@"; do
    i=$((i + 1)); n="tg$i"; sv=P2; case "$t" in *@*) sv="${t#*@}"; t="${t%@*}" ;; esac
    if [ "$t" = none ]; then line='F1 [P1] x.go:10 — d'; else line="F1 [$sv] [$t] x.go:10 — d"; fi
    printf '%s\n' "$V" "$G" "$line" >"$T/a/$n"; args+=("V$i=$T/a/$n")
  done
  tly tally "${args[@]}"
  [ "$RC" = 0 ] || { fail "tally exit $RC for tags $*"; echo err; return; }
  sed -n 's/^F1 \[P[0-3?]\] \[\([a-z-]*\)\] .*/\1/p' "$OUTF" | head -1
}
r_tag_majority_and_ties() {
  eq "$(tag_of important nit)" important "tie important/nit → important"
  eq "$(tag_of nit important)" important "tie nit/important (order does not matter)"
  eq "$(tag_of nit pre-existing)" pre-existing "tie nit/pre-existing → pre-existing"
  eq "$(tag_of pre-existing important)" important "tie pre-existing/important → important"
  eq "$(tag_of nit nit)" nit "both nit → nit (positive control: a nit CAN win)"
  eq "$(tag_of pre-existing pre-existing)" pre-existing "both pre-existing"
  eq "$(tag_of none nit)" important "an untagged finding counts as important"
  eq "$(tag_of none none)" important "two untagged → important"
  eq "$(tag_of nit nit important)" nit "majority of three: nit"
  eq "$(tag_of important nit pre-existing)" important "1-1-1 → important"
  eq "$(tag_of nit nit pre-existing)" nit "nit 2, pre-existing 1"
  eq "$(tag_of pre-existing pre-existing important)" pre-existing "pre-existing 2, important 1"
  eq "$(tag_of important important nit)" important "important 2, nit 1"
}
sev_of() { # sev_of <sevA> <sevB>  ("none" = no severity): the severity of the kept finding
  local i=0 t line args=()
  for t in "$@"; do
    i=$((i + 1))
    if [ "$t" = none ]; then line='F1 [important] x.go:10 — d'; else line="F1 [$t] [important] x.go:10 — d"; fi
    printf '%s\n' "$V" "$G" "$line" >"$T/a/sv$i"; args+=("V$i=$T/a/sv$i")
  done
  tly tally "${args[@]}"; sed -n 's/^F1 \[\(P[0-9?]\)\] .*/\1/p' "$OUTF" | head -1
}
r_worst_severity_wins() {
  eq "$(sev_of P2 P1)" P1 "P2 and P1"; eq "$(sev_of P1 P2)" P1 "P1 and P2"; eq "$(sev_of P0 P3)" P0 "P0 and P3"
  eq "$(sev_of P3 none)" P3 "one named severity beats none"; eq "$(sev_of none none)" "P?" "no severity at all"
  eq "$(sev_of P3 P3)" P3 "positive control: equal"
}
goal_of() { # goal_of <goal line A> <goal line B> [C]: the head of the merged GOAL line ("" = no GOAL line at all)
  local i=0 t args=()
  for t in "$@"; do
    i=$((i + 1))
    if [ -z "$t" ]; then printf '%s\n' 'VERDICT: PASS' >"$T/a/gl$i"; else printf '%s\n' 'VERDICT: PASS' "GOAL: $t" >"$T/a/gl$i"; fi
    args+=("V$i=$T/a/gl$i")
  done
  tly tally "${args[@]}"; awk -F' — ' '/^GOAL:/ { sub(/^GOAL: /, "", $1); print $1; exit }' "$OUTF"
}
r_goal_verdict_of_a_vote() {
  eq "$(goal_of 'MET — a' 'MET — b')" MET "MET MET"
  eq "$(goal_of 'MET — a' 'NOT MET — b')" "NOT MET" "MET, NOT MET: a minority MET must not close the goal"
  eq "$(goal_of 'MET — a' 'CANNOT TELL — b')" "CANNOT TELL" "MET, CANNOT TELL"
  eq "$(goal_of 'NOT MET — a' 'CANNOT TELL — b')" "NOT MET" "NOT MET wins over CANNOT TELL"
  eq "$(goal_of 'CANNOT TELL — a' 'CANNOT TELL — b')" "CANNOT TELL" "both cannot tell"
  eq "$(goal_of 'NOT MET — a' 'NOT MET — b')" "NOT MET" "both not met"
  eq "$(goal_of 'MET — a' 'MET — b' 'NOT MET — c')" MET "2 of 3 MET"
  eq "$(goal_of 'MET — a' 'NOT MET — b' 'NOT MET — c')" "NOT MET" "1 of 3 MET"
  eq "$(goal_of 'MET — a')" MET "one voter: its own verdict, MET"
  eq "$(goal_of 'NOT MET — a')" "NOT MET" "one voter: NOT MET"
  eq "$(goal_of 'CANNOT TELL — a')" "CANNOT TELL" "one voter: CANNOT TELL"
  eq "$(goal_of 'met — lower' 'Met — mixed')" MET "case does not matter"
  eq "$(goal_of 'MET' 'MET')" MET "a bare MET"
  eq "$(goal_of 'MET — a' '')" "CANNOT TELL" "a voter with no GOAL line does not count as MET"
  eq "$(goal_of '' '')" "CANNOT TELL" "no GOAL line from anybody"
  eq "$(goal_of 'not met — a' 'MET — b')" "NOT MET" "lower case NOT MET is still NOT MET (and not MET)"
}
r_goal_line_lists_every_voter() {
  printf '%s\n' 'VERDICT: PASS' 'GOAL: MET — a' >"$T/a/A"; printf '%s\n' 'VERDICT: PASS' 'GOAL: NOT MET — b' >"$T/a/B"
  tly tally --meta "$META" A="$T/a/A" B="$T/a/B"; want_rc 0
  has "$OUTF" "(A=MET; B=NOT MET)" "who said what"; eq "$(pj "$META" "d['goal_votes']")" "{'A': 'MET', 'B': 'NOT MET'}" "meta goal_votes"
}

# ══ tally: the merged text ════════════════════════════════════════════════════════════════════════════════════════════
r_unseen_and_vote_lines() {
  printf '%s\n' "$V" "$G" 'F1 [P1] [important] x.go:10 — d' 'UNSEEN: the tests were cut' >"$T/a/A"
  printf '%s\n' "$V" "$G" 'F1 [P1] [important] x.go:10 — d' >"$T/a/B"
  tly tally A="$T/a/A" B="$T/a/B"; want_rc 0
  has "$OUTF" "UNSEEN: A: the tests were cut" "UNSEEN carries what a voter could not see"
  has "$OUTF" "VOTE: 2 voter(s) answered (A, B); a finding is kept when 2 agree; window 15 lines" "VOTE line"
  tly tally A="$T/a/B"; want_rc 0; has "$OUTF" "UNSEEN: -" "no voter lists an unseen part (positive control for the line above)"
}
r_merged_text_reads_back_the_same() {
  # the judge reads the merged text with parse(): ids F1.., U-lines are not findings, the tag and place survive
  printf '%s\n' "$V" "$G" 'F1 [P1] [important] x.go:10-14 — real' 'F2 [P3] [nit] y.go:3 — style' 'F3 [P2] [important] z.go:1 — only A' >"$T/a/A"
  printf '%s\n' "$V" "$G" 'F1 [P2] [important] x.go:12 — real' 'F2 [P3] [nit] y.go:4 — style' >"$T/a/B"
  tly tally A="$T/a/A" B="$T/a/B"; want_rc 0; cp "$OUTF" "$T/a/merged"
  tly parse "$T/a/merged"; want_rc 0
  eq "$(pj "$OUTF" "[(f['id'], f['sev'], f['tag'], f['path'], f['lo'], f['hi']) for f in d]")" \
    "[('F1', 'P1', 'important', 'x.go', 10, 14), ('F2', 'P3', 'nit', 'y.go', 3, 3)]" "the merged findings as parse reads them (U-lines are not findings)"
}
r_pass_and_findings_verdict() {
  printf '%s\n' 'VERDICT: PASS' "$G" >"$T/a/A"; cp "$T/a/A" "$T/a/B"
  tly tally A="$T/a/A" B="$T/a/B"; want_rc 0; has "$OUTF" "VERDICT: PASS"; lacks "$OUTF" "VERDICT: FINDINGS" "output"
  fa x.go:1 >"$T/a/C"; fa x.go:1 >"$T/a/D"; tly tally C="$T/a/C" D="$T/a/D"; want_rc 0; has "$OUTF" "VERDICT: FINDINGS"
}
r_meta_shape() {
  fa x.go:10 >"$T/a/A"; fa x.go:11 >"$T/a/B"; printf '%s\n' "$V" "$G" 'F1 [P2] [important] q.go:1 — alone' >"$T/a/C"
  rm -f "$META"; tly tally --meta "$META" A="$T/a/A" B="$T/a/B" C="$T/a/C"; want_rc 0
  eq "$(pj "$META" "sorted(d.keys())" | tr -d "[]' ")" "confirmed,goal_votes,quorum,unconfirmed,voters,window" "meta keys"
  eq "$(pj "$META" "d['voters']")" "['A', 'B', 'C']" "voters in the order given"
  eq "$(pj "$META" "d['unconfirmed'][0]['text'].startswith('F1 [P2]')")" "True" "unconfirmed text is the voter's own line"
  rm -f "$META"; tly tally A="$T/a/A" B="$T/a/B"; want_rc 0; [ ! -e "$META" ] || fail "a meta file was written without --meta"
}

# ══ tally: arguments ══════════════════════════════════════════════════════════════════════════════════════════════════
r_tally_bad_arguments() {
  fa x.go:1 >"$T/a/A"; fa x.go:1 >"$T/a/B"
  tly tally; want_rc 2; has "$ERRF" "no vote given"
  tly tally --window 5; want_rc 2
  tly tally A="$T/a/A" A="$T/a/B"; want_rc 2; has "$ERRF" "twice"; eq "$(wc -c <"$OUTF" | tr -d ' ')" 0 "stdout bytes after a duplicate voter name"
  tly tally A="$T/a/A" "$T/a/B"; want_rc 2   # no NAME=
  tly tally -x="$T/a/A" B="$T/a/B"; want_rc 2   # a name must start with a letter or digit
  tly tally "=$T/a/A"; want_rc 2
  tly tally A="$T/a/A" --bogus; want_rc 2
  tly tally A="$T/a/A" --window; want_rc 2
  tly tally A="$T/a/A" --meta; want_rc 2
  tly tally A="$T/a/A" B="$T/a/B"; want_rc 0   # positive control
}
r_tally_window_range() {
  fa x.go:1 >"$T/a/A"; fa x.go:1 >"$T/a/B"; local w
  for w in 501 1000 -1 abc 1.5 "" " 5" 5x 99999999999999999999; do
    tly tally --window "$w" A="$T/a/A" B="$T/a/B"; [ "$RC" = 2 ] || fail "--window '$w' gave exit $RC, wanted 2"
  done
  for w in 0 1 500 007; do tly tally --window "$w" A="$T/a/A" B="$T/a/B"; [ "$RC" = 0 ] || fail "--window '$w' gave exit $RC, wanted 0"; done
}
r_tally_unreadable_answer() {
  fa x.go:1 >"$T/a/A"
  tly tally A="$T/a/A" B="$T/a/none"; want_rc 3; has "$ERRF" "cannot read"; lacks "$ERRF" "Traceback" "stderr"; eq "$(wc -c <"$OUTF" | tr -d ' ')" 0 "stdout bytes (no half answer)"
  tly tally A="$T/a/A" B="$T/a"; want_rc 3
}
r_tally_path_with_equals_sign() {
  mkdir -p "$T/a/x=y"; fa x.go:1 >"$T/a/x=y/f.txt"; fa x.go:1 >"$T/a/B"
  tly tally A="$T/a/x=y/f.txt" B="$T/a/B"; want_rc 0; has "$OUTF" "agreed by A, B" "only the first = splits name and path"
}
r_tally_name_forms() {
  fa x.go:1 >"$T/a/A"; fa x.go:1 >"$T/a/B"
  tly tally vendor-4.argon_1="$T/a/A" 9lives="$T/a/B"; want_rc 0; has "$OUTF" "agreed by vendor-4.argon_1, 9lives"
}

# ══ cross-author fixes of 2026-10-24 (rows added after the lead's rulings) ═══════════════════════════════════════════════
r_parse_bare_names_need_a_known_extension() {
  # a bare "name.ext" (no folder, no :line) is a location only with a known source/doc extension: "e.g." is not a file
  A bare "$V" 'F1 [P1] [important] the check misses e.g. empty input' 'F2 [P1] [important] i.e. nothing is checked' \
    'F3 [P1] [important] foo.Bar() is called twice' 'F4 [P1] [important] x.go — bare' 'F5 [P1] [important] README.md — doc' \
    'F6 [P1] [important] a.c in C' 'F7 [P1] [important] b.h a header' 'F8 [P1] [important] c.m objective' 'F9 [P1] [important] X.GO in capitals' \
    'F10 [P1] [important] foo.Bar:12 — a line makes it a location' 'F11 [P1] [important] pkg/foo.Bar — a folder makes it a location' \
    'F12 [P1] [important] the check, e.g. in a.go:5 — the real one comes later' 'F13 [P1] [important] v1.2 is released'
  parse_of bare; want_rc 0
  eq "$(pj "$OUTF" "[f['path'] for f in d]")" "[None, None, None, 'x.go', 'README.md', 'a.c', 'b.h', 'c.m', 'X.GO', 'foo.Bar', 'pkg/foo.Bar', 'a.go', None]" "path of each finding"
  eq "$(pj "$OUTF" "d[11]['lo']")" 5 "the line of the real location after an e.g."
}
r_parse_file_less_findings_with_e_g_never_agree() {
  printf '%s\n' "$V" "$G" 'F1 [P1] [important] the check misses e.g. empty input' >"$T/a/A"; cp "$T/a/A" "$T/a/B"
  tly tally --meta "$META" A="$T/a/A" B="$T/a/B"; want_rc 0; has "$OUTF" "VERDICT: PASS" "two voters' e.g. findings"; lacks "$OUTF" "agreed by" "output"
  printf '%s\n' "$V" "$G" 'F1 [P1] [important] foo.Bar() is called twice' >"$T/a/C"; cp "$T/a/C" "$T/a/D"
  tly tally A="$T/a/C" B="$T/a/D"; want_rc 0; has "$OUTF" "VERDICT: PASS" "two voters' foo.Bar() findings"
  # positive control: the same sentences with a real bare file name agree
  printf '%s\n' "$V" "$G" 'F1 [P1] [important] the check in x.go misses empty input' >"$T/a/E"; cp "$T/a/E" "$T/a/F"
  tly tally A="$T/a/E" B="$T/a/F"; want_rc 0; has "$OUTF" "agreed by A, B" "bare x.go"
}
r_parse_tag_after_the_location() {
  A tagafter "$V" 'F1 [P1] src/a.go:5 [nit] naming' 'F2 [P2] src/a.go:7-9 [pre-existing] old' 'F3 [nit] src/b.go:3 [P3] both brackets before' \
    'F4 earlier.go [P1] [important] no location after the brackets' 'F5 [P1] see src/c.go:11 [important] the place stands between the brackets' \
    'F6 [P1] [important] this.go:1 — a location after the brackets beats one before' 'F7 first.go:2 [P1] [important] last.go:8'
  parse_of tagafter; want_rc 0
  eq "$(pj "$OUTF" "[(f['id'], f['tag'], f['path'], f['lo'], f['hi']) for f in d]")" \
    "[('F1', 'untagged', 'src/a.go', 5, 5), ('F2', 'untagged', 'src/a.go', 7, 9), ('F3', 'untagged', 'src/b.go', 3, 3), ('F4', 'important', 'earlier.go', None, None), ('F5', 'untagged', 'src/c.go', 11, 11), ('F6', 'important', 'this.go', 1, 1), ('F7', 'important', 'last.go', 8, 8)]" \
    "tag and place of each finding (the place after the last bracket wins; with none there, the whole line is searched; a tag standing after the location is not the finding's tag since then, but the location is still found)"
}
# ══ the tag is the bracket group next to the severity; a P0/P1 is never a nit (cross-author, 2026-10-26) ════════════════
# The oracles are written by hand from the bug report and the fix's stated rule: the finding's tag stands DIRECTLY after
# its severity (or directly before it, or at the start of a line with no severity); a tag anywhere else is the reviewer quoting the
# diff and reads "untagged" (which is judged); and a P0 or P1 can never be a nit, because a nit is not judged.
tags_of() { # tags_of <finding text after the id>...: the tags parse reads, in order, joined by commas (F1, F2 ... added here)
  local i=0 l args=("$V" "$G")
  for l in "$@"; do i=$((i + 1)); args+=("F$i $l"); done
  A tagsof "${args[@]}"; parse_of tagsof
  [ "$RC" = 0 ] || { fail "parse exit $RC"; echo err; return; }
  pj "$OUTF" "','.join(f['tag'] for f in d)"
}
r_p0_p1_is_never_a_nit() {
  local row line want
  # "<line>|<expected tag>": the first group is the bug attack, the lines after it are the neighbours that must stay as they were
  for row in \
    '[P1] a.go:1 — added twice [nit]|untagged' \
    '[P0] a.go:2 — reads x[nit] out of range|untagged' \
    '[P1][nit] a.go:3 — the tag is glued to the severity|important' \
    '[P0] [nit] a.go:3 — a plain P0 with a nit tag|important' \
    '[P1] [nit]x a.go:3 — the tag is glued to the text|important' \
    '[nit] [P1] a.go:3 — the tag stands before the severity|important' \
    '[nit][P0] a.go:3 — before and glued|important' \
    '[P1] [pre-existing] a.go:4 — an old defect|pre-existing' \
    '[P0] [pre-existing][nit] a.go:4 — pre-existing first, nit glued after|pre-existing' \
    '[P1] [important] [nit] a.go:4 — two tags, the first is the finding'"'"'s|important' \
    '[P3] [nit] [important] a.go:4 — two tags, the first is the finding'"'"'s|nit' \
    '[P3] [nit] a.go:5 — a P3 nit (positive control)|nit' \
    '[P2] [nit] a.go:5 — a P2 nit (positive control)|nit' \
    '[nit] [P3] a.go:5 — the tag before a P3 (positive control)|nit' \
    '[nit] a.go:6 — no severity, tag at the start (positive control)|nit' \
    'foo [nit] a.go:6 — no severity, the tag is not at the start|untagged' \
    '[P3] a.go:7 — a late tag [nit]|untagged' \
    '[P1] [NIT] a.go:8 — upper case|important' \
    '[p1] [Nit] a.go:8 — lower case severity, mixed case tag|important' \
    '[P3] [NIT] a.go:8 — upper case on a P3 (positive control)|nit' \
    '[P1] [ nit ] a.go:9 — blanks inside the brackets|important' \
    '[P3] [ nit ] a.go:9 — blanks inside the brackets on a P3 (positive control)|nit' \
    '[P1]	[nit] a.go:9 — a TAB between|important' \
    '[P1] [P3] [nit] a.go:10 — two severities: the second is not the severity, so the tag is not next to it|untagged' \
    '[P1] ［nit］ a.go:11 — full-width brackets are no tag|untagged' \
    '[P3] ［nit］ a.go:11 — full-width brackets are no tag, P3 too|untagged' \
    '[P3] [nit] a.go:12 and a [P0] later in the text|nit'
  do
    line="${row%|*}"; want="${row##*|}"
    eq "$(tags_of "$line")" "$want" "tag of: $line"
  done
}
# A P1 nit voter in a vote: it counts as important, so the merged tag is not a nit that the judge would skip.
r_p1_nit_voter_counts_as_important() {
  eq "$(tag_of nit@P1 nit@P3)" important "a P1 voter and a P3 voter, both tagged nit: the P1 one reads important, the tie goes important"
  eq "$(tag_of nit@P1 nit@P1)" important "two P1 nit voters"
  eq "$(tag_of nit@P0)" important "one P0 nit voter"
  eq "$(tag_of nit@P3 nit@P2)" nit "positive control: two non-P1 nit voters keep the nit"
  # hostile text: both voters put [nit] at the end of a P1 line; the merged finding must be important (untagged counts important)
  printf '%s\n' "$V" "$G" 'F1 [P1] x.go:10 — d [nit]' >"$T/a/h1"; cp "$T/a/h1" "$T/a/h2"
  tly tally A="$T/a/h1" B="$T/a/h2"; want_rc 0; has "$OUTF" "F1 [P1] [important]" "merged line of two trailing-[nit] P1 voters"; lacks "$OUTF" "F1 [P1] [nit]" "merged heading"
  # round trip: a vote can leave "[P1] [nit]" in the merged text (two nit voters outvote a P1 one); parse must still read it as important
  printf '%s\n' "$V" "$G" 'F1 [P2] [nit] x.go:10 — d' >"$T/a/r1"; printf '%s\n' "$V" "$G" 'F1 [P3] [nit] x.go:10 — d' >"$T/a/r2"; printf '%s\n' "$V" "$G" 'F1 [P1] [nit] x.go:10 — d' >"$T/a/r3"
  tly tally A="$T/a/r1" B="$T/a/r2" C="$T/a/r3"; want_rc 0; cp "$OUTF" "$T/a/merged"; parse_of merged; want_rc 0
  eq "$(pj "$OUTF" "[(f['sev'], f['tag']) for f in d if f['id'] == 'F1']")" "[('P1', 'important')]" "the merged text read back: worst severity P1 and never a nit"
}
r_goal_head_must_end_at_the_word() {
  local h
  for h in "METHODS unclear" "METAL" "NOT METHOD" "METEOR — x" "CANNOT TELLING" "NOTMET" "MET1" "MET_x" "CANNOT"; do
    A gh 'VERDICT: PASS' "GOAL: $h"; tly tally --meta "$META" A="$T/a/gh"; [ "$RC" = 0 ] || { fail "goal '$h': exit $RC"; continue; }
    eq "$(pj "$META" "d['goal_votes']['A']")" "?" "GOAL: $h reads as ?"
    lacks "$OUTF" "GOAL: MET" "output for GOAL: $h"
  done
  local pair
  for pair in "MET|MET" "MET — x|MET" "MET - x|MET" "MET – x|MET" "MET.|MET" "MET,|MET" "MET: ok|MET" "met. all|MET" "NOT MET|NOT MET" "NOT MET.|NOT MET" "NOT MET: x|NOT MET" "CANNOT TELL — y|CANNOT TELL" "CANNOT TELL.|CANNOT TELL" "not met, x|NOT MET"; do
    A gh 'VERDICT: PASS' "GOAL: ${pair%%|*}"; tly tally --meta "$META" A="$T/a/gh"; [ "$RC" = 0 ] || { fail "goal '${pair%%|*}': exit $RC"; continue; }
    eq "$(pj "$META" "d['goal_votes']['A']")" "${pair##*|}" "GOAL: ${pair%%|*}"
  done
}
r_tally_meta_unwritable_is_exit_3() {
  fa x.go:1 >"$T/a/A"; fa x.go:1 >"$T/a/B"
  tly tally --meta "$T/a/no-such-folder/m.json" A="$T/a/A" B="$T/a/B"; want_rc 3
  has "$ERRF" "review_tally: cannot write the meta file $T/a/no-such-folder/m.json (FileNotFoundError)" "stderr"; lacks "$ERRF" "Traceback" "stderr"
  eq "$(wc -c <"$OUTF" | tr -d ' ')" 0 "stdout bytes (nothing is printed when the meta cannot be written)"
  tly tally --meta "$T/a" A="$T/a/A" B="$T/a/B"; want_rc 3; has "$ERRF" "cannot write the meta file" "a folder as the meta file"; eq "$(wc -c <"$OUTF" | tr -d ' ')" 0 "stdout bytes (folder)"
  # positive control: a writable path prints the answer and writes the file
  tly tally --meta "$T/a/meta-ok.json" A="$T/a/A" B="$T/a/B"; want_rc 0; [ -s "$OUTF" ] || fail "no answer on stdout"; [ -s "$T/a/meta-ok.json" ] || fail "no meta file"
}

# ══ round 3 of the cross-author rows, 2026-10-24 (check-the-work F2, F3) ═══════════════════════════════════════════════════
r_tally_a_bare_name_cannot_join_two_files() {
  # F2: "config.ts" is the tail of BOTH web/config.ts and api/config.ts; it must not join the two into one finding
  fa config.ts:10 >"$T/a/A"; fa web/config.ts:10 >"$T/a/B"; fa api/config.ts:10 >"$T/a/C"
  tly tally --meta "$META" A="$T/a/A" B="$T/a/B" C="$T/a/C"; want_rc 0
  has "$OUTF" "F1 [P1] [important] web/config.ts:10 — agreed by A, B (2 of 3 voters)" "the bare name and web agree; the merged place is the longest path"
  has "$OUTF" "U1 (only C) F1 [P1] [important] api/config.ts:10" "api stays single"; lacks "$OUTF" "agreed by A, B, C" "output"
  eq "$(pj "$META" "d['confirmed'][0]['from']")" "['A:F1', 'B:F1']" "meta"; eq "$(pj "$META" "len(d['unconfirmed'])")" 1 "unconfirmed"
  # the other order: web first, then api (a different file: its own cluster), then the bare name joins the FIRST cluster
  tly tally --meta "$META" B="$T/a/B" C="$T/a/C" A="$T/a/A"; want_rc 0
  has "$OUTF" "agreed by B, A (2 of 3 voters)" "web and the bare name"; has "$OUTF" "U1 (only C)" "api single"
  # the longest path names the place, with ITS lines (the first member was the bare name with other lines)
  fa config.ts:10 >"$T/a/A"; fa web/config.ts:12 >"$T/a/B"; tly tally A="$T/a/A" B="$T/a/B"; want_rc 0; has "$OUTF" "F1 [P1] [important] web/config.ts:12 — agreed by A, B" "longest path with its lines"
  # three voters on the same long path, the bare name first: all three agree
  fa web/config.ts:10 >"$T/a/C"; fa web/config.ts:11 >"$T/a/B"; fa config.ts:10 >"$T/a/A"; tly tally A="$T/a/A" B="$T/a/B" C="$T/a/C"; want_rc 0; has "$OUTF" "agreed by A, B, C (3 of 3 voters)" "three on one file"
  # positive controls: the diff-style prefix and a folder in front still merge
  fa b.go:5 >"$T/a/A"; fa a/b.go:5 >"$T/a/B"; tly tally A="$T/a/A" B="$T/a/B"; want_rc 0; has "$OUTF" "F1 [P1] [important] b.go:5 — agreed by A, B (2 of 2 voters)" "b.go + a/b.go"
  fa b.go:5 >"$T/a/A"; fa x/b.go:5 >"$T/a/B"; tly tally A="$T/a/A" B="$T/a/B"; want_rc 0; has "$OUTF" "x/b.go:5 — agreed by A, B" "b.go + x/b.go"
  # two different long paths never merge, bare name or not
  fa web/config.ts:10 >"$T/a/A"; fa api/config.ts:10 >"$T/a/B"; tly tally A="$T/a/A" B="$T/a/B"; want_rc 0; has "$OUTF" "VERDICT: PASS" "web vs api"
}
pycall() { # pycall <python expression over m = the module under test>: prints its value
  python3 -I -c 'import sys, importlib.util
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("rt_under_test", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(eval(sys.argv[2]))' "$SUT" "$1"
}
r_path_takes_one_diff_prefix_at_most() {
  # F3: a/b/c.py is the real path b/c.py; ./a/x.py is the real path a/x.py
  A pp "$V" 'F1 [P1] [important] a/b/c.py:1 — x' 'F2 [P1] [important] ./a/x.py:2 — x' 'F3 [P1] [important] ./x.py:3 — x' 'F4 [P1] [important] a/x.go:4 — x' \
    'F5 [P1] [important] b/x.go:5 — x' 'F6 [P1] [important] ./b/y.go:6 — x' 'F7 [P1] [important] a/a/z.go:7 — x' 'F8 [P1] [important] c/x.py:8 — x' 'F9 [P1] [important] ./c/x.py:9 — x'
  parse_of pp; want_rc 0
  eq "$(pj "$OUTF" "[f['path'] for f in d]")" "['b/c.py', 'a/x.py', 'x.py', 'x.go', 'x.go', 'b/y.go', 'a/z.go', 'c/x.py', 'c/x.py']" "path of each finding"
  eq "$(pycall "[m._path(p) for p in ['./', 'a/', 'b/', 'c/', './a/', 'x.go', 'a/b/c.py', './a/x.py', './x.py', 'a/x.go', 'b/x.go', 'b/b/q.go', 'a/a/q.go', './b/q.go']]")" \
    "['./', 'a/', 'b/', 'c/', 'a/', 'x.go', 'b/c.py', 'a/x.py', 'x.py', 'x.go', 'x.go', 'b/q.go', 'a/q.go', 'b/q.go']" "_path on its own: a prefix alone stays, one prefix at most comes off"
}

# ── run every row ─────────────────────────────────────────────────────────────────────────────────────────────────────
begin "parse: tags important / nit / pre-existing / preexisting (any case); a missing or unbracketed tag is 'untagged'"; r_parse_tags; finish
begin "parse: severity P0..P3 in any case and padding; none or P4 is null"; r_parse_severity; finish
begin "parse: the severity and tag brackets are never read as the file"; r_parse_severity_never_a_path; finish
begin "parse: locations (range, reversed, en dash, no line, a/ b/ ./ prefixes, no file, first location wins)"; r_parse_locations; finish
begin "parse: a huge or zero line number is read, no crash"; r_parse_huge_line_numbers; finish
begin "parse: only a line that STARTS with F<n> is a finding; the first of a duplicate id wins"; r_parse_ids; finish
begin "parse: after an ALSO-ASKED header the ids carry the model name"; r_parse_also_asked_prefix; finish
begin "parse: an empty answer is [], invalid UTF-8 is replaced"; r_parse_empty_and_binary; finish
begin "cli: no args / unknown command / parse without file → 2; unreadable file or directory → 3, no traceback"; r_cli_exit_codes; finish
begin "tally: two voters at the same place keep the finding (and say who agreed)"; r_two_voters_agree; finish
begin "tally: the default window is 15 lines — gap 15 agrees, 16 does not, both directions and ranges"; r_window_boundary_default; finish
begin "tally: --window 0 / 3 / 500 are honoured and recorded"; r_window_flag; finish
begin "tally: findings too far apart are UNCONFIRMED, the verdict is PASS"; r_not_agreed_is_unconfirmed; finish
begin "tally: same file = equal path or a tail at a folder boundary (xb.go is not b.go)"; r_file_matching; finish
begin "tally: a finding with a file but no line agrees with any finding on that file"; r_file_without_line_agrees_on_that_file; finish
begin "tally: a finding with no file never agrees with another"; r_finding_without_file_never_agrees; finish
begin "tally: a voter never confirms itself (two findings of one voter stay single)"; r_voter_never_confirms_itself; finish
begin "tally: kept findings are numbered by cluster order, single ones become U-lines"; r_output_order_follows_clusters; finish
begin "tally: quorum is 1 for one voter, 2 for two or three voters"; r_quorum; finish
begin "tally: a third voter cannot make a cluster count twice"; r_third_voter_cannot_double_a_cluster; finish
begin "tally: the tag is the majority; a tie goes important > pre-existing > nit; untagged counts as important"; r_tag_majority_and_ties; finish
begin "tally: the worst severity named wins; none is P?"; r_worst_severity_wins; finish
begin "tally: the goal is MET only when 2 voters saw it MET (one voter: its own); NOT MET before CANNOT TELL"; r_goal_verdict_of_a_vote; finish
begin "tally: the GOAL line names every voter's verdict and the meta holds them"; r_goal_line_lists_every_voter; finish
begin "tally: UNSEEN lists what a voter could not see; the VOTE line states voters, quorum and window"; r_unseen_and_vote_lines; finish
begin "tally: the merged text reads back through parse (ids, tags, places; U-lines are not findings)"; r_merged_text_reads_back_the_same; finish
begin "tally: verdict PASS when nothing is kept, FINDINGS when something is"; r_pass_and_findings_verdict; finish
begin "tally: the meta file has the documented shape and is written only with --meta"; r_meta_shape; finish
begin "tally: bad arguments (no vote, no NAME=, bad name, duplicate name, unknown flag, flag without value) → 2"; r_tally_bad_arguments; finish
begin "tally: --window outside 0..500 or not a whole number → 2"; r_tally_window_range; finish
begin "tally: an unreadable answer file → 3 with no traceback and no half answer"; r_tally_unreadable_answer; finish
begin "tally: a path with = in it works (only the first = splits)"; r_tally_path_with_equals_sign; finish
begin "tally: voter names with dot, dash, underscore and a leading digit work"; r_tally_name_forms; finish

begin "parse: a bare name.ext is a file only with a known extension (e.g. / i.e. / foo.Bar() are not; x.go README.md .c .h .m are)"; r_parse_bare_names_need_a_known_extension; finish
begin "tally: file-less findings with e.g. or foo.Bar() never agree; a real bare file name does"; r_parse_file_less_findings_with_e_g_never_agree; finish
begin "parse: the tag may follow the location; the place after the last bracket still wins"; r_parse_tag_after_the_location; finish
begin "parse: a P0/P1 is never a nit; the tag is the group next to the severity, a tag elsewhere reads untagged"; r_p0_p1_is_never_a_nit; finish
begin "tally: a P1 voter tagged nit counts as important; trailing [nit] on P1 lines does not make the merged finding a nit"; r_p1_nit_voter_counts_as_important; finish
begin "goal head: METHODS / METAL / NOT METHOD read as ?; MET followed by a space, dash, dot, comma or colon is MET"; r_goal_head_must_end_at_the_word; finish
begin "tally: --meta to an unwritable path → exit 3, one stderr line, empty stdout"; r_tally_meta_unwritable_is_exit_3; finish

begin "tally: a bare name (config.ts) cannot join web/config.ts and api/config.ts into one finding; the longest path names the place"; r_tally_a_bare_name_cannot_join_two_files; finish
begin "_path: one diff prefix at most (a/b/c.py is b/c.py, ./a/x.py is a/x.py); a prefix alone stays"; r_path_takes_one_diff_prefix_at_most; finish
echo "review-tally-test: $N rows, $PASSED passed"
[ "$PASSED" = "$N" ] && exit 0
echo "review-tally-test: $((N - PASSED)) row(s) FAILED"
exit 1
