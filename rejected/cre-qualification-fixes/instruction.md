<uploaded_files>/app</uploaded_files>

# Lender qualification recommendation does not follow the deal score

## Issue details

The lender CRE (commercial real estate) qualification analysis produces a numeric
`deal_score` (0-100) plus a headline "recommendation" that is shown to lenders in
two places: the qualification hero banner in the web UI and the cover of the
generated PDF qualification report. Underwriting has reported two problems with
that headline on the `loangen-agent` backend:

1. **The headline recommendation ignores the deal score.** The hero and the PDF
   cover are driven by the rules-based `decision` action (proceed / decline /
   manual_underwriting / insufficient_data) rather than by the deal score, so a
   deal that scores in the low 80s can still surface a cautious or mismatched
   headline. Lenders expect the headline to track the deal score directly and to
   read the same way in the UI and the PDF.

2. **Cached analyses render with no recommendation.** Qualification results are
   persisted/cached as `overall` payloads. Snapshots produced before the
   recommendation existed have no recommendation fields, so when they are
   re-loaded the hero/PDF fall back to a blank or default headline instead of one
   consistent with the stored `deal_score`.

## Expected outcome

Introduce a single deal-score-derived recommendation that the backend computes
and returns on the qualification `overall` object, so the UI hero and the PDF
cover render the same headline.

- Expose the mapping as a module
  `agent.services.cre_qualification.recommendation` with this public API (other
  backend code and the tests import it):
  - `resolve_recommendation(*, deal_score: Optional[float], deal_score_available: bool)`
    returning a display value with attributes `band` (str), `label` (str) and
    `color` (str, a `#RRGGBB` hex string).
  - The mapping from deal score to display, applied in order:

    | condition                              | band                | label             | color     |
    |----------------------------------------|---------------------|-------------------|-----------|
    | score unavailable or `None`            | `insufficient_data` | `Insufficient Data` | `#64748b` |
    | `deal_score >= 80`                     | `strong_proceed`    | `Strong Proceed`  | `#047857` |
    | `deal_score >= 60`                     | `proceed`           | `Proceed`         | `#34d399` |
    | `deal_score >= 40`                     | `manual_uw`         | `Manual UW`       | `#f59e0b` |
    | `deal_score < 40`                      | `review`            | `Review Required` | `#eab308` |

- The `OverallQualificationSchema` (in
  `agent.services.cre_qualification.schemas`) must carry the recommendation as
  three fields — `recommendation_band`, `recommendation_label`,
  `recommendation_color` — and their allowed band values are exactly the five
  above. Constructing/validating an `overall` payload that omits these fields
  (e.g. a cached snapshot) must still yield a recommendation consistent with the
  payload's `deal_score` / `deal_score_available`, not a static default.

- `run_qualification_engine` must populate these recommendation fields on the
  `overall` result so they are consistent with the computed `deal_score`.

- The PDF qualification report cover must display the recommendation `label` and
  `color` for its headline (rather than the raw decision action).

## Affected areas

The CRE qualification subsystem of `loangen-agent`
(`agent/services/cre_qualification/`): the scoring/engine output, the response
schemas, the PDF report builder, and module-level constants. Do not modify
anything under `loangen-agent/tests/`.

## Testing

Run the backend unit test suite from `/app/loangen-agent`:

    python -m pytest tests -v

Tests are hermetic — no database, queue, or external service is required.
