# Reference plan — latent-phone-invites

## Construction (LATENT-BUG pattern)

Base image is the clean HEAD of loangenus (`04b8abc`). The environment Dockerfile
resets to that commit and then applies a small **defect patch** that plants five
subtle edge-only errors in the CRM phone-normalization and loan-type-resolution
logic. The agent starts from base+defects. There is **no failing local test**
pointing at any defect: the full existing suite stays at its clean baseline
(7 failed / 166 passed / 24 skipped — the 7 failures are a pre-existing rot set in
`test_inbound_calls` / `test_document_ingestion_readiness` /
`test_ingestion_stale_recovery` / `test_document_report`, unrelated to this task)
because every visible test feeds ordinary values that never land on the edge that
bites.

The gold tests (`tests/test_phone_alias_boundaries.py`) are injected only at grade
time from `config.json`'s `test_patch`. They feed exactly the edge inputs the
defects corrupt and assert the correct outputs. "Green locally" is not the bar —
the grader's edge tests are. The phone functions are pure given the `phonenumbers`
library and the loan-type resolvers are pure table lookups, so every gold test is
a direct call with **zero mocks**.

## Defects planted (file : symptom : trigger the visible tests never feed)

1. `phone.py` `try_normalize_phone_to_e164` — the default-region priority guard
   `if default:` weakened to `if not default:`, so the configured default region
   is no longer prepended to the fallback list. It still resolves correctly when
   the default is `US` (US is first in `_CRM_FALLBACK_REGIONS` anyway), so every
   visible test — all of which use `US` — is unaffected; only a non-US default
   (e.g. `GB`) loses its priority. Edge: `try_normalize_phone_to_e164("2079460958",
   default_region="GB")` returns `+12079460958` (US) instead of `+442079460958`.

2. `phone.py` `try_normalize_phone_to_e164` — the possible-match tiebreak
   `return possible_matches[0]` shifted to `possible_matches[-1]`, returning the
   last fallback region's interpretation instead of the earliest. This path is
   only reached when no region yields a *valid* number; every visible input
   resolves via a valid match (or the explicit-`+` branch), so none exercises it.
   Edge: `try_normalize_phone_to_e164("1201234567", default_region="US")` returns
   `+491201234567` (DE) instead of `+11201234567`.

3. `phone.py` `normalize_phone_to_e164` — the `00` international-access-prefix
   rewrite `value[2:]` shifted to `value[1:]`, leaving a stray leading zero so the
   number no longer parses. No visible test feeds a `00`-prefixed number to the
   strict normalizer. Edge: `normalize_phone_to_e164("00442079460958")` raises
   `ValueError` instead of returning `+442079460958`.

4. `loan_types.py` `loan_type_label` — the humanization fallback `.title()`
   changed to `.capitalize()`, so a multi-word legacy id gets only its first word
   capitalized. Only reached for ids **not** in the current catalog; the 20 known
   ids all return their exact label from the loop. Edge: `loan_type_label(
   "hard_money")` returns `"Hard money"` instead of `"Hard Money"`.

5. `loan_types.py` `resolve_loan_type` — the exact-id branch `return value.lower()`
   changed to `return value`, echoing the raw casing instead of the canonical
   lowercase id. This branch is only reached by an underscore-bearing id typed with
   its underscore (compact ids go through an earlier branch), and only differs when
   that id carries uppercase — a form nobody types casually. Edge:
   `resolve_loan_type("Working_Capital")` returns `"Working_Capital"` instead of
   `"working_capital"`.

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch, restoring `if default:`,
`possible_matches[0]`, `value[2:]`, `.title()`, and `return value.lower()`. That is
the minimal correct fix; any equivalent edge correction also passes the gold tests.

## Verifier design

- `tests/test.sh` (verbatim from the canonical) applies `test_patch` from
  verifier-controlled config, runs `run_script.sh`, parses per-test verdicts, and
  awards reward 1 only if every `fail_to_pass` and `pass_to_pass` test passed.
- `fail_to_pass` = the 5 gold edge tests (fail at base+defects, pass once the edges
  are corrected).
- `pass_to_pass` = 12 existing tests that pass throughout (loan-type resolution,
  phone normalization, CSV import / contact update / create, cartesia twilio sync)
  — the "green locally" lull. Runs whole files, so the p2p list can be trimmed to
  4 in config.json without rebuilding the image.
- `run_script.sh` runs the gold file plus `test_smb_contacts_csv_and_update.py` and
  `test_cartesia_twilio_sync.py`, which hold the pass_to_pass set.

## Fairness

- All five defected functions are live: `resolve_loan_type` / `loan_type_label` are
  used by `smbcontacts/service.py`, `smbcontacts/schemas.py` and
  `smbinvites/{service,schemas}.py`; the phone normalizers are used by
  `smbcontacts/service.py` and `calls/{inbound,service}.py`.
- The instruction names the two modules and the symptom class (unusual formats /
  region ambiguity / odd casing) but not the functions, the exact inputs, the
  boundary direction, or the count — the agent must read and reason about the
  edge logic to locate and correct each slip.
- Every gold test is a pure direct call with no mocks, so no oracle implementation
  choice is encoded; any implementation that returns the correct value passes.
- Deterministic, offline, no secrets beyond the baked JWT_SECRET_KEY.
- Round-1 note: the sibling task `forge-contacts-invites` planted OBSERVABLE defects
  in the SAME two files (dropping `IN` from `_CRM_FALLBACK_REGIONS`; returning the
  label instead of the id in the `resolve_loan_type` label loop) and failed easiness.
  This task deliberately avoids those sites and every defect here bites only inputs
  no visible test or casual user feeds.
