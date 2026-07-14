<uploaded_files>/app</uploaded_files>

The document-intelligence tools — the ones that read uploaded financial
documents into labelled figures, table rows and structured view reports —
produce wrong results for certain inputs, even though the whole test suite is
green. The wrong results cluster around **exact boundary values and edge
cases**: a figure sitting precisely on a size or length cutoff, a value at the
very edge of a valid range, a table cell landing right at the edge of the
detected grid, or a collection holding just enough (or just too many) items for
a rule to fire. Away from those edges the output is correct, which is why the
existing tests — they feed values comfortably inside the ranges — never surface
the problem.

The affected code is the deterministic document math under
`loangen-agent/agent/documents/`: the Azure-table serialization and row/amount
extraction in `extraction/table_text.py`, the per-type report assembly in
`report/builders.py`, and the multi-property portfolio aggregation in
`deal_summary/portfolio.py`. This is pure, side-effect-free string, arithmetic
and collection logic; the bugs are in how the boundaries themselves are handled
— a comparison that drops the equal case, an index range that runs one past its
end, a minimum-count guard set one too high, a return cap made too loose, a
divide guard that admits a zero denominator — not in any I/O, model or storage
layer.

Correct the boundary handling so these tools are right on the exact-threshold
and edge inputs, without changing behavior anywhere ordinary inputs already
land. Do not weaken, loosen or delete behavior that is already correct; the bar
is correctness on the edge and boundary inputs while everything that currently
works keeps working.

Do not modify anything under `loangen-agent/tests/`.

Verify with:

    cd /app/loangen-agent && python -m pytest tests -v
