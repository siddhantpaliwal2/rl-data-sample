# Reference plan — latent-doc-scoring

## Construction (LATENT-BUG pattern)

Base is the clean `loangenus` repo at commit `04b8abc`. The environment
Dockerfile builds from the warm repo image (`loangenus-repo:v1`), resets to base,
plants five single-token boundary slips into three pure, deterministic document
modules, then collapses git history (`rm -rf .git && git init`) so the planted
state is not recoverable via `git diff`/`git log`/reflog. The agent starts from
base+defects. There is **no failing test** pointing at any defect: the visible
suite is byte-for-byte green versus clean HEAD (same 7 pre-existing rot
failures). The suite driving table_text (`test_document_layout_extraction.py`)
stays green, the suite driving builders (`test_document_report.py`) keeps only
its one pre-existing rot failure, and the suite driving portfolio
(`test_bridge_broadway_extraction.py`) is skipped in-image — because every
planted slip only bites an exact-boundary input those tests never feed.

The graded tests (`tests/test_document_scoring_boundaries.py`) are injected only
at grade time from `config.json`'s `test_patch`; they feed exactly the edge
inputs the defects corrupt and assert the correct outputs.

## Cluster & disjointness

Cluster: `agent/documents/**` — `extraction/table_text.py` (layout),
`report/builders.py` (report), `deal_summary/portfolio.py` (portfolio
aggregation). All three import cleanly offline (table_text/portfolio are
stdlib-only; builders adds pydantic via report.schemas and transitively loads
settings/qdrant/beanie at import, which works with the baked `JWT_SECRET_KEY` and
no network). Deconflicted from the concurrent builder loan6 (who owns
`document_qa/retrieval.py` + `service.py` — NOT touched here) and disjoint from
every banked sibling: latent-doc-extractors (extractors/cre_fields.py),
latent-credit-normalize (credit_pdf/*), latent-financial-tools
(analytics/services/*), latent-market-structure (services/cre_qualification/*),
latent-phone-invites (cartesia/phone.py, smbcontacts/loan_types.py). Avoids
loan6's document_qa + voice/call cluster and the used ingestion/ subtree.

## Defects planted (file : boundary : the edge ordinary inputs never feed)

1. `extraction/table_text.py` `last_amount_in_text` — zero-amount inclusion
   `value >= 0` tightened to `> 0`. A $0.00 amount is discarded (returns None);
   surfaces one call-hop up as a missing `closing_balance` in
   `extract_bank_statement_fields`. Pinned by "0.00 is a valid amount" + a
   sign-free money regex. MEDIUM, with distance.

2. `extraction/table_text.py` `build_table_grid` — column index bound
   `0 <= col_idx < column_count` made `<= column_count`. A cell at
   `column_index == column_count` is no longer skipped and raises IndexError.
   Pinned by the adjacent grid construction `range(column_count)`. EASY.

3. `report/builders.py` `_build_tax_report` — chart gate
   `len(chart_points) >= 2` raised to `> 2`. A two-amount tax report renders no
   comparison chart. Pinned by five sibling chart gates that all use `>= 2`.
   EASY.

4. `report/builders.py` `_cards_from_numeric_facts` — card-return cap
   `len(cards) >= limit` loosened to `> limit`. Returns limit+1 cards. Pinned by
   the `limit` parameter's max-count semantics (append-then-check off-by-one).
   MEDIUM.

5. `deal_summary/portfolio.py` `merge_portfolio_property` — occupancy-weight
   division guard `if occ_weight > 0` widened to `>= 0`. When no property has
   occupancy/square-footage the weight is 0 and `occ_weighted / occ_weight`
   raises ZeroDivisionError. Pinned by the guard-before-divide on the very next
   line. MEDIUM.

## Oracle fix

`solution/solve.sh` reverses each planted slip via a unique-substring Python
replacement (robust to whitespace; each edit asserts `count == 1`), restoring
the inclusive `>= 0`, `< column_count`, `>= 2`, `>= limit`, and `> 0` boundaries.
Any equivalent boundary correction also passes (the constants and control flow
are pre-existing and untouched).

## Verifier design

- `tests/test.sh` (verbatim from the proven loangenus contract) applies
  `test_patch` from verifier-controlled config, runs `run_script.sh`, parses
  per-test verdicts, and awards reward 1 only if every `fail_to_pass` and
  `pass_to_pass` test passed.
- `fail_to_pass` = 5 gold boundary tests (one per defect; fail at base+defects,
  pass once the boundaries are corrected).
- `pass_to_pass` = 10 tests that pass throughout — the just-off-edge cases
  (nonzero/positive amounts, in-bounds and last-valid-column cells, one/three
  -amount reports, at/below the card cap, a weighted average with nonzero weight
  and a non-appraisal merge) — the "green locally" lull.
- `run_script.sh` runs the single gold file.

## Fairness

- All three defected modules are live document-intelligence code (Azure-table
  extraction, per-type report assembly, portfolio aggregation), not dead paths.
- The instruction names the three module files and the boundary/edge symptom
  class but not the functions, the boundary directions, the trigger values, or
  the count — the agent must read and reason about the math to locate and
  correct each slip.
- Every gold test uses pure literal inputs (only a SimpleNamespace cell stand-in
  with explicit attributes) and asserts pre-existing output values; no test
  encodes an oracle-specific implementation choice, and no mocks are used.
- Deterministic, offline, no secrets. Verified: git history len 1, diff empty,
  visible suite byte-identical to clean HEAD (0 new failures); null reward 0
  (5 f2p FAILED, 10 p2p PASSED); oracle reward 1 (15/15); partial (2 of 5)
  reward 0.
