# Reference plan (author only — not shown to the agent)

Mined from real fix commit `5509cc2b5775dab9ccf6faa66d62a8998f8b660d` ("fix the
issue") on the boostmoney `loangenus` repo. Base commit
`2a36b03d4b42746716af8a41e409460aa0e481ab` is its parent — the last state before
the recommendation bands existed.

## Root cause (author only)

The lender qualification hero (UI banner) and the PDF report cover rendered their
headline from the rules-based `decision` action, which is computed from
DSCR/LTV/liquidity gates and is independent of the numeric `deal_score`. There was
no deal-score-derived recommendation on the backend `overall` object at all, so:
1. the headline could disagree with the deal score, and
2. cached `overall` snapshots (persisted before any recommendation existed) had
   nothing to render.

## Oracle fix (files in scope for this task — `agent/services/cre_qualification/`)

- `recommendation.py` (new): `resolve_recommendation(*, deal_score, deal_score_available)`
  returns a frozen `RecommendationDisplay(band, label, color)`. Score bands
  (applied top-down): >=80 strong_proceed `#047857`, >=60 proceed `#34d399`,
  >=40 manual_uw `#f59e0b`, else review `#eab308`; unavailable/None →
  insufficient_data `#64748b`.
- `constants.py`: `RECOMMENDATION_STRONG_PROCEED_MIN=80.0`,
  `RECOMMENDATION_PROCEED_MIN=60.0`, `RECOMMENDATION_MANUAL_UW_MIN=40.0`.
- `schemas.py`: `OverallQualificationSchema` gains `recommendation_band`
  (`Literal` of the five bands), `recommendation_label`, `recommendation_color`
  with defaults, plus a `model_validator(mode="after")` that re-derives all three
  from `deal_score`/`deal_score_available` via `resolve_recommendation` — this is
  what backfills cached payloads that omit the fields.
- `engine.py`: `run_qualification_engine` calls `resolve_recommendation` and sets
  `recommendation_band/label/color` on `OverallQualificationSchema`.
- `qualification_report_pdf.py`: cover headline uses
  `analysis.overall.recommendation_label` and `HexColor(recommendation_color)`
  instead of `DECISION_LABELS`/`DECISION_COLORS`.

The same commit also changes `loangen-app/` (TS types + hero component). Those are
out of scope for the verifier — the solution patch is restricted to
`loangen-agent/agent/services/cre_qualification/`.

## Verifier

- Gold tests = the two test files from the fix commit, with one hardening change:
  every module-level import of `agent.services.cre_qualification.recommendation`
  (which does not exist at base) is moved inside the test bodies so the files
  collect at base and each test fails individually (per-test FAILED lines for the
  parser instead of a file-level collection ERROR). The
  `OverallQualificationSchema` import stays at module level — that class exists at
  base, so it collects; the backfill test then fails on `.recommendation_band`
  (AttributeError) at base and passes at fix.
- 7 fail_to_pass: 6 in `test_qualification_recommendation.py` (5 band cases + the
  schema-backfill case) and 1 in `test_cre_qualification.py`
  (`test_rich_cre_context_enables_deal_score_and_cross_checks`, which now also
  asserts `overall.recommendation_band == resolve_recommendation(...).band`).
- 6 pass_to_pass: the 4 untouched `test_cre_qualification.py` tests + the 2
  `test_qualification_report_pdf.py` tests. The PDF file is the "stable extra"
  file; it exercises the modified `qualification_report_pdf.py` and passes at both
  base and fix (its two tests only assert that a non-empty PDF is produced / that a
  minimal insufficient-data analysis renders, not the specific cover label).
- Environment: no task-specific env vars. The tests call the engine, the
  recommendation mapping, and the schema directly; they pass with the repo image's
  baked-in `JWT_SECRET_KEY` / `LIVEKIT_*` stubs alone. Verified in docker: null =
  7 fail / 6 pass (reward 0), oracle = 13/13 pass (reward 1), suite <1s, offline.

## Fairness note

The instruction names the module path, the `resolve_recommendation` signature, and
the full band→label→color→threshold table because the gold tests import that
module and assert those exact band strings, labels, and two of the colors
(`#047857`, `#eab308`) — API/display contract, the same pattern as the canonical
task publishing signatures and default values. It does not prescribe the
implementation: the `RecommendationDisplay` dataclass, the `model_validator`
backfill mechanism, the engine call site, and the PDF cover rewrite are left to the
solver. The task is not one-liner grep-solvable: `recommendation` does not exist at
base, and the fix must add a new module and integrate it across the schema, the
engine, and the PDF builder.
