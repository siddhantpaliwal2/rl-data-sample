#!/bin/sh
# COMMON SETUP; DO NOT MODIFY
# Compiles and runs the JUnit boundary suite for the FIU-adapter parsing,
# object-copy, request-validation and config-mapping helpers and leaves per-test
# verdicts in webservice/target/surefire-reports for the parser. Fully offline:
# the repo image warms the Maven cache (including the surefire JUnit-platform
# provider) and installs the sibling modules to the local repo at build time, so
# only the graded ``webservice`` module is (re)built here.
set -u

REPO_DIR=""
for d in /app /testbed; do
    if [ -f "$d/pom.xml" ] && [ -d "$d/webservice/src" ]; then
        REPO_DIR="$d"
        break
    fi
done
[ -n "$REPO_DIR" ] || { echo "run_script.sh: maven repo root not found" >&2; exit 2; }
cd "$REPO_DIR"

# Start each run from a clean report dir so the parser only sees this run.
rm -rf webservice/target/surefire-reports

GOLD_CLASS="FiuHelperBoundaryTest"

run_all_tests() {
    mvn -o -B -q -pl webservice -Dtest="$GOLD_CLASS" -DfailIfNoTests=false test 2>&1 || true
}

run_selected_tests() {
    # comma-separated "Class::method" ids -> Maven -Dtest filter "Class#method,..."
    filter="$(printf '%s' "$1" | sed 's/::/#/g')"
    mvn -o -B -q -pl webservice -Dtest="$filter" -DfailIfNoTests=false test 2>&1 || true
}

if [ "${1:-}" = "" ]; then
    run_all_tests
else
    run_selected_tests "$1"
fi
