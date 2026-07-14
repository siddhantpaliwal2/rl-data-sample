<uploaded_files>/app</uploaded_files>

The loan-intake backend returns wrong answers for certain borrower inputs even
though nothing in the app is obviously broken and the routine flows behave
normally. The wrong results cluster around **exact threshold values and edge
cases** — a figure sitting precisely on a published limit, a set of inputs
right at the minimum size that a rule is supposed to accept, a value that is
legitimately zero, or an action taken exactly at a cutoff. Away from those
edges the behavior is correct, which is why the everyday paths (they feed
values comfortably inside the ranges) never surface the problem.

Concretely, the following user- and API-level symptoms have been reported:

- A borrower whose requested amount lands **exactly on a product's advertised
  minimum or maximum** is turned away, even though the stated limits are
  supposed to be allowed amounts, not the first rejected ones.
- The helper that decides whether a group of still-needed fields should be
  gathered with a structured form **declines to offer the form when the number
  of fields it covers is right at the minimum** the rule documents as
  sufficient; it only offers the form once there are strictly more.
- The progress indicator that reports how much applicant information has been
  collected **fails to credit a field whose supplied value is zero**, treating
  a real, deliberately-zero answer as if it had never been provided.
- The one-time-passcode check **lets a guess through one time too many** after
  the failed-attempt limit has been reached, instead of locking out at the
  limit.

The affected code is the deterministic, side-effect-free arithmetic and
comparison logic in the loan-intake and verification helpers — the pieces that
validate amounts, match needed fields to forms, tally collection progress, and
guard passcode verification. These are pure input/output functions; the bugs
are in how the boundaries themselves are handled (inclusive vs. exclusive
comparisons, a truthiness test where a presence test is meant, an off-by-one
guard). Correct the boundary handling so these helpers are right on the exact-
threshold and edge inputs, without changing behavior anywhere the routine paths
already rely on. Existing behavior must be preserved; correctness on the
edge/boundary inputs is the bar.

Do not modify anything under `tests/`.
