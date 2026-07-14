# Reference plan — latent-financial-tools

## Construction (LATENT-BUG pattern)

Base image is the clean HEAD of loangenus (`04b8abc`). The environment Dockerfile
resets to that commit and then applies a small **defect patch** that plants five
subtle boundary errors in the deterministic summarization math of the
financial-data analysis tools (the bank / credit-bureau / accounting analytics
services). The agent starts from base+defects. There is **no failing local test**
pointing at any defect: the full existing suite stays green with the defects
present, because every visible test either never calls these helpers or feeds
values that sit safely inside the ranges and never lands on the exact edge that
bites.

Count and selection are calibrated against the platform gate across three
rounds. Six defects graded Opus 0/10 — not a count problem but an
**underdetermined** defect (a convention choice, not a derivable boundary) which
scores p≈0 individually and drags the whole task to zero; that one
(seasonality-band edge) was dropped. The resulting five *cleanly-derivable*
defects then graded Opus **8/10** — too easy, because each cleanly-pinned
boundary is ~95% solvable and the joint stayed high. The final calibration swaps
exactly one **easy** defect (the credit-score tier floor, a p≈1.0 anchor solved
in essentially every trial) for one **medium** defect whose correct side is
pinned only by **cross-function tracing** (the monthly-gap window, defect 4
below). Every surviving defect is still uniquely derivable — but one now requires
following the data across functions rather than reading a single line, which
lowers the joint solve into the target band.

The gold tests (`tests/test_financial_tools_boundaries.py`) are injected only at
grade time from `config.json`'s `test_patch`. They feed exactly the edge inputs
the defects corrupt and assert the correct outputs. "Green locally" is not the
bar — the grader's edge tests are.

## Defects planted (file : function : boundary : derivability signal)

1. `analytics/services/credit_bureau_analytics.py`
   `build_credit_analytics_checklist_v1` — severe-delinquency guard
   `late_90 > 0` tightened to `late_90 > 1`. A tradeline with exactly one
   90-day-late mark (no charge-off) stops counting as severe. DERIVABLE (easy):
   the sibling `delinquent_open_count` treats `late_90 > 0` as delinquent, and a
   single 90-DPD is unambiguously severe by domain convention.

2. `analytics/services/plaid_analytics.py` `_compute_volatility` — the
   single-point guard `len(values) < 2` widened to `len(values) <= 2`. A
   two-observation series wrongly collapses to 0.0 volatility. DERIVABLE (easy):
   `statistics.stdev` is defined for n >= 2, so the guard must exclude only
   n < 2.

3. `analytics/services/plaid_analytics.py`
   `build_bank_analytics_checklist_v1` — near-limit cutoff
   `utilization_pct >= 75.0` weakened to `> 75.0`. A revolving line at exactly
   75% utilization is dropped from the near-limit count. DERIVABLE (easy):
   `docs/BANK_ANALYTICS_CHECKLIST.md` (referenced by the function's own
   docstring) defines the field as "accounts with `utilization_pct >= 75`".

4. `analytics/services/plaid_analytics.py`
   `build_bank_analytics_checklist_v1` — monthly-gap observation window
   `if len(months_observed) >= 2:` tightened to `>= 3`. With exactly two
   observed months, the expected inclusive month range is no longer computed, so
   a missing interior calendar month (e.g. Feb, between an observed Jan and Mar)
   is silently dropped from `missing_months_in_range`. DERIVABLE (**medium** —
   requires **cross-function tracing**): the correct threshold `2` is not visible
   at the guard; it is pinned by the non-adjacent sibling checklist field
   `net_cash_trend_reviewed_for_window`, ~160 lines later in the same function,
   which uses `len(months_observed) >= 2` for the same "reviewable window"
   concept, and by the gap-detection semantics (two bracketing months already
   define a range with a detectable interior gap; `_enumerate_months_inclusive`
   handles a two-month span). An engineer who only reads the guard sees a
   plausible `>= 3` and must follow the field's consumer / sibling to fix it.

5. `analytics/services/quickbooks_analytics.py` `_extract_monthly_from_summary`
   — minimum-width guard `len(col_data) < num_months + 2` widened to
   `<= num_months + 2`. A P&L summary at its minimum valid column width
   (`[label, month..., TOTAL]`) returns an empty monthly series. DERIVABLE
   (medium): the sibling `_row_to_line_item` accepts monthly data at the same
   `len(values) >= num_months + 2`, pinning `num_months + 2` as the minimum
   valid width.

## Derivability + difficulty audit (why these five, and what was swapped out)

Each candidate is checked twice: (a) can a strong engineer determine the
uniquely-correct side of the boundary at all (else it is underdetermined and
sinks the whole task to 0), and (b) how hard is that determination (a board of
all-easy defects grades too high because each is ~95% solvable).

- severe `late_90` — DERIVABLE, easy (sibling `> 0` + 90-DPD is severe). KEPT.
- `_compute_volatility` n=2 — DERIVABLE, easy (stdlib stdev needs n >= 2). KEPT.
- near-limit 75 — DERIVABLE, easy (BANK_ANALYTICS_CHECKLIST.md says `>= 75`).
  KEPT.
- monthly min-width — DERIVABLE, medium (sibling `_row_to_line_item`). KEPT.
- monthly-gap window `>= 2` — DERIVABLE, **medium via cross-function tracing**
  (non-adjacent sibling `net_cash_trend_reviewed_for_window` uses `>= 2` +
  gap-detection semantics). ADDED this round to replace the tier anchor.
- `_classify_risk_tier` 740 — DERIVABLE but **easy** (sibling floors all `>=`
  make it a one-line inconsistency; graded p≈1.0). REMOVED this round: its band
  is left correct and its three gold tests reclassified to pass_to_pass.
- `_compute_seasonality` ratio 2.0 — **UNDERDETERMINED** (no doc/docstring/
  comment; the only sibling `> 1.5` is a weak signal and seasonality bands are
  commonly stated inclusively). DROPPED in the prior round; its whole test class
  was removed (a pass_to_pass pin on 2.0 would be the mirror-image trap).

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch, restoring the original
`> 0`, `< 2`, `>= 75.0`, `>= 2` (monthly-gap window), and `< num_months + 2`
boundary logic. That is the minimal correct fix; any equivalent boundary
correction also passes the gold tests.

## Verifier design

- `tests/test.sh` (verbatim from the canonical latent task) applies `test_patch`
  from verifier-controlled config, runs `run_script.sh`, parses per-test
  verdicts, and awards reward 1 only if every `fail_to_pass` and `pass_to_pass`
  test passed.
- `fail_to_pass` = 8 gold boundary tests (fail at base+defects, pass once the
  boundaries are corrected), spanning all five defects across the three services.
- `pass_to_pass` = 13 gold tests pinning the just-off-edge behavior adjacent to
  each defect (values one tick above/below the boundary, larger/smaller sets)
  plus the three now-correct credit-tier tests — all pass at both the planted and
  the fixed state.
- `run_script.sh` runs only the gold file; every f2p and p2p node lives there.

## Fairness

- All five defected functions are live code: `build_credit_analytics_checklist_v1`
  feeds the credit dashboard/chat summaries, the two `build_bank_analytics_checklist_v1`
  boundaries and `_compute_volatility` feed the bank checklist, and
  `_extract_monthly_from_summary` feeds `parse_profit_and_loss` /
  `compute_qb_analytics` (monthly income) — none are dead paths.
- The instruction names the domain area and the three analytics service files
  (bank/credit/accounting), plus the symptom shape (wrong numbers clustered on
  exact thresholds / minimal windows / small sets). It gives no function names,
  boundary directions, trigger values, or defect count — the agent must read and
  reason about each boundary to locate and correct the slip, and each slip has a
  uniquely-derivable correct answer.
- Deterministic, offline, no secrets beyond the baked `JWT_SECRET_KEY`. The gold
  tests are pure-input (dict/list/scalar in, scalar/list/dict out) and use zero
  mocks, so no oracle implementation choice is encoded.
