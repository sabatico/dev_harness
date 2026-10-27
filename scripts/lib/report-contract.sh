# scripts/lib/report-contract.sh — the fixed fields of a sub-session's FINAL report, and the one check of them. Sourced by
# scripts/check-the-work.d/20-report-contract.sh (which refuses) and by anything else that wants to flag a report; one copy,
# so two callers can never disagree on what a complete report is.
#
# WHY: the MASS study (arXiv 2610.12176) found that OUTPUT CONTRACTS and hop order carried most of the gains of a
# multi-agent system; a free-text "done" makes the next hop guess. Here the next hop is the lead's merge: a FINAL report
# that does not name its commits, its raw gate lines, its bug ids, what it deferred and what it still asks makes the lead
# re-derive them (and in the first adopting project, three dead sessions in one day left no usable report at all).
# Design: docs/ci/session-resilience.md.
#
# The contract (a report whose first non-blank line starts with FINAL; INTERIM and QUESTION reports are not checked):
#   COMMITS:   each commit as `<sha> <subject>` (7 to 40 hex digits), or `none — <why>`
#   GATES:     the raw summary line of each gate or test run, or `none — <why>`
#   BUGS:      the <PREFIX>-nnn ids filed or fixed (PREFIX = HARNESS_BUG_PREFIX, default BUG, or SEC), or `none`
#   DEFERRED:  what is left and where it is recorded, or `none`
#   QUESTIONS: what the lead or the owner must answer, or `none`
# A field is a line that starts with the name and a colon; list markers (`- `, `* `) and bold marks (`**`) around the
# name are allowed. The value is the rest of that line plus the lines under it, up to the next field or heading.
# Optional: STOP-REASON (a best partial result: why the work stopped short).
# Bash 3.2 compatible.

REPORT_CONTRACT_FIELDS="COMMITS GATES BUGS DEFERRED QUESTIONS"
# The ONE rule for "a commit id" in a COMMITS field: 7 to 40 lowercase hex digits, not glued to a letter or digit on either side
# (so "1234567x" and "xabc1234" are no id). The field check and the extractor below both use it; once they had
# two rules, and a glued token passed the check but the extractor found nothing ("OK, 0 commit ids").
REPORT_SHA_RE='(^|[^0-9a-zA-Z])[0-9a-f]{7,40}([^0-9a-zA-Z]|$)'

# The bug-id token of the BUGS field: <PREFIX>-<digits> with PREFIX from HARNESS_BUG_PREFIX (default BUG) or SEC (security
# findings have their own register). Built at call time, not at source time, so a caller that loads harness.conf AFTER
# sourcing this file still gets its project's prefix. A prefix with anything but letters, digits or "_" is dropped (it
# goes into a regular expression; a hostile or typo'd value must not change what the pattern means).
report_bug_re() {
  local p="${HARNESS_BUG_PREFIX:-BUG}"
  case "$p" in *[!A-Za-z0-9_]*|"") p="BUG" ;; esac
  if [ "$p" = "SEC" ]; then printf '(SEC)-[0-9]+'; else printf '(%s|SEC)-[0-9]+' "$p"; fi
}

# report_is_final <file> — exit 0 when the first non-blank line starts with the word FINAL
report_is_final() {
  # a file with no non-blank line is not a FINAL report (the main rule exits at the first non-blank line; END keeps its code)
  awk 'NF { seen = 1; code = ($0 ~ /^[[:space:]]*(\*\*)?FINAL([^A-Za-z0-9_]|$)/) ? 0 : 1; exit code } END { if (!seen) exit 1; exit code }' "$1" 2>/dev/null
}

# report_contract_problems <file> — one line per missing or invalid field ("COMMITS: missing", ...); prints nothing when
# the report meets the contract. Exit 0 always (callers read the output). Does not judge INTERIM/QUESTION: call it on a
# FINAL report only.
report_contract_problems() {
  awk -v fields="$REPORT_CONTRACT_FIELDS" -v shatok="$REPORT_SHA_RE" -v bugre="$(report_bug_re)" '
    function norm(s) { sub(/^[[:space:]]*([-*+][[:space:]]+)?/, "", s); gsub(/\*\*|__/, "", s); return s }  # harness:allow-uncited awk helper of the report contract (ci/session-resilience.md S2)
    function fieldof(s,   i) { for (i = 1; i <= nf; i++) if (index(s, F[i] ":") == 1) return F[i]; if (index(s, "STOP-REASON:") == 1) return "STOP-REASON"; return "" }  # harness:allow-uncited awk helper of the report contract (ci/session-resilience.md S2)
    BEGIN { nf = split(fields, F, " ") }
    {
      s = norm($0)
      f = fieldof(s)
      if (f != "") { cur = f; seen[f] = 1; v = substr(s, length(f) + 2); val[f] = val[f] " " v; next }
      if ($0 ~ /^[[:space:]]*#/) { cur = ""; next }
      if (cur != "") val[cur] = val[cur] " " s
    }
    END {
      for (i = 1; i <= nf; i++) {
        f = F[i]; v = val[f]; gsub(/[[:space:]]+/, " ", v); sub(/^ /, "", v); sub(/ $/, "", v)
        if (!(f in seen)) { print f ": missing"; continue }
        if (v == "") { print f ": empty (write none, or none — <why>)"; continue }
        lv = tolower(v)
        isnone = (lv ~ /^none([^a-z]|$)/)
        # "none" needs a reason where the lead would otherwise expect evidence: no commits, no gate run
        reason = v; sub(/^[Nn][Oo][Nn][Ee][[:space:]]*[-—:,(]*[[:space:]]*/, "", reason)
        if (f == "COMMITS" && !isnone && v !~ shatok) print f ": no commit sha (7-40 hex digits) and not none — <why>"
        else if ((f == "COMMITS" || f == "GATES") && isnone && length(reason) < 3) print f ": none needs a reason (none — <why>)"
        else if (f == "BUGS" && !isnone && v !~ bugre) print f ": no bug id (<PREFIX>-nnn or SEC-nnn) and not none"
      }
    }' "$1"
}

# report_commit_shas <file> — the commit ids the COMMITS field names, one per line (for a cross-check against git). A COMMITS
# field that says `none — <why>` names nothing: a long number in the reason (bytes, a date) is not an id to look up.
report_commit_shas() {
  awk -v shatok="$REPORT_SHA_RE" '
    function norm(s) { sub(/^[[:space:]]*([-*+][[:space:]]+)?/, "", s); gsub(/\*\*|__/, "", s); return s }  # harness:allow-uncited awk helper of the report contract (ci/session-resilience.md S2)
    function take(t,   h) {  # harness:allow-uncited awk helper of the report contract (ci/session-resilience.md S2)
      if (!decided) { if (t !~ /[^[:space:]]/) return; decided = 1; none = (tolower(t) ~ /^[[:space:]]*none([^a-z]|$)/) }
      if (none) return
      while (match(t, shatok)) {
        h = substr(t, RSTART, RLENGTH); gsub(/[^0-9a-f]/, "", h); print h; t = substr(t, RSTART + RLENGTH - 1)
      }
    }
    { s = norm($0) }
    s ~ /^(COMMITS|GATES|BUGS|DEFERRED|QUESTIONS|STOP-REASON):/ {
      on = (index(s, "COMMITS:") == 1)
      if (on) { decided = 0; none = 0; take(substr(s, 9)) }
      next
    }
    /^[[:space:]]*#/ { on = 0; next }
    on { take(s) }' "$1"
}

# report_contract_selfproof — the detector proves itself on known answers before a "complete" verdict is trusted
# (a check whose "nothing found" cannot be told from "I am broken" is not evidence). Exit 0 = sound.
report_contract_selfproof() {
  local d good bad nonefile out multi glued blank bp
  bp="${HARNESS_BUG_PREFIX:-BUG}"; case "$bp" in *[!A-Za-z0-9_]*|"") bp="BUG" ;; esac
  d="$(mktemp -d "${TMPDIR:-/tmp}/report-contract.XXXXXX")" || return 1
  good="$d/good" bad="$d/bad" nonefile="$d/none" multi="$d/multi" glued="$d/glued" blank="$d/blank"
  printf '%s\n' "FINAL — DONE" "- **COMMITS:** abc1234 fix: a thing" "GATES:" "  ok 12 passed" "BUGS: $bp-901" "DEFERRED: none" "QUESTIONS: none" > "$good"
  printf '%s\n' "FINAL — DONE" "COMMITS: fixed it" "BUGS: some" "GATES:" > "$bad"
  printf '%s\n' "FINAL — DONE" "COMMITS: none" "GATES: none — docs only" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" > "$nonefile"
  # the commit-id extractor feeds the commit lookup: if it found nothing, every made-up id would pass ("0 commit ids")
  printf '%s\n' "FINAL — DONE" "COMMITS:" "- abc1234 one" "- (def56789ab two) and ABC1234567 not hex" "GATES: ok deadbee1 is no commit" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" > "$multi"
  printf '%s\n' "FINAL — DONE" "COMMITS: none — not allowed to commit; the file is 1048576 bytes" "GATES: none — docs" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" > "$d/nonelong"
  printf '%s\n' "FINAL — DONE" "COMMITS: 1234567x and xabc1234" "GATES: none — docs" "BUGS: none" "DEFERRED: none" "QUESTIONS: none" > "$glued"
  printf '\n\n   \n' > "$blank"
  out="$(report_contract_problems "$good")$(report_is_final "$good" || echo notfinal)"
  local bad_out none_out good_shas multi_shas nonelong_shas glued_shas glued_probs
  bad_out="$(report_contract_problems "$bad" | cut -d: -f1 | sort | paste -sd' ' -)"
  none_out="$(report_contract_problems "$nonefile" | cut -d: -f1 | paste -sd' ' -)"
  good_shas="$(report_commit_shas "$good" | paste -sd' ' -)"
  multi_shas="$(report_commit_shas "$multi" | paste -sd' ' -)"
  nonelong_shas="$(report_commit_shas "$d/nonelong" | paste -sd' ' -)"
  glued_shas="$(report_commit_shas "$glued" | paste -sd' ' -)"
  glued_probs="$(report_contract_problems "$glued" | cut -d: -f1 | paste -sd' ' -)"
  local blank_final=0; report_is_final "$blank" && blank_final=1
  rm -rf -- "$d"
  [ -z "$out" ] && [ "$bad_out" = "BUGS COMMITS DEFERRED GATES QUESTIONS" ] && [ "$none_out" = "COMMITS" ] \
    && [ "$good_shas" = "abc1234" ] && [ "$multi_shas" = "abc1234 def56789ab" ] && [ -z "$nonelong_shas" ] \
    && [ -z "$glued_shas" ] && [ "$glued_probs" = "COMMITS" ] && [ "$blank_final" -eq 0 ]
}
