<uploaded_files>/app</uploaded_files>

# Bank report generation fails for users whose Plaid data was seeded, not synced

## Issue details

The SMB dashboard renders a "bank report" for each borrower — connected
accounts, spend/income analytics, and a transaction list — from their Plaid
data. The report is produced by `build_bank_report_view` in
`agent/plaid/report_service.py` on the `loangen-agent` backend.

Production borrowers who complete a live Plaid link get their transactions
written into the normalized `PlaidTransaction` collection, and the report
builds correctly for them. Trial and UAT borrowers are onboarded differently:
their bank data is seeded straight into the raw `PlaidDataDocument` collection
(the raw `/transactions/get` JSON, keyed by `smb_id`), and normalized
`PlaidTransaction` rows are never created for them.

Operations reports that for these seeded borrowers the bank report page always
fails with **"No bank transactions found for the selected primary account,"**
even though the borrower's accounts and transactions are clearly present in the
raw Plaid data. Because the report cannot be generated, the analytics panel and
the downloadable report are both unavailable for every trial/UAT account.

## Expected outcome

`build_bank_report_view` must still prefer normalized `PlaidTransaction` rows
when they exist (production path is unchanged). But when there are **no**
normalized transactions for the resolved primary account, it must fall back to
the borrower's seeded raw Plaid JSON instead of failing:

- Look up the borrower's raw Plaid data (`PlaidDataDocument`, matched on the
  user's id) and build the report from it, restricted to the **primary
  account** that would otherwise have been used. The resulting report must
  contain only that primary account's transactions, and its
  `total_transactions` must reflect that filtered count.
- The institution name and the caller-supplied user/business names must be
  carried through onto the resulting report.
- The fallback must be tolerant of imperfect seed data. It must produce a
  report only when the raw JSON actually contains a usable, non-empty list of
  accounts, a usable, non-empty list of transactions, **and** at least one
  transaction belonging to the primary account. Missing optional sections
  (e.g. no institution/`item` block) must not prevent a report from being
  built.
- When there is genuinely nothing to report — no connected accounts at all, no
  seeded raw data for the user, or seeded data that contains no transactions
  for the primary account — the existing `BankReportNotFoundError` behavior
  must be preserved.

## Public API (unchanged; other code and the tests rely on it)

In `agent/plaid/report_service.py`:

- `async def build_bank_report_view(*, user_id: str, user_first_name: str | None = None, user_last_name: str | None = None, business_name: str | None = None) -> BankReportViewResponse`
  — the entry point described above.
- `class BankReportNotFoundError(Exception)` — raised when a report cannot be
  generated due to missing data.

The module already contains a helper that builds a `BankReportViewResponse`
from a raw Plaid-shaped payload; reuse the existing building blocks rather than
duplicating report assembly.

## Affected areas

`agent/plaid/report_service.py` in `loangen-agent`. Do not modify anything
under `loangen-agent/tests/`.

## Testing

Run the backend unit test suite from `/app/loangen-agent`:

    python -m pytest tests -v

Tests are hermetic — no database, queue, or external service is required.
