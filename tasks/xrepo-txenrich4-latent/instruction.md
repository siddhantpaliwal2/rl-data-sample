<uploaded_files>/app</uploaded_files>

# Regression QA - RC 2.14: transaction-categorization findings

**Test round:** RC 2.14 pre-release categorization pass
**Prepared by:** QA (enrichment)
**Verdict:** Not signed off - the findings below must clear before this build ships

## Summary

The RC 2.14 pass replays our labelled statement-fixture corpus through the
enrichment stage and diffs every derived field against the accepted baseline.
The overwhelming majority of fixtures reproduce their baseline labels exactly.
A thin residue of rows, though, now derive a category or a counterparty name
that disagrees with the accepted answer. Each regressed row is stable - the same
fixture yields the identical wrong field every time it is replayed - and each one
hinges on a narrow, individually rare pattern in the underlying reference text
rather than on the size of the amount or on which customer it belongs to.
Ordinary purchases, routine transfers and everyday deposits all reproduce
baseline, which is why the aggregate diff read clean until these edge fixtures
were isolated.

The findings are recorded in the order they surfaced. QA has not traced any of
them to a root cause; that is left to engineering. Acceptance for this build is
simply that every listed finding derives its baseline field again and that no
fixture already matching baseline moves.

## Findings

**F-1.** A cheque-type debit whose statement note carries nothing but the
instrument's own number - a short, bare run of digits with no other text sitting
beside it - is landing in the generic transfer bucket. Cheque debits whose notes
are shaped even slightly differently keep their correct cheque label, so the miss
is confined to this one bare-number note form.

**F-2.** On a cleared cheque, the counterparty column is coming back with an
internal clearing tag in place of the account-holder's name. The affected rows
all share one raw-narration layout, copied here from a fixture:

> `CHQ PAID-MICR CLG-RAVI KUMAR`

For this layout the field is returning a fragment of the reference instead of the
name that should be lifted from it.

**F-3.** A slice of inbound electronic-transfer credits - the plain
national-transfer kind - are arriving with the counterparty-name column left
completely blank. The category on these rows is right; it is only the name that
goes missing. Other electronic-transfer credits, whose references are laid out
differently, still resolve their names normally, so this is not a blanket failure
of name extraction.

**F-4.** An incoming person-to-person instant-payment credit is showing a bare
reference number where the sender's name belongs. The value that surfaces is a
fragment of the very reference string the name should have been read from;
neighbouring instant-payment layouts still resolve their names correctly.

**F-5.** A small nominal deposit that a bank posts purely to confirm an account
is reachable - the token "is this account live" credit rather than a real
payment - is being filed as an ordinary transfer instead of being recognised as
an account-verification entry. Ordinary deposits are untouched; only these token
confirmation credits regressed.

## Exit criteria

The enrichment path is fully deterministic and runs offline, so each finding
above is reproducible on demand from the fixture that triggered it. Restore the
correct category and counterparty on the listed forms without disturbing any
fixture that already agrees with baseline. A change that rescues these rows but
shifts the label or the name of ordinary, currently-correct traffic does not meet
acceptance: the bar is that the specific regressions listed here clear and
everything else stays exactly where the baseline has it.
