#!/bin/sh
# Verifier entrypoint — SWE-Bench Pro style contract.
# The gold JUnit class enters the tree only here, at grading time, from
# config.json's test_patch; it is never visible to the agent during its run and
# cannot be substituted or weakened by anything the agent did.
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
for d in /app /testbed; do
    if [ -d "$d/.git" ] && [ -f "$d/pom.xml" ]; then
        REPO_ROOT="$d"
        break
    fi
done
[ -n "$REPO_ROOT" ] || { echo "test.sh: repo root with .git not found" >&2; exit 1; }

# Apply the gold test patch from verifier-controlled config (never from the
# candidate repo). Reverse any half-applied state first for idempotency.
python3 - "$TESTS_DIR/config.json" <<'PYEOF' > /tmp/gold_tests.patch
import json, sys
print(json.load(open(sys.argv[1]))["test_patch"], end="")
PYEOF
cd "$REPO_ROOT"
git apply --reverse --check /tmp/gold_tests.patch 2>/dev/null && git apply --reverse /tmp/gold_tests.patch
git apply /tmp/gold_tests.patch || { echo "test.sh: gold test patch failed to apply" >&2; exit 1; }

sh "$TESTS_DIR/run_script.sh" "" > /tmp/runner_stdout.txt 2>&1
cat /tmp/runner_stdout.txt
python3 "$TESTS_DIR/parser.py" "$REPO_ROOT/webservice/target/surefire-reports" > "$REWARD_DIR/output.json"
cp /tmp/runner_stdout.txt "$REWARD_DIR/stdout.txt" 2>/dev/null || true
cat "$REWARD_DIR/output.json"
echo

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
