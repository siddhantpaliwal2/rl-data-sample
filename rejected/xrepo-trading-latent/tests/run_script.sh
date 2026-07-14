#!/bin/sh
# COMMON SETUP; DO NOT MODIFY
# Runs the formatters boundary suite with bun and emits per-test verdicts as
# JUnit XML (bun's default console reporter prints only failures, so the XML
# reporter is what carries the passing verdicts the grader needs).
set -u

REPO_DIR=""
for d in /app /testbed; do
    if [ -f "$d/package.json" ] && [ -d "$d/lib" ]; then
        REPO_DIR="$d"
        break
    fi
done
[ -n "$REPO_DIR" ] || { echo "run_script.sh: repo root not found" >&2; exit 2; }
cd "$REPO_DIR"

JUNIT="/tmp/formatters_junit.xml"
rm -f "$JUNIT"

run_all_tests() {
    bun test tests/formatters_boundaries.test.ts \
        --reporter=junit --reporter-outfile="$JUNIT" 2>&1 || true
}

run_selected_tests() {
    # comma-separated bun test node ids / patterns (unused by the default flow;
    # the whole boundary file is small, so we always run it in full).
    bun test tests/formatters_boundaries.test.ts \
        --reporter=junit --reporter-outfile="$JUNIT" 2>&1 || true
}

if [ "${1:-}" = "" ]; then
    run_all_tests
else
    run_selected_tests "$1"
fi

# Surface the machine-readable per-test verdicts for the parser. The console
# output above stays in the stream for human debugging.
echo "----- JUNIT-XML-BEGIN -----"
cat "$JUNIT" 2>/dev/null || echo "(no junit xml produced)"
echo "----- JUNIT-XML-END -----"
