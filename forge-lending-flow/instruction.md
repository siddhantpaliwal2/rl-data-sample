<uploaded_files>/app</uploaded_files>

# CRE deal qualification is returning wrong verdicts across the flow

## Context

Our lender-facing commercial-real-estate qualification flow scores a deal end to end: it
pulls structured facts out of the uploaded documents (appraisals, rent rolls, personal
financial statements, HUD statements, credit reports), builds the sponsor and property
picture, decides which of the lender's catalog products the deal fits, checks the required-
document / conditions checklist, and prints an overall recommendation. Since the last
release, loan operations and two lenders have reported a cluster of wrong outputs in this
flow. Nothing errors out — the numbers and verdicts just come back wrong on particular
deals. Their reports are below.

## What operations is seeing

**Product matching.** Term-loan applications no longer surface our conventional term product.
On a plain "term" request the product-fit list comes back empty or shows only unrelated
products — the borrower's own term product is dropped — while SBA-only products are turning up
as matches for term requests. (CRE / real-estate deals still match the real-estate product
correctly; this is specific to term requests.)

**Construction / rehab budget.** Deals with a rehab or construction component are showing the
wrong total project budget. A deal with $183,750 already spent and $107,000 left to complete
shows no total budget at all, and a couple of other rehab deals are reporting a "total" that is
actually smaller than what the borrower has already spent. The total should be what's been
spent plus what's left to complete.

**Sponsor liquidity.** Two separate complaints. On a PFS where the import had mistakenly copied
the whole balance-sheet total into the liquid line, we are now crediting the sponsor with their
entire asset base as liquidity — one sponsor with roughly $615K of actual cash is showing about
$14.8M liquid. And on statements where the cash is spread across several accounts (checking,
savings, marketable securities), the liquidity ratio only reflects one of those accounts, so it
comes out far too low.

**Required-document checklist.** The conditions checklist is flagging documents as still missing
when they were actually provided. A property appraisal uploaded under its formal, fully-qualified
type label is not being recognized as an appraisal. And an uploaded rehab budget no longer clears
the construction-budget line, even though either of those documents should satisfy it.

**Recommendation band.** Mid- and low-scoring deals are now coming back as "Insufficient Data" on
the recommendation hero, where they used to read "Review Required." (Deals that genuinely have no
score should still read "Insufficient Data" — that part is right.)

**Appraisal value capture.** Appraisals that state the value on a labeled line such as
"As-Is Value: $1,250,000" are not having that figure captured at all, so it drops out of the
downstream collateral picture.

## Expected outcome

Restore the intended behavior across the qualification flow: term applications match the
conventional term product and not SBA; rehab/construction deals report spent-plus-remaining as the
total budget; sponsor liquidity reflects real cash — not the entire balance sheet, and summed across
all liquid accounts; provided or equivalent documents satisfy the checklist; the recommendation band
reads correctly for mid and low scores; and labeled "As-Is Value" figures are captured.

## Testing

The qualification flow is exercised by the backend unit suite, which is hermetic — no database,
queue, or external service is required. Run it from `/app/loangen-agent`:

    cd /app/loangen-agent && python -m pytest tests -v
