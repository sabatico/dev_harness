#!/usr/bin/env bash
# check-image-pins-test.sh — known-answer matrix for check-image-pins.sh (the ratchet): a NEW floating
# third-party pull fails; pinned tags, digests, our own $VAR:latest push tags and baselined entries pass.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/ip-test.XXXXXX")"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q; export HARNESS_ROOT_OVERRIDE="$T"; mkdir -p "$T/scripts"; cp "$HERE/check-image-pins.sh" "$T/scripts/"
pass=0; fail=0
row() { # label want(0|1) file content
  rm -f "$T/x.sh" "$T/Dockerfile" "$T/docker-compose.yml" "$T/scripts/security-sweep.sh"
  printf '%s\n' "$4" > "$T/$3"; (cd "$T" && git add -A >/dev/null 2>&1)
  (cd "$T" && bash scripts/check-image-pins.sh --check >/dev/null 2>&1); local rc=$?
  if [ "$rc" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  want=$2 got=$rc  $1"; fi
}
row 'new docker run of ns/img:latest'     1 x.sh 'docker run --rm evilcorp/scanner:latest scan .'
row 'new registry image :latest'          1 x.sh 'docker run ghcr.io/acme/tool:latest'
row 'FROM untagged'                       1 Dockerfile 'FROM node'
row 'FROM :latest'                        1 Dockerfile 'FROM node:latest'
row 'compose image :latest'               1 docker-compose.yml 'services:
  db:
    image: postgres:latest'
row 'SQL FROM in a shell script is not an image' 0 x.sh 'psql -c "SELECT 1
FROM information_schema.tables"'
row 'pinned version tag'                  0 x.sh 'docker run --rm aquasec/trivy:0.56.2 fs .'
row 'pinned digest'                       0 Dockerfile 'FROM node:22-alpine@sha256:abc123'
row 'FROM pinned tag'                     0 Dockerfile 'FROM golang:1.26 AS build'
row 'our own $VAR:latest push tag'        0 x.sh 'docker push "$ECR:latest"'
mkdir -p "$T/.harness/baselines"; echo 'scripts/security-sweep.sh aquasec/trivy' > "$T/.harness/baselines/image-pins.txt"
row 'baselined entry passes (ratchet)'    0 scripts/security-sweep.sh 'docker run aquasec/trivy:latest fs .'
row 'comment is ignored'                  0 x.sh '# docker run evilcorp/scanner:latest'
echo "image-pins matrix: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
