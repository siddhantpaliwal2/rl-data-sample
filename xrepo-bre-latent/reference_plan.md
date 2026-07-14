# Reference plan — xrepo-bre-latent (boundary errors in the BRE eligibility engine)

## Construction (LATENT-BUG pattern)

Base is the clean HEAD of `business-rule-engine` (`5afc479`). There is no
prebuilt registry base image for this repo, so the task image is built in two
stages:

1. `bre-repo:v1` — a plain `python:3.11-slim` with `git` installed, the whole
   repo `COPY`-ed to `/app` (including its `.git`), and `pip install pytest
   pymongo python-dateutil`. Only these three deps are installed; the full
   `requirements.txt` (Flask, google-cloud-aiplatform, openai, ...) is
   deliberately skipped because the targeted modules never touch it. `pymongo`
   is present only so the config package imports — it connects lazily inside
   methods the boundary paths never call, so importing is offline.
2. `environment/Dockerfile` — `FROM bre-repo:v1`, applies a small **defect
   patch** that plants five subtle boundary errors, then collapses git history
   (`rm -rf .git && git init && commit "import codebase"`) so the planted state
   is not recoverable via `git diff`/`log`/`reflog`.

The agent starts from base+defects. **No local test fails** and the repo ships
with essentially no test suite, so "green locally" is vacuous — the grader's
edge tests are the only bar.

The gold tests (`tests/test_bre_boundaries.py`) are injected only at grade time
from `config.json`'s `test_patch`. They feed exactly the edge inputs the
defects corrupt and assert the correct outputs.

## Defects planted (file : boundary : the edge no ordinary input feeds)

1. `bre_engine/engine/operator_handler.py` — the `between` operator lambda
   `e[0] <= a <= e[1]` weakened to `e[0] < a <= e[1]`. A value exactly equal to
   the lower bound is wrongly reported outside the range. Correct behavior is
   pinned by the parallel `between` implementation in
   `custom_functions/base._apply_operator` (inclusive on both ends) and by the
   inclusive semantics the upper bound still uses.

2. `bre_engine/engine/field_extractor.py` — dot-notation array indexing guard
   `0 <= index < len(value)` shifted to `0 < index < len(value)`. Index 0 (the
   first list element) becomes unreachable and returns the default. Correct
   behavior is pinned by the inline example `'items.0.name'`, which documents
   index-0 access as a supported feature.

3. `bre_engine/engine/custom_functions/zype_functions.py`
   `ActiveAccountsCheckFunction` — the in-limit test `0 < amount <= max_limit`
   changed to `0 < amount < max_limit`. A sanctioned amount exactly on the
   ceiling is dropped. Correct behavior is pinned by the inline comment "within
   limit (up to max_limit)" and the docstring "up to 2 lakhs" — "up to" is
   inclusive.

4. `bre_engine/engine/custom_functions/zype_functions.py`
   `AmountOverdueThresholdCheckFunction` — the high-overdue test
   `overdue_amount > threshold` changed to `>= threshold`. An overdue balance
   exactly on the cutoff is wrongly flagged as a serious overdue. Correct
   behavior is pinned by the docstring: "Exclude overdue up to ₹3000 ... checks
   if any account has overdue > threshold" — the cutoff value is excluded.

5. `intelligent_recommendation_engine/services/rule_evaluation_service.py`
   `_evaluate_credit_score` — the pass test `credit_score >= threshold` changed
   to `credit_score > threshold`. A score exactly at the threshold is downgraded
   from PASS to a WARNING. Correct behavior is pinned by the branch's own
   message, "meets minimum requirement of {threshold}" — equality meets the
   minimum.

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch, restoring the original
`<=` / `0 <=` / `<= max_limit` / `> threshold` / `>= threshold` boundary logic.
That is the minimal correct fix; any equivalent boundary correction also passes
the gold tests.

## Verifier design

- `tests/test.sh` (verbatim from the canonical latent task) applies `test_patch`
  from verifier-controlled config, runs `run_script.sh`, parses per-test
  verdicts, and awards reward 1 only if every `fail_to_pass` and `pass_to_pass`
  test passed.
- `fail_to_pass` = 5 gold boundary tests (one per defect; fail at base+defects,
  pass once the boundaries are corrected).
- `pass_to_pass` = 12 adjacent-behavior tests in the same gold file that pass
  throughout (values off the edge), pinning the correct behavior an over-eager
  fix might disturb (e.g. the `between` upper bound must stay inclusive).
- `run_script.sh` runs the single gold test file (the repo has no pre-existing
  suite to run).

## Fairness

- All five defected functions are live: they are reachable from the engine's
  rule execution / recommendation evaluation paths.
- Every correct side is uniquely derivable from in-repo evidence (a parallel
  implementation, an inline example, a docstring, or a branch message) — no
  convention-only band-edge picks and no tie-break guesses.
- The gold tests are pure-input `unittest` assertions with ZERO mocks; the IRE
  module is loaded straight from its file to avoid pulling cloud/DB SDKs, and no
  test asserts an oracle-specific implementation detail.
- Deterministic, offline, no secrets required.
