<uploaded_files>/app</uploaded_files>

The credit-report PDF parser keeps or discards the wrong records for certain
borrower and tradeline profiles, even though the whole test suite is green. The
wrong verdicts cluster around **edge inputs that only superficially resemble
another category** — for example a value that matches a "throwaway" list only
when letter case is ignored, a line that looks like another one merely because
it begins the same way, two records that are really the same but were written
with slightly different capitalisation, or a token whose accepted spelling
variants are not all handled. Away from those edges the classification is
correct, which is why the existing tests (they feed ordinary, well-formed
values) never surface the problem: a genuine record is silently thrown away, or
a junk/duplicate record is let through, only at the edge.

The affected code is the deterministic line-classification and text
normalization logic under `loangen-agent/agent/documents/credit_pdf/` — the
creditor-line, bureau-tag and address/contact helpers in `normalize.py`, and the
artifact-rejection and de-duplication helpers in `junk_filter.py`. This is pure,
side-effect-free string and comparison logic; the bugs are in how these helpers
handle the edges (case handling, how much of a line a pattern is allowed to
match, and which recognized forms of a token are covered).

For each slip the intended, correct behaviour is pinned by the surrounding code
— the data the helper compares against, the sibling patterns and helpers right
next to it, and the lookup tables it consults — so which side of the boundary is
right is not a matter of taste; read those neighbours to decide.

Correct the handling so these helpers are right on the edge inputs, without
changing behavior anywhere the current tests already pin. The repository's
existing tests all pass and must stay passing; correctness on the edge inputs is
the bar.

Do not modify anything under `loangen-agent/tests/`.

Verify with:

    cd /app/loangen-agent && python -m pytest tests -v
