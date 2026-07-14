# Reference plan — latent-doc-extractors

## Construction (LATENT-BUG pattern)

Base image is the clean HEAD of loangenus (`04b8abc`). The environment Dockerfile
resets to that commit and then applies a small **defect patch** that plants five
subtle boundary errors in the CRE document field-extraction math in
`loangen-agent/agent/documents/extractors/cre_fields.py`. The agent starts from
base+defects. There is **no failing local test** pointing at any defect: the full
existing suite stays exactly as it is at clean HEAD — 7 failed / 166 passed / 24
skipped, and the 7 failures are the pre-existing rot set unrelated to extraction
(`test_inbound_calls`, `test_document_ingestion_readiness`,
`test_ingestion_stale_recovery`, `test_document_report`). Every visible test that
touches these extractors feeds values comfortably inside the ranges, with
odd-sized inputs and roomy tables, so it never lands on the exact edge that bites.

The gold tests (`tests/test_extractor_boundaries.py`) are injected only at grade
time from `config.json`'s `test_patch`. They feed exactly the edge inputs the
defects corrupt and assert the correct outputs. "Green locally" is not the bar —
the grader's edge tests are.

## Defects planted (file : symptom : trigger the visible tests never feed)

All five are single-token operator/literal/index slips in `cre_fields.py`.

1. `_sanitize_value_amount` — floor comparison `f >= min_amount` weakened to
   `f > min_amount`. An appraisal amount at exactly the $100,000 floor is
   discarded (returns None) instead of kept. Visible appraisal tests feed
   1.25M / 1.7M / 1.85M / 2.05M / 2.1M — never exactly 100k.

2. `_sum_rent_amounts` — minimum-row guard `count >= 2` tightened to
   `count >= 3`. A rent roll with exactly two rent lines (the smallest set that
   still reads as a roll) returns None instead of the summed rent. Visible rent
   tests supply a labeled gross-rent figure, so this fallback path is never taken.

3. `extract_hud_fields` — the loan-plausibility floor `val < _MIN_HUD_LOAN_AMOUNT`
   loosened to `val <= _MIN_HUD_LOAN_AMOUNT`. A settlement loan amount of exactly
   $10,000 is dropped instead of kept. The visible HUD test feeds 800k.

4. `extract_pfs_from_text._scan_after_label` — the sub-floor skip guard
   `val < min_amount` loosened to `val <= min_amount`. A personal-financial-
   statement total (e.g. total assets) landing exactly on the scan's
   `min_amount` floor is skipped as noise instead of captured. No visible test
   feeds a PFS total exactly on the floor: the in-image consumer feeds a
   "Total Assets" line that does not match the "22. Total of All Assets" label,
   and the sample-file test (skipped in-image) uses multi-million-dollar totals.

5. `extract_credit_report_fields` (FICO band) — the named-bureau validity band
   `300 <= score <= 850` narrowed to `300 <= score < 850`. A bureau score of
   exactly 850 (band maximum) is dropped instead of kept; identical elsewhere.
   No visible test feeds an 850 bureau score through a named-bureau pattern.
   NOTE: the sibling fallback band a few lines below still reads `<= 850`, so the
   change leaves a faint (fair) inconsistency but no test signposts it.

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch, restoring `>= min_amount`,
`count >= 2`, `< _MIN_HUD_LOAN_AMOUNT`, `val < min_amount`, and `<= 850`. That is
the minimal correct fix; any equivalent boundary correction also passes the gold
tests.

## Verifier design

- `tests/test.sh` (verbatim from the canonical latent task) applies `test_patch`
  from verifier-controlled config, runs `run_script.sh`, parses per-test
  verdicts, and awards reward 1 only if every `fail_to_pass` and `pass_to_pass`
  test passed.
- `fail_to_pass` = the 5 gold boundary tests (one per defect; fail at
  base+defects, pass once the boundaries are corrected).
- `pass_to_pass` = 10 adjacent-behavior pins in the same gold file (just above /
  below each edge, correct with or without the defect) + 4 existing
  `test_cre_field_extraction.py` tests — the "green locally" lull.
- `run_script.sh` runs the gold file plus `test_cre_field_extraction.py`.

## Fairness

- All five defected functions are live: `extract_appraisal_fields`,
  `extract_rent_roll_fields`, `extract_hud_fields`, `extract_pfs_from_text` and
  `extract_credit_report_fields` are the public extractors dispatched from
  `agent/documents/extractors/generic.py::extract_structured_fields`; the helpers
  `_sanitize_value_amount`, `_sum_rent_amounts` and the nested `_scan_after_label`
  feed them directly.
- Every defect passes a DERIVABILITY audit: a strong engineer reading only the
  visible code, the parameter/constant names and domain conventions can
  determine the uniquely-correct side of each boundary (inclusive $100k floor;
  FICO max 850; a minimum meaningful sum needs two addends; a `min_amount` /
  `_MIN_HUD_LOAN_AMOUNT` floor is inclusive). None is a convention-pick
  (no upper-vs-lower median, no clamp-or-not, no unstated band edge). Target mix
  achieved: 2 easy-derivable (A, E) + 3 medium-derivable requiring the agent to
  trace the parsing/fallback logic (B, C, F).
- The instruction names the directory and the one file, and describes the edge
  *shapes* (on-a-threshold, top-of-range, minimum-rows) but not the function
  names, the boundary direction, the trigger values, or the count — the agent
  must read and reason about the boundary math to locate and correct each slip.
- Gold tests are pure-input unittest: raw text strings fed to the `extract_*`
  functions, zero mocks, so no test encodes an implementation choice.
- Deterministic, offline, no secrets beyond the baked `JWT_SECRET_KEY`.
