<uploaded_files>/app</uploaded_files>

The native trading client renders many small values — market sizes, price
changes, timestamps, wallet identifiers, user-entered contact details — through
one shared set of display and validation helpers. Users have started reporting
that some of these come out wrong, but only at very specific inputs: the
outputs are correct across the normal range and misbehave only when an input
lands **exactly on a boundary** the formatting logic reasons about.

The affected code is the display-formatting and input-validation utilities in
`lib/formatters.ts`. These are pure, side-effect-free functions, and the wrong
results cluster around exact-threshold and edge cases — for example a value
sitting precisely on a magnitude cutoff so it renders in the wrong form, or an
input that is well-formed only up to a point yet is still accepted. Away from
those edges the outputs are correct, which is why the module's existing tests —
they feed values that sit comfortably inside the ranges — stay green and never
surface the problem.

The defects are in how the boundaries themselves are handled: the comparisons,
cutoffs, and match scopes that decide which branch or representation applies at
the exact edge. Read the boundary logic across these helpers and correct it so
they are right on the exact-threshold and edge inputs, without changing
behavior anywhere the current tests already pin. The repository's existing
tests all pass and must stay passing; correctness on the edge/boundary inputs
is the bar, and "green locally" is not enough to know you are done.

Do not modify anything under `test/` or `tests/`.

Verify the existing suite still passes with:

    cd /app && bun test test/formatters.test.ts
