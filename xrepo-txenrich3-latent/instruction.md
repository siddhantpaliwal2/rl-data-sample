<uploaded_files>/app</uploaded_files>

The bank-statement enrichment service assigns the wrong labels to certain
transactions. Ordinary transactions enrich correctly; the mistakes cluster
around **exact-width, sentinel, account-type and fixed-layout edge inputs** — for
example a cheque remark that is a bare instrument number of the exact digit width
the rule is meant to accept, a rupee-one mandate-registration credit that is the
kind used to verify an account, a card reversal credit whose labelling path is
selected by the account type, a structured payroll/mandate credit whose payee
name sits at the very end of a delimiter-separated reference layout, and a
structured transfer whose payee is the single captured field of its reference
layout. Away from those edges the labels are correct, which is why routine
transactions never surface the problem.

The enrichment logic reads the raw description, remark, amount and type off each
transaction and derives its category, subcategory and payee name. This is
deterministic string / amount / comparison logic; the errors are in how the exact
boundaries and structural offsets themselves are handled, not in the ordinary
cases. Symptoms that have been observed include a bare-instrument-number cheque
falling through to a generic transfer, a rupee-one verification credit no longer
being marked as an account verification, a card reversal coming out as an
ordinary refund for one account type, a payee resolving to a fixed layout token
instead of the real name, and a payee coming back empty on a structured transfer.

Correct the boundary and structural handling so these edge transactions are
labelled correctly, without changing behavior anywhere the ordinary cases already
produce the right label. Correctness on the exact edge/boundary inputs is the bar.
