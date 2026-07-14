# Reference plan (author only — not shown to the agent)

Planted-defect (forge) task on the boostmoney `loangenus` repo at HEAD
`04b8abc5515c22bdb7a2da32bf2719c8ac702174`. Six natural, single-line,
type-preserving logic slips across the SMB contacts / invites / phone cluster.
No new public API is introduced by the fix, so the instruction publishes no
module paths or signatures — only user-level symptoms.

## Planted defects (author only)

| id | file | line | slip | fix |
|----|------|------|------|-----|
| D1 | `integrations/cartesia/phone.py` | `_CRM_FALLBACK_REGIONS` | drop `"IN"` from the no-country-code fallback regions | restore `"IN"` |
| D2 | `services/smbcontacts/loan_types.py` | `resolve_loan_type` label-match branch | `return choice["label"]` | `return choice["id"]` |
| D3 | `services/smbinvites/schemas.py` | `CreateInviteRequest.validate_loan_type_id` | inverted guard `if resolved:` | `if not resolved:` |
| D4 | `services/smbcontacts/service.py` | `_apply_csv_row_to_contact` | `contact.mobile == mobile_stored` | `contact.mobile != mobile_stored` |
| D5 | `services/smbinvites/service.py` | `_build_tracking` pending_sources | `... or s not in skipped_sources` | `... and s not in skipped_sources` |
| D6 | `services/smbinvites/service.py` | `_seed_crm_hints` | `"crm_hint_loan_type" in state` | `"crm_hint_loan_type" not in state` |

## Rule-5 structure

- **Interacting pair (D2 + D3) on the invite-create data path.** Loan-type
  validation calls `resolve_loan_type`. When an invite (or contact) supplies a
  *display label* not covered by the alias table (`SBA 7(a) Loan`,
  `SBA 504 Loan`, `SBA Express Loan`, `USDA…`), the resolver reaches its
  label-match branch. With BOTH defects, the request raises (inverted guard sees
  a truthy label). Fix D3 alone and the request now silently stores the raw
  label instead of `sba7a`; fix D2 alone and the (still inverted) guard rejects
  the now-correct id. Only fixing both restores label→id normalization.
  `test_accepts_display_label_loan_type_id` / `_alias` assert this and stay red
  under any single-defect fix (verified: partial fix of D3 alone leaves them
  failing).
- **Distance defect (D1).** The defective line is a module-level region tuple in
  `phone.py`. Its visible symptom appears ≥2 hops away: `create_smb_contact` /
  `update_smb_contact` → `_mobile_from_input_or_error` → `try_normalize_mobile`
  → `try_normalize_phone_to_e164`. Without `"IN"`, `8050306043` normalizes to a
  wrong-country `+49…`/`+1…` instead of `+918050306043`. D2 also manifests at a
  distance through the CSV importer (`import_contacts_csv` →
  `_parse_loan_type_from_csv` → `resolve_loan_type`).
- **Breadth.** 16 fail_to_pass spanning 4 source files (phone, loan_types,
  smbinvites/schemas, smbinvites/service) plus the CSV-mobile bug in
  smbcontacts/service. An agent that fixes only the literal reported example
  (e.g. the invite rejection) fails ≥8 hidden tests.

## Hidden construction

`environment/Dockerfile` resets to base, applies the defect patch, then DELETES
the three repo test files that fail against the plants
(`test_smb_contacts_csv_and_update.py`, `test_smb_invite_schemas.py`,
`test_smb_invite_conversation.py`), then `rm -rf .git && git init` + a single
`import codebase` commit. In-image: `git log` length 1, `git diff` empty, the
remaining suite carries only the 7 pre-existing base-state failures (ingestion /
inbound-calls / document-report subsystems — unrelated to this cluster; verified
identical set at the clean base commit). `tests/config.json` `test_patch`
re-creates the three deleted files verbatim + augmented (creation diffs);
`solution/solve.sh` reverses the six source defects only.

## Verifier

- f2p = 16 (9 contacts-file, 4 invite-schema, 3 invite-conversation), spanning
  5 defective source files.
- p2p = 20: the green canaries in the three restored files (14) + 6 always-green
  tests in the never-deleted `test_smb_invite_production.py` (its two
  INTERNAL_API_KEY-gated tests skip and are excluded).
- Ladder: NULL reward 0 (`required passed: 20/36`, every f2p a per-test FAILED,
  no collection ERRORs); ORACLE reward 1 (36/36); PARTIAL (fix D1+D3+D6 only)
  reward 0 (`26/36`, interaction tests still red). No task env vars needed —
  the baked JWT/LIVEKIT env is sufficient; the suite is mocked and offline.

## Fairness note

The fix changes only logic inside functions that already exist at base; it
introduces no new names, so the instruction can be pure symptom report with zero
API leakage. All gold tests assert observable behavior (returned string, stored
attribute, response field) — the alternative-implementation audit passes: any
correct normalization/validation/merge yields the asserted values. Collaborator
mocks (`SMBContact`, `_get_lender_contact`, `_locked_contact_ids`) are the repo's
own established hermetic patterns, patched with explicit attribute values or a
`MagicMock(**kwargs)` factory, and are orthogonal to the defective functions the
agent must fix.
