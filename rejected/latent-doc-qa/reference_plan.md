# Reference plan — latent-doc-qa

## Naming / cluster / ownership note

The task was originally slugged `latent-voice-calls`, but the voice/telephony
surface proved to be almost entirely async orchestration with too few pinned
pure-math sites for five no-convention-pick defects. The team lead approved a
pivot to the **document Q&A** cluster (`agent/documents/document_qa/`), which is
fully synchronous, hermetic, and dense with pinned boundary math, and scoped this
task to `document_qa/` **exclusively** (a sibling builder, corr2, owns the other
documents sub-clusters — layout/report/intelligence, extraction/table_text,
deal_summary — with no overlap). `service.py` in `document_qa/` is async
(settings + Qdrant + Mongo) and not hermetically testable, so all five defects
live in `retrieval.py`, which imports only `re` + typing. The cluster is DISJOINT
from every prior loangenus task (used document files were
`documents/extractors/cre_fields.py` and `documents/credit_pdf/*`). Deliverable
slug: `latent-doc-qa`.

## Construction (LATENT-BUG pattern)

Base image is the clean HEAD of loangenus (`04b8abc`). The environment Dockerfile
resets to that commit and applies a small **defect patch** that plants five subtle
boundary errors in the deterministic term/label/scoring math of the document Q&A
hybrid-retrieval helpers. The agent starts from base+defects. There is **no
failing local test** pointing at any defect: the full existing suite stays green
with the defects present (7 failed / 166 passed / 24 skipped — identical to clean
HEAD, the 7 being pre-existing rot), because every visible test either never
exercises the affected path or feeds values that sit safely away from the exact
edge that bites.

The gold tests (`tests/test_document_qa_boundaries.py`) are injected only at grade
time from `config.json`'s `test_patch`. They feed exactly the edge inputs the
defects corrupt and assert the correct outputs.

## Defects planted (all in document_qa/retrieval.py : function : boundary : shape : derivability)

1. `extract_search_terms` — minimum capitalized-phrase length `len(phrase) >= 5`
   tightened to `> 5`. The shortest two-word capitalized phrase (5 chars, e.g.
   "My Co") is dropped. Shape: operator `>=`/`>`. DERIVABLE (medium): the
   capitalized-sequence regex cannot produce a match under 5 chars, so `>= 5`
   admits every real match; requires regex-minimum reasoning.

2. `extract_labeled_amounts` — minimum label length `len(label) < 3` widened to
   `<= 3`. An exactly-3-char label (e.g. "NOI") is discarded. Shape: operator
   `<`/`<=`. DERIVABLE (easy): the module's `_LABELED_AMOUNT_RE` label group
   `.{3,80}` sets the min to 3, and the left-correct quoted-phrase sibling `>= 3`
   confirms 3 as the minimum meaningful length.

3. `merge_hybrid_hits` — duplicate-chunk dedup `existing.vector_score = max(...)`
   changed to `min(...)`. A chunk surfaced by two signals keeps its weaker score.
   Shape: `max`->`min` function swap. DERIVABLE (medium): the adjacent sibling
   line merges `keyword_score` with `max(...)` (left correct); the two must be
   symmetric, and RRF dedup keeps the strongest evidence.

4. `extract_labeled_amounts` — fact-count cap `len(facts) >= limit` widened to
   `> limit`. Collects `limit + 1` facts instead of exactly `limit`. Shape:
   operator `>=`/`>`. DERIVABLE (medium): `limit` is the maximum number of facts;
   once the set holds `limit` entries collection must stop, so the guard breaks at
   `>= limit`.

5. `extract_search_terms` — minimum search-term length `len(w) >= 3` tightened to
   `>= 4`. Three-letter terms (LTV, ROI, NOI, DTI) are dropped from keyword terms.
   Shape: threshold value 3->4. DERIVABLE (easy): the sibling quoted-phrase
   threshold `len(phrase) >= 3` (left correct) uses 3 as the minimum meaningful
   token length, and a 3-letter acronym is unambiguously a real search term.

## Difficulty audit

2 EASY (D2, D5) + 3 MEDIUM (D1, D3, D4). All single-token edits on existing lines,
no new imports/helpers/comments, across five statements in three functions. Edit
shapes: `>=`/`>` (D1), `<`/`<=` (D2), `max`->`min` (D3), `>=`/`>` (D4), value 3->4
(D5). Two share the `>=`/`>` shape-type but sit on different expressions,
functions and derivations (phrase length pinned by regex-minimum vs fact-count cap
pinned by limit-semantics), so no single grep collapses them — the approved
latent-financial-tools likewise shipped two `<`/`<=` and two value-changes. Two
in-file anchors are left CORRECT to pin the defects: the quoted-phrase `>= 3`
(pins D2 and D5) and the keyword-score `max` (pins D3).

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch (doubled-heredoc), restoring
`>= 5`, `< 3`, `max(...)`, `>= limit`, and `>= 3`. Any equivalent boundary
correction also passes the gold tests.

## Verifier design

- `tests/test.sh` (verbatim canonical) applies `test_patch` from verifier
  controlled config, runs `run_script.sh`, parses per-test verdicts, and awards
  reward 1 only if every fail_to_pass and pass_to_pass test passed.
- `fail_to_pass` = 5 gold boundary tests (one per defect, disjoint), failing at
  base+defects and passing once the boundaries are corrected.
- `pass_to_pass` = 11 gold tests pinning the just-off-edge behavior adjacent to
  each defect (four/two-char terms; six/eighteen-char phrases; four/two-char
  labels; all-facts-under-limit and limit-equal-to-count; keyword dedup / single /
  distinct chunks) — all pass at both the planted and fixed states.
- `run_script.sh` runs only the gold file; every f2p and p2p node lives there.

## Verification ladder (all run in-image)

- Leak: git history len 1, git diff empty, git status clean, gold file absent from
  the agent tree.
- Visible suite green: 7 failed / 166 passed / 24 skipped at base+defects, byte
  identical to clean HEAD (0 new failures).
- NULL (planted, no fix): reward 0; all 5 f2p report FAILED per-test (no collection
  errors); 11/16 required passed.
- ORACLE (solve.sh): reward 1; 16/16 passed.
- PARTIAL (revert 2 of 5): reward 0; 13/16 (the 3 unfixed f2p still fail).

## Fairness

- All five defected sites are live retrieval code: `extract_search_terms` feeds the
  Mongo keyword search, `extract_labeled_amounts` feeds PFS fact extraction, and
  `merge_hybrid_hits` performs the reciprocal-rank-fusion of vector + keyword hits.
- The instruction names the domain and the `document_qa/retrieval.py` module plus
  three prose symptom examples; it gives no function names, boundary directions,
  trigger values, defect count, or defect shape.
- Deterministic, offline, no secrets beyond the baked JWT_SECRET_KEY. `retrieval.py`
  imports only `re` + typing (no settings/DB/embedding/vector-store). The gold
  tests are pure-input with zero mocks, so no oracle implementation choice is
  encoded.
