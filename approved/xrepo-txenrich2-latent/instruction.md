<uploaded_files>/app</uploaded_files>

The bank-statement enrichment service assigns the wrong labels to certain
transactions for a couple of banks. Ordinary transactions enrich correctly; the
mistakes cluster around **exact-width, boundary and edge inputs** — for example
a reference field that is a bare instrument number of the exact digit width the
rule is meant to accept, an amount that lands exactly on a special sentinel, a
structured payroll credit whose payee name sits at the very end of a
delimiter-separated reference layout, an account whose type selects a particular
labelling path, and a structured transfer whose payee is pulled from one
specific part of its layout. Away from those edges the labels are correct, which
is why routine transactions never surface the problem.

The affected code is the per-bank categorization logic under
`categorizationapp/categorizationapp/BankScripts/`, specifically the Kotak and
SBI scripts that read the raw description, remark, amount and type off each
transaction and derive its category, subcategory and payee name. This is
deterministic string/amount/comparison logic; the errors are in how the
boundaries and structural offsets themselves are handled, not in the ordinary
cases.

Correct the boundary and structural handling so these scripts label the
edge/boundary transactions correctly, without changing behavior anywhere the
ordinary cases already produce the right label. Correctness on the exact
edge/boundary inputs is the bar.
