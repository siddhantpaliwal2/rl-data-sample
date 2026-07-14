# Reference plan — cre-scoring-latent-bugs

## Construction (LATENT-BUG pattern)

Base image is the clean HEAD of loangenus (`04b8abc`). The environment Dockerfile
resets to that commit and then applies a small **defect patch** that plants four
subtle boundary errors in the CRE qualification scoring math. The agent starts
from base+defects. There is **no failing local test** pointing at any defect:
the full existing qualification suite (26 tests across
`test_cre_qualification`, `test_oak_hill_qualification`,
`test_bridge_broadway_qualification`, `test_qualification_recommendation`,
`test_lender_product_match`, `test_required_docs`) stays green with the defects
present, because every visible test feeds values that sit safely inside the
ranges and never lands on the exact edge that bites.

The gold tests (`tests/test_cre_scoring_boundaries.py`) are injected only at
grade time from `config.json`'s `test_patch`. They feed exactly the edge inputs
the defects corrupt and assert the correct outputs. "Green locally" is not the
bar — the grader's edge tests are.

## Defects planted (file : symptom : trigger the visible tests never feed)

1. `facts.py` `resolve_appraisal_value` — floor comparison `v >= 100_000`
   weakened to `v > 100_000`. An appraisal at exactly 100,000 is discarded
   (returns None). Visible tests use appraisals of 800k / 1.7M / 1.85M / 2.0M —
   never exactly 100k.

2. `facts.py` `resolve_document_fico` — bureau-median index
   `scores[len(scores) // 2]` shifted to `scores[(len(scores) - 1) // 2]`. On an
   **even** number of bureau scores this returns the lower-middle instead of the
   framework's upper-middle score; identical on odd counts. Visible tests only
   ever use a single bureau score (odd), so the change is invisible to them.

3. `facts.py` `resolve_tenant_concentration` — fraction/percent boundary
   `v / 100.0 if v > 1 else v` changed to `>= 1`. A value of exactly `1.0`
   (100% concentration expressed as a fraction) is wrongly divided by 100 to
   0.01. No visible test feeds `tenant_concentration` at all.

4. `scoring.py` `weighted_score` — per-component clamp dropped
   (`weight * clamp(val)` → `weight * val`). Component scores outside 0-100 leak
   into the weighted blend instead of being capped. The one visible test feeds
   an in-range value (80.0), so the missing clamp is invisible.

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch, restoring the original
`>= 100_000`, `len // 2`, `> 1`, and `clamp(val)` boundary logic. That is the
minimal correct fix; any equivalent boundary correction also passes the gold
tests.

## Verifier design

- `tests/test.sh` (verbatim from the canonical) applies `test_patch` from
  verifier-controlled config, runs `run_script.sh`, parses per-test verdicts,
  and awards reward 1 only if every `fail_to_pass` and `pass_to_pass` test
  passed.
- `fail_to_pass` = the 7 gold boundary tests (fail at base+defects, pass once
  the boundaries are corrected).
- `pass_to_pass` = 12 existing qualification tests that pass throughout — the
  "green locally" lull.
- `run_script.sh` runs the gold file plus the six existing qualification files
  that hold the pass_to_pass set.

## Fairness

- All four defected functions are reachable from `run_qualification_engine`
  (used in `engine.py` / `cross_checks.py`), so they are live code, not dead
  paths.
- The instruction names the two modules and the four symptoms but not the exact
  lines, the boundary direction, the trigger values, or the count — the agent
  must read and reason about the boundary math to locate and correct each slip.
- Deterministic, offline, no secrets beyond the baked `JWT_SECRET_KEY`.
