<uploaded_files>/app</uploaded_files>

The commercial-real-estate qualification engine returns wrong numbers for
certain borrower and property profiles, even though the whole test suite is
green. The wrong results cluster around **exact threshold values and boundary
cases** — for example a value sitting precisely on a program limit, a metric
right at the edge of a scoring band, or an even-sized set of inputs where the
midpoint is what gets used. Away from those edges the numbers are correct,
which is why the existing tests (they feed values comfortably inside the
ranges) never surface the problem.

The affected code is the deterministic scoring math under
`loangen-agent/agent/services/cre_qualification/` — the fact resolvers in
`facts.py` that read structured values off appraisals, credit reports and rent
rolls, and the score-normalization helpers in `scoring.py`. This is pure,
side-effect-free arithmetic and comparison logic; the bugs are in how the
boundaries themselves are handled.

Correct the boundary handling so the resolvers and normalizers are right on
these exact-threshold and edge inputs, without changing behavior anywhere the
current tests already pin. The repository's existing tests all pass and must
stay passing; correctness on the edge/boundary inputs is the bar.

Do not modify anything under `loangen-agent/tests/`.

Verify with:

    cd /app/loangen-agent && python -m pytest tests -v
