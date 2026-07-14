# Reference plan — xrepo-txenrich3-latent

Third clone of the proven `xrepo-txenrich-latent` (Opus 1/10) /
`xrepo-txenrich2-latent` (Opus 0/10) pattern, on two FRESH bank scripts:
**IDBI** and **Indusind** (task 1 used HDFC + ICICI, task 2 used Kotak + SBI).
Same harness, same repo base image (`txenrich-repo:v1`), same instruction voice.

## Construction (LATENT-BUG pattern)

Base image is the clean transaction-enrichment-python tree (a Flask
bank-statement enrichment service; ~40 per-bank categorization scripts of
deterministic `np.select` string/amount/comparison logic). The environment
Dockerfile plants five subtle single-token defects into the working tree and then
collapses git history, so the agent starts from base+defects with **no failing
local test** pointing at any defect — the repository ships no test files, and
every ordinary transaction still enriches correctly.

The gold tests (`tests/test_txenrich3_boundaries.py`) are injected only at grade
time from `config.json`'s `test_patch`. They construct single-row DataFrames of
raw transaction fields, call the actual `categorize_IDBI_transactions` /
`categorize_Indusind_transactions`, and assert the correct category / payee on
exactly the edge inputs the defects corrupt. "Green locally" is not the bar — the
grader's edge tests are.

## Defects planted (file : mechanism : the edge ordinary inputs never feed)

1. `Indusind.py` cheque-by-remark width — accepted width
   `remark.str.contains("^[0-9]{5,6}$")` narrowed to `^[0-9]{5}$`. **Load-bearing
   rare-trigger** (fires only when the remark is a bare 6-digit instrument /
   cheque number, exactly the untested edge). Pinned by **seven** repo-wide
   occurrences of the identical `^[0-9]{5,6}$` idiom (Axis, BankOfMaharashtra,
   PNB, Indusind). A bare 6-digit-remark debit stops being CHEQUE_PAID.

2. `Indusind.py` mandate verification — sentinel `amount.eq(1)` typo'd to
   `eq(2)`. Pinned by 11 repo-wide `amount.eq(1)` verification siblings and, after
   the substrate normalization below, by an **identical adjacent `amount.eq(1)`
   twin** on the line directly beneath it. A rupee-one mandate credit stops being
   ACCOUNT_VERIFICATION (falls to TRANSFER).

   **Substrate normalization (NOT a defect; present in both planted and correct
   states, never reverted).** The two adjacent account-verification sibling lines
   are rewritten from string-sentinel form (`amount.isin(["1","-1"])`,
   `amount.isin(["1"])`) to numeric form (`amount.isin([1,-1])`, `amount.eq(1)`).
   Both siblings gate on inputs no test row carries — one needs a `BANK_VER`
   keyword in the narration, the other needs `type == "DEBIT"` at amount 1 — so
   the rewrite changes no observable output at any f2p/p2p input. Its sole purpose
   is fairness/pin strength: the original string-vs-numeric mismatch between the
   defect line (numeric `eq`) and its string-`isin` neighbors was a decoy that
   diverted Opus solvers into "fixing" the siblings' dtype and leaving `eq(2)`
   untouched (observed in probe trajectories a5/a10, which patched lines 29/31 and
   never touched line 30). Normalizing the siblings removes the decoy and leaves
   `eq(2)` as the lone sentinel anomaly among a cluster of numeric `eq(1)`/`isin([1..])`
   verification rules.

3. `Indusind.py` POS card-reversal account gate — `accountType=="SAVING"` typo'd
   to `"SAVINGS"`. Pinned by 6 repo-wide `=="SAVING"` occurrences, the `"CURRENT"`
   convention, and the adjacent line 27 (same POS-savings path, keeps `"SAVING"`).
   A savings-account POS reversal credit falls through to the line-27 REFUND rule
   instead of CARD_PAYMENT_REVERSAL.

4. `IDBI.py` ACH mandate payee slice — `sep_by_dash(description,3,4)` shifted to
   `(2,3)`. The same-line literal `^ACH-BD-NACH` has three dash-prefix tokens
   (ACH, BD, NACH), so the payee is segment 3; the adjacent `^ACH-BD-` sibling
   uses `(2,3)` for its two-token layout. The payee comes out as the literal
   "Nach".

5. `IDBI.py` long-reference payee extraction — `py_extract(..., pat="[0-9]{10,}
   (.*)", index=0)` shifted to `index=1`. The pattern has exactly one capture
   group, so index 1 is out of range and `py_extract` returns empty; pinned by the
   pervasive `index=0` idiom on single-group patterns (IDBI 3x, Indusind 70x, zero
   `index=1` anywhere). The transfer payee is no longer extracted.

Five distinct slip shapes (regex-quantifier bound, integer sentinel literal,
string-casing typo, dash-slice index, capture-group index) — no grep-able twins.
Two easy-derivable (D2 sentinel, D3 casing), three medium (D1 width, D4 slice,
D5 group).

## Oracle fix

`solution/solve.sh` reverses the five single-token slips with an exact byte-level
replacement (the repo files use CRLF endings, so byte replacement is used instead
of `git apply -R`, which would fail on the CR mismatch). Any equivalent boundary /
structural correction also passes the gold tests, which assert observable output
(verified: `^[0-9]{5}[0-9]?$`, `amount.isin([1])`, `accountType!="CURRENT"`,
`sep_by_dash(3,5)`, index-0 all reach reward 1).

## Verifier design

- `tests/test.sh` (verbatim from the sibling) applies `test_patch` from
  verifier-controlled config, runs `run_script.sh`, parses per-test verdicts, and
  awards reward 1 only if every fail_to_pass and pass_to_pass test passed.
- `run_script.sh` runs the single gold file `tests/test_txenrich3_boundaries.py`
  from `/app`.
- `fail_to_pass` = 5 gold boundary tests (one per defect, mutually disjoint; fail
  at base+defects, pass once corrected).
- `pass_to_pass` = 14 tests pinning adjacent correct behavior plus general
  categorization breadth across both bank scripts (green throughout).

## Verification ladder (all run in the built image, --network none) — re-verified after softening

- Leak: `git log --oneline | wc -l` == 1, `git status` clean, `git diff` empty;
  five planted defect markers present (width `{5}`, `eq(2)`, `"SAVINGS"`,
  slice `2,3`, `index=1`), two substrate markers present (`isin([1,-1])`,
  `eq(1) & type.eq("DEBIT")`), no correct defect-forms remaining. PASS.
- NULL (planted): reward 0, all 5 f2p report per-test FAILED, 14/14 p2p pass. PASS.
- ORACLE (`solve.sh`): reward 1, 19/19 required pass. PASS.
- PARTIAL (revert D1+D4 only): reward 0, other 3 f2p (D2, D3, D5) still FAILED
  (16/19). PASS.
- FAIRNESS: materially different correct fixes (`^[0-9]{5}[0-9]?$`,
  `amount.isin([1])`, `accountType!="CURRENT"`, `sep_by_dash(3,5)`, `index=0`)
  reach reward 1, 19/19. PASS — confirms the numeric-sibling substrate leaves the
  alternative sentinel fix `isin([1])` valid.

## Fairness

- Pure-input unittests, zero mocks, no private-name coupling; assertions pin
  observable category / payee output, so alternative correct fixes pass.
- All five defected branches are reachable from the live categorizers (verified
  by direct exercise: each defect flips exactly its f2p edge input and leaves
  every p2p input unchanged). Deterministic, offline, no secrets.
- Instruction is an abstract symptom report; it names neither the banks, the file
  paths, the functions, the defect count, the boundary directions, nor the
  trigger values. It DOES quote, verbatim, the raw statement narration a customer
  would paste for the two payee-extraction symptoms — a mandate/salary credit
  whose raw text reads `ACH-BD-NACH-<employer>` and comes out named `NACH`, and a
  structured transfer whose raw text is a short letter block + long digit run +
  name (e.g. `GBHDL0123456789 RAVI KUMAR`) whose name comes out blank. Quoting
  observed input data is legitimate symptom reporting (the sibling
  `xrepo-txenrich-latent` forum-digest instruction does the same with
  `0000000000012345` / `TO: <person>` shapes); it localizes the second file
  without naming it, and leaves the actual fix (which dash segment / which capture
  index) to the solver.

## Softening history (0/10 -> target 2-3/10)

An Opus-4.8 mini-swe-agent probe (10 trials) scored the earlier build 0/10:
every trial that engaged (6/10) fixed the three Indusind category slips (D1/D3
always, D2 in 4/6) but **never ran a single command against `IDBI.py`** — the two
IDBI payee symptoms were described too generically and were absorbed into
Indusind's abundant payee-extraction logic (one failed trial's final thought was
literally "maybe the empty-name / leftover-reference symptoms are in a *different*
file"). Two changes address this without leaving the strict 1-4 band:

1. **Localization (instruction).** The two payee symptoms now quote their unique
   raw-narration shapes (`ACH-BD-NACH-...`, `^[A-Z]{5}[0-9]{10,} <name>`), both
   of which are unique to `IDBI.py` repo-wide, so a grep of the pasted text lands
   directly on the D4/D5 lines. The fix itself stays a genuine derivation.
2. **D2 pin (substrate normalization).** The string-vs-numeric sibling decoy that
   caused engaged solvers to miss the mandate `eq(2)` is removed (see defect 2),
   lifting D2's findability among engaged solvers from ~0.67 toward the rest.

Band math (independent-ish): D1 0.6 x D2 ~0.8 x D3 0.6 x D4 ~0.7 x D5 ~0.7 ~= 0.14,
and the 40% of trials that converged on nothing at all cap the ceiling well under
the reject threshold — landing ~2-3/10.
