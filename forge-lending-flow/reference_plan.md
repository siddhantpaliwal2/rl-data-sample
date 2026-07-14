# Reference plan — forge-lending-flow (planted-defect / forge style, author only)

Not shown to the agent. Hardened construction per CONSTRUCTION_V2 (defects buried
in a fresh single commit; failing gold tests deleted from the image and restored
only through the verifier test_patch; symptom-only instruction).

## Design

Base = current HEAD of loangenus, `04b8abc5515c22bdb7a2da32bf2719c8ac702174`.
Nine natural-looking logic slips are planted across the CRE qualification flow —
four modules under `agent/services/cre_qualification/` plus one adjacent upstream
extractor that feeds facts into the flow. Types and signatures are unchanged; the
code still runs and only produces wrong values on specific inputs. Together they
flip **12** existing tests red across seven gold test files; **21** tests
(canaries in those files plus stable engine/PDF integration files) stay green.

Difficulty comes from breadth (12 f2p over 5 source files), one interacting
defect pair on the construction-budget path, and one distance defect whose only
symptom is an engine-level verdict two call-hops downstream.

## Planted defects

| ID | File | Function | Change | Role |
|----|------|----------|--------|------|
| 1 | cre_qualification/facts.py | resolve_liquid_assets (guard) | `abs(direct - total_assets) < 1` → `> 1` | breadth |
| 2 | cre_qualification/facts.py | resolve_liquid_assets (PFS summation) | `total += amount` → `total = amount` | **distance** |
| 3 | cre_qualification/facts.py | resolve_construction_budget (remaining source) | `get_fact("remaining_budget")` → `get_fact("costs_to_complete")` | **interaction B** |
| 4 | cre_qualification/facts.py | resolve_construction_budget (fallback total) | `spent + remaining` → `spent - remaining` | **interaction A** |
| 5 | cre_qualification/lender_match.py | product_matches_application_loan_type | `category == "conventional"` → `"sba"` | breadth (high fan-out) |
| 6 | cre_qualification/required_docs.py | normalize_document_type | `rsplit(".", 1)[-1]` → `[0]` | breadth |
| 7 | cre_qualification/required_docs.py | _upload_satisfies | `equivalents & uploaded_types` → `equivalents <= uploaded_types` | breadth |
| 8 | cre_qualification/recommendation.py | resolve_recommendation | `return _REVIEW` → `return _INSUFFICIENT` | breadth |
| 9 | documents/extractors/cre_fields.py | extract_appraisal_fields | label `"as-is value"` → `"as-was value"` | breadth (upstream) |

### Interaction pair (defects 3 + 4), construction-budget data path

Both live in `resolve_construction_budget`. The gold test supplies
`{"spent_to_date": 183_750, "remaining_budget": 107_000}` and expects `290_750`.

- Both planted → `remaining` reads `costs_to_complete` (absent) → `None`, so the
  `spent + remaining` branch is skipped entirely → returns `None`.
- Fix only defect 4 (`-` back to `+`) → `remaining` is still `None` → still `None`. FAIL.
- Fix only defect 3 (key back to `remaining_budget`) → hits `spent - remaining`
  = `76_750`. FAIL.
- Fix both → `290_750`. PASS.

Fixing either alone changes the failure mode (None ↔ wrong number) rather than
clearing it. Verified in-image, all four combinations.

### Distance defect (defect 2), liquidity-ratio verdict

`resolve_liquid_assets`'s PFS line-item summation is only reached when there is no
direct `liquid_assets`/`pfs_cash` fact — i.e. when cash is spread across line
items. Changing `total += amount` to `total = amount` makes the sum equal only the
last matching account. The direct unit test for this function
(`test_liquid_assets_rejects_total_assets_mistake`) takes the `pfs_cash` branch and
does **not** catch it. The only test that fails is the engine integration test
`test_liquidity_ratio_when_pfs_and_loan`, which asserts `liquidity_ratio ≈ 0.2`
computed inside the sponsor intelligence head — two call-hops downstream
(`run_qualification_engine` → sponsor builder → `resolve_liquid_assets`). Verified:
applied alone, only that engine test fails.

## fail_to_pass (12, spanning 5 source files)

- test_cre_qualification.py::…::test_liquidity_ratio_when_pfs_and_loan  (defect 2, distance)
- test_oak_hill_qualification.py::…::test_construction_budget_is_spent_plus_remaining  (defects 3+4, interaction)
- test_oak_hill_qualification.py::…::test_oak_hill_term_app_filters_non_matching_products  (defect 5)
- test_bridge_broadway_qualification.py::…::test_bridge_application_product_fit  (defect 5)
- test_bridge_broadway_qualification.py::…::test_liquid_assets_rejects_total_assets_mistake  (defect 1)
- test_bridge_broadway_qualification.py::…::test_term_construction_matches_only_term_product  (defect 5)
- test_qualification_recommendation.py::…::test_review_band  (defect 8)
- test_lender_product_match.py::…::test_term_matches_business_term_loan_only  (defect 5)
- test_lender_product_match.py::…::test_term_still_matches_when_cre_collateral_present  (defect 5)
- test_required_docs.py::…::test_normalize_enum_style_type  (defect 6)
- test_required_docs.py::…::test_rehab_budget_satisfies_construction_budget  (defect 7)
- test_cre_field_extraction.py::…::test_appraisal_extracts_as_is_value  (defect 9)

Defect 5 (product category gate) is the highest fan-out: it breaks two unit tests
plus three engine integration tests, so a fix must be validated through the engine
product-fit path, not just the `lender_match` unit tests.

## pass_to_pass (21)

18 canaries in the seven restored gold files (they share files with the defects, so
an agent cannot pass by blanket-rewriting a module) + 3 stable tests from two
untouched engine/PDF integration files (`test_qualification_report_pdf.py`,
`test_oak_hill_extraction.py`) that exercise the whole flow end to end.

## Hidden construction (rules 1–2)

- `environment/Dockerfile`: `FROM loangenus-repo:v1`; reset to base; `git apply`
  the source-only defect patch; `rm -f` the seven failing gold test files; then
  `rm -rf .git && git init -qb main && … && git commit -qm "import codebase"`.
  In-image: `git log --oneline | wc -l == 1`, `git diff` empty, gold test files
  absent, and the remaining pytest suite carries only the repo's 7 pre-existing
  env-gated failures (test_inbound_calls / ingestion / document_report — unrelated
  to CRE and red on the clean base too), i.e. the defects add zero new failures.
- `tests/config.json` `test_patch` restores the seven gold files verbatim as
  full-file adds; `test.sh` `rm -f`s any agent-created same-named file before
  applying, so tampering with tests is impossible.

## Restore mechanism (oracle)

`solution/solve.sh` reverse-applies the identical source defect patch
(`git apply -R`, canonical double-heredoc check+apply). Reversing the nine hunks
restores every file to base and returns the selected suite to 33/33 green.

## Verification (all in docker, silver-task-forge-lending-flow)

| Scenario | Result |
|----------|--------|
| Clean base, 10 CRE files | 33 passed / 10 skipped, no env |
| In-image leak | git history len 1, git diff empty, gold tests absent |
| NULL (planted) | required passed 21/33, **reward 0**, all 12 f2p FAILED (per-test lines) |
| ORACLE (solve.sh) | required passed 33/33, **reward 1** |
| PARTIAL (fix 5 of 9, facts.py left) | required passed 30/33, **reward 0** (distance + interaction + guard still red) |
| Interaction | fix-A-only FAIL, fix-B-only FAIL, fix-both PASS |
| Distance | defect 2 alone flips only the engine liquidity test; direct unit test still green |
| Full-suite delta | base 7 fail / planted+deleted 7 fail (identical env-gated set) |

## Fairness note (rule 4)

Every f2p fails solely because of a planted logic slip in an editable source file
and passes once that line is restored; no f2p assertion depends on task env (none
is set). The gold tests are the repository's own tests, restored verbatim — they
assert observable behavior (a budget value, a liquid figure, a matched product name,
a recommendation band, a normalized type, an extracted amount) using SimpleNamespace
/ typed fakes with explicit attribute values and `LoanProductCriteria`, never a bare
`MagicMock` patched at a consumer module, so no near-correct implementation crashes
on a mock. The alternative-implementation audit holds: each assertion pins a value or
a name, not the oracle's control flow, so a materially different correct fix still
passes.

## rule-3 litmus

The instruction is a symptom report: no file paths, module or function names, defect
counts, "single-line" hints, thresholds, or field contracts. A strong dev can narrow
each symptom to a subsystem (that is inherent to any honest bug report), but cannot
locate the nine specific lines without investigation — the construction-budget symptom
hides a two-line interaction (fixing the obvious sign leaves it blank), the liquidity
symptom hides two distinct bugs in one function plus a two-hop trace from the ratio to
the summation, and neither the per-file defect multiplicity nor the exact lines are
stated. An agent that fixes only the literal reported example fails multiple hidden
tests.
