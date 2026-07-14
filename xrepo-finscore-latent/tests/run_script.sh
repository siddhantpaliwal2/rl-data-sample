#!/bin/sh
# COMMON SETUP; DO NOT MODIFY
# Compiles and runs the JUnit boundary suite for the FinScore analysis math and
# leaves per-test verdicts in target/surefire-reports for the parser. Fully
# offline: the repo image warms the Maven cache (including the surefire
# JUnit-platform provider) at build time.
set -u

REPO_DIR=""
for d in /app /testbed; do
    if [ -f "$d/pom.xml" ] && [ -d "$d/src" ]; then
        REPO_DIR="$d"
        break
    fi
done
[ -n "$REPO_DIR" ] || { echo "run_script.sh: maven repo root not found" >&2; exit 2; }
cd "$REPO_DIR"

# Start each run from a clean report dir so the parser only sees this run.
rm -rf target/surefire-reports

GOLD_CLASS="FinscoreBoundaryTest"

run_all_tests() {
    mvn -o -B -q -Dtest="$GOLD_CLASS" -DfailIfNoTests=false test 2>&1 || true
}

run_selected_tests() {
    # comma-separated "Class::method" ids -> Maven -Dtest filter "Class#method,..."
    filter="$(printf '%s' "$1" | sed 's/::/#/g')"
    mvn -o -B -q -Dtest="$filter" -DfailIfNoTests=false test 2>&1 || true
}

if [ "${1:-}" = "" ]; then
    run_all_tests
else
    run_selected_tests "$1"
fi
