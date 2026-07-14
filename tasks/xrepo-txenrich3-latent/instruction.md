<uploaded_files>/app</uploaded_files>

# SEV-1 INCIDENT - RELEASE BLOCKER
**Title:** Statements are filing some payments under the wrong kind of transaction, or dropping the payee name
**Owner:** Payments Operations
**Disposition:** Do not ship this release until it is resolved

## What customers reported

Over the past few days support has collected a run of tickets that all share one
shape: the money itself moved fine, but the app files the payment under a category
that does not match what the customer actually did, or shows the wrong name - or
no name at all - beside it. In every case the row that misbehaves carries one very
particular, uncommon form of raw statement text; everyday rows are labeled exactly
as before. The tickets below are anonymized, but the raw narration each customer
pasted is reproduced verbatim, because that raw text is what makes each case
reproducible.

> "I wrote a cheque against my account and the app just lists it as a general
> transfer now - nothing marks it as a cheque anymore. My earlier cheques were
> tagged correctly. The only thing sitting in that row's note is the cheque's own
> number, nothing else around it."

> "My salary came in and the amount is right, but where my employer's name should
> be the app now just prints the word `NACH`. The raw text on that row looks like
> `ACH-BD-NACH-ACME INDUSTRIES` - it used to lift the employer's name off the end
> of that reference, and now it is picking up the wrong piece of it."

> "On some transfers that come in, the sender's name is blank now. Those rows all
> share the same reference layout - a short block of letters, then a long string
> of digits, then the name - for example `GBHDL0123456789 RAVI KUMAR`. The name
> sitting at the end just is not being pulled through anymore; the name column
> comes out empty."

The same batch of complaints also covers two quieter cases that are about the
category rather than the name. The token confirmation charge a bank posts when a
new auto-debit mandate is set up - a small nominal amount, with the note flagging
it as a mandate - is being filed as an ordinary transfer instead of being
recognized as a verification entry. And a refund that came back on a card is
landing as a plain refund for some customers when it should read as a card
reversal; a customer on a different type of account sees the same kind of refund
labeled correctly, so the wrong label appears to depend on the account category.

## Scope of impact

Everyday activity - normal purchases, routine transfers, regular deposits - is
categorized and named correctly, which is precisely why this slipped through QA and
why our monitoring dashboards looked healthy. The breakage is confined to a small
set of unusual transaction forms - among them a note or reference that is exactly
a certain number of digits wide - each one hinging on some exact shape of the raw
row rather than anything about the customer, and each form individually uncommon. But they occur right across the customer base, so they
generate a steady trickle of "why is this labeled wrong" tickets and, more
damaging, they poison the spending-category summaries and payee histories that
several downstream features rely on. That combination is why we are treating it
as ship-blocking rather than a backlog item.

## What we need from engineering

The labeling path is fully deterministic and runs offline - hand it the same
transaction and it reproduces the same wrong answer every time - so each of these
is reproducible on demand and can be pinned down exactly. Get the affected forms
labeling and naming correctly again, and do it without disturbing any transaction
that is already labeled right today. A fix that rescues these cases but nudges the
behavior of ordinary, currently-correct transactions is not acceptable: the pass
condition is simply that the specific problem payments described above come out
right and everything else stays exactly where it is.
