#!/bin/sh
# COMMON SETUP; DO NOT MODIFY
# Runs the backend test suite and emits verbose per-test verdict lines.
set -u

REPO_DIR=""
for d in /app /app/loan-genai-backend /testbed; do
    if [ -d "$d/tests" ] && [ -d "$d/Workflow" ]; then
        REPO_DIR="$d"
        break
    fi
done
[ -n "$REPO_DIR" ] || { echo "run_script.sh: repo root not found" >&2; exit 2; }
cd "$REPO_DIR"

run_all_tests() {
    # Only the injected gold boundary suite is run. The repo's root-level
    # test_auth.py / test_swagger.py require a live server + DB and are excluded.
    python3 -m pytest -v --tb=short --no-header -p no:cacheprovider \
        tests/test_loangenai2_boundaries.py || true
}

run_selected_tests() {
    # comma-separated pytest node ids
    IFS=','
    set -- $1
    unset IFS
    python3 -m pytest -v --tb=short --no-header -p no:cacheprovider "$@" || true
}

if [ "${1:-}" = "" ]; then
    run_all_tests
else
    run_selected_tests "$1"
fi
