<uploaded_files>/app</uploaded_files>

We are chasing a set of edge-case wrong answers a partner bank surfaced while
certifying against our FIU adapter (the middle layer that brokers requests to
Account Aggregators). The module compiles, the existing checks are green, and
ordinary traffic looks fine — the trouble only appears on exact-boundary
values. The escalation thread is reproduced below; treat it as the bug report.

---

**From:** Integration Engineering, partner bank (AA sandbox)
**To:** FIU Connect engineering
**Subject:** Sandbox mismatches — a few derived fields look off

Hi team — wrapping up sandbox certification and we're seeing a handful of small
mismatches that all feel like the same class of bug. Nothing crashes; the values
are just subtly wrong at the edges. Collecting what we've hit so far:

- In the config payload your side returns to our app, the **company-name field
  is coming back with our brand-colour value** (e.g. we get `#0B7A75` where we
  expect `Acme Bank`). The logo and colour fields themselves look right — it's
  only the name that's picking up the wrong source value.

- When we send a **partial update that leaves some optional fields blank**, the
  fields we *did* fill in get dropped, and the blank ones overwrite what was
  already stored. It behaves as if "skip the empty fields" is doing the exact
  opposite — keeping the empties and discarding the filled ones.

- When a notification we post is missing **exactly one** required field, the
  error you return is the generic *"fields are invalid"* response, as if several
  fields were bad. We'd expect the specific single-field message in that case;
  the generic one only seems right once two or more fields are actually missing.

- Separately, some values your side **derives by pulling a piece out of the
  dotted, compact tokens** we exchange are coming back pointing at the wrong part
  of the token — the extracted piece isn't the segment the structure says it
  should be.

- And occasionally a **credential/token that doesn't have the expected number of
  parts** slips through instead of being turned away — a well-formed one's own
  structure makes clear how many parts it must have, so the malformed one should
  be rejected the same way.

Everything else certifies fine. Happy to send exact request/response captures if
useful.

---

**From:** Tech lead, FIU Connect
**To:** Integration Engineering
**Subject:** RE: Sandbox mismatches — a few derived fields look off

Thanks — this is useful, and I think it all traces to one class of code on our
end. Each item you listed goes through one of our tiny internal utilities: the
one that copies a record field-by-field, the ones that slice identifiers and
tokens apart, the piece that tallies how many required fields are missing, and
the routine that assembles the config record we return. On the self-generated,
canonical inputs the service normally runs against, every one of them behaves;
they slip only on the sharp-edged values your certification pushes through,
which is exactly why our regression suite stayed quiet.

I'll have someone tighten up the edge handling so these malformed and boundary
inputs resolve correctly, taking care not to disturb anything the current suite
already locks down.

---

Your job: make the boundary cases above behave correctly. Everything involved is
plain in-process logic (copying, splitting, counting, mapping) with no database
and no outbound calls, so each fix is local. Two hard rules: leave every
behaviour the current checks already lock in exactly as it is, and keep those
checks green — getting the exact-edge inputs right is the whole target.

Leave everything under `src/test/` untouched — add nothing, change nothing there.

Confirm your work compiles and the module's checks still pass with:

    cd /app && mvn -o -q -pl webservice test
