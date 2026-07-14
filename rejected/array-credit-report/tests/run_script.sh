#!/bin/sh
# COMMON SETUP; DO NOT MODIFY
# Runs the backend test suite and emits verbose per-test verdict lines.
set -u

REPO_DIR=""
for d in /app/loangen-agent /app /testbed; do
    if [ -d "$d/tests" ] && [ -d "$d/agent" ]; then
        REPO_DIR="$d"
        break
    fi
done
[ -n "$REPO_DIR" ] || { echo "run_script.sh: repo root not found" >&2; exit 2; }
cd "$REPO_DIR"

run_all_tests() {
    python3 -m pytest -v --tb=short --no-header \
        tests/test_array_credit_verification.py \
        tests/test_smb_invite_flow.py \
        tests/test_required_docs.py || true
}

run_selected_tests() {
    # comma-separated pytest node ids
    IFS=','
    set -- $1
    unset IFS
    python3 -m pytest -v --tb=short --no-header "$@" || true
}

if [ "${1:-}" = "" ]; then
    run_all_tests
else
    run_selected_tests "$1"
fi
