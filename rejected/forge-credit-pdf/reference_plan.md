# Reference plan — forge-credit-pdf (planted-defect / forge style)

Author-only. Not shown to the agent.

## Design

Base = current HEAD of loangenus, `04b8abc5515c22bdb7a2da32bf2719c8ac702174`.
Seven type-preserving, single-line defects are planted across three source files
in the credit-report PDF pipeline and the CRE structured-field extractor. Each
keeps signatures intact, raises no exception on the happy path, and produces a
wrong value only on specific inputs. Difficulty comes from breadth (15 hidden
f2p across three source files), one interacting pair on a shared data path, and
two distance defects whose symptom appears two call-hops downstream in the
document-intelligence report.

The defects live in the image as a fresh single-commit working tree (applied via
`git apply` in the Dockerfile, then `rm -rf .git && git init … && commit`), so
`git diff`/`git log` reveal nothing. The two existing test files that would go
red are removed in the image and re-introduced verbatim by the verifier's
`test_patch`, alongside a new hidden gold file.

## Planted defects

| ID | File | Function | Change | Role |
|----|------|----------|--------|------|
| D1 | credit_pdf/junk_filter.py | `_JUNK_CREDITOR_PATTERNS` | `^past\s+due\b` → `^past\s+owed\b` | interacting pair (junk) |
| D2 | credit_pdf/bureau_router.py | `_assign_tradelines` | tag branch `if bureau in tags` → `if bureau in active` | interacting pair (router) |
| D3 | extractors/cre_fields.py | `extract_hud_fields` | `val < _MIN_HUD_LOAN_AMOUNT` → `val > …` | distance → HUD report card |
| D4 | extractors/cre_fields.py | `extract_rent_roll_fields` | `occupied / int(total_units)` → `int(total_units) / occupied` | breadth |
| D5 | extractors/cre_fields.py | `extract_appraisal_fields` | label `"as-is value"` → `"as-was value"` | distance → appraisal report card |
| D6 | credit_pdf/junk_filter.py | `_JUNK_CREDITOR_PATTERNS` | `^\[Table\s+\d+` → `^\[Tabel\s+\d+` | breadth |
| D7 | extractors/cre_fields.py | `extract_t12_fields` | derived NOI `egi - opex` → `egi + opex` | breadth |

### Interacting pair (D1 + D2) — one data path

`finalize_parsed_report` pools tradelines through `filter_tradelines` (junk
filter) and then routes them per bureau in `_assign_tradelines`. The gold test
`test_tagged_and_junk_tradelines_resolve_to_single_bureau` feeds a report whose
Experian-tagged tradelines include a leaked "Past Due" artifact and asserts
Experian ends with exactly the real creditor and TransUnion/Equifax with none.
Verified half-fix behaviour:
- fix junk only → Experian correct, but TransUnion still gets the line (router
  over-broadcasts) → still fails.
- fix router only → TransUnion empty, but the junk artifact still sits in
  Experian → still fails.
- both fixed → passes.

### Distance defects (D3, D5) — two hops

The symptom the maintainer observes is a missing headline card in the
document-intelligence report. The cause is in the extractor two hops upstream:
`extract_hud_fields` / `extract_appraisal_fields` (cre_fields.py) →
`extract_structured_fields` (extractors/generic.py) → `build_report_from_facts`
(report/builders.py) → summary card. D3 also flips the other direction: a
mislabeled $9,000 "loan amount" that the plausibility floor should discard is
wrongly surfaced. Gold tests exercise text → structured fields → report card.

## Restore mechanism (oracle)

`solution/solve.sh` reverse-applies the identical seven-hunk defect patch
(`git apply -R`, canonical double-heredoc check+apply). Reversing restores every
file byte-for-byte to base.

## Anti-tamper (test_patch) mechanism

The image ships a single "import codebase" commit with the defects planted and
`test_credit_pdf_pipeline.py` / `test_cre_field_extraction.py` deleted. `test.sh`
restores any tracked test file the agent touched (`git checkout -- tests/`),
removes the three gold-file paths, then applies `test_patch`, which adds all
three gold files (the two deleted files restored verbatim + the new
`test_document_extraction_pipeline.py`) as fresh files. An agent that weakens or
recreates a gold test gains nothing: the pristine versions are what run.

## Verifier

- 15 fail_to_pass across three source files: 3 in `test_credit_pdf_pipeline.py`
  (junk + router), 3 in `test_cre_field_extraction.py` (appraisal/HUD/rent), and
  9 in the new `test_document_extraction_pipeline.py` (interaction, both distance
  report-card tests, HUD reverse-direction, tagged-two-bureaus, rent variant, and
  derived-T12 NOI). An agent that fixes only the literal reported examples still
  fails the permutation and interaction tests.
- 9 pass_to_pass canaries share files with the defects (untagged broadcast, junk
  $1-rule tradeline, real-creditor acceptance, filter-before-assignment, explicit
  T12 NOI) plus a stable untouched file (`test_credit_pdf_upload.py`), so an agent
  cannot pass by blanket-rewriting a module.

## Environment

The image sets `DOCUMENT_INGESTION_ENABLED`/`DOCUMENT_QA_ENABLED` and dummy
Azure/Qdrant/LLM values (copied from the canonical task) so the visible full
suite is at its cleanest baseline. None of the four selected test files require
those vars — credit-PDF, CRE extraction, and the report-builder path all import
and run offline without them; the env block only trims the count of unrelated
pre-existing failures (`test_inbound_calls`, the config-defaults conflict) that
exist at base independent of this task.

## Fairness note

Every f2p fails solely because of a planted defect in an editable source file and
passes once that line is restored; no f2p depends on the task environment. The
gold tests use only real constructors and public functions with explicit values
(no bare-Mock coupling); an alternative correct implementation of any fix passes
them. Because reward requires every f2p to pass, any partial fix scores 0.
