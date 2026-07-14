<uploaded_files>/app</uploaded_files>

The loan-intake backend produces wrong loan-offer figures for certain borrower
inputs even though nothing in the app is obviously broken and the routine flows
behave normally. The wrong results cluster around **exact threshold values and
edge cases** — a figure sitting precisely on a published band or tier, a value
that is legitimately zero, a shorthand amount whose parsed result lands exactly
on its multiplier. Away from those edges the behavior is correct, which is why
the everyday paths (they feed values comfortably inside the ranges) never
surface the problem.

Concretely, the following user- and API-level symptoms have been reported:

- A figure that sits **exactly on a published band or tier boundary** is handled
  as though it fell on the wrong side of it: a borrower whose credit score
  reaches a rate tier exactly is quoted the next, worse tier's rate instead of
  the tier they actually qualify for, and an applicant whose income lands
  exactly on a scoring band is denied the adjustment that band is supposed to
  grant.
- A **zero-interest** scenario is mishandled — instead of returning the
  straightforward payment (the principal spread evenly across the term), the
  calculation errors out.
- The helper that recognizes **shorthand money amounts** misjudges a correctly
  parsed amount as a *failed* parse when the parsed number lands exactly on the
  shorthand's own value, so a perfectly good conversion is thrown away.
- An amount that legitimately **resolves to zero** is accepted as a real zero
  rather than falling back to the default the code uses for unusable inputs.

The affected code is the deterministic, side-effect-free arithmetic and
comparison logic behind loan-offer generation — the pieces that map a credit
score to a rate band, estimate a score from applicant details, amortize a
payment, normalize free-text money amounts, and screen out unusable parsed
values. These are pure input/output helpers; the bugs are in how the boundaries
themselves are handled (inclusive vs. exclusive comparisons at a band or tier
edge, a special-case guard that no longer matches the value it was meant to
catch, a threshold that is off by the smallest step). Correct the boundary
handling so these helpers are right on the exact-threshold and edge inputs,
without changing behavior anywhere the routine paths already rely on. Existing
behavior must be preserved; correctness on the edge/boundary inputs is the bar.

Do not modify anything under `tests/`.
