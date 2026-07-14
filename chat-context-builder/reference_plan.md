# Reference plan (author only — not shown to the agent)

Mined from real fix commit `869aa675bacf72c7d5308146c7b94fed7bc5c4d9`
("fixed chat issues …") on the boostmoney `loangenus` repo. Base commit
`2dac686ab097d5fd3d8094e98159a9475efc802b` is its parent — the last broken
state. This is a MULTI-defect task drawn from the full backend surface of the
commit.

## Root cause (author only)

1. `tools/qualification_engine.py` (`qualify` and `match_lenders`) summed
   `t.get("monthly_payment", 0)` directly (a present `None` value breaks the
   `sum`) and did `datetime.now().year - company.get("year_established", now)`
   (a string or `None` year raises `TypeError`). The same slip is duplicated in
   `context_builder.build_qualification_prompt`.
2. `context_builder._map_qb_financials` read the wrong keys off the QuickBooks
   analytics result: `income_statement.total_revenue` (the result exposes
   `total_income`), `balance_sheet.cash` (the result exposes `cash_and_bank`),
   and `key_metrics.dscr` (the result exposes a top-level `dscr`). So revenue,
   cash on hand, and DSCR mapped to `0`/`None`.
3. `pipeline.INTENT_PATTERNS` had no personalised-data intents, and
   `context_builder.INTENT_DATA_REQUIREMENTS` had no `qb_financials` entry, so
   those questions fell through to the generic path and the missing-QuickBooks
   gate never fired.

## Oracle fix (scope = the three tested source files)

- `tools/qualification_engine.py`: add `_safe_num` and coerce
  `monthly_payment`; parse/guard `year_established` (str/None → int/current
  year) in both `qualify` and `match_lenders`.
- `context_builder.py`: `_map_qb_financials` reads `total_income` /
  `cash_and_bank` / top-level `dscr` (with fallbacks); add `"qb_financials":
  ["quickbooks"]` to `INTENT_DATA_REQUIREMENTS`; mirror the `year_established`
  and `monthly_payment` guards in `build_qualification_prompt`.
- `pipeline.py`: add `personal_credit`, `bank_cashflow`, `qb_financials`,
  `applications_overview` pattern groups to `INTENT_PATTERNS` (before the
  existing intents) and the matching one-shot enrichment branches.

`solution/solve.sh` applies the source diff restricted to
`context_builder.py`, `pipeline.py`, and `tools/qualification_engine.py` — the
commit's `chat_server.py`, `quickbooks/router.py`, and `loangen-app/` changes
are not needed to make the gold tests pass and are left out.

## Verifier

- Gold tests are authored (the fix commit shipped no backend tests, and the
  `loangen-agent/tests/` tree does not exist at this base). One new file
  `tests/test_chat_context_pipeline.py`, entered only via `config.json`'s
  `test_patch`; every `agent.*` import is inside a test body so the file
  collects at base and each f2p emits a per-test FAILED line.
- 12 fail_to_pass across 3 source files:
  - qualification_engine (public `qualify` / `match_lenders`): None monthly
    payment → dscr 20.0 (not a crash); string `"2019"` year → qualifies;
    `None` year → tolerated; `match_lenders` returns a list.
  - context_builder: `_map_qb_financials` maps revenue/cash/DSCR from the real
    result shape; `get_missing_data_response("qb_financials", …)` surfaces
    QuickBooks as missing.
  - pipeline (public `detect_intent`): the four new intents classify correctly.
- 4 pass_to_pass on behaviour the fix leaves unchanged (clean-input
  qualification; the existing `qualification` intent; `_map_qb_financials` empty
  for unmappable input and its `period` passthrough).
- Verified in docker: null = 12 failed / 4 passed → reward 0 (each f2p FAILED
  individually, no collection errors); oracle = 16/16 → reward 1; suite < 1s,
  no network. No task env beyond the baked image is required.

## Fairness note

The instruction is symptom-framed with concrete examples and publishes only the
cross-module intent identifiers the gold tests assert (`personal_credit`,
`bank_cashflow`, `qb_financials`, `applications_overview`) plus the "string year
must be read as that year" behaviour — the API-contract exception the canonical
task used. It does not reveal the QuickBooks result field names, the mapping
fallback chains, the `_safe_num` helper, or the regexes.

Alternative-implementation audit: the coercion tests assert only the sensible
observable result (missing payment → 0; string `"2019"` → year 2019) — every
correct fix produces those. The mapping tests feed a result in the *real*
QBAnalyticsResult shape (which any correct fix must read) and assert the mapped
financials, not the fallback ordering. The intent tests assert the published
intent identifiers. No collaborator is mocked (fully hermetic, dict/SimpleNamespace
inputs, no MagicMock); settings are untouched by the tested code paths.
