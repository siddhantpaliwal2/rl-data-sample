<uploaded_files>/app</uploaded_files>

The transaction-correlation service scores how strongly a source record (for
example a credit-report line) matches candidate bank or card transactions, and
formats those records into human-readable strings. For certain inputs the
scores and the formatted output come out subtly wrong even though nothing
raises and the test suite is green. The wrong results cluster around **exact
boundary values and edge cases** — a quantity sitting precisely on an
accept/reject threshold, an input at the very top or bottom of a valid range,
or a pair of records where one side's tokens are entirely contained in the
other. Away from those edges every number and string is correct, which is why
ordinary inputs (values comfortably inside the ranges) never surface the
problem.

The affected code is the deterministic scoring and formatting math: the
correlation-decisioning scorer in `Service/Correlation_Decisioning.py` and the
record/date formatter in `Service/Get_Transactions_Custom_Logic.py`. This is
pure, side-effect-free arithmetic, set and string logic; the errors are in how
the boundaries themselves are handled — an inclusive range that has been made
exclusive, a comparison that drops the equal case, a set-overlap classification
that misreads full containment.

Correct the boundary handling so the scorer and the formatter are right on
these exact-threshold and edge inputs, without changing behavior anywhere
ordinary inputs already land. Do not weaken, loosen or delete behavior that is
already correct; the bar is correctness on the edge and boundary inputs while
everything that currently works keeps working.

Verify with:

    cd /app && python -m pytest tests -v
