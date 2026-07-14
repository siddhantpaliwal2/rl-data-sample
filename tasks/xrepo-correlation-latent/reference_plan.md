# Reference plan — xrepo-correlation-latent

## Construction (LATENT-BUG pattern)

Base is the current working tree of the `correlation-core` repo. The environment
Dockerfile builds from a clean repo image (`correlation-repo:v1`), plants a small
**defect patch** of five single-token boundary slips into two pure, stdlib-only
modules, then collapses git history (`rm -rf .git && git init`) so the planted
state is not recoverable via `git diff`/`git log`/reflog. The agent starts from
base+defects. There is **no failing test** pointing at any defect: the repo ships
no tests, so the agent-visible suite is vacuously green with the defects present.

The graded tests (`tests/test_correlation_boundaries.py`) are injected only at
grade time from `config.json`'s `test_patch`; they feed exactly the edge inputs
the defects corrupt and assert the correct outputs. "Green locally" is not the
bar — the grader's edge tests are.

The two target modules import only the standard library (`datetime`, `json`,
`uuid`), so the repo image installs no third-party runtime deps beyond pytest;
the heavy similarity models (torch / sentence-transformers / polyfuzz) are never
imported by the graded code.

## Defects planted (file : symptom : trigger the visible/ordinary inputs never feed)

1. `Get_Transactions_Custom_Logic.py` `format_date` — the ordinal-suffix guard
   `4 <= day <= 20 or 24 <= day <= 30` widened to `... or 23 <= day <= 30`. Day
   23 is swept into the "th" run and rendered "23th" instead of "23rd". Ordinary
   days (1st/2nd/3rd, 4..20, 21st/22nd, 24..30) are unchanged. The else branch's
   own table `["st","nd","rd"][day % 10 - 1]` pins 23 → "rd".

2. `Correlation_Decisioning.py` `calculate_score` (name tier) — partial-match
   guard `len(common_words) > 0` tightened to `> 1`. A name pair sharing exactly
   one token (and not a full match) drops from the partial score to the
   no-match score. The comment "Partial match (some words match)" pins ≥1 shared
   token as a partial match.

3. `Correlation_Decisioning.py` `calculate_score` (name tier) — full-match guard
   `== len(source) or == len(target)` changed to `... and ...`. A name whose
   tokens are a strict subset of the other (unequal sizes, full containment)
   drops from full-match to partial. The comment "Full match (all words match)"
   plus the two separate length checks pin the intended `or` (either side fully
   covered).

4. `Correlation_Decisioning.py` `calculate_score` (semantic scaling) — validity
   guard `0 <= semantic_similarity <= 1` made exclusive at the top
   (`... < 1`). A perfect semantic similarity of exactly 1.0 leaves
   `semantic_score` unassigned and the score computation raises. Similarity is a
   cosine-based value on [0, 1]; the `* 100` scaling confirms 1.0 → 100.

5. `Correlation_Decisioning.py` `is_valid_correlation` — accept comparison
   `score >= threshold` tightened to `score > threshold`. A score landing
   exactly on the threshold (default 70) is wrongly rejected. A threshold is the
   minimum-to-qualify, so equality must accept.

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch, restoring the inclusive
`24 <= day`, `> 0`, `or`, `<= 1`, and `>= threshold` boundary logic. Any
equivalent boundary correction (the score values 100/70/30, the [0,1] scaling,
and the default threshold are all pre-existing and untouched) also passes.

## Verifier design

- `tests/test.sh` (verbatim from the canonical) applies `test_patch` from
  verifier-controlled config, runs `run_script.sh`, parses per-test verdicts,
  and awards reward 1 only if every `fail_to_pass` and `pass_to_pass` test passed.
- `fail_to_pass` = 5 gold boundary tests (one per defect; fail at base+defects,
  pass once the boundaries are corrected).
- `pass_to_pass` = 11 tests that pass throughout — the ordinal cases away from
  the seam, identical / two-token / disjoint name pairs, mid-range similarity
  scaling, and clearly above/below-threshold scores — the "green locally" lull.
- `run_script.sh` runs the single gold file (the repo has no other tests).

## Fairness

- Both defected functions are the public API of their classes and the core of
  the correlation decisioning/formatting path — live code, not dead paths.
- The instruction names the two module files and the boundary/edge symptom class
  but not the functions, the boundary directions, the trigger values, or the
  count — the agent must read and reason about the math to locate and correct
  each slip.
- Every gold test uses pure literal inputs and asserts pre-existing output
  values (score constants, the ordinal table, the scaling factor); no test
  encodes an oracle-specific implementation choice, and no mocks are used.
- Deterministic, offline, no secrets.
