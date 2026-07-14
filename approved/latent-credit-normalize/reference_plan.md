# Reference plan — latent-credit-normalize

## Construction (LATENT-BUG pattern)

Base image is the clean HEAD of loangenus (`04b8abc`). The environment
Dockerfile resets to that commit and then applies a small **defect patch** that
plants five subtle edge-case errors in the credit-PDF line-classification and
normalization helpers (`normalize.py`, `junk_filter.py` under
`loangen-agent/agent/documents/credit_pdf/`). The agent starts from
base+defects. There is **no failing local test** pointing at any defect: the
full existing suite stays green with the defects present (identical to clean
HEAD: 7 failed / 166 passed / 24 skipped), because every visible test feeds
ordinary values and never lands on the exact edge that bites.

The gold tests (`tests/test_credit_normalize_boundaries.py`) are injected only
at grade time from `config.json`'s `test_patch`. They feed exactly the edge
inputs the defects corrupt and assert the correct outputs, using raw
strings/lines and plain dataclass inputs — pure input, zero mocks.

## Derivability principle (round-2 gate rule)

Every defect is chosen so the uniquely-correct side of the boundary is
determinable from the visible code alone — no convention-picks (no upper-vs-lower
median, no clamp-or-not, no undocumented threshold direction). Each fix is pinned
by an adjacent artifact the agent can read: a lower-cased lookup set, a sibling
key that is case-folded, sibling regexes that are end-anchored, or an
abbreviation table that lists the missing code.

## Defects planted (file : symptom : what pins the correct side : derivability)

1. `junk_filter.py` `is_junk_creditor_name` — placeholder check
   `name.lower() in _UNKNOWN_CREDITOR` -> `name in _UNKNOWN_CREDITOR`. A
   placeholder ("Unknown"/"N/A") in any casing other than exactly lower-case
   slips through as a real creditor. **Pinned by:** the `_UNKNOWN_CREDITOR`
   frozenset a few lines above is entirely lower-case, so matching mixed-case
   input requires case-folding. **Derivability: easy.**

2. `junk_filter.py` `dedupe_tradelines` — dedupe key
   `f"{creditor.lower()}|{acct}"` -> `f"{creditor}|{acct}"`. Two copies of the
   same account whose creditor differs only in casing are no longer de-duplicated.
   **Pinned by:** the sibling `dedupe_inquiries` (same file, next function) and
   `_pool_tradelines` (bureau_router.py) build the identical key WITH `.lower()`.
   **Derivability: easy.**

3. `normalize.py` `is_address_or_contact_line` — street-suffix pattern loses its
   trailing `$` anchor (`^(...suffixes...)\.?$` -> `^(...suffixes...)\.?`), so it
   now matches any line that merely *starts* with a suffix token; a borrower name
   like "Steven" (starts with "st") is misclassified as an address line and
   dropped. **Pinned by:** the sibling patterns in the same helper
   (`_CITY_STATE_RE`, `_ZIP_ONLY_RE`, `_PHONE_RE`) are all `$`-anchored, and the
   suffix list is a whole-line fragment matcher. **Derivability: medium.**

4. `normalize.py` `bureau_tags_from_text` — tag alternation drops the `EFX`
   branch (`(TUC|EXP|EQX|TU|EFX)` -> `(TUC|EXP|EQX|TU)`), so an "EFX-B1" Equifax
   column tag maps to nothing. **Pinned by:** `_BUREAU_TAG_MAP` at the top of the
   file maps `"EFX" -> "equifax"` (alongside `"EQX"`), so EFX is a recognized tag
   the pattern must accept. **Derivability: medium.**

5. `normalize.py` `is_plausible_creditor_line` — the all-numeric reject loses its
   trailing `$` anchor (`^[\d\$\.,\s%]+$` -> `^[\d\$\.,\s%]+`), so any line that
   merely *starts* with a digit/currency char is rejected; a real creditor like
   "1ST NATIONAL BANK" is discarded. **Pinned by:** the character class describes
   an entire numeric/currency line, and the adjacent SSN reject
   `^\d{3}...\d{4}$` is `$`-anchored. **Derivability: medium.**

Target mix achieved: 2 easy-derivable + 3 medium-derivable, zero convention-picks.

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch, restoring the `.lower()`
case-folds, the two end-anchors, and the `EFX` alternation branch. That is the
minimal correct fix; any equivalent correction (e.g. `re.fullmatch` for an
anchor, `str.casefold` for a case-fold) also passes the gold tests.

## Verifier design

- `tests/test.sh` (verbatim from the canonical) applies `test_patch` from
  verifier-controlled config, runs `run_script.sh`, parses per-test verdicts,
  and awards reward 1 only if every `fail_to_pass` and `pass_to_pass` test
  passed.
- `fail_to_pass` = the 5 gold edge tests (one per defect; fail at base+defects,
  pass once corrected).
- `pass_to_pass` = 14 tests that pass throughout — 10 adjacent-boundary pins in
  the gold file (the neighbouring inputs the defects do NOT move) plus 4
  existing credit-PDF pipeline tests (the "green locally" lull).
- `run_script.sh` runs the gold file plus `test_credit_pdf_pipeline.py`.

## Fairness

- All five defected functions are live code, reached from the Xactus tri-merge
  adapter (`adapters/xactus.py`), `validation.py`, and `bureau_router.py` during
  real credit-PDF parsing — not dead paths.
- The instruction names the two modules and the boundary *shapes* (case
  handling, pattern match-scope, token-variant coverage) but not the function
  names, the exact lines, the boundary direction, the trigger values, or the
  count — it does not enumerate the defects 1:1.
- Gold tests use only raw strings/lines and plain `ParsedTradeline` dataclasses;
  no mocks, no patched module attributes, so no oracle implementation choice is
  encoded. Materially different correct fixes still pass.
- Deterministic, offline, no secrets beyond the baked `JWT_SECRET_KEY`.

## Gate result (banked)

The 5-defect build gated **Sonnet 0/5, Opus 3/10** — strict-corridor quality.
Two additional cross-function-traced mediums (normalize_date slice, parse_money
currency-symbol) were prototyped and verified but are parked in scratch
(`seven-defect-variant/`) for a possible SEPARATE second normalize task; they are
NOT part of this banked task.
