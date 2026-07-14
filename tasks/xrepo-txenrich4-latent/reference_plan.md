# Reference plan — xrepo-txenrich4-latent

Fourth clone of the proven `xrepo-txenrich-latent` (Opus 1/10) /
`xrepo-txenrich2-latent` (Opus 0/10) / `xrepo-txenrich3-latent` pattern, on two
FRESH bank scripts: **PNB** and **Canara** (task 1 used HDFC + ICICI, task 2
used Kotak + SBI, task 3 used IDBI + Indusind). Same harness, same repo base
image (`txenrich-repo:v1`), same instruction discipline (symptoms only), a
distinct QA-regression instruction voice.

## Construction (LATENT-BUG pattern)

Base image is the clean transaction-enrichment-python tree (a Flask
bank-statement enrichment service; ~40 per-bank categorization scripts of
deterministic `np.select` string/amount/comparison logic). The environment
Dockerfile plants five subtle single-token defects into the working tree and
then collapses git history, so the agent starts from base+defects with **no
failing local test** pointing at any defect — the repository ships no test files,
and every ordinary transaction still enriches correctly.

The gold tests (`tests/test_txenrich4_boundaries.py`) are injected only at grade
time from `config.json`'s `test_patch`. They construct single-row DataFrames of
raw transaction fields, call the actual `categorize_PNB_transactions` /
`categorize_Canara_transactions`, and assert the correct category / payee on
exactly the edge inputs the defects corrupt. "Green locally" is not the bar — the
grader's edge tests are.

## Banks chosen

PNB (192 lines, 65 `np.select` category rules + a three-stage partyName pipeline)
and Canara (201 lines, 80 category rules + a three-stage partyName pipeline) are
the two most rule-dense of the still-free candidate scripts (Axis, PNB, BOB,
Federal, UnionBank, Canara, YES). Both carry the full shape vocabulary the
pattern needs: cheque-by-remark digit-width regexes, `sep_by_dash` / `sep_by_`
segment slices, single-group `py_extract` capture indices, and rupee-sentinel
account-verification amount guards.

## Defects planted (file : mechanism : the edge ordinary inputs never feed)

1. `PNB.py` cheque-by-remark width — accepted width
   `remark.str.contains("^[0-9]{5,6}$")` narrowed to `^[0-9]{5}$` on the
   CHEQUE_PAID/DEBIT rule only. **Load-bearing rare-trigger** (fires only when
   the remark is a bare 6-digit instrument / cheque number). Pinned by the
   **identical adjacent twin** on the very next line (`^[0-9]{5,6}$` for the
   CHEQUE_DEPOSIT/CREDIT rule) plus **seven** repo-wide `^[0-9]{5,6}$`
   occurrences (Axis, BankOfMaharashtra, PNB, Indusind). A bare 6-digit-remark
   debit stops being CHEQUE_PAID (falls to TRANSFER). Breadth; shape = regex
   quantifier upper bound. Est. p ~= 0.9.

2. `PNB.py` NEFT payee capture-group — `py_extract(description, pat="NEFT (.*)",
   index=0)` shifted to `index=1`. **GATE (main).** The pattern has exactly one
   capture group, so index 1 is out of range and `py_extract` returns empty
   (its `.get(1)` is `None` -> `pd.Series("")`); pinned by the same-line single
   group and by the pervasive `index=0` idiom on single-group patterns
   (`index=1` appears repo-wide only on multi-group patterns). A `^NEFT <name>`
   credit loses its counterparty name. Unsignposted in the instruction (F-3
   describes only "name goes blank"). Shape = capture-group index. Est. p ~= 0.55.

3. `Canara.py` cleared-cheque payee slice — `sep_by_dash(description,2,3)`
   shifted to `(1,2)` on the `^CHQ PAID-` rule only. The `CHQ PAID-<clearing>-
   <name>` layout has two dash-prefix tokens before the payee, so the payee is
   segment 2; pinned by the **identical adjacent twin** on the line directly
   above (`Chq Paid-Home Clearing-` -> `sep_by_dash(...,2,3)`) and by four more
   repo-local `sep_by_dash(...,2,3)` siblings. The payee comes out as the middle
   clearing token. Breadth; shape = dash-slice segment index. Est. p ~= 0.9.

4. `Canara.py` account-verification sentinel — `amount.lt(2)` narrowed to
   `amount.lt(1)` on the `BANK_VERIF` account-verification rule. **GATE
   (second).** `lt(2)` is the rupee-one penny-drop admission threshold; `lt(1)`
   admits nothing at amount 1, so a one-rupee verification credit falls to
   TRANSFER. Pinned by the identical `amount.lt(2)` verification idiom in PNB,
   HDFC and RBL (4 repo-wide, cross-file). Unsignposted in the instruction (F-5
   describes only "token confirmation credit filed as a transfer", no value).
   Shape = numeric amount sentinel/threshold. Est. p ~= 0.45.

5. `Canara.py` UPI person-to-person payee slice — `sep_by_(description,3,4)`
   shifted to `(2,3)` on the `^UPI/[CD]R` rule only. The slash layout puts the
   sender name in segment 3; pinned by the **identical adjacent twin** on the
   line directly below (`UPV/DR/` -> `sep_by_(...,3,4)`). The payee comes out as
   the numeric reference in segment 2 (which the downstream `^[0-9]{5,}` cleanup
   does not blank because it is prefixed). Breadth; shape = slash-slice segment
   index. Est. p ~= 0.9.

Five distinct slip shapes (regex-quantifier bound, capture-group index,
dash-slice index, amount sentinel/threshold, slash-slice index) — no grep-able
twins (each is reached by a different search: `{5,6}`, `pat="NEFT (.*)"`,
`sep_by_dash(...`, `amount.lt(2)`, `^UPI/[CD]R` respectively). Three breadth
(D1/D3/D5, adjacent-twin-pinned) + two gates (D2 capture-group ~0.55, D4 sentinel
~0.45), spread across BOTH bank files (PNB 2, Canara 3), with each file localized
by at least one concrete breadth symptom so neither is ignored (the failure mode
of the first txenrich3 build).

## Oracle fix

`solution/solve.sh` reverses the five single-token slips with an exact byte-level
replacement (the repo files use CRLF endings, so byte replacement is used instead
of `git apply -R`, which would fail on the CR mismatch). Any equivalent boundary /
structural correction also passes the gold tests, which assert observable output
(verified: `^[0-9]{5}[0-9]?$` width, two-group `(NEFT) (.*)` index=1,
`sep_by_dash(2,4)` final-segment slice, `amount.le(1)` sentinel, `sep_by_(3,5)`
slice all reach reward 1).

## Verifier design

- `tests/test.sh` (verbatim from the sibling) applies `test_patch` from
  verifier-controlled config, runs `run_script.sh`, parses per-test verdicts, and
  awards reward 1 only if every fail_to_pass and pass_to_pass test passed.
- `run_script.sh` runs the single gold file `tests/test_txenrich4_boundaries.py`
  from `/app`.
- `fail_to_pass` = 5 gold boundary tests (one per defect, mutually disjoint; fail
  at base+defects, pass once corrected).
- `pass_to_pass` = 14 tests pinning adjacent correct behavior (the identical
  cheque-deposit/cheque-clearing/UPV twins, the alternately-laid-out NEFT payee,
  the ordinary/high-amount verification rows) plus general categorization breadth
  across both bank scripts (green throughout).

## Verification ladder (all run in the built image, --network none)

- Leak: `git log --oneline | wc -l` == 1, `git status` clean, `git diff` empty;
  five planted defect markers present (`^[0-9]{5}$` DEBIT, `pat="NEFT (.*)",
  index=1`, `^CHQ PAID-` slice `1,2`, verify `amount.lt(1)`, `^UPI/[CD]R` slice
  `2,3`), no correct defect-forms remaining.
- NULL (planted): reward 0, all 5 f2p report per-test FAILED, 14/14 p2p pass.
- ORACLE (`solve.sh`): reward 1, 19/19 required pass.
- PARTIAL (revert D1+D3 only): reward 0, other 3 f2p (D2, D4, D5) still FAILED.
- FAIRNESS: materially different correct fixes (`^[0-9]{5}[0-9]?$`,
  `(NEFT) (.*)` index=1, `sep_by_dash(2,4)`, `amount.le(1)`, `sep_by_(3,5)`)
  reach reward 1, 19/19.

## Fairness

- Pure-input unittests, zero mocks, no private-name coupling; assertions pin
  observable category / payee output, so alternative correct fixes pass.
- All five defected branches are reachable from the live categorizers (verified
  by direct exercise: each defect flips exactly its f2p edge input and leaves
  every p2p input unchanged). Deterministic, offline, no secrets.
- Instruction is an abstract QA-regression report; it names neither the banks,
  the file paths, the functions, the defect count, the boundary directions, nor
  the trigger values. It quotes, verbatim, a single raw-narration shape
  (`CHQ PAID-MICR CLG-RAVI KUMAR`) for the one cleared-cheque payee finding, to
  localize the second bank without revealing which reference segment is at fault;
  the two gate defects (D2 blank name, D4 token verification) are described only
  qualitatively, with no example value.
