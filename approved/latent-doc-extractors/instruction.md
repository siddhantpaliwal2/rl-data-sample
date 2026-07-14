<uploaded_files>/app</uploaded_files>

The document field extractors that read structured numbers off uploaded deal
documents return wrong values for certain documents, even though the whole test
suite is green. The wrong results cluster around **exact threshold values and
boundary cases** — for example an amount sitting precisely on a plausibility
floor, a figure right at the top of a valid range, or a table with only the
fewest rows that still count as data. Away from those edges the extracted
numbers are correct, which is why the existing tests (they feed values
comfortably inside the ranges, with roomy tables) never surface the problem.

The affected code is the deterministic parsing and labeled-amount math under
`loangen-agent/agent/documents/extractors/`, specifically the type-specific
field extractors in `cre_fields.py` that pull values off appraisals, rent rolls,
settlement statements and credit reports. This is pure, side-effect-free string
parsing, thresholding and comparison logic; the bugs are in how the boundaries
themselves are handled — which side of a threshold is included, and how many
rows are enough to trust.

Correct the boundary handling so the extractors are right on these
exact-threshold and edge inputs, without changing behavior anywhere the current
tests already pin. The repository's existing tests all pass and must stay
passing; correctness on the edge/boundary inputs is the bar.

Do not modify anything under `loangen-agent/tests/`.

Verify with:

    cd /app/loangen-agent && python -m pytest tests -v
