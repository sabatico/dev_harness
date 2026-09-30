#!/usr/bin/env bash
# check-image-pins.sh — no NEW third-party container image is pulled at a floating tag (security
# baseline item 5: "pin your versions"). A RATCHET: the existing unpinned pulls are baselined below with
# the ticket that pins them; anything new fails.
#
# WHY (2026-09-29, security-baseline-30 map): lockfiles are committed and OSV reads them, but the SCANNERS
# themselves — gitleaks, osv-scanner, trivy, nuclei, testssl, prowler, curl — are pulled at `:latest`
# and run with the repo mounted. A floating tag is someone else's release process deciding what code
# runs against this tree, the exact supply-chain door the dependency scans exist to close. Pinning each
# (a version tag, better a @sha256 digest) needs a chosen version, so it is a ticket, not a silent edit;
# the ratchet stops the list growing meanwhile. Generalised 2026-09-29 from a live project.
# BASELINE: $HARNESS_BASELINE_DIR/image-pins.txt, one "path image" per line (e.g. "scripts/scan.sh aquasec/trivy").
#
# Counts: `FROM <img>:latest|untagged`, `image: <img>:latest`, and `docker run … <ns>/<img>:latest` in
# tracked Dockerfiles, compose files, shell scripts, YAML and terraform. NOT counted: our own images
# pushed with a :latest convenience tag next to an immutable :$SHA tag (the name is a $VARIABLE).
# Usage: scripts/check-image-pins.sh [--check]    (test: scripts/check-image-pins-test.sh)
set -uo pipefail
ROOT="${HARNESS_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null)}" || exit 2
cd "$ROOT" || exit 2
[ -f harness.conf ] && . ./harness.conf
[ "${1:-}" = "--check" ] && shift
BF="${HARNESS_BASELINE_DIR:-.harness/baselines}/image-pins.txt"
BASELINE="$(cat "$BF" 2>/dev/null || true)"
files="$(git ls-files 2>/dev/null | grep -E '(^|/)(Dockerfile[^/]*|docker-compose[^/]*\.ya?ml|[^/]+\.(sh|ya?ml|tf))$|^scripts/hooks/' | grep -v node_modules | grep -v 'check-image-pins-test\.sh$')"
# ^ the gate's own matrix is excluded: its fixtures ARE floating pulls on purpose. (It passed while the
#   test was untracked; the first commit turned the gate red on itself — 2026-09-29.)
[ -n "$files" ] || { echo "✗ enumerated 0 files — a zero here would be a lie"; exit 1; }
python3 - "$BASELINE" $files <<'PY'
import re, sys
base = {tuple(l.split()) for l in sys.argv[1].strip().splitlines() if l.strip()}
files = sys.argv[2:]
IMG = r"((?:[\w.-]+\.[a-z]{2,}/)?[\w.-]+/[\w.-]+|[\w.-]+)"
pats = [re.compile(r"^\s*FROM\s+" + IMG + r"(?::latest)?(?:\s+AS\s+\w+)?\s*$", re.I),
        re.compile(r"^\s*image:\s*[\"']?" + IMG + r":latest\b"),
        re.compile(r"\b" + r"((?:[\w.-]+\.[a-z]{2,}/)?[\w.-]+/[\w.-]+)" + r":latest\b")]
found, seen = [], set()
for f in files:
    try:
        lines = open(f, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        continue
    for n, l in enumerate(lines, 1):
        if l.lstrip().startswith("#"):
            continue
        for i, rx in enumerate(pats):
            # FROM counts only in Dockerfiles: SQL `FROM information_schema.tables` in a shell heredoc
            # is not an image (first real-tree run, 2026-09-29). `image:` only in YAML/compose.
            fname = f.rsplit("/", 1)[-1]
            if i == 0 and not fname.startswith("Dockerfile"):
                continue
            if i == 1 and not re.search(r"\.ya?ml$", fname):
                continue
            m = rx.search(l)
            if not m or "$" in m.group(1):
                continue
            if i == 0 and (":" in l.split()[1] and not l.split()[1].endswith(":latest")):
                continue   # FROM with an explicit non-latest tag
            if i == 0 and "@sha256:" in l:
                continue
            key = (f, m.group(1))
            if key not in seen:
                seen.add(key); found.append((f, n, m.group(1)))
            break
new = [x for x in found if (x[0], x[2]) not in base]
print(f"image-pins: {len(found)} floating third-party pull(s); {len(found) - len(new)} baselined, {len(new)} new")
for f, n, img in new: print(f"  ✗ {f}:{n}  {img}:latest — pin a version tag or @sha256 digest")
stale = [b for b in base if not any((x[0], x[2]) == b for x in found)]
for b in stale: print(f"  ℹ baseline entry no longer present (pinned? remove it from the list): {b[0]} {b[1]}")
sys.exit(1 if new else 0)
PY
