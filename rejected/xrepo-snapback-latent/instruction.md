<uploaded_files>/app</uploaded_files>

The shared utility layer of this standup bot returns wrong results for a
handful of inputs, even though its whole unit-test suite is green. The failures
all sit at the *edges* of each helper's input range — the value exactly on a
limit, the wrong side of a conversion, a missing member of an allowed set, a
dropped constraint — which is exactly where the existing tests never look. They
exercise comfortable mid-range values (and the guards they already pin), so the
slips stay invisible to them.

The affected code is the small, dependency-light package of pure helpers under
`packages/shared/src/`: the time helpers in `time.ts`, the date-key helpers in
`dates.ts`, the callback encoder/decoder in `callbacks.ts`, and the `zod`
validators in `schemas.ts`. This is pure, deterministic, side-effect-free logic
— string/date formatting, a small round-tripped encoder/decoder, and schema
validation; the mistakes are all in how the boundaries themselves are handled.

Reported symptoms, from user-facing behavior:

- The time-of-day slot a standup gets filed under comes out wrong for afternoon
  and around-midnight moments — a mid-afternoon check-in is bucketed as if it
  were the small hours of the morning — while morning check-ins look fine.
- The step that plans the *following* day keeps landing on the wrong calendar
  date.
- Tapping one of the standup's inline buttons does nothing: the tap for that
  particular check-in is silently ignored, as if the action were unknown, while
  the other buttons work.
- Validation that is supposed to guarantee well-formed workflow data lets some
  malformed values through: an item with no real name, and a position/index
  that isn't a whole number, are both accepted when they should be rejected.

In each case a correct sibling right next to the defect — or the package's own
type definitions — shows what the intended behavior is. Correct the boundary
handling so these edge inputs produce the right results, without changing
behavior anywhere the current tests already pin. The existing suite passes and
must stay passing; correctness on the edge cases is the bar.

Do not modify the test files (`*.test.ts`) under `packages/shared/src/`.

Verify with:

    cd /app && bun test packages/shared/src/*.test.ts
