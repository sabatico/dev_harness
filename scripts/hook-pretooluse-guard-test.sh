#!/usr/bin/env bash
# hook-pretooluse-guard-test.sh — the guard's KNOWN-ANSWER matrix (the self-proof pattern applied
# to the guard itself). Run after ANY edit to hook-pretooluse-guard.sh or guard-check.py.
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
#
# Every row runs with HARNESS_GUARD_LOG pointed at a temp file, so the matrix never writes the real
# .harness-logs/guard.log (its deny counts are a metric the owner reviews; a test run would pollute
# it). Each DENY row also asserts exactly ONE new log line naming the expected rule; each ALLOW row
# asserts NO new line. Nothing in this file executes a payload — the guard only judges the string.
#
# Rows added 2026-09-30 (cross-authored, not by the builder of guard-check.py): the disguise and
# destructive-family rows the parser rewrite claims to stop, the control floor, the override, the
# deny log, and the fail-closed paths. Second round (same day): the test author's invented cases that
# the builder then fixed (quoted separators, `..`, case, ~user, repo root by relative path, system
# folders, more wrappers, here-strings, push-delete of main, infra spellings, the control floor by
# folder/case/symlink/rsync/>|, deny-log injection). Cases left unfixed BY DECISION (a command or target
# held in a variable, git aliases, interpreter writes, the parenthesised-commit-message over-block) are
# deliberately not rows.
set -uo pipefail
cd "$(dirname "$0")"
HERE="$(pwd)"

GUARD="$HERE/hook-pretooluse-guard.sh"
REPO="$(git rev-parse --show-toplevel 2>/dev/null || (cd .. && pwd))"
# A maintenance session may be LAUNCHED with the override; the floor rows must not inherit it.
unset HARNESS_ALLOW_CONTROL_EDITS HARNESS_CONTROL_PATHS
T="$(mktemp -d "${TMPDIR:-/tmp}/guardtest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
GLOG="$T/guard.log"; : > "$GLOG"
export HARNESS_GUARD_LOG="$GLOG"
RUNSID="g$$zzzzzzz"; RUNSID="${RUNSID:0:8}"   # one session id per run; the real log must never see it
pass=0; fail=0

loglines() { wc -l < "$GLOG" | tr -d ' '; }

# judge <want> <payload-json> <label> [rule]
#   env knobs: EXTRA_ENV (VAR=val ... for the hook's launch env), GUARD_CWD (dir to run in),
#   GUARD_BIN (a different copy of the hook).
judge() {
  local want="$1" payload="$2" label="$3" rule="${4:-}" before after out got line why=""
  before="$(loglines)"
  out="$(cd "${GUARD_CWD:-$HERE}" && printf '%s' "$payload" | env ${EXTRA_ENV:-} bash "${GUARD_BIN:-$GUARD}" 2>/dev/null)"
  after="$(loglines)"
  if printf '%s' "$out" | grep -q '"deny"'; then got=DENY; else got=ALLOW; fi
  line="$(tail -1 "$GLOG" 2>/dev/null)"
  if [ "$got" != "$want" ]; then why="want=$want got=$got"
  elif [ "$got" = DENY ]; then
    [ "$after" -eq $((before + 1)) ] || why="deny wrote $((after - before)) log lines, want 1"
    if [ -z "$why" ] && [ -n "$rule" ]; then
      case "$line" in *" rule=$rule") ;; *) why="wrong rule: log says '${line##* }', want rule=$rule" ;; esac
    fi
    if [ -z "$why" ] && ! printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
      why="deny output is not valid JSON"
    fi
  else
    [ "$after" -eq "$before" ] || why="ALLOW wrote $((after - before)) log line(s)"
  fi
  if [ -z "$why" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  $why  $label"; fi
}

mkpayload() { # tool cmd fp [notebook_path]   (env: ROW_CWD = the payload's cwd, as Claude Code sends it)
  # The command travels on STDIN, as the hook's own payload does, never as an argument: Linux caps one
  # argument at 128 KiB, so the 200 KB row's python3 died with E2BIG, the guard got an EMPTY payload and
  # rightly failed closed (rule=cannot-run), and the row reported the fixture's failure as the guard's
  # (first Linux install, 2026-10-07). macOS has no per-argument cap, which is why it passed there.
  printf '%s' "$2" | python3 -c '
import json,sys
tool,fp,nb,sid,cwd=sys.argv[1:6]
cmd=sys.stdin.read()
ti={"command":cmd,"file_path":fp}
if nb: ti={"notebook_path":nb,"new_source":"x"}
d={"session_id":sid,"tool_name":tool,"tool_input":ti}
if cwd: d["cwd"]=cwd
print(json.dumps(d))' "$1" "$3" "${4:-}" "$RUNSID" "${ROW_CWD:-}"
}

t() { # want tool cmd fp label [rule]
  judge "$1" "$(mkpayload "$2" "$3" "$4")" "$5" "${6:-}"
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

# ══ 2026-09-30 rows: the parser judge (guard-check.py) ═══════════════════════
# ── DENY: rm flag spellings ──────────────────────────────────────────────────
t DENY Bash 'rm -r -f ~/Documents/x' '' 'split flags -r -f' rm-recursive
t DENY Bash 'rm -R -f ~/x' '' 'capital -R -f' rm-recursive
t DENY Bash 'rm -Rf ~/projects' '' 'capital -Rf' rm-recursive
t DENY Bash 'rm -fr ~' '' 'reversed -fr on bare ~' rm-recursive
t DENY Bash 'rm --recursive --force ~/x' '' 'long --recursive' rm-recursive
t DENY Bash 'rm -r --force ~/.ssh' '' 'mixed short/long on ~/.ssh' rm-recursive
t DENY Bash 'rm -Rv ~/x' '' '-R without -f is still recursive' rm-recursive
t DENY Bash 'rm -rf -- ~/x' '' 'target after --' rm-recursive
t DENY Bash 'rm	-rf	~/x' '' 'tab-separated tokens' rm-recursive
t DENY Bash 'rm -rf ~/x # just a comment' '' 'trailing comment does not hide the target' rm-recursive
# ── DENY: wrappers that run a string as code ─────────────────────────────────
t DENY Bash "bash -c 'rm -rf ~/x'" '' 'bash -c wrapper' rm-recursive
t DENY Bash 'sh -c "git reset --hard"' '' 'sh -c wrapper' reset-hard
t DENY Bash "zsh -lc 'rm -rf ~/x'" '' 'zsh -lc clustered flag' rm-recursive
t DENY Bash "bash -o errexit -c 'git clean -fd'" '' 'bash with options before -c' git-clean
t DENY Bash 'eval rm -rf ~/x' '' 'eval wrapper (bare words)' rm-recursive
t DENY Bash 'eval "git push -f origin main"' '' 'eval wrapper (one quoted string)' force-push
t DENY Bash "sudo sh -c 'rm -rf ~/x'" '' 'sudo + sh -c nested' rm-recursive
t DENY Bash "bash -c \"sh -c 'rm -rf ~/x'\"" '' 'two shells deep' rm-recursive
# ── DENY: prefixes that only wrap the real command ───────────────────────────
t DENY Bash 'command rm -rf ~/x' '' 'command prefix' rm-recursive
t DENY Bash 'env rm -rf ~/x' '' 'env prefix' rm-recursive
t DENY Bash 'env -u FOO rm -rf ~/x' '' 'env -u VAR prefix' rm-recursive
t DENY Bash 'env -i PATH=/bin rm -rf ~/x' '' 'env -i + VAR=val prefix' rm-recursive
t DENY Bash 'sudo -u root rm -rf ~/x' '' 'sudo -u user prefix' rm-recursive
t DENY Bash 'sudo -E -- rm -rf ~/x' '' 'sudo -E -- prefix' rm-recursive
t DENY Bash 'FOO=1 BAR=2 rm -rf ~/x' '' 'VAR=val prefixes' rm-recursive
t DENY Bash '\rm -rf ~/x' '' 'leading backslash' rm-recursive
t DENY Bash '/bin/rm -rf ~/x' '' 'absolute /bin/rm' rm-recursive
t DENY Bash '/usr/bin/git reset --hard' '' 'absolute /usr/bin/git' reset-hard
t DENY Bash 'nohup rm -rf ~/x' '' 'nohup prefix' rm-recursive
t DENY Bash 'timeout 5 rm -rf ~/x' '' 'timeout N prefix' rm-recursive
t DENY Bash 'nice -n 10 rm -rf ~/x' '' 'nice -n N prefix' rm-recursive
t DENY Bash 'time -p git clean -f' '' 'time -p prefix' git-clean
t DENY Bash 'exec git push --force' '' 'exec prefix' force-push
t DENY Bash "'rm' -rf ~/x" '' 'quoted command name' rm-recursive
t DENY Bash 'r\m -rf ~/x' '' 'backslash inside the command name' rm-recursive
t DENY Bash 'if true; then rm -rf ~/x; fi' '' 'inside if/then' rm-recursive
t DENY Bash 'while read l; do rm -rf ~/x; done' '' 'inside while/do' rm-recursive
t DENY Bash '! rm -rf ~/x' '' 'negated with !' rm-recursive
t DENY Bash '{ rm -rf ~/x; }' '' 'inside a brace group' rm-recursive
t DENY Bash 'echo $(rm -rf ~/x)' '' 'inside $( )' rm-recursive
t DENY Bash 'echo `rm -rf ~/x`' '' 'inside backticks' rm-recursive
t DENY Bash 'diff <(rm -rf ~/x) /dev/null' '' 'inside process substitution' rm-recursive
t DENY Bash 'ls && rm -rf ~/x &' '' 'backgrounded after &&' rm-recursive
# ── DENY: home spellings and mixed targets ───────────────────────────────────
t DENY Bash 'rm -rf $HOME/x' '' '$HOME target' rm-recursive
t DENY Bash 'rm -rf ${HOME}/x' '' '${HOME} target' rm-recursive
t DENY Bash 'rm -rf "$HOME"' '' 'quoted bare $HOME' rm-recursive
t DENY Bash 'rm -rf ~/' '' 'home with trailing slash' rm-recursive
t DENY Bash "rm -rf $HOME/Documents" '' 'absolute home path, expanded' rm-recursive
t DENY Bash "rm -rf $REPO" '' 'the repo root by absolute path (under home)' rm-recursive
t DENY Bash 'rm -rf /tmp/x ~/x' '' 'excluded temp path alongside a protected one' rm-recursive
t DENY Bash 'rm -rf node_modules ~/Documents' '' 'node_modules alongside home' rm-recursive
t DENY Bash 'rm -rf ~/x /tmp/y' '' 'protected first, excluded second' rm-recursive
# ── DENY: root, top-level, cwd, glob ─────────────────────────────────────────
t DENY Bash 'rm -rf /' '' 'rm -rf /' rm-recursive
t DENY Bash 'rm -rf //' '' 'rm -rf //' rm-recursive
t DENY Bash 'rm -rf /*' '' 'rm -rf /*' rm-recursive
t DENY Bash 'rm -rf /usr' '' 'top-level /usr' rm-recursive
t DENY Bash 'rm -rf /etc/' '' 'top-level /etc/' rm-recursive
t DENY Bash 'rm -rf /Users' '' 'top-level /Users' rm-recursive
t DENY Bash 'rm -rf /home/someone' '' '/home/<user>' rm-recursive
t DENY Bash 'rm -rf .' '' 'rm -rf .' rm-recursive
t DENY Bash 'rm -rf ./' '' 'rm -rf ./' rm-recursive
t DENY Bash 'rm -rf *' '' 'rm -rf *' rm-recursive
t DENY Bash 'rm -rf ./*' '' 'rm -rf ./*' rm-recursive
t DENY Bash 'rm -rf .*' '' 'rm -rf .*' rm-recursive
t DENY Bash 'rm -rf ..' '' 'rm -rf ..' rm-recursive
t DENY Bash 'rm -rf .git/' '' '.git with trailing slash' rm-recursive
t DENY Bash 'rm -rf sub/.git/objects' '' 'inside a .git dir' rm-recursive
# ── DENY: find as rm by another spelling ─────────────────────────────────────
t DENY Bash 'find ~ -delete' '' 'find home -delete' find-delete
t DENY Bash 'find . -delete' '' 'find . -delete' find-delete
t DENY Bash 'find -delete' '' 'find with no path = cwd' find-delete
t DENY Bash 'find ~/x -type f -delete' '' '-type is not a name filter' find-delete
t DENY Bash 'find / -exec rm -rf {} \;' '' 'find / -exec rm' find-delete
t DENY Bash 'find $HOME -exec /bin/rm {} +' '' 'find $HOME -exec /bin/rm' find-delete
t DENY Bash 'find . -mtime +3 -execdir rm {} \;' '' 'find . -execdir rm' find-delete
# ── DENY: git destructive families ───────────────────────────────────────────
t DENY Bash 'git reset --hard' '' 'reset --hard' reset-hard
t DENY Bash 'git reset --hard HEAD~1' '' 'reset --hard ref' reset-hard
t DENY Bash 'git -C ../other reset --hard' '' 'git -C dir reset --hard' reset-hard
t DENY Bash 'git -c core.x=y reset --hard origin/main' '' 'git -c k=v reset --hard' reset-hard
t DENY Bash 'git clean -f' '' 'clean -f' git-clean
t DENY Bash 'git clean -fd' '' 'clean -fd' git-clean
t DENY Bash 'git clean -xdf' '' 'clean -xdf' git-clean
t DENY Bash 'git clean -d -f' '' 'clean -d -f' git-clean
t DENY Bash 'git clean --force -d' '' 'clean --force' git-clean
t DENY Bash 'git clean -ffdx' '' 'clean -ffdx' git-clean
t DENY Bash 'git branch -D feature' '' 'branch -D' branch-force-delete
t DENY Bash 'git branch -d -f feature' '' 'branch -d -f' branch-force-delete
t DENY Bash 'git branch -df feature' '' 'branch -df' branch-force-delete
t DENY Bash 'git branch --delete --force feature' '' 'branch --delete --force' branch-force-delete
t DENY Bash 'git push origin +main' '' 'push +refspec' force-push
t DENY Bash 'git push origin +HEAD:refs/heads/main' '' 'push +HEAD:ref' force-push
t DENY Bash 'git push -f' '' 'push -f' force-push
t DENY Bash 'git push -fu origin x' '' 'push -fu cluster' force-push
t DENY Bash 'git push origin main --force' '' 'push --force after the refspec' force-push
t DENY Bash 'git push --force-with-lease' '' 'push --force-with-lease' force-push
t DENY Bash 'git push --force-with-lease=main:abc origin main' '' 'push --force-with-lease=ref:sha' force-push
t DENY Bash 'git push --force-if-includes origin main' '' 'push --force-if-includes' force-push
t DENY Bash 'git -C ../other push --force' '' 'git -C dir push --force' force-push
t DENY Bash 'git --git-dir=../o/.git push -f' '' 'git --git-dir=x push -f' force-push
t DENY Bash 'git stash clear' '' 'stash clear' stash-clear
t DENY Bash 'git checkout .' '' 'checkout .' checkout-discard
t DENY Bash 'git checkout -f' '' 'checkout -f' checkout-discard
t DENY Bash 'git checkout --force main' '' 'checkout --force branch' checkout-discard
t DENY Bash 'git checkout HEAD -- .' '' 'checkout HEAD -- .' checkout-discard
t DENY Bash 'git restore .' '' 'restore .' checkout-discard
t DENY Bash 'git restore --worktree --staged docs/x.md' '' 'restore --worktree --staged' checkout-discard
t DENY Bash 'git restore -SW docs/x.md' '' 'restore -SW' checkout-discard
t DENY Bash 'git restore --source=HEAD~2 docs/x.md' '' 'restore --source (worktree)' checkout-discard
# ── DENY: infra destroy spellings ────────────────────────────────────────────
t DENY Bash 'terraform -chdir=infra destroy' '' 'terraform -chdir=x destroy' infra-destroy
t DENY Bash 'terraform apply -auto-approve -destroy' '' 'terraform apply -destroy' infra-destroy
t DENY Bash 'tofu destroy' '' 'tofu destroy' infra-destroy
t DENY Bash 'terragrunt destroy' '' 'terragrunt destroy' infra-destroy
t DENY Bash 'pulumi down' '' 'pulumi down' infra-destroy
t DENY Bash 'pulumi destroy --yes' '' 'pulumi destroy --yes' infra-destroy
t DENY Bash 'cd infra && TF_LOG=1 terraform destroy' '' 'VAR=val terraform destroy' infra-destroy
# ── DENY: heredoc bodies are judged (an interpreter fed a heredoc runs them) ─
t DENY Bash $'cat <<EOF > /tmp/x.sh\nrm -rf ~/x\nEOF' '' 'heredoc body line' rm-recursive
t DENY Bash $'bash <<EOF\ngit reset --hard\nEOF' '' 'heredoc fed to bash' reset-hard
t DENY Bash $'cat <<\'EOF\'\ndon\'t worry, it is fine\nEOF\ngit push --force origin main' '' 'apostrophe in a heredoc does not swallow a later real command' force-push
t DENY Bash $'echo "it\'s ok"\nrm -rf ~/x' '' 'unbalanced-looking quote then a real command on the next line' rm-recursive
# ── DENY: a very long command still judged in full (oversized input) ───────
long="$(python3 -c 'print("echo " + "a" * 200000)')"
t DENY Bash "$long; git clean -fdx" '' '200 KB of prose before a real command' git-clean

# ── DENY: the test author's nastier disguises that the judge DOES catch ─────
t DENY Bash "eval 'r''m -rf ~/x'" '' 'eval of a quote-glued command name' rm-recursive
t DENY Bash 'xargs -0 rm -rf ~/x' '' 'xargs -0 (option without a value)' rm-recursive
t DENY Bash 'sudo -i rm -rf ~/x' '' 'sudo -i' rm-recursive
t DENY Bash 'git stash clear 2>/dev/null' '' 'stash clear with a redirect' stash-clear
t DENY Bash 'git --no-pager push -f' '' 'git --no-pager push -f' force-push
t DENY Bash 'git -Cdir push -f' '' 'git -C glued to its dir' force-push
t DENY Bash 'git --work-tree . reset --hard' '' 'git --work-tree <dir> reset --hard' reset-hard
t DENY Bash 'GIT_DIR=x git clean -fdx' '' 'GIT_DIR= prefix' git-clean
t DENY Bash 'git clean -f -e keep' '' 'clean -f -e pattern' git-clean
t DENY Bash 'git clean --force=1' '' 'clean --force=x' git-clean
t DENY Bash 'git clean -fdx "x;y"' '' 'clean with a quoted arg holding a separator' git-clean
t DENY Bash 'git restore --worktree=x a' '' 'restore --worktree=' checkout-discard
t DENY Bash 'git reset --hard=HEAD' '' 'reset --hard=' reset-hard
t DENY Bash 'git branch -Dr origin/x' '' 'branch -Dr' branch-force-delete
t DENY Bash 'rm -rf ../' '' 'rm -rf ../' rm-recursive
t DENY Bash 'rm -rf ~/proj/tmp-old' '' 'a dir merely NAMED tmp-something under home is not excluded' rm-recursive
t DENY Bash 'printf x 1>harness.conf' '' '1>harness.conf' control-edit
t DENY Bash 'cat > harness.conf <<EOF' '' 'cat > control <<EOF' control-edit
t DENY Bash 'exec 3> harness.conf' '' 'exec fd redirect onto control' control-edit
t DENY Bash 'cp -f /tmp/x harness.conf' '' 'cp -f onto control' control-edit
t DENY Bash 'install -m 644 /tmp/x scripts/guard-check.py' '' 'install -m mode onto a judge' control-edit
t DENY Bash 'git checkout -- harness.conf' '' 'checkout -- a control file' checkout-discard

# ══ round 2 (2026-09-30): the invent-nastier cases the builder fixed ═════════
ME="$(id -un)"; REPO_NAME="$(basename "$REPO")"; REPO_PARENT="$(dirname "$REPO")"
# ── a quoted argument holding a separator no longer hides the target ─────────
t DENY Bash 'rm -rf "$HOME" "x;y"' '' 'quoted home + quoted arg holding ;' rm-recursive
t DENY Bash "rm -rf '/' 'a|b'" '' 'quoted / + quoted arg holding |' rm-recursive
t DENY Bash 'rm -rf "$HOME/x" "(a)"' '' 'quoted home path + quoted arg holding parens' rm-recursive
t DENY Bash "rm -rf ~/x 'it''s'" '' 'protected target + glued-quote arg' rm-recursive
# An apostrophe in a heredoc body makes the WHOLE text unparseable for the quote-aware pass, so only
# the quote-blind pass (and its unbalanced-quote fallback) sees the later real command.
t DENY Bash $'cat <<\'EOF\'\ndon\'t\nEOF\nrm -rf "$HOME" "x;y"' '' 'heredoc apostrophe + quoted separator: the fallback strips the quotes' rm-recursive
t DENY Bash $'cat <<\'EOF\'\ndon\'t\nEOF\n\'rm\' -rf ~/x "a;b"' '' 'heredoc apostrophe + QUOTED command name in an unbalanced piece' rm-recursive
# ── .. is folded before judging ──────────────────────────────────────────────
t DENY Bash 'rm -rf ~/build/..' '' '~/build/.. is home' rm-recursive
t DENY Bash 'rm -rf ~/tmp/..' '' '~/tmp/.. is home' rm-recursive
t DENY Bash "rm -rf /tmp/..$HOME" '' '/tmp/../<home> is home' rm-recursive
t DENY Bash 'rm -rf $HOME/x/node_modules/../..' '' 'node_modules/../.. climbs to home' rm-recursive
t DENY Bash 'rm -rf /tmp/../etc' '' '/tmp/../etc is a system dir' rm-recursive
t ALLOW Bash 'rm -rf ~/proj/build/../node_modules' '' '.. that lands in another excluded dir'
t ALLOW Bash 'rm -rf /tmp/a/../b' '' '.. that stays in /tmp'
# ── case-insensitive command names (RM runs rm on this filesystem) ───────────
t DENY Bash 'RM -rf ~/x' '' 'RM' rm-recursive
t DENY Bash 'Rm -Rf ~/x' '' 'Rm' rm-recursive
t DENY Bash 'GIT reset --hard' '' 'GIT reset --hard' reset-hard
t DENY Bash 'git RESET --hard' '' 'git RESET (subcommand case)' reset-hard
t DENY Bash 'SUDO RM -rf ~/x' '' 'SUDO RM' rm-recursive
# ── ~user is a home ──────────────────────────────────────────────────────────
t DENY Bash "rm -rf ~$ME" '' '~<me>' rm-recursive
t DENY Bash "rm -rf ~$ME/Documents" '' '~<me>/Documents' rm-recursive
t ALLOW Bash "rm -rf ~$ME/proj/node_modules" '' '~<me>/…/node_modules is excluded'
# ── relative paths are resolved against the payload's cwd ────────────────────
ROW_CWD="$REPO"
t DENY  Bash "rm -rf ../$REPO_NAME" '' 'repo root by relative path (cwd = repo)' rm-recursive
t DENY  Bash "rm -rf ./../$REPO_NAME/" '' 'repo root by ./../name/' rm-recursive
t DENY  Bash 'rm -rf ../../' '' 'an ancestor of the repo' rm-recursive
t DENY  Bash 'rm -rf ../other-project' '' 'a sibling outside the repo, under home' rm-recursive
t DENY  Bash 'find ../other-project -delete' '' 'find -delete outside the repo, under home' find-delete
t ALLOW Bash 'rm -rf src/generated' '' 'relative path inside the repo'
t ALLOW Bash 'rm -rf build' '' 'relative build dir'
t ALLOW Bash 'rm -rf scripts/lib/old' '' 'deep relative path inside the repo'
t ALLOW Bash 'rm -rf ../other-project/node_modules' '' 'outside the repo but an excluded dir'
ROW_CWD="$REPO/scripts"
t DENY  Bash 'rm -rf ..' '' 'cwd = repo/scripts: .. is the repo root' rm-recursive
t DENY  Bash 'rm -rf ../../..' '' 'cwd = repo/scripts: an ancestor' rm-recursive
t ALLOW Bash 'rm -rf ../running-files/old' '' 'cwd = repo/scripts: ../x stays inside the repo'
ROW_CWD="$HOME"
t DENY  Bash 'rm -rf Documents' '' 'cwd = home: a bare relative name is a home path' rm-recursive
# a cwd that is a SYMLINK to the repo: bash resolves .. physically, so ../<name> IS the real repo
ln -s "$REPO" "$T/repolink"
ROW_CWD="$T/repolink"
t DENY  Bash "rm -rf ../$REPO_NAME" '' 'cwd is a symlink to the repo: ../<repo> is the real repo' rm-recursive
t ALLOW Bash 'rm -rf src/generated' '' 'cwd is a symlink to the repo: a path inside it stays allowed'
ROW_CWD="$T/repolink/scripts"
t DENY  Bash 'rm -rf ..' '' 'cwd is a symlinked repo/scripts: .. is the repo root' rm-recursive
ROW_CWD='relative/not/absolute'
t DENY  Bash "rm -rf ../$REPO_NAME" '' 'a non-absolute cwd is ignored (falls back to the repo root)' rm-recursive
unset ROW_CWD
# ── system folders below the top level ───────────────────────────────────────
t DENY Bash 'rm -rf /usr/local' '' '/usr/local' rm-recursive
t DENY Bash 'rm -rf /System/Library' '' '/System/Library' rm-recursive
t DENY Bash 'rm -rf /etc/ssh' '' '/etc/ssh' rm-recursive
t DENY Bash 'rm -rf /opt/homebrew' '' '/opt/homebrew' rm-recursive
t DENY Bash 'rm -rf /Library/Preferences' '' '/Library/Preferences' rm-recursive
t ALLOW Bash 'rm -rf /var/folders/ab/cd/T/build' '' '/var/folders temp stays allowed'
# ── more wrappers ────────────────────────────────────────────────────────────
t DENY Bash 'caffeinate -i rm -rf ~/x' '' 'caffeinate -i' rm-recursive
t DENY Bash 'caffeinate -t 60 git clean -fdx' '' 'caffeinate -t N' git-clean
t DENY Bash 'setsid rm -rf ~/x' '' 'setsid' rm-recursive
t DENY Bash 'watch -n1 rm -rf ~/x' '' 'watch -n1' rm-recursive
t DENY Bash 'flock /tmp/l git reset --hard' '' 'flock <lockfile>' reset-hard
t DENY Bash 'env -S "rm -rf ~/x"' '' 'env -S split-string' rm-recursive
t DENY Bash "env --split-string='git push -f'" '' 'env --split-string= (glued long form)' force-push
t DENY Bash 'env --split-string "git reset --hard"' '' 'env --split-string (separate)' reset-hard
t DENY Bash "bash -c -- 'rm -rf ~/x'" '' 'bash -c -- string' rm-recursive
t DENY Bash "fish -c 'rm -rf ~/x'" '' 'fish -c' rm-recursive
# ── here-strings and echo-into-a-shell ───────────────────────────────────────
t DENY Bash "bash <<< 'rm -rf ~/x'" '' 'here-string to bash' rm-recursive
t DENY Bash 'sh <<< "git stash clear"' '' 'here-string to sh' stash-clear
t DENY Bash "echo 'rm -rf ~/x' | bash" '' 'echo piped into bash' rm-recursive
t DENY Bash "printf 'git reset --hard' | sh -s" '' 'printf piped into sh -s' reset-hard
t ALLOW Bash "echo 'rm -rf ~/x' | grep rm" '' 'echo piped into grep is prose'
t DENY  Bash "cat <<< 'rm -rf ~/x'" '' 'a here-string body is judged whatever reads it (same deliberate policy as heredoc bodies)' rm-recursive
# ── git: switch, mirror, deleting the shared branch ──────────────────────────
t DENY Bash 'git switch -f main' '' 'switch -f' checkout-discard
t DENY Bash 'git switch --discard-changes main' '' 'switch --discard-changes' checkout-discard
t DENY Bash 'git switch --force feature' '' 'switch --force' checkout-discard
t DENY Bash 'git push --mirror' '' 'push --mirror' force-push
t DENY Bash 'git push origin --delete main' '' 'push --delete main' push-delete
t DENY Bash 'git push -d origin master' '' 'push -d master' push-delete
t DENY Bash 'git push origin :main' '' 'push :main' push-delete
t DENY Bash 'git push origin :refs/heads/main' '' 'push :refs/heads/main' push-delete
t ALLOW Bash 'git switch main' '' 'plain switch'
t ALLOW Bash 'git switch -c feature' '' 'switch -c'
t ALLOW Bash 'git push origin --delete feature-x' '' 'deleting a FEATURE branch'
t ALLOW Bash 'git push origin :feature-x' '' ':feature-x'
t ALLOW Bash 'git push origin --delete feature/main' '' 'feature/main is not main (only refs/heads/ is stripped)'
t ALLOW Bash 'git push origin :feature/master' '' ':feature/master is not master'
t ALLOW Bash 'git push origin --delete main-old' '' 'main-old is not main'
t DENY  Bash 'git push origin --delete refs/heads/main' '' '--delete refs/heads/main' push-delete
t ALLOW Bash 'git push origin main:main' '' 'a normal src:dst refspec'
# ── infra spellings ──────────────────────────────────────────────────────────
t DENY Bash 'pulumi -C infra destroy' '' 'pulumi -C dir destroy' infra-destroy
t DENY Bash 'pulumi --cwd infra destroy --yes' '' 'pulumi --cwd dir destroy' infra-destroy
t DENY Bash 'terragrunt --terragrunt-working-dir x destroy' '' 'terragrunt --terragrunt-working-dir x destroy' infra-destroy
t DENY Bash 'terraform -chdir infra destroy' '' 'terraform -chdir x (space)' infra-destroy
t DENY Bash 'terragrunt run-all destroy' '' 'terragrunt run-all destroy' infra-destroy
t DENY Bash 'terraform apply -destroy=true' '' 'apply -destroy=true' infra-destroy
t DENY Bash 'tofu apply --destroy' '' 'tofu apply --destroy' infra-destroy
t ALLOW Bash 'terraform apply -destroy=false' '' 'apply -destroy=false'
t ALLOW Bash 'pulumi -C infra up' '' 'pulumi -C dir up'
# ── the control floor: folder destinations, case, symlinks, more copy tools ──
t DENY Bash 'cp /tmp/hook-pretooluse-guard.sh scripts/' '' 'cp INTO scripts/ (trailing slash)' control-edit
t DENY Bash 'mv /tmp/guard-check.py scripts' '' 'mv INTO an existing scripts dir' control-edit
t DENY Bash 'cp -r /tmp/x/harness.conf .' '' 'cp INTO . lands on harness.conf' control-edit
t DENY Bash 'git mv /tmp/verify-check.py scripts/' '' 'git mv INTO scripts/' control-edit
t DENY Bash 'rsync /tmp/x harness.conf' '' 'rsync onto harness.conf' control-edit
t DENY Bash 'rsync -a /tmp/hook-x.sh scripts/' '' 'rsync INTO scripts/' control-edit
t DENY Bash 'ditto /tmp/x harness.conf' '' 'ditto onto harness.conf' control-edit
t DENY Bash 'awk -i inplace 1 harness.conf' '' 'gawk -i inplace' control-edit
t ALLOW Bash 'cp /tmp/notes.md scripts/' '' 'cp a non-control file INTO scripts/'
t ALLOW Bash 'rsync -a harness.conf /tmp/backup/' '' 'rsync FROM harness.conf'
t ALLOW Bash "awk '{print}' harness.conf" '' 'awk reading harness.conf'
t DENY Bash 'echo x > HARNESS.CONF' '' 'case-variant redirect' control-edit
t DENY Write '' 'Harness.conf' 'case-variant Write Harness.conf' control-edit
t DENY Write '' '.Claude/Settings.json' 'case-variant .Claude/Settings.json' control-edit
t DENY Edit '' 'Scripts/Hook-pretooluse-guard.sh' 'case-variant Scripts/Hook-*.sh' control-edit
t DENY Edit '' 'scripts/GUARD-CHECK.PY' 'case-variant judge' control-edit
ln -s "$REPO/harness.conf" "$T/innocent.txt"
ln -s "$REPO/scripts" "$T/innocent-dir"
t DENY Write '' "$T/innocent.txt" 'Write through a symlink to harness.conf' control-edit
t DENY Bash "echo x > $T/innocent.txt" '' 'redirect through a symlink to harness.conf' control-edit
t DENY Edit '' "$T/innocent-dir/guard-check.py" 'Edit through a symlinked folder' control-edit
t DENY Bash "ln -s $REPO/harness.conf /tmp/h" '' 'ln -s naming a control file' control-edit
t DENY Bash 'echo x >| harness.conf' '' 'clobber >| onto harness.conf' control-edit
t DENY Bash 'echo x >| scripts/hook-pretooluse-guard.sh' '' 'clobber >| onto a hook' control-edit
t DENY Bash 'echo x > ${HOME}/.claude/settings.json' '' '${HOME} settings redirect' control-edit
t DENY Bash 'git checkout stash@{0} -- harness.conf' '' 'checkout stash@{0} -- control' checkout-discard
# ── the two over-blocks that were fixed ──────────────────────────────────────
t ALLOW Bash 'echo "a > harness.conf"' '' 'echo prose with > control inside quotes'
t ALLOW Bash 'git commit -m "never redirect > harness.conf"' '' 'commit message with > control inside quotes'
t ALLOW Bash 'git rm --cached harness.conf' '' 'git rm --cached (index only)'
t DENY  Bash 'git rm harness.conf' '' 'git rm without --cached still denied' control-edit

# ── ALLOW: near-misses of the new families ───────────────────────────────────
t ALLOW Bash 'git commit -m "guard now stops rm -r -f ~/x, git reset --hard, git clean -f, git branch -D, git stash clear and git push -f"' '' 'commit message naming every new family'
t ALLOW Bash 'echo git push --force-with-lease is blocked now' '' 'echo naming a force push'
t ALLOW Bash 'printf "%s\n" "rm -rf ~" "git reset --hard"' '' 'printf args naming commands'
t ALLOW Bash '# rm -rf ~/x' '' 'a whole-line shell comment'
t ALLOW Bash 'grep -rn "git clean -f" docs/' '' 'grep for a destructive spelling'
t ALLOW Bash "find . -name '*.pyc' -delete" '' 'find with -name filter'
t ALLOW Bash "find ~/x -path '*/cache/*' -delete" '' 'find home with -path filter'
t ALLOW Bash "find . -iname '*.orig' -exec rm {} +" '' 'find -exec rm with -iname filter'
t ALLOW Bash 'find . -type f -print' '' 'find without delete'
t ALLOW Bash 'git clean -n' '' 'clean -n dry run'
t ALLOW Bash 'git clean -fdn' '' 'clean -fdn (dry run wins)'
t ALLOW Bash 'git clean -f --dry-run' '' 'clean -f --dry-run'
t ALLOW Bash 'git branch -d feature' '' 'branch -d (refuses unless merged)'
t ALLOW Bash 'git branch --delete feature' '' 'branch --delete'
t ALLOW Bash 'git stash drop stash@{0}' '' 'stash drop one entry'
t ALLOW Bash 'git stash list' '' 'stash list'
t ALLOW Bash 'git reset --soft HEAD~1' '' 'reset --soft'
t ALLOW Bash 'git reset --keep HEAD~1' '' 'reset --keep'
t ALLOW Bash 'git reset HEAD docs/x.md' '' 'reset (mixed) unstage path'
t ALLOW Bash 'git restore -S docs/x.md' '' 'restore -S (staged only)'
t ALLOW Bash 'git checkout -b feature' '' 'checkout -b'
t ALLOW Bash 'git push -u origin feature' '' 'push -u'
t ALLOW Bash 'git push --follow-tags origin main' '' 'push --follow-tags'
t ALLOW Bash 'git -C ../other push origin main' '' 'git -C dir normal push'
t ALLOW Bash 'git log --oneline -5' '' 'git log'
t ALLOW Bash 'terraform plan -destroy' '' 'terraform plan -destroy is a plan'
t ALLOW Bash 'pulumi preview' '' 'pulumi preview'
t ALLOW Bash 'pulumi up' '' 'pulumi up'
t ALLOW Bash 'rm -rf /private/tmp/x' '' 'rm -rf /private/tmp'
t ALLOW Bash 'rm -rf /var/folders/ab/T/x' '' 'rm -rf macOS temp'
t ALLOW Bash 'rm -rf $TMPDIR/x' '' 'rm -rf $TMPDIR/x'
t ALLOW Bash "rm -rf $HOME/proj/scratchpad/x" '' 'rm -rf a scratchpad path under home'
t ALLOW Bash 'rm -rf node_modules' '' 'rm -rf node_modules (bare)'
t ALLOW Bash 'rm -rf build dist target .next coverage' '' 'rm -rf build dirs'
t ALLOW Bash 'rm -rf ~/proj/node_modules ~/proj/build' '' 'build dirs under home'
t ALLOW Bash 'rm -rf src/old' '' 'rm -rf a relative project subdir'
t ALLOW Bash 'rm -f ~/x.txt' '' 'non-recursive rm in home'
t ALLOW Bash 'ls 2>&1 > /tmp/x' '' 'redirect 2>&1 > /tmp/x'
t ALLOW Bash 'make test 2>&1 | tee /tmp/out.log' '' 'tee to a temp file'
t ALLOW Bash 'bash scripts/hook-pretooluse-guard-test.sh' '' 'running the guard matrix'
t ALLOW Bash 'bash scripts/hook-repeat-check-test.sh && bash scripts/hook-stop-verifycheck-test.sh' '' 'running the hook matrices'

# ══ the CONTROL FLOOR: the harness's own enforcement ═════════════════════════
for tool in Write Edit MultiEdit; do
  t DENY $tool '' '.claude/settings.json' "$tool .claude/settings.json" control-edit
done
t DENY Edit '' '.claude/settings.local.json' 'Edit .claude/settings.local.json' control-edit
t DENY Write '' "$REPO/.claude/settings.json" 'Write absolute repo .claude/settings.json' control-edit
t DENY Write '' '~/.claude/settings.json' 'Write ~/.claude/settings.json (user level)' control-edit
t DENY Write '' "$HOME/.claude/settings.json" 'Write $HOME/.claude/settings.json expanded' control-edit
t DENY Edit '' '/elsewhere/proj/.claude/settings.local.json' 'any .claude/settings*.json anywhere' control-edit
t DENY Write '' 'scripts/hook-pretooluse-guard.sh' 'Write scripts/hook-pretooluse-guard.sh' control-edit
t DENY Edit '' "$REPO/scripts/hook-stop-claimcheck.sh" 'Edit absolute scripts/hook-*.sh' control-edit
t DENY Write '' 'scripts/hook-brand-new.sh' 'a NEW scripts/hook-*.sh is control too' control-edit
t DENY Edit '' 'scripts/guard-check.py' 'Edit scripts/guard-check.py' control-edit
t DENY Edit '' 'scripts/verify-check.py' 'Edit scripts/verify-check.py' control-edit
t DENY MultiEdit '' 'scripts/claim-check.py' 'MultiEdit scripts/claim-check.py' control-edit
t DENY Write '' 'harness.conf' 'Write harness.conf' control-edit
t DENY Write '' './scripts/../harness.conf' 'harness.conf via a dot-dot path' control-edit
judge DENY "$(mkpayload NotebookEdit '' '' 'scripts/hook-x.sh')" 'NotebookEdit notebook_path onto a hook' control-edit
# Bash spellings that write, move or delete a control file
t DENY Bash 'echo {} > .claude/settings.json' '' 'redirect > settings' control-edit
t DENY Bash 'echo x >> harness.conf' '' 'append >> harness.conf' control-edit
t DENY Bash 'echo x >harness.conf' '' 'redirect with no space' control-edit
t DENY Bash 'echo x > "scripts/guard-check.py"' '' 'redirect to a quoted path' control-edit
t DENY Bash 'echo x 2>&1 > harness.conf' '' '2>&1 > harness.conf' control-edit
t DENY Bash 'echo x &> harness.conf' '' '&> harness.conf' control-edit
t DENY Bash 'cat /tmp/x > ~/.claude/settings.json' '' 'redirect onto user-level settings' control-edit
t DENY Bash 'echo {} > $HOME/.claude/settings.local.json' '' 'redirect onto $HOME settings.local' control-edit
t DENY Bash "sed -i '' 's/a/b/' scripts/guard-check.py" '' 'sed -i (BSD form)' control-edit
t DENY Bash "sed -i.bak 's/a/b/' harness.conf" '' 'sed -i.bak' control-edit
t DENY Bash "sed -Ei 's/a/b/' scripts/hook-stop-verifycheck.sh" '' 'sed -Ei cluster' control-edit
t DENY Bash "sed --in-place 's/a/b/' scripts/verify-check.py" '' 'sed --in-place' control-edit
t DENY Bash "perl -pi -e 's/a/b/' harness.conf" '' 'perl -pi' control-edit
t DENY Bash 'mv /tmp/x scripts/hook-pretooluse-guard.sh' '' 'mv onto a hook' control-edit
t DENY Bash 'mv scripts/guard-check.py /tmp/' '' 'mv a judge away' control-edit
t DENY Bash 'rm scripts/verify-check.py' '' 'rm a judge' control-edit
t DENY Bash 'rm -f harness.conf' '' 'rm -f harness.conf' control-edit
t DENY Bash 'unlink scripts/claim-check.py' '' 'unlink a judge' control-edit
t DENY Bash 'cp /tmp/x harness.conf' '' 'cp with harness.conf as DESTINATION' control-edit
t DENY Bash 'cp /tmp/x ./.claude/settings.json' '' 'cp onto ./.claude/settings.json' control-edit
t DENY Bash 'ln -sf /dev/null scripts/guard-check.py' '' 'ln -sf over a judge' control-edit
t DENY Bash 'tee scripts/claim-check.py < /tmp/x' '' 'tee onto a judge' control-edit
t DENY Bash 'echo x | tee -a harness.conf' '' 'tee -a harness.conf' control-edit
t DENY Bash 'truncate -s 0 harness.conf' '' 'truncate harness.conf' control-edit
t DENY Bash 'chmod -x scripts/hook-pretooluse-guard.sh' '' 'chmod a hook' control-edit
t DENY Bash 'dd if=/dev/null of=harness.conf' '' 'dd of=harness.conf' control-edit
t DENY Bash 'git rm scripts/hook-stop-claimcheck.sh' '' 'git rm a hook' control-edit
t DENY Bash 'git mv scripts/guard-check.py old.py' '' 'git mv a judge' control-edit
t DENY Bash "bash -c 'echo x > harness.conf'" '' 'redirect inside bash -c' control-edit
t DENY Bash 'HARNESS_ALLOW_CONTROL_EDITS=1 sed -i x harness.conf' '' 'override as a VAR=val prefix does not lift the floor' control-edit
t DENY Bash 'export HARNESS_ALLOW_CONTROL_EDITS=1; echo x > harness.conf' '' 'override exported in the Bash tool does not lift the floor' control-edit
# ALLOW: reading or copying FROM a control file, and the non-control neighbours
t ALLOW Bash 'cat .claude/settings.json' '' 'cat settings'
t ALLOW Bash 'grep -n HARNESS harness.conf' '' 'grep harness.conf'
t ALLOW Bash 'sed -n 1,20p scripts/guard-check.py' '' 'sed -n (no -i) on a judge'
t ALLOW Bash 'cp scripts/hook-pretooluse-guard.sh /tmp/guard.sh' '' 'cp with a hook as SOURCE'
t ALLOW Bash 'cp harness.conf harness.conf.bak' '' 'cp harness.conf to a backup name'
t ALLOW Bash 'python3 scripts/guard-check.py . < /tmp/payload.json' '' 'stdin redirect FROM a control file area'
t ALLOW Bash 'git diff harness.conf scripts/guard-check.py' '' 'git diff control files'
t ALLOW Bash 'git add scripts/guard-check.py' '' 'staging a control file'
t ALLOW Bash 'shellcheck scripts/hook-pretooluse-guard.sh' '' 'linting a hook'
t ALLOW Read '' 'harness.conf' 'Read tool on harness.conf'
t ALLOW Write '' 'scripts/other.sh' 'Write a non-hook script'
t ALLOW Write '' 'harness.conf.example' 'Write harness.conf.example'
t ALLOW Write '' '.claude/agents/x.md' 'Write .claude/agents (not settings)'
t ALLOW Write '' 'dot-claude/settings.json' 'Write the kit template dot-claude/settings.json'
t ALLOW Edit '' 'src/settings.json' 'a settings.json outside .claude'

# ── the owner's launch override lifts the floor (and ONLY the floor) ─────────
EXTRA_ENV='HARNESS_ALLOW_CONTROL_EDITS=1'
t ALLOW Write '' '.claude/settings.json' 'override: Write settings'
t ALLOW Edit '' 'scripts/guard-check.py' 'override: Edit judge'
t ALLOW Bash 'echo x > harness.conf' '' 'override: redirect onto harness.conf'
t ALLOW Bash "sed -i '' s/a/b/ scripts/hook-stop-verifycheck.sh" '' 'override: sed -i a hook'
t DENY  Bash 'rm -rf ~/x' '' 'override does NOT lift the destructive rules' rm-recursive
t DENY  Bash 'git reset --hard' '' 'override does NOT lift reset --hard' reset-hard
EXTRA_ENV='HARNESS_ALLOW_CONTROL_EDITS=yes'
t DENY  Write '' 'harness.conf' 'override must be exactly 1' control-edit
unset EXTRA_ENV

# ── the override written INTO harness.conf must NOT lift the floor ───────────
TR="$T/repo"; mkdir -p "$TR/scripts" "$TR/ci"; git -C "$TR" init -q
printf 'HARNESS_ALLOW_CONTROL_EDITS=1\nexport HARNESS_ALLOW_CONTROL_EDITS=1\nHARNESS_LOG_DIR="%s"\nHARNESS_CONTROL_PATHS="ci/*.sh"\n' "$T/repo-logs" > "$TR/harness.conf"
GUARD_CWD="$TR"
t DENY  Write '' 'harness.conf' 'conf override: Write harness.conf still denied' control-edit
t DENY  Write '' "$TR/.claude/settings.json" 'conf override: Write settings still denied' control-edit
t DENY  Bash 'echo x > scripts/hook-a.sh' '' 'conf override: redirect onto a hook still denied' control-edit
t DENY  Write '' 'ci/gate.sh' 'HARNESS_CONTROL_PATHS in harness.conf ADDS control paths' control-edit
t ALLOW Write '' 'ci/notes.md' 'HARNESS_CONTROL_PATHS glob does not over-match'
EXTRA_ENV='HARNESS_ALLOW_CONTROL_EDITS=1'
t ALLOW Write '' 'harness.conf' 'negative control: the same temp repo DOES allow with the launch override'
unset EXTRA_ENV GUARD_CWD
# the HARNESS_BASE_REF branch is protected from remote deletion like main/master
TB="$T/repo-base"; mkdir -p "$TB"; git -C "$TB" init -q
printf 'HARNESS_BASE_REF="origin/release"\n' > "$TB/harness.conf"
GUARD_CWD="$TB"
t DENY  Bash 'git push origin --delete release' '' 'HARNESS_BASE_REF branch: --delete denied' push-delete
t DENY  Bash 'git push origin :release' '' 'HARNESS_BASE_REF branch: :ref denied' push-delete
t DENY  Bash 'git push origin --delete main' '' 'main stays protected alongside the base ref' push-delete
t ALLOW Bash 'git push origin --delete release-notes' '' 'a branch merely STARTING with the base name'
unset GUARD_CWD
t ALLOW Bash 'git push origin --delete release' '' 'negative control: release is NOT protected where it is not the base ref'
[ -f "$T/repo-logs/guard.log" ] && { fail=$((fail+1)); echo "FAIL  HARNESS_GUARD_LOG did not override HARNESS_LOG_DIR from harness.conf"; } || pass=$((pass+1))

# ── the deny LOG: one line, names the rule, never the command text ───────────
before="$(loglines)"
judge DENY "$(python3 -c 'import json; print(json.dumps({"session_id":"sessABCDEFGH","tool_name":"Bash","tool_input":{"command":"rm -rf ~/GUARDLOGMARKER-x9"}}))')" 'log probe deny' rm-recursive
line="$(tail -1 "$GLOG")"
if [ "$(loglines)" -eq $((before + 1)) ] && printf '%s' "$line" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z session=sessABCD tool=Bash rule=rm-recursive$' \
   && ! grep -q 'GUARDLOGMARKER' "$GLOG"; then pass=$((pass+1))
else fail=$((fail+1)); echo "FAIL  deny log line must be 'ts session=<8> tool=<t> rule=<r>' with no command text: $line"; fi
# log INJECTION: a session id carrying a newline (or spaces, or a fake rule=) must yield ONE clean line
for sid in 'ab\nrule=x' 'a b rule=fake' 'x$(id)\r\n'; do
  before="$(loglines)"
  judge DENY "{\"session_id\":\"$sid\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git reset --hard\"}}" "log injection via session id: $sid" reset-hard
  line="$(tail -1 "$GLOG")"
  if [ "$(loglines)" -eq $((before + 1)) ] && printf '%s' "$line" | grep -qE '^[0-9TZ:-]+ session=[A-Za-z0-9-]{1,8} tool=Bash rule=reset-hard$'; then pass=$((pass+1))
  else fail=$((fail+1)); echo "FAIL  session id must be sanitised to one clean log line: $(tail -2 "$GLOG" | tr '\n' '|')"; fi
done

# ── command INJECTION through the payload (family I): judged, never executed ─
judge DENY "$(python3 -c 'import json,sys; print(json.dumps({"session_id":"x$(touch %s/pwn1)" % sys.argv[1],"tool_name":"Bash","tool_input":{"command":"x'"'"'; touch %s/pwn2; '"'"' ; git reset --hard" % sys.argv[1]}}))' "$T")" 'hostile quotes in command + session id' reset-hard
judge ALLOW "$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":"$(touch %s/pwn3)`touch %s/pwn4`" % (sys.argv[1], sys.argv[1])}}))' "$T")" 'hostile file_path'
if ls "$T"/pwn* >/dev/null 2>&1; then fail=$((fail+1)); echo "FAIL  payload text was EXECUTED by the hook"; else pass=$((pass+1)); fi
judge DENY '{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_input":{"command":"git stash clear"}}' 'duplicate JSON keys: the last one (what runs) is judged' stash-clear

# ── must DENY: the guard CANNOT RUN (fail-closed) ────────────────────────────
# The guard's own empty-scan case. Without these rows the fail-closed branches are exactly the kind
# of never-watched code path this matrix exists to catch — and their failure mode is a silent ALLOW.
nopy="$T/nopy"
mkdir -p "$nopy" && printf '#!/bin/sh\nexit 127\n' > "$nopy/python3" && chmod +x "$nopy/python3"
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"terraform destroy"}}' \
       | PATH="$nopy:$PATH" bash "$GUARD" 2>/dev/null)"
if printf '%s' "$out" | grep -q '"deny"'; then pass=$((pass+1));
else fail=$((fail+1)); echo "FAIL  want=DENY got=ALLOW  no python3 must fail CLOSED"; fi

out="$(printf 'not json at all' | bash "$GUARD" 2>/dev/null)"
if printf '%s' "$out" | grep -q '"deny"'; then pass=$((pass+1));
else fail=$((fail+1)); echo "FAIL  want=DENY got=ALLOW  unparseable payload must fail CLOSED"; fi

# guard-check.py missing: a copy of the hook in a dir WITHOUT the judge must deny, not allow
mkdir -p "$T/nojudge" && cp "$GUARD" "$T/nojudge/hook-pretooluse-guard.sh"
before="$(loglines)"
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$T/nojudge/hook-pretooluse-guard.sh" 2>/dev/null)"
if printf '%s' "$out" | grep -q '"deny"' && printf '%s' "$out" | grep -q 'guard-check.py is missing' \
   && [ "$(loglines)" -eq $((before + 1)) ] && tail -1 "$GLOG" | grep -q 'rule=cannot-run$'; then pass=$((pass+1))
else fail=$((fail+1)); echo "FAIL  missing guard-check.py must fail CLOSED (and log rule=cannot-run): ${out:-<silent>}"; fi
# the judge crashing (a non-string command) must fail closed too
out="$(printf '{"tool_name":"Bash","tool_input":{"command":["rm","-rf","/"]}}' | bash "$GUARD" 2>/dev/null)"
if printf '%s' "$out" | grep -q '"deny"' && printf '%s' "$out" | grep -q 'judge'; then pass=$((pass+1))
else fail=$((fail+1)); echo "FAIL  judge ERROR must fail CLOSED: ${out:-<silent>}"; fi

# ── conf-dependent rows (exercised only when harness.conf sets the vars) ─────
skipped=0
ROOT="$REPO"
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

# ── the matrix itself never wrote the REAL deny log ──────────────────────────
real_log="$REPO/${HARNESS_LOG_DIR:-.harness-logs}/guard.log"
if [ -f "$real_log" ] && grep -q "session=$RUNSID " "$real_log"; then
  fail=$((fail+1)); echo "FAIL  the matrix wrote the REAL guard log ($real_log)"
else pass=$((pass+1)); fi

# A skip is not a pass (common.sh's exit vocabulary, applied to this matrix). Printing only
# "N pass, 0 fail" over silently-unexercised rows is the same lie the gates refuse to tell.
echo "guard-test: $pass pass, $fail fail, $skipped skipped (unexercised — NOT passes)"
[ "$skipped" -gt 0 ] && echo "  those rows cover the guard branches your harness.conf does not configure; set the vars to exercise them"
[ "$fail" -eq 0 ] && echo "self-proof: OK ($pass known-answer verdicts correct)" || exit 1
exit 0
