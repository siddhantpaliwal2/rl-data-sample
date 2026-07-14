# Reference plan — latent-market-structure

## Construction (LATENT-BUG pattern)

Base image is the clean HEAD of loangenus (`04b8abc`). The environment Dockerfile
resets to that commit and then applies a small **defect patch** that plants five
subtle boundary / empty-case errors in the CRE market, deal-structure and
lender-match math. The agent starts from base+defects. There is **no failing
local test** pointing at any defect: the full existing qualification suite stays
green with the defects present, because every visible test feeds values that sit
safely inside the ranges and never lands on the exact edge (or the empty / zero
degenerate case) that bites.

The gold tests (`tests/test_market_structure_boundaries.py`) are injected only at
grade time from `config.json`'s `test_patch`. They feed exactly the edge inputs
the defects corrupt and assert the correct outputs. "Green locally" is not the
bar — the grader's edge tests are.

The five defect sites are **disjoint** from the sibling `cre-scoring-latent-bugs`
task (which lives entirely in `facts.py` + `scoring.py`); this task uses only
`market.py`, `structure.py`, `lender_match.py`. The two tasks may ship together.

Calibration: the count was set to **five** — the frozen corridor. Live gate data
on this exact substrate: 4 defects = Opus 5/10 (one above the 1-4 corridor),
6 defects = Opus 0/10 (too hard); 5 is the target. The instruction also names the
three source files (file-level localization), the calibrated fairness lever —
Sonnet still scores 0/5 with files named. Defect flavor matters: Sonnet solves
logic-shape plants (inverted membership) but is 0-for-~25 lifetime on
boundary-direction plants (`==`/`>=`, `<=`/`<`), so three of the five are pure
boundary-direction slips; the two empty-guard slips add breadth without giving
Sonnet a foothold (it must still find every one).

## Defects planted (file : symptom : trigger the visible tests never feed)

1. `market.py` `resolve_state` — the two-letter validity check
   `len(st) == 2` weakened to `len(st) >= 2`. A malformed / over-length state
   string (a full name, or a 3-char OCR artifact) is accepted verbatim instead
   of being skipped, so an invalid business value can shadow a valid owner code
   and the wrong (or default) market metrics are used. Visible tests feed only
   valid 2-char states (`MA`, `CA`) or none — `==` and `>=` agree.

2. `structure.py` `_purpose_score` — the empty-input guard
   `if not text.strip()` weakened to `if not text`. Because the composed text
   always contains a separating space it is never falsy, so a deal with **no
   loan purpose and no loan type** gets the generic 75.0 purpose sub-score
   instead of `None` ("no basis"). Every visible test supplies a loan type.

3. `structure.py` `_exit_strategy_score` — the fallback guard
   `if text.strip()` weakened to `if text`. A **fully blank** exit picture (no
   purpose, no exit strategy, no stabilization signal) returns 65.0 instead of
   `None`. Visible tests always supply a purpose or a stabilization signal.

4. `structure.py` `compute_interest_coverage` — the guard
   `if noi is None or noi <= 0` weakened to `noi < 0`. A **break-even property**
   (NOI exactly 0) is no longer rejected, so it yields a coverage ratio of 0.0
   instead of `None` ("undefined"). The `noi is None` check runs first, so the
   change is None-safe; visible tests feed strictly positive NOI.

5. `lender_match.py` `compute_lender_match_score` — the loan-size band
   `min_amount <= loan_amount <= max_amount` narrowed to
   `min_amount <= loan_amount < max_amount`. A request landing **exactly on the
   product maximum** drops from full loan-size credit (100) to out-of-range
   (20), lowering the match score. Visible callers request amounts strictly
   inside the band. (The sibling ltv/dscr boundaries in this function are
   self-healing — both branches equal 100 at equality — so loan-size is the only
   discontinuous boundary here.)

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch, restoring `len == 2`,
`not text.strip()`, `if text.strip()`, `noi <= 0`, and `<= max_amount`. That is
the minimal correct fix; any equivalent boundary / empty-case correction also
passes the gold tests.

## Verifier design

- `tests/test.sh` (verbatim from the canonical) applies `test_patch` from
  verifier-controlled config, runs `run_script.sh`, parses per-test verdicts,
  and awards reward 1 only if every `fail_to_pass` and `pass_to_pass` test
  passed.
- `fail_to_pass` = 7 gold boundary tests spanning all three files (2 market,
  4 structure, 1 lender) — fail at base+defects, pass once the boundaries are
  corrected. Fixing fewer than all five defects leaves ≥1 fail_to_pass red.
- `pass_to_pass` = 20: the 14 gold "adjacent correct behavior" tests (pinning
  the value just off each edge so an over-broad rewrite can't pass) + 1 gold
  test for a boundary edge NOT defected in this cut (a blank loan-type label —
  green at the planted state) + 5 existing qualification tests that exercise the
  same functions and stay green throughout (the "green locally" lull).
- `run_script.sh` runs the gold file plus the five existing qualification files
  that hold the pass_to_pass set.

## Fairness

- All five defected functions are reachable from `run_qualification_engine`
  (`compute_market_intelligence` → `resolve_state`; `compute_structure_score`
  → `_purpose_score` / `_exit_strategy_score` / `compute_interest_coverage`;
  `_build_lender_fit` → `compute_lender_match_score`), so they are live code,
  not dead paths, and the corrupt edge is engine-reachable (an over-length
  state, a blank purpose/type, a break-even NOI, a max-sized request all flow
  through the engine). NOTE: `_in_list`'s empty-list branch was rejected as a
  candidate precisely because its caller guards it with `if asset_classes:` —
  that edge is *not* engine-reachable.
- The instruction names the three source files (calibrated localization) but not
  the functions, thresholds, boundary directions, trigger values, or the defect
  count — the agent must read and reason about the boundary math in three thin
  files to locate and correct each slip.
- Every defect is a single-token / operator / small-idiom slip on an existing
  line (`==`→`>=`, `<=`→`<`, `.strip()` dropped), leaving no dangling import,
  comment, or new name as a structural tell. The two `.strip()` slips are in
  different functions with opposite polarity, so finding one does not reveal the
  other.
- Deterministic, offline, no secrets beyond the baked `JWT_SECRET_KEY`.
