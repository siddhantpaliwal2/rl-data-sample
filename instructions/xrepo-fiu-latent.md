<uploaded_files>/app</uploaded_files>

# Partner escalation digest - FIU adapter interop issues

Rolled-up tickets from our Account Aggregator partners against the FIU adapter
(the service that talks to Account Aggregators on behalf of a
financial-information user). The build is clean and the shipped checks pass, so
none of this is caught before deploy. Both reporters emphasise the same
pattern: ordinary traffic is fine, and the failures key off the *content* of
specific values rather than load, timing, or sequence.

---

**AA partner (ticket #4471):**
> Your adapter is rejecting a subset of our callbacks as `invalid` on the
> transaction / consent identifier, and the rejected ids are well-formed UUIDs -
> canonical form, straight from our generator. Most UUIDs go through. We diffed
> accepted vs rejected ids and cannot see what distinguishes them; whatever
> validity check you run is *almost* right, and genuinely malformed ids are
> still (correctly) refused.

**AA partner (ticket #4488):**
> Separately: your outgoing notification timestamps are wrong in the afternoon.
> An event we both logged at 13:47 UTC arrives stamped 01:47 on the same date.
> Date, minutes, seconds all agree; mornings are fine. Our parser now rejects
> some of your afternoon messages outright.

---

**Triage note (ops):** these two are the ones partners have pinned down, but
our own sweep says they are not isolated. A few more of the adapter's small,
deterministic helpers in the same family - identifier and payload handling,
field validation - drift in exactly the same way: correct on the ordinary
values the system produces for itself, wrong by a hair on one specific edge
form that routine traffic never feeds them. Away from those edges everything
behaves, which is why the shipped checks never surface any of it.

This is all pure string / date / pattern logic - no persistence, no external
calls. Restore correct behaviour on these content-dependent edge inputs without
changing anything on the paths that already behave; the project's checks pass
now and must stay passing.

Do not add or modify anything under `src/test/`.

Verify the build with:

    cd /app && mvn -o -q -pl webservice test
