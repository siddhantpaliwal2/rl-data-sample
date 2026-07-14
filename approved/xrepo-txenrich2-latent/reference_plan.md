# Reference plan — xrepo-txenrich2-latent

Clone of the proven `xrepo-txenrich-latent` (Opus 1/10, Sonnet 0/5) on two
DIFFERENT bank scripts: **Kotak** and **SBI** (the sibling used HDFC + ICICI).
Same harness, same repo base image, same instruction voice.

## Construction (LATENT-BUG pattern)

Base image is the clean transaction-enrichment-python tree (a Flask bank-statement
enrichment service; ~40 per-bank categorization scripts of deterministic
`np.select` string/amount/comparison logic). The environment Dockerfile plants a
small set of subtle single-token defects into the working tree and then collapses
git history, so the agent starts from base+defects with **no failing local test**
pointing at any defect — the repository ships no test files, and every ordinary
transaction still enriches correctly.

The gold tests (`tests/test_txenrich2_boundaries.py`) are injected only at grade
time from `config.json`'s `test_patch`. They construct real single/two-row
DataFrames of raw transaction fields, call the actual `categorize_Kotak_transactions`
/ `categorize_SBI_transactions`, and assert the correct category / subcategory /
payee on exactly the edge inputs the defects corrupt. "Green locally" is not the
bar — the grader's edge tests are.

## Defects planted (file : mechanism : the edge ordinary inputs never feed)

1. `Kotak.py` cheque-deposit-by-remark — accepted width `remark.str.contains("^[0-9]{3,5}$")`
   narrowed to `{3,4}`. Pinned by three identical `^[0-9]{3,5}$` siblings in the same
   file. A bare 5-digit-remark credit stops being CHEQUE_DEPOSIT. **Load-bearing
   rare-trigger** (fires only on a bare 3-5 digit instrument number).

2. `Kotak.py` Received-from verification — sentinel `amount.eq(1)` typo'd to `eq(2)`.
   Pinned by 11 repo-wide `amount.eq(1)` verification siblings and the adjacent
   Karz-Xx4002 verification line. A rupee-one Received-from credit stops being
   ACCOUNT_VERIFICATION (falls to IMPS).

3. `Kotak.py` NACH salary payee — `sep_by_dash(description,4,5)` shifted to `(3,4)`.
   The same-line literal `^NACH-SAL-CR-SAL-` has four dash-prefix tokens, so the
   payee is segment 4; the adjacent `^NACH-...-CR-` sibling uses `(3,4)` for its
   three-token layout. The payee comes out as the literal "Sal".

4. `SBI.py` bulk-posting payee — `accountType == "SAVING"` typo'd to `"SAVINGS"`.
   Pinned by 6 repo-wide `== "SAVING"` occurrences and the `"CURRENT"` convention.
   A savings-account bulk-posting payee is no longer extracted.

5. `SBI.py` internet-banking payee — `py_extract(..., pat="TO TRANSFER INB (.*)", index=0)`
   shifted to `index=1`. The pattern has exactly one capture group, so index 1 is
   out of range and yields empty; pinned by the pervasive `index=0` idiom on
   single-group patterns. The INB transfer payee is no longer extracted.

Five distinct slip shapes (regex-quantifier bound, integer sentinel literal,
dash-slice index, string-casing typo, capture-group index) — no grep-able twins.

## Oracle fix

`solution/solve.sh` reverses the five single-token slips with an exact byte-level
replacement (the repo files use CRLF endings, so byte replacement is used instead
of `git apply -R`, which would fail on the CR mismatch). Any equivalent boundary /
structural correction also passes the gold tests, which assert observable output
(verified: `isin([1])`, `!= "CURRENT"`, `sep_by_dash(4,6)`, index-0 all reach reward 1).

## Verifier design

- `tests/test.sh` (verbatim from the canonical cre-scoring task) applies
  `test_patch` from verifier-controlled config, runs `run_script.sh`, parses
  per-test verdicts, and awards reward 1 only if every fail_to_pass and
  pass_to_pass test passed.
- `run_script.sh` runs the single gold file `tests/test_txenrich2_boundaries.py`
  from `/app`.
- `fail_to_pass` = 5 gold boundary tests (one per defect, mutually disjoint;
  fail at base+defects, pass once corrected).
- `pass_to_pass` = 14 tests pinning adjacent correct behavior plus general
  categorization breadth across both bank scripts (green throughout).

## Verification ladder (all run in the built image)

- Leak: `git log --oneline | wc -l` == 1, `git status` clean, `git diff` empty;
  planted markers present. PASS.
- NULL (planted): reward 0, all 5 f2p report per-test FAILED, 14 p2p pass. PASS.
- ORACLE (`solve.sh`): reward 1, 19/19 required pass. PASS.
- PARTIAL (revert D1+D4 only): reward 0, other 3 f2p still FAILED. PASS.
- FAIRNESS: materially different correct fixes reach reward 1. PASS.

## Fairness

- Pure-input unittests, zero mocks, no private-name coupling; assertions pin
  observable category/subcategory/payee output, so alternative correct fixes pass.
- All five defected branches are reachable from the live categorizers.
  Deterministic, offline, no secrets.
- Instruction is an abstract symptom report naming the BankScripts directory and
  the two affected bank scripts (Kotak, SBI), but no function names, line numbers,
  boundary directions, trigger values, or defect count.
