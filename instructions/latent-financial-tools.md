<uploaded_files>/app</uploaded_files>

# Incident write-up: financial-summary metrics disagree with source data at the margins

## Issue details

Several of the read-only routines that roll raw bank-feed, credit-bureau, and
accounting exports up into the structured metric blocks on the underwriting
surface are emitting figures that do not match their inputs - but only for a
narrow class of records. Every reproduction gathered so far sits on a margin of
some kind: a quantity landing exactly on a documented cut-off instead of
comfortably past it; a report handed over at the smallest column or period count
the format permits; a collection holding an even pair, so the count itself is
what decides the answer; and a field carrying one of the
reserved "nothing here" placeholder codes that is being echoed back as if it
were a genuine amount. Hand the same routines data sitting well inside the usual
ranges and the numbers come out right, which is why nothing stood out in review.

## Expected outcome

Each metric should agree with what the source record plainly says at these
margins. A value resting on a threshold is handled the way the documented rule
for that threshold states. The smallest well-formed report still yields its
per-period figures. A two-element collection is measured from its actual
contents rather than dismissed as too small. A
reserved placeholder code is discarded, never read as data. Everywhere away from
the margins the output must not move at all.

## Affected areas

The fault is contained in the deterministic, side-effect-free summarization
layer: plain arithmetic, comparisons, and roll-ups over already-parsed bank,
credit, and accounting structures. No database, network, or model component is
in the loop. Each wrong figure traces to how one boundary - or one reserved
value - is treated inside that computation, so the corrections are small and
local.

## Testing notes

The existing automated checks all pass today and must still pass afterward; they
only ever drive mid-range inputs, so they are silent about the margins described
above. Judge the fix on whether the summaries come out correct on the
exact-threshold, minimum-size, single/pair, and placeholder-code cases. Do not
touch anything under the project's `tests` tree.

Reproduce and confirm with:

    cd /app/loangen-agent && python -m pytest tests -v
