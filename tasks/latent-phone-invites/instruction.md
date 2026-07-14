<uploaded_files>/app</uploaded_files>

Subject: escalation - recurring CRM data-quality complaints from the field

I'm writing this up on behalf of Customer Success. Over the past few sprints our
account managers have logged a run of small but genuine mistakes in how the contact
tooling saves and shows two fields: a contact's mobile number and their loan type.
Every one of these has been reproduced on a live account, so please treat them as
real defects rather than user error. They only bite when a contact's details come in
a slightly off-pattern shape, which is why they slipped past everyone for weeks - the
routine cases (a plain US mobile, a loan type chosen from the dropdown) come out
perfectly correct, and our automated checks only ever exercise those routine cases.

Here is what the managers actually reported, in their words:

- "I onboarded a borrower in London and typed their mobile the way it's printed on
  their letterhead. Our workspace is configured to default to the UK, but the number
  saved under a US code (+1...) instead of the UK code (+44...)." So: when the digits
  could belong to more than one country, the contact's configured home region is being
  ignored and the wrong country is winning.

- "A few contacts gave me their number in the international style that starts with a
  double-zero access code - a 0044 UK number, for instance. Instead of accepting it,
  the tool told me the number was invalid and I had to retype it by hand." So: the 00
  international prefix isn't being treated as equivalent to a leading +.

- "One of my older accounts is tagged with a loan type from before we cleaned up the
  catalog, and the label on the record printed as 'Hardmoney' - no space - when it
  should read 'Hard Money', same word-by-word capitalization as every other loan type
  we display." So: an unfamiliar loan-type code isn't being turned into a readable,
  properly spaced and capitalized label.

- "A rep entered a loan type as 'Working_Capital', with the odd capitals and the
  underscore, and that's exactly the string that got stored on the contact - not the
  tidy internal code the rest of the system matches against." So: an oddly-cased entry
  of a known type is being stored verbatim rather than normalized to its standard code.

There may be more corners like these; those are simply the ones we could reproduce.
The common thread is that all of it is pure string-and-lookup work - deciding a
country for a number, reshaping a dialed number into storage form, and mapping a
loan-type string to its code and its display label. No database or network calls are
involved, so each case is reproducible from a direct call.

What I need from engineering: make the saved and displayed values correct for these
unusual-but-legitimate inputs, and do it without disturbing how the ordinary inputs
(the ones our current checks cover) already behave. Please don't touch the existing
test files, and confirm the current suite still passes when you're done:

    cd /app/loangen-agent && python -m pytest tests -v
