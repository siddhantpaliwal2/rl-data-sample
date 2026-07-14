# Reference plan — trading-formatters-boundary-latent-bugs

## Construction (LATENT-BUG pattern)

Substrate is `apps/native/lib/formatters.ts` from the TradingApp monorepo — a
self-contained set of pure display/validation helpers with **zero imports**.
Rather than install the whole monorepo, the environment image carries only that
one module plus its existing test into a tiny bun workspace, so `bun test` runs
the formatters fully offline with no third-party dependencies.

The image is the clean module with a small set of **single-token boundary
defects** planted directly into the committed source. The agent starts from the
planted state. There is **no failing local test** pointing at any defect: the
module's existing test suite (`test/formatters.test.ts`, 9 tests) stays green
with the defects present, because every visible assertion feeds values that sit
safely inside the ranges and never lands on the exact edge that bites.

The gold tests (`tests/formatters_boundaries.test.ts`) are injected only at
grade time from `config.json`'s `test_patch`. They feed exactly the edge inputs
the defects corrupt and assert the correct outputs. "Green locally" is not the
bar — the grader's edge tests are.

Every defect's correct side is DERIVABLE from a concrete pin in the visible
code — a sibling comparison or a sibling function — not from a display
convention. (An earlier draft included two convention-picks — whether 0% shows
a `+`, and whether exactly-7-days reads as "7d ago" vs a date — which no visible
code pins; a gate showed Opus failed exactly those two 10/10 while solving the
other three 10/10, so both were swapped out for the sibling-pinned phone and
crypto boundaries below.)

## Defects planted (function : boundary : edge the visible tests never feed)

1. `formatCompactNumber` — K cutoff `value >= 1e3` weakened to `value > 1e3`.
   A value of exactly 1000 falls through and renders as `"1000.00"` instead of
   `"1.00K"`. Pin: the sibling M and B cutoffs both use `>=`; the lone K cutoff
   using `>` is internally inconsistent. Visible tests use 999 / 1500 / 2.5M /
   3B — never exactly 1000. (EASY.)

2. `formatCryptoAmount` — very-small precision band `value < 0.01` widened to
   `value <= 0.01`. An amount of exactly 0.01 renders at 8 decimals
   (`"0.01000000"`) instead of the 4-decimal band (`"0.0100"`). Pin: the
   parallel sibling band boundary `else if (value < 1)` is exclusive, so the
   descending band ladder must use exclusive `<` at both edges. Visible tests
   use 0.00001234 / 0.125 / 12.5 — never exactly 0.01. (EASY.)

3. `formatAddress` — abbreviation floor `address.length <= chars * 2` narrowed
   to `< chars * 2`. An address exactly `2*chars` long is abbreviated into a
   middle-dotted string no shorter than the original, instead of being returned
   whole. Pin: at length `2*chars` the abbreviated form is as long as or longer
   than the input, so abbreviating is pointless — the guard exists to return
   such inputs whole. Visible tests use lengths 5 and 18 with `chars=4` — never
   exactly 8. (MEDIUM.)

4. `isValidEmail` — the validation regex loses its trailing `$` anchor
   (`/^…$/` → `/^…/`), so a well-formed prefix followed by trailing text is
   accepted. Pin: the leading `^` remains, so the one-sided anchoring is
   internally inconsistent for a whole-string validator. Visible tests use a
   clean address and an at-sign-less string — neither has trailing junk after a
   valid prefix. (MEDIUM.)

5. `isValidPhone` — digit-count gate `>= 10` tightened to `> 10`, so a bare
   ten-digit number is rejected. Pin: the sibling `formatPhoneNumber` formats
   exactly `cleaned.length === 10` numbers as canonical US phones, establishing
   ten as THE valid phone length in the same file; a validator that rejects
   ten-digit numbers contradicts it. Visible tests use an 11-digit international
   number and a 5-digit string — never exactly 10. (MEDIUM.)

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch, restoring `>= 1e3`,
`< 0.01`, `<= chars * 2`, the `$`-anchored email regex, and `>= 10`. Any
equivalent boundary correction also passes the gold tests (the tests assert
behavior, not the specific token); a materially-different-fix audit confirms
this — see SCAFFOLD_REPORT.json.

## Verifier design

- `tests/test.sh` (canonical contract) applies `test_patch` from
  verifier-controlled config, runs `run_script.sh`, parses per-test verdicts,
  and awards reward 1 only if every `fail_to_pass` and `pass_to_pass` test
  passed.
- `run_script.sh` runs `bun test tests/formatters_boundaries.test.ts` with the
  JUnit reporter. bun's default console reporter prints only failing tests, so
  the JUnit XML is what carries the passing verdicts the grader needs.
- `parser.py` maps each JUnit `<testcase>` to `{name, status}`: a `<failure>`
  child is `failed`, otherwise `passed`; identity is `"<describe> > <test>"`.
  Regex-only, so it needs no XML library on the minimal Debian python3.
- `fail_to_pass` = the 5 gold boundary tests (fail at planted, pass once the
  boundaries are corrected). `pass_to_pass` = 14 gold tests exercising the same
  five helpers at non-edge inputs (green throughout — the "green locally" lull).

## Fairness

- All five defected functions are live, exported helpers with existing visible
  tests; none is dead code.
- The instruction names only the module and the boundary/edge CLASS of problem
  with two non-exhaustive illustrative examples — not the function names, the
  boundary directions, the trigger values, or the defect count. A dev must read
  and reason about each helper's boundary logic to locate and correct it.
- Deterministic, offline (`bun test` needs no network; the image installs git
  and python3 at build time only), no secrets.
