#!/bin/sh
# Verifier entrypoint — SWE-Bench Pro style contract.
# The image ships a single "import codebase" commit with the planted defects and
# with the failing test files removed. At grading time we restore any tracked
# test files the agent may have touched, then introduce the verifier-controlled
# gold suite (config.json test_patch) as fresh files. The candidate's non-test
# source fixes are left untouched, so only real behavior is graded.
set -u

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REWARD_DIR="${REWARD_DIR:-/logs/verifier}"
mkdir -p "$REWARD_DIR"

# A reward file must always exist, even if this harness crashes.
REWARD=0
echo "$REWARD" > "$REWARD_DIR/reward.txt"
cleanup_and_reward() {
    echo "$REWARD" > "$REWARD_DIR/reward.txt"
    echo "reward: $REWARD"
}
trap cleanup_and_reward EXIT

REPO_ROOT=""
for d in /app /app/loangenus /testbed; do
    if [ -d "$d/.git" ]; then
        REPO_ROOT="$d"
        break
    fi
done
[ -n "$REPO_ROOT" ] || { echo "test.sh: repo root with .git not found" >&2; exit 1; }
cd "$REPO_ROOT"

# Anti-tamper: restore any tracked test file the agent modified back to its
# committed state (source fixes outside tests/ are untouched).
git checkout -- loangen-agent/tests/ 2>/dev/null || true

# Ensure the gold files are absent so the new-file test_patch applies cleanly,
# even if the agent created files at those paths.
rm -f loangen-agent/tests/test_credit_pdf_pipeline.py \
      loangen-agent/tests/test_cre_field_extraction.py \
      loangen-agent/tests/test_document_extraction_pipeline.py

# Apply the gold test patch from verifier-controlled config (never from the
# candidate repo).
python3 - "$TESTS_DIR/config.json" <<'PYEOF' > /tmp/gold_tests.patch
import json, sys
print(json.load(open(sys.argv[1]))["test_patch"], end="")
PYEOF
git apply /tmp/gold_tests.patch || { echo "test.sh: gold test patch failed to apply" >&2; exit 1; }

sh "$TESTS_DIR/run_script.sh" "" > /tmp/runner_stdout.txt 2>&1
cat /tmp/runner_stdout.txt
python3 "$TESTS_DIR/parser.py" < /tmp/runner_stdout.txt > "$REWARD_DIR/output.json"
cp /tmp/runner_stdout.txt "$REWARD_DIR/stdout.txt" 2>/dev/null || true

# Every fail_to_pass AND pass_to_pass test must have passed.
if python3 - "$TESTS_DIR/config.json" "$REWARD_DIR/output.json" <<'PYEOF'
import json, sys
cfg = json.load(open(sys.argv[1]))
out = json.load(open(sys.argv[2]))
verdicts = {t["name"]: t["status"] for t in out["tests"]}
required = cfg["fail_to_pass"] + cfg["pass_to_pass"]
passed = [t for t in required if verdicts.get(t) == "passed"]
print(f"required passed: {len(passed)}/{len(required)}")
missing = [t for t in required if verdicts.get(t) != "passed"]
for t in missing:
    print(f"  NOT PASSED ({verdicts.get(t, 'not-run')}): {t}")
sys.exit(0 if not missing else 1)
PYEOF
then
    REWARD=1
fi
exit 0
