<uploaded_files>/app</uploaded_files>

The FIU adapter (the service that talks to Account Aggregators on behalf of a
financial-information user) is returning wrong results for a scattering of
**edge inputs**, even though the project builds clean and its checks pass. The
common thread is the small, deterministic, side-effect-free helpers the adapter
leans on everywhere — the ones that parse identifiers, normalise strings, do a
little date arithmetic and render timestamps. On the ordinary, well-formed
values the system produces for itself the numbers look right; it is only at the
boundaries that they drift.

Two concrete reports from the field:

- **Valid identifiers are being rejected as malformed.** Some perfectly valid
  transaction / consent UUIDs coming back from the Account Aggregator fail the
  adapter's own "is this a valid id" check and the request is turned away as a
  bad request. Slightly different-looking (but still invalid) ids are correctly
  rejected, so the check is *almost* right.

- **Outgoing timestamps show the wrong hour.** Timestamps generated in the
  afternoon sometimes go out reading as the morning of the same day (e.g. a
  13:xx event is stamped 01:xx); the date, minute and second are fine — only
  the hour is off, and only past noon.

These two are not isolated. Several other small helpers in the same family —
the ones that parse an identifier into its parts, decide whether a field is
"empty", and shift a date by a number of units — are subtly wrong in the same
way: correct on the ordinary values the system feeds them, off by a hair on an
exact-edge input (a boundary element, a value that must be normalised first, a
unit that has to land in the right field). Away from those edges everything
behaves, which is why the shipped checks never surface any of it.

This is all pure, deterministic string / date / pattern logic — no persistence,
no external calls. Correct the boundary behaviour so these edge inputs are
handled right, without changing behaviour anywhere the current checks already
pin. The project's checks pass now and must stay passing; correctness on the
edge/boundary inputs is the bar.

Do not add or modify anything under `src/test/`.

Verify the build with:

    cd /app && mvn -o -q -pl webservice test
