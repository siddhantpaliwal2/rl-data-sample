# Reference plan — xrepo-loangenai2-latent

## Relationship to the sibling task

This is the SECOND latent-bug task on `loan-genai-backend`. The banked sibling
`xrepo-loangenai-latent` planted its five defects in
`Workflow/state/validation_rules.py` (`validate_loan_amount`),
`Workflow/parameter_schema.py` (`get_form_for_missing_fields`),
`Workflow/state/parameter_schema.py` (`calculate_completion_percentage`), and
`Service/otp_service.py` (`verify_otp`). This task is **disjoint**: every defect
lives in a different module — `Workflow/v1/agents/loan_offer_generator_v1.py`,
the loan-offer generation / credit-scoring math — and touches none of those four
functions. The repo image `loangenai-repo:v1` is reused (`FROM loangenai-repo:v1`).

## Construction (LATENT-BUG pattern)

The substrate is the pure financial-math cluster inside
`Workflow/v1/agents/loan_offer_generator_v1.py`: a credit-score → rate-tier map
(three parallel `get_*_loan_base_rates`), a credit-score estimator
(`estimate_credit_score`), a standard amortized-payment formula
(`calculate_monthly_payment`), a free-text money-amount normalizer
(`fallback_parameter_parsing` / nested `clean_number`), and a parse-failure
detector (`is_likely_failed_parsing`). These functions are deterministic and
side-effect-free; they use only `Decimal`/arithmetic/`str` operations.

The module's *top* imports LangChain, a LangGraph state type, and an LLM factory,
so importing it as a package would drag the agent stack in. The gold tests load
it straight from its file after registering lightweight `sys.modules` stubs for
those (unused-at-runtime) infrastructure imports; the functions under test never
call any of it, so the stubs cannot influence a correct implementation's result.

The task environment Dockerfile (`FROM loangenai-repo:v1`) applies a small
**defect patch**, then `rm -rf .git && git init … && git add -A && git commit`
so the planted state is not recoverable via git. There is no runnable local
suite (the repo's root `test_auth.py` / `test_swagger.py` need a live server +
DB); the gold suite is injected only at grade time from `config.json`'s
`test_patch`.

## Defects planted (5, single-token boundary slips)

1. `get_personal_loan_base_rates` — top rate tier `credit_score >= 750` tightened
   to `> 750`. A score of exactly 750 is quoted the 700–749 tier's (worse) rate.
   MEDIUM. (`>=`→`>`)
2. `calculate_monthly_payment` — zero-interest guard `annual_rate == 0` shifted to
   `< 0`. A 0% loan no longer takes the `principal / months` branch and instead
   divides by `(1+r)^n − 1 == 0` → `ZeroDivisionError`. MEDIUM. (`==`→`<`)
3. `is_likely_failed_parsing` — the "shorthand present but value too small"
   guard `parsed_value < 1000` loosened to `<= 1000`. A correct "1k" → 1000 parse
   is wrongly reported as failed. MEDIUM. (`<`→`<=`)
4. `fallback_parameter_parsing` — invalid-amount default guard `loan_amount <= 0`
   tightened to `< 0`. A parsed amount of exactly 0 is kept as a real $0 loan
   instead of falling back to the default. EASY. (`<=`→`<`)
5. `estimate_credit_score` — top income band `annual_income >= 100000` tightened
   to `> 100000`. An income of exactly 100000 misses the top bonus and drops to
   the 75k band. EASY. (`>=`→`>`)

Balance: 2 easy (the two locally-twinned guards, 4 & 5) + 3 medium (the
cross-function tier consistency 1, the amortization-definition guard 2, the
multiplier-semantics threshold 3). All five bite only exact-edge inputs; every
routine value sits strictly inside the ranges where the two comparison forms
agree.

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch (doubled heredoc: one copy
for `git apply -R --check`, one for `git apply -R`), restoring `>= 750`,
`== 0`, `< 1000`, `<= 0`, and `>= 100000`. Any equivalent boundary correction
also passes the gold tests.

## Verifier design

- `tests/test.sh` — verbatim SWE-Bench-Pro harness: applies `test_patch` from
  verifier-controlled config, runs `run_script.sh`, parses per-test verdicts,
  awards reward 1 only if every `fail_to_pass` and `pass_to_pass` test passed.
- `tests/run_script.sh` — REPO_DIR detection `[ -d tests ] && [ -d Workflow ]`;
  runs the single gold file.
- `tests/parser.py` — verbatim.
- `fail_to_pass` = 5 gold edge tests (one per defect), each FAILED at the planted
  state with a per-test line (no collection ERRORs).
- `pass_to_pass` = 13 tests in the same file that pass throughout: interior tier
  / above-tier / second-tier scores, the untouched auto & home top-tier twins, a
  positive-rate payment, a shorthand-too-small parse, a plain number, the
  untouched million-abbreviation twin, an interior amount, the untouched
  zero-income twin, and above-band / second-band / mid-range income scores.

## Ladder (verified in-image)

- git history len 1, `git diff` empty, status clean, reflog len 1, planted lines
  present.
- Gold suite green at base (18/18) — no visible failure points at any defect.
- NULL: reward 0; all 5 fail_to_pass report FAILED (per-test lines, no ERRORs);
  13/18 required passed.
- ORACLE: `solve.sh` → reward 1; 18/18 required passed.
- PARTIAL: reverse-apply the two easy hunks only (2 of 5 fixed) → reward 0
  (15/18).

## Fairness

- All five defected functions are live code reachable from the offer-generation
  flow (`loan_offer_generator_v1` → `generate_loan_offers` /
  `parse_financial_parameters` → these helpers).
- The gold tests load the module by file path with typed `sys.modules` stubs for
  the LangChain / LangGraph-state / LLM-factory imports the pure math never
  calls — no MagicMock, no oracle-implementation coupling. Each assertion is on
  observable output (a returned rate dict, a payment number, a boolean flag, a
  parsed amount, an integer score), so any correct boundary fix passes equally.
- The instruction names no file, function, threshold value, or defect count; it
  is a symptom report of edge-clustered behaviors. Deterministic, offline,
  no secrets.
