# Reference plan — xrepo-loangenai-latent

## Construction (LATENT-BUG pattern, new repo)

The substrate is `loan-genai-backend` (a Flask + LangGraph loan-intake service,
98 py files). The repo image is built from a scratch Dockerfile
(`FROM python:3.11-slim` + git + `COPY . /app` + `pip install pytest structlog
"python-json-logger<3" flask colorama redis`) — only the deps the five target
modules actually import. The repo's own `.dockerignore` excludes `tests/`,
`.git`, `*.md`, and the root `test_*.py` server tests, so the agent image is a
clean source tree with no runnable local suite (the full app tests need the
whole langchain/DB stack and a live server). The task environment Dockerfile
(`FROM loangenai-repo:v1`) applies a small **defect patch**, then
`rm -rf .git && git init … && git add -A && git commit` so the planted state is
not recoverable via git.

The agent starts from base+defects. **There is no failing local test pointing at
any defect** — there is effectively no local suite at all. The gold tests
(`tests/test_loangenai_boundaries.py`) are injected only at grade time from
`config.json`'s `test_patch`; they feed the exact edge inputs the defects
corrupt and assert the correct outputs.

## Defects planted (5, single-token boundary slips)

1. `Workflow/state/validation_rules.py` `validate_loan_amount` — minimum floor
   `amount < min` weakened to `amount <= min`. A request for exactly the
   advertised minimum is rejected. (personal 1000 / auto 5000 / home 50000)
2. same function — maximum ceiling `amount > max` weakened to `amount >= max`.
   A request for exactly the advertised maximum is rejected. (personal 100000 /
   auto 200000 / home 1000000)
3. `Workflow/parameter_schema.py` `get_form_for_missing_fields` — viability
   guard `overlap >= 2` tightened to `overlap > 2`. A form covering exactly two
   of the missing fields is no longer offered, contradicting the "# 2. At least
   2 fields overlap" comment directly above it.
4. `Workflow/state/parameter_schema.py` `calculate_completion_percentage` — the
   collected-field test `category_data[field] is not None` weakened to a
   truthiness test `category_data[field]`. A field whose value is a legitimate
   0 / 0.0 is dropped from the tally, disagreeing with the sibling
   `get_missing_parameters` (which uses `is None`).
5. `Service/otp_service.py` `verify_otp` — lockout guard
   `attempts >= max_attempts` weakened to `attempts > max_attempts`, letting one
   guess through past the cap before locking.

Balance: 2 easy (the two message-anchored loan-amount edges) + 3 medium (the
comment-anchored overlap guard, the sibling-consistency completion count, the
attempt-flow lockout). Spans 4 source files.

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch (doubled heredoc: one copy
for `git apply -R --check`, one for `git apply -R`), restoring `<`, `>`,
`overlap >= 2`, `is not None`, and `attempts >= max_attempts`. Any equivalent
boundary correction also passes the gold tests.

## Verifier design

- `tests/test.sh` (verbatim from cre-scoring-latent-4) applies `test_patch` from
  verifier-controlled config, runs `run_script.sh`, parses per-test verdicts,
  and awards reward 1 only if every `fail_to_pass` and `pass_to_pass` test
  passed.
- `tests/run_script.sh` — REPO_DIR detection changed to `[ -d tests ] && [ -d
  Workflow ]`; test list is the single gold file (the root `test_auth.py` /
  `test_swagger.py` need a server and are excluded).
- `tests/parser.py` — verbatim.
- `fail_to_pass` = 9 gold edge tests (fail at base+defects, one to two per
  defect, covering permutations across products / forms / zero-valued fields).
- `pass_to_pass` = 13 tests in the same gold file that pass throughout (interior
  amounts, full/no overlap, single-field guard, real-field and None-field
  counts, below-cap and success OTP paths) — the "green locally" lull, made
  concrete since the repo ships no runnable suite.

## Ladder (verified in-image)

- git history len 1, `git diff` empty, status clean, reflog len 1.
- NULL: reward 0; all 9 fail_to_pass report FAILED (per-test lines, no ERRORs).
- ORACLE: `solve.sh` -> reward 1; 22/22 required passed.
- PARTIAL: reverse-apply the loan-amount hunk only (2 of 5 fixed) -> reward 0
  (17/22).

## Fairness

- All five defected functions are live code (see SCAFFOLD_REPORT fairness_audit).
- The gold tests load the three pure modules by file path (bypassing the
  langchain-wiring `Workflow/__init__.py`) and use a typed `_FakeCache` with
  explicit values for the OTP test — no MagicMock, no oracle-implementation
  coupling.
- The instruction names no file, function, threshold value, or defect count; it
  is a symptom report of four edge-clustered behaviors. Deterministic, offline,
  no secrets.
