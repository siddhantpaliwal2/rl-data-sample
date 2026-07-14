#!/bin/sh
# COMMON SETUP; DO NOT MODIFY
# Runs the shared-package test suite with bun and emits a JUnit XML report on
# stdout (the gold boundary file plus the four existing unit-test files that
# hold the pass_to_pass set).
set -u

REPO_DIR=""
for d in /app /testbed; do
    if [ -d "$d/packages/shared/src" ] && [ -d "$d/tests" ]; then
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
    tests/shared_boundaries.test.ts \
    packages/shared/src/time.test.ts \
    packages/shared/src/dates.test.ts \
    packages/shared/src/callbacks.test.ts \
    packages/shared/src/schemas.test.ts \
    --reporter=junit --reporter-outfile="$JUNIT_OUT" > /tmp/bun_console.log 2>&1 || true

cat "$JUNIT_OUT"
