# Reference plan — loangen-agent-multibug (planted-defect / forge style)

## Design

Base = current HEAD of loangenus, `04b8abc5515c22bdb7a2da32bf2719c8ac702174`.
Fifteen single-line defects are planted across ten well-tested source modules
(eight subsystems). Each defect keeps types and signatures intact, raises no
exception on the happy path, and produces a wrong value only on specific inputs.
Together they flip **21** existing tests red across the ten selected test files;
**35** tests in the same files stay green as canaries. The instruction is terse
and gives no per-defect localization beyond the ten-file edit allowlist — the
difficulty comes from breadth, not from any single hard bug.

The defects live in the image as a dirty working tree (applied via
`git apply` in the Dockerfile, nothing committed). The oracle simply
reverse-applies the same patch.

## Planted defects

| ID | File | Function | Change | Flips (test id) |
|----|------|----------|--------|-----------------|
| D1 | cre_qualification/facts.py | resolve_construction_budget | `spent + remaining` → `spent - remaining` (spent+remaining fallback) | test_oak_hill_qualification::test_construction_budget_is_spent_plus_remaining |
| D2 | cre_qualification/facts.py | resolve_liquid_assets | `abs(direct - total_assets) < 1` → `> 1` | test_bridge_broadway_qualification::test_liquid_assets_rejects_total_assets_mistake |
| D3 | cre_qualification/required_docs.py | normalize_document_type | `rsplit(".", 1)[-1]` → `[0]` | test_required_docs::test_normalize_enum_style_type |
| D4 | cre_qualification/required_docs.py | _upload_satisfies | `equivalents & uploaded_types` → `equivalents <= uploaded_types` | test_required_docs::test_rehab_budget_satisfies_construction_budget |
| D5 | cre_qualification/lender_match.py | product_matches_application_loan_type | `category == "conventional"` → `category == "sba"` | test_lender_product_match::test_term_matches_business_term_loan_only, ::test_term_still_matches_when_cre_collateral_present; test_bridge_broadway_qualification::test_term_construction_matches_only_term_product, ::test_bridge_application_product_fit; test_oak_hill_qualification::test_oak_hill_term_app_filters_non_matching_products |
| D6 | credit_pdf/bureau_router.py | _assign_tradelines | `if bureau in tags` → `if bureau not in tags` | test_credit_pdf_pipeline::test_assigns_tagged_tradeline_to_one_bureau |
| D7 | credit_pdf/junk_filter.py | _JUNK_CREDITOR_PATTERNS | `^past\s+due\b` → `^past\s+owed\b` | test_credit_pdf_pipeline::test_rejects_past_due_label |
| D8 | credit_pdf/junk_filter.py | _JUNK_CREDITOR_PATTERNS | `^\[Table\s+\d+` → `^\[Tabel\s+\d+` | test_credit_pdf_pipeline::test_rejects_table_artifact_creditor |
| D9 | documents/extractors/cre_fields.py | extract_rent_roll_fields | `occupied / int(total_units)` → `int(total_units) / occupied` | test_cre_field_extraction::test_rent_roll_occupancy |
| D10 | documents/extractors/cre_fields.py | extract_hud_fields | `val < _MIN_HUD_LOAN_AMOUNT` → `val > _MIN_HUD_LOAN_AMOUNT` | test_cre_field_extraction::test_hud_loan_amount |
| D11 | documents/extractors/cre_fields.py | extract_appraisal_fields | label `"as-is value"` → `"as-was value"` | test_cre_field_extraction::test_appraisal_extracts_as_is_value |
| D12 | cre_qualification/recommendation.py | resolve_recommendation | `return _REVIEW` → `return _INSUFFICIENT` | test_qualification_recommendation::test_review_band |
| D13 | smbcontacts/loan_types.py | resolve_loan_type | label branch `return choice["id"]` → `return choice["label"]` | test_smb_contacts_csv_and_update::test_resolves_label |
| D14 | smbinvites/schemas.py | CreateInviteRequest.validate_loan_type_id | `if not resolved:` → `if resolved:` | test_smb_invite_schemas::test_accepts_valid_loan_type_id, ::test_rejects_unknown_loan_type_id |
| D15 | integrations/cartesia/phone.py | _CRM_FALLBACK_REGIONS | tuple drops `"IN"` | test_smb_contacts_csv_and_update::test_try_normalize_indian_number_without_country_code, ::test_updates_mobile_with_international_number |

Note D5 is intentionally the highest-fan-out defect: the wrong product-category
gate breaks term-loan matching, which the two engine integration tests
(`test_oak_hill_...`, `test_bridge_application_product_fit`) also depend on, so a
fix must be verified against the engine path, not just the `lender_match` unit
tests.

## Restore mechanism (oracle)

`solution/solve.sh` reverse-applies the identical defect patch
(`git apply -R`, canonical double-heredoc check+apply). Reversing the 15 hunks
restores every file byte-for-byte to base, returning the selected suite to
56/56 green (and the full repo suite to its 166-green baseline).

## Anti-tamper (test_patch) mechanism

The gold tests already exist in the repo at base. `tests/test.sh` therefore does
NOT add them; instead, before grading it runs
`git checkout <BASE> -- loangen-agent/tests/`, which discards any edit the agent
made under `tests/` while leaving the agent's non-test source fixes intact. It
then applies `test_patch` — a trivial one-line comment added to
`tests/test_required_docs.py` — purely to keep the patch-apply plumbing
exercised and non-empty. An agent that weakens or deletes an f2p test gains
nothing: the pristine test is restored and re-run. Verified: tampering
`test_review_band` to `return` still yields a red verdict at the original
assertion line and reward 0.

## Environment

No task-specific env vars are required — the ten selected test files are pure /
mocked and pass with 56/56 on the clean base image with no ENV block. The four
env-dependent suites (test_inbound_calls, test_document_ingestion_readiness,
test_ingestion_stale_recovery, test_document_report) are excluded from
`selected_test_files_to_run` and from both test lists.

## Verification results

| Scenario | Command | Result |
|----------|---------|--------|
| Clean base | run 10 files at 04b8abc, no defects | 56 passed |
| NULL | `test.sh` on defect image | required passed 35/56, **reward 0** (all 21 f2p red) |
| ORACLE | `solve.sh && test.sh` | required passed 56/56, **reward 1** |
| PARTIAL | fix 3 files (junk_filter, phone, recommendation) then `test.sh` | required passed 40/56, **reward 0** |
| TAMPER | neuter `test_review_band`, then `test.sh` | test restored, **reward 0** |

## Fairness note

Every f2p test fails solely because of a planted single-line defect in a listed,
editable source file, and passes once that line is restored to its base value; no
f2p assertion depends on the task environment. All 15 defects are individually
test-caught, and because reward requires every f2p to pass, any partial fix
scores 0. The 35 p2p canaries share files with the defects, so an agent cannot
pass by blanket-rewriting a module.
