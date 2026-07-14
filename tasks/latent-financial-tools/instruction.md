<uploaded_files>/app</uploaded_files>

The financial-data analysis tools — the ones that summarize bank, credit-bureau
and accounting data into structured metrics — return wrong numbers for certain
inputs, even though the whole test suite is green. The wrong results cluster
around **exact threshold values and boundary cases**: a value sitting precisely
on a cutoff, a metric landing right at the edge of a scoring or risk band, a
reporting window at its minimum valid size, or a small/even-sized set of inputs
where the boundary itself is what gets used. Away from those edges the numbers
are correct, which is why the existing tests — they feed values comfortably
inside the ranges — never surface the problem.

The wrong numbers show up in the deterministic summarization math under
`loangen-agent/agent/analytics/services/` — the bank-feed metrics in
`plaid_analytics.py`, the bureau metrics in `credit_bureau_analytics.py`, and
the accounting metrics in `quickbooks_analytics.py`: threshold classifications,
utilization and ratio comparisons, reporting-window handling, and roll-ups over
collections of line items. This is pure, side-effect-free arithmetic and
comparison logic; the bugs are in how the boundaries themselves are handled, not
in any I/O or model layer.

Correct the boundary handling so these summaries are right on the
exact-threshold and edge inputs, without changing behavior anywhere the current
tests already pin. The repository's existing tests all pass and must stay
passing; correctness on the edge/boundary inputs is the bar.

Do not modify anything under `loangen-agent/tests/`.

Verify with:

    cd /app/loangen-agent && python -m pytest tests -v
