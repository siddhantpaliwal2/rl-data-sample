# Reference plan — xrepo-txenrich-latent

## Construction (LATENT-BUG pattern)

Base image is the clean transaction-enrichment-python tree (a Flask bank-statement
enrichment service; ~40 per-bank categorization scripts of deterministic
`np.select` string/amount/comparison logic). The environment Dockerfile plants a
small set of subtle single-token defects into the working tree and then collapses
git history, so the agent starts from base+defects with **no failing local test**
pointing at any defect — the repository ships no test files, and every ordinary
transaction still enriches correctly.

The gold tests (`tests/test_txenrich_boundaries.py`) are injected only at grade
time from `config.json`'s `test_patch`. They construct real single/two-row
DataFrames of raw transaction fields, call the actual `categorize_HDFC_transactions`
/ `categorize_ICICI_transactions`, and assert the correct category / subcategory /
payee on exactly the edge inputs the defects corrupt. "Green locally" is not the
bar — the grader's edge tests are.

## Defects planted (file : mechanism : the edge ordinary inputs never feed)

1. `HDFC.py` cheque-deposit-by-remark — length guard `remark.str.len().eq(16)`
   weakened to `.eq(15)`. The 16 is pinned by the sibling regex `^[0]{11}[0-9]{5}`
   (11+5 chars). A 16-char zero-prefixed remark stops being CHEQUE_DEPOSIT.

2. `HDFC.py` six-digit savings-salary — `accountType=="SAVING"` typo'd to
   `"SAVINGS"`. Pinned by 45 correct `=="SAVING"` occurrences repo-wide. A
   six-digit savings credit stops being SALARY.

3. `HDFC.py` adjacent-reversal detector — `description.shift(periods=1)` shifted to
   `periods=2` on the REVERSAL branch only. Pinned by the near-identical
   AUTO_PAYMENT_BOUNCE sibling that keeps `shift(periods=1)`. A genuine offsetting
   credit is misfiled as AUTO_PAYMENT_BOUNCE.

4. `ICICI.py` account-verification — `amount.isin([1,-1])` narrowed to `isin([1])`.
   Pinned by the pervasive `isin([1,-1])` sentinel idiom (31 occurrences). A -1
   verification debit stops being ACCOUNT_VERIFICATION.

5. `ICICI.py` BIL/INFT payee extraction — `sep_by_(description,3,4)` shifted to
   `(2,3)`. Pinned by the same-line `count("/").eq(3)` guard (four segments, payee
   last). The payee comes out as the numeric reference instead of the name.

Five distinct slip shapes (length-eq, string-casing, shift-adjacency, list-
membership, slice-index) — no grep-able twins.

## Oracle fix

`solution/solve.sh` reverses the five single-token slips with an exact byte-level
replacement (the repo files use CRLF endings, so byte replacement is used instead
of `git apply -R`, which would fail on the CR mismatch). Any equivalent boundary /
structural correction also passes the gold tests, which assert observable output.

## Verifier design

- `tests/test.sh` (verbatim from the canonical cre-scoring task) applies
  `test_patch` from verifier-controlled config, runs `run_script.sh`, parses
  per-test verdicts, and awards reward 1 only if every fail_to_pass and
  pass_to_pass test passed.
- `run_script.sh` runs the single gold file from `/app`.
- `fail_to_pass` = 5 gold boundary tests (one per defect, mutually disjoint;
  fail at base+defects, pass once corrected).
- `pass_to_pass` = 12 tests pinning adjacent correct behavior plus general
  categorization breadth across both bank scripts (green throughout).

## Verification ladder (all run in the built image)

- Leak: `git log --oneline | wc -l` == 1, `git status` clean, `git diff` empty;
  planted markers present.
- NULL (planted): reward 0, all 5 f2p report per-test FAILED, 12 p2p pass.
- ORACLE (`solve.sh`): reward 1, 17/17 required pass.
- PARTIAL (2 of 5 defects reversed): reward 0, 3 f2p still FAILED.

## Fairness

- Pure-input unittests, zero mocks, no private-name coupling; assertions pin
  observable category/subcategory/payee output, so alternative correct fixes pass.
- All five defected branches are reachable from `Controller.categorize` (live
  code). Deterministic, offline, no secrets.
- Instruction is an abstract symptom report naming the BankScripts directory and
  the two affected bank scripts, but no function names, line numbers, boundary
  directions, trigger values, or defect count.
