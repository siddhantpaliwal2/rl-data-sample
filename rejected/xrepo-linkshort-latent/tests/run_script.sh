#!/bin/sh
# COMMON SETUP; DO NOT MODIFY
# Runs the link-shortener boundary suite and emits verbose per-test verdict
# lines for the parser. The suite is a pure/offline pytest file; the only
# runtime input it needs is LINK_SHORTENER_DATABASE_URL (baked into the image),
# re-exported here defensively so importing link_shortener.main succeeds.
set -u

REPO_DIR=""
for d in /app /testbed; do
    if [ -d "$d/tests" ] && [ -d "$d/link_shortener" ]; then
        REPO_DIR="$d"
        break
    fi
done
[ -n "$REPO_DIR" ] || { echo "run_script.sh: repo root not found" >&2; exit 2; }
cd "$REPO_DIR"

export LINK_SHORTENER_DATABASE_URL="${LINK_SHORTENER_DATABASE_URL:-sqlite://}"

run_all_tests() {
    python3 -m pytest -v --tb=short --no-header -p no:cacheprovider \
        tests/test_linkshort_boundaries.py || true
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
