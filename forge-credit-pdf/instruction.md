<uploaded_files>/app</uploaded_files>

# Credit-report parsing and document reports are producing wrong numbers

## Issue details

Operations and the underwriting team have reported a cluster of problems in the
`loangen-agent` backend that ingests borrower documents — merged (tri-bureau)
credit-report PDFs and commercial-real-estate documents such as appraisals,
rent rolls, T12 operating statements, and HUD settlement statements. Types and
API shapes look right and nothing crashes, but the parsed and displayed values
are wrong on specific inputs.

### 1. Credit reports mis-route and pollute tradelines

- **Tradelines land on the wrong bureau.** When a parsed credit report contains
  a tradeline that was reported to only one bureau (its per-line bureau tag names
  just that bureau), the finalized report shows that tradeline under *every*
  active bureau instead of only the one it was reported to. A line tagged to
  Experian, for example, comes back attached to TransUnion and Equifax as well.
  Untagged tradelines, which are supposed to broadcast to every active bureau,
  still behave correctly.
- **Junk / artifact rows survive into the parsed report.** Lines that are
  obviously not creditors are no longer filtered out. Examples seen in
  production: a "Past Due" heading row, and table-extraction artifacts whose
  "creditor" text is a bracketed table marker like `[Table 35]`. These come back
  as if they were real tradelines. The two problems compound — a tagged junk row
  ends up duplicated across bureaus.

### 2. Document reports show wrong or missing figures

The document-intelligence report generated for an uploaded document is missing or
misstating headline numbers for certain — but not all — document phrasings:

- An appraisal that states its value as **"As-Is Value: $1,250,000"** generates a
  report with no appraised / as-is value at all.
- A HUD / settlement statement listing **"Loan Amount: $800,000"** generates a
  report with no loan-amount figure. Separately, a clearly-too-small mislabeled
  line such as **"Loan Amount: $9,000"** is wrongly surfaced as the loan amount.
- A rent roll stating **"Total Units: 20"** and **"Occupied: 18"** reports an
  occupancy above 100% rather than 90%.
- A T12 operating statement that gives effective gross income and operating
  expenses but no explicit NOI line reports a net operating income larger than
  the gross income itself.

## Expected outcome

- A tradeline carrying an explicit bureau tag is assigned only to the bureau(s)
  it names; untagged tradelines continue to broadcast to all active bureaus.
- Artifact / heading rows such as "Past Due" and bracketed table markers are
  rejected and never appear as creditors in the parsed report.
- The document reports recover the correct figures for the phrasings above
  (as-is / appraised value, HUD loan amount, rent-roll occupancy, and derived
  T12 NOI), and generalize beyond these exact examples to equivalent inputs —
  including keeping implausibly small mislabeled amounts out of the loan-amount
  figure.

## Affected areas

The document-ingestion pipeline of `loangen-agent`: credit-report PDF parsing
and the commercial-real-estate document handling that feeds the
document-intelligence reports. Do not modify anything under `loangen-agent/tests/`.

## Testing

Run the backend unit test suite from `/app/loangen-agent`:

    cd /app/loangen-agent && python -m pytest tests -v

Tests are hermetic — no database, queue, or external service is required.
