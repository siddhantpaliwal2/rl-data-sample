<uploaded_files>/app</uploaded_files>

The link-shortener backend has started returning subtly wrong results for a
handful of requests, even though the service's existing test suite is green.
The wrong behavior only shows up at specific inputs — values that sit right on a
boundary the logic reasons about, or unusual-but-valid inputs the happy-path
tests never send. Away from those cases everything is correct, which is why the
current tests (they use ordinary, comfortably-in-range inputs) never surface any
of it.

The affected code is all under `backend/link_shortener/`, in `config.py`,
`main.py`, and `services.py`. Reported symptoms, filed by different users:

- **Settings parsing.** When the list of authorized parties is supplied as a
  comma-separated string, an item that is empty or only whitespace (for example
  the middle field of `"party-a, ,party-b"`) is kept as a blank entry instead of
  being dropped — a sibling setting parsed the same way does drop it, so the two
  behave inconsistently.

- **Per-user rate limiting.** Requests that authenticate with an
  `Authorization: Bearer <token>` header are occasionally bucketed under a
  rate-limit key that carries a stray leading space in front of the token, so
  the same caller can be split across two different buckets.

- **Stored expiry timestamps.** When a link is created with an expiry given at a
  non-UTC timezone offset, the stored instant is wrong: the wall-clock reading is
  preserved but the offset is thrown away, so a time submitted at, say, +05:30 is
  recorded as though that same clock reading were already UTC (it should be
  converted to the equivalent UTC instant).

- **Listing links, first page.** The first page of a user's links comes back
  missing its most recent entries — page one behaves as though it were a later
  page and skips the newest items that should head the list.

- **Database URL normalization.** When the configured database URL happens to
  embed a second URL (for example a callback parameter) that itself looks like a
  Postgres URL, the driver-normalization step rewrites that embedded occurrence
  too; only the leading connection scheme should be adjusted.

Away from these edges every path is correct, which is why the module's existing
tests stay green and never catch the problem. The bugs are in how the boundaries
and unusual-but-valid inputs are handled — the comparisons, offsets, filters,
and conversions that decide what happens at the edge. Correct that handling so
these behaviors are right on the edge/boundary inputs, without changing behavior
anywhere the current tests already pin. The repository's existing tests all pass
and must stay passing; correctness on the edge/boundary inputs is the bar.

Do not modify anything under `tests/`.

Verify with:

    cd /app && python -m pytest tests
