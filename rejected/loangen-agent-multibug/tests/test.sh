#!/bin/sh
# Verifier entrypoint — SWE-Bench Pro style contract.
# The gold suite already exists in the repo at base_commit. Before grading we
# restore every test file to its base state (undoing any edit the agent made
# under tests/), then apply the verifier-controlled test_patch. The candidate's
# fixes to non-test source are left untouched, so only real behavior is graded.
set -u

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REWARD_DIR="${REWARD_DIR:-/logs/verifier}"
mkdir -p "$REWARD_DIR"

BASE_COMMIT=04b8abc5515c22bdb7a2da32bf2719c8ac702174

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

# Restore the gold test suite to its pristine base state — this discards any
# tampering the agent may have done to tests, but keeps the agent's source fixes.
git checkout "$BASE_COMMIT" -- loangen-agent/tests/ \
    || { echo "test.sh: could not restore base test suite" >&2; exit 1; }

# Apply the verifier-controlled test_patch (never from the candidate repo).
# Reverse any half-applied state first for idempotency.
python3 - "$TESTS_DIR/config.json" <<'PYEOF' > /tmp/gold_tests.patch
import json, sys
print(json.load(open(sys.argv[1]))["test_patch"], end="")
PYEOF
git apply --reverse --check /tmp/gold_tests.patch 2>/dev/null && git apply --reverse /tmp/gold_tests.patch
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
