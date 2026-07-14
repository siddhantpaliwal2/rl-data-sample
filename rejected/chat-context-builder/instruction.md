<uploaded_files>/app</uploaded_files>

# The SMB AI advisor mishandles connected data and personal-data questions

## Issue details

The small-business "AI advisor" chat answers a borrower's questions by first
detecting what they're asking about, then enriching the prompt with whatever
data (personal credit, bank cash-flow, QuickBooks financials) is connected.
Several related problems have been reported from production.

1. **Real-world data crashes the qualification math.** Borrower records that come
   from forms and third-party syncs are messy: a tradeline can arrive with no
   monthly payment (a `null`), and a company's founding year can arrive as a
   string like `"2019"` (or be missing entirely as `null`). When the advisor
   tries to qualify such a borrower, the analysis errors out instead of
   producing a result. Example: a borrower with two tradelines — one paying
   $500/mo and one with a missing monthly payment — should be scored with a
   monthly debt service of $500, but instead the qualification blows up.
   Example: a borrower whose `year_established` is the string `"2019"` should be
   treated as founded in 2019, but instead the analysis errors.

2. **QuickBooks financials come back empty.** When a borrower has connected and
   synced QuickBooks, the advisor still reports their revenue, cash on hand, and
   DSCR as zero/blank. The synced numbers are there, but the advisor isn't
   reading them, so answers about the borrower's own financials are wrong.

3. **Personal-data questions aren't recognised.** Questions like "what's my
   credit score", "show me my cash flow", "what's my revenue this year", and
   "what's the status of my application" are not routed to the right
   personalised view — they fall through to the generic path. In particular,
   asking a QuickBooks-financials question when QuickBooks is *not* connected
   does not tell the borrower that QuickBooks needs to be connected first.

## Expected outcome

- Qualification (both the product qualification and the lender matching paths)
  must tolerate messy inputs without crashing:
  - a tradeline with a missing/`null` monthly payment contributes `0` to the
    monthly debt service;
  - a `year_established` given as a numeric string such as `"2019"` is
    understood as that year; a missing/`null` `year_established` is treated as
    the current year (0 years in business) rather than erroring.
- A borrower who has connected and synced QuickBooks must see their real
  QuickBooks revenue, cash on hand, and DSCR reflected in the advisor (not zero).
- The pipeline's intent detection must recognise the personalised-data
  questions and classify them into these intent identifiers (other modules key
  off these exact strings):
  - `personal_credit` — questions about the borrower's own credit / FICO;
  - `bank_cashflow` — questions about bank cash-flow / statements / overdrafts;
  - `qb_financials` — questions about revenue / profit / P&L / balance sheet /
    DSCR / QuickBooks;
  - `applications_overview` — questions about the status of the borrower's loan
    applications.
  Existing intents (e.g. `qualification`) must keep working.
- Asking a `qb_financials` question while QuickBooks is not connected must
  surface QuickBooks as a required-but-missing source.

## Affected areas

The SMB advisor chat pipeline of `loangen-agent`: intent detection, context
assembly (including the QuickBooks financials mapping), and the deterministic
qualification engine. Do not modify anything under `loangen-agent/tests/`.

## Testing

Run the backend unit test suite from `/app/loangen-agent`:

    python -m pytest tests -v

Tests are hermetic — no database, network, or LLM is required.
