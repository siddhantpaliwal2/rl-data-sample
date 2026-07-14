<uploaded_files>/app</uploaded_files>

The bank-statement enrichment service assigns the wrong labels to certain
transactions for a couple of banks. Ordinary transactions enrich correctly; the
mistakes cluster around **exact-length, boundary and edge inputs** — for
example a reference field whose length sits precisely on the value its digit
layout implies, an amount that lands exactly on a special sentinel, an
offsetting credit that arrives directly after its matching debit, an account
whose type selects a particular labelling path, and a structured description
whose payee segment sits at the very end of a fixed-width layout. Away from
those edges the labels are correct, which is why routine transactions never
surface the problem.

The affected code is the per-bank categorization logic under
`categorizationapp/categorizationapp/BankScripts/`, specifically the HDFC and
ICICI scripts that read the raw description, remark, amount and type off each
transaction and derive its category, subcategory and payee name. This is
deterministic string/amount/comparison logic; the errors are in how the
boundaries and structural offsets themselves are handled, not in the ordinary
cases.

Correct the boundary and structural handling so these scripts label the
edge/boundary transactions correctly, without changing behavior anywhere the
ordinary cases already produce the right label. Correctness on the exact
edge/boundary inputs is the bar.
