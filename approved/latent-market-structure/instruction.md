<uploaded_files>/app</uploaded_files>

The commercial-real-estate qualification engine returns wrong numbers for
certain deals, even though the whole test suite is green. The wrong answers
cluster at boundary inputs: a value sitting exactly on a program limit, a metric
right at the edge of a band, and the degenerate "empty" or "zero" cases (a
missing/blank field, a break-even figure). Away from those edges the numbers are
correct, which is why the existing tests — they feed values comfortably inside
the ranges — never surface the problem.

The affected code is the deterministic scoring math under
`loangen-agent/agent/services/cre_qualification/` — the market-metric resolution
in `market.py`, the deal-structure scoring in `structure.py`, and the
application-to-lender-product match scoring in `lender_match.py`.

Concretely, the symptoms a reviewer would notice:

- A deal whose request or profile lands *exactly* on a stated threshold is
  scored as if it were on the wrong side of that threshold.
- A borderline or malformed reference value that should be ignored (or should
  fall back to a safe default) is instead taken at face value.
- When a piece of input is absent, blank, or degenerate (e.g. a break-even
  figure), the affected computation reports a concrete-looking number instead of
  correctly signalling "no basis to score."

This is pure, deterministic, side-effect-free arithmetic and comparison logic;
the bugs are in how the boundaries and the empty/zero cases themselves are
handled, not in any data fetch or model call.

Correct the boundary and empty-case handling so these market, deal-structure,
and lender-match computations are right on the exact-threshold and degenerate
inputs, without changing behavior anywhere the current tests already pin. The
repository's existing tests all pass and must stay passing; correctness on the
edge/boundary inputs is the bar.

Do not modify anything under `loangen-agent/tests/`.

Verify with:

    cd /app/loangen-agent && python -m pytest tests -v
