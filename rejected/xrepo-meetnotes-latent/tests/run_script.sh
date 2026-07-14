#!/bin/sh
# COMMON SETUP; DO NOT MODIFY
# Runs the gold boundary suite with bun and emits a JUnit XML report on stdout.
# The gold file is the only test file: the pure library utilities have no
# third-party runtime deps, so the suite runs fully offline with `bun:test`.
set -u

REPO_DIR=""
for d in /app /testbed; do
    if [ -d "$d/frontend/src/lib" ] && [ -d "$d/backend/src/services" ]; then
        REPO_DIR="$d"
        break
    fi
done
[ -n "$REPO_DIR" ] || { echo "run_script.sh: repo root not found" >&2; exit 2; }
cd "$REPO_DIR"

JUNIT_OUT="${JUNIT_OUT:-/tmp/bun_junit.xml}"
rm -f "$JUNIT_OUT"

# bun test exits non-zero when any test fails; the JUnit file is still written,
# and per-test verdicts are what the grader reads, so swallow the exit code.
bun test \
    tests/lib_boundaries.test.ts \
    --reporter=junit --reporter-outfile="$JUNIT_OUT" > /tmp/bun_console.log 2>&1 || true

cat "$JUNIT_OUT"
