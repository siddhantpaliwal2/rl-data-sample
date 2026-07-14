# Reference plan (author only — not shown to the agent)

Mined from real fix commit `e9774cc699d77f26e06400f670420f40aea92ded`
("fix the bank data report issue") on the boostmoney `loangenus` repo. Base
commit `e8e4a09379eeee13cc9ea058b87054b77b3b338d` is its parent — the last
broken state. Single-file fix: `loangen-agent/agent/plaid/report_service.py`
(+89 / -2).

## Root cause (author only)

`build_bank_report_view` sourced the report exclusively from the normalized
`PlaidTransaction` collection. When that query returns nothing it raised
`BankReportNotFoundError`. Trial/UAT borrowers are seeded only into the raw
`PlaidDataDocument` collection (raw Plaid `/transactions/get` JSON keyed by
`smb_id`) and never get normalized rows, so their report was permanently
unavailable even though the data existed.

## Oracle fix

Add a fallback that runs only when `not transactions`: look up
`PlaidDataDocument` by `smb_id == user_id`, validate the raw JSON has non-empty
`accounts` and `transactions` lists and at least one transaction for the
resolved primary account, then reuse the pre-existing
`build_bank_report_view_from_preview_payload` (which filters to
`selected_account_id`, computes analytics, and assembles the response) to build
the report. If the raw data is missing/unusable the fallback returns `None`
and the original `BankReportNotFoundError` is raised. The fix also carries the
institution name from the raw `item` block and forwards user/business names.

`solution/solve.sh` applies the full source diff (the only file the commit
touched).

## Verifier

- Gold tests are authored from scratch (the fix commit touched no tests; the
  `loangen-agent/tests/` directory does not even exist at base). The new file
  `tests/test_plaid_report_service.py` drives the public entry point
  `build_bank_report_view` with all four DB seams mocked
  (`PlaidAccount`/`PlaidItem`/`PlaidTransaction` classes stubbed in
  `report_service`; `PlaidDataDocument.find_one` + `.smb_id` stubbed on the
  shared source class so the patch also resolves at base). `compute_plaid_analytics`
  is a pure function, so the success tests run the *real* preview-builder path
  and assert on actual report content (filtering, counts, institution, names).
- 6 fail_to_pass — all success behaviors that only exist after the fix:
  1. `test_falls_back_to_data_document_when_no_normalized_transactions`
  2. `test_fallback_filters_transactions_to_primary_account`
  3. `test_fallback_selects_transactions_of_selected_primary_account`
  4. `test_fallback_builds_report_when_raw_item_missing`
  5. `test_fallback_passes_selected_account_id_to_preview_builder`
  6. `test_fallback_forwards_business_and_user_name`
- 3 pass_to_pass — invariants preserved at base and fix (all three raise
  `BankReportNotFoundError`): no connected accounts; no transactions and no
  seeded document; seeded document with no transactions for the primary
  account. These come from the same authored file (there is no pre-existing
  test file at base to draw from).
- Environment: no task-specific env vars. Importing
  `agent.plaid.report_service` succeeds with only the credentials baked into
  the base repo image. Verified: null = 6 fail / 3 pass (reward 0), oracle =
  9/9 pass (reward 1), suite runs in <1s with no network.

## Fairness note

The instruction names the module path and the *pre-existing* public signatures
the tests import (`build_bank_report_view`, `BankReportNotFoundError`) — these
exist at base and are contract, not leak. It describes the observable fallback
contract (prefer normalized rows; else rebuild from raw data filtered to the
primary account; raise when nothing usable) without revealing the private
helper name, the guard ordering, the `isinstance` list checks, the timezone/
field handling, or how the preview builder is invoked. The single-file scope is
guarded against grep-only solutions by the success tests, which require a
correctly *filtered* report (primary-account-only transactions, exact counts,
selected-account resolution, carried-through institution/names) rather than the
mere presence of a fallback branch.
