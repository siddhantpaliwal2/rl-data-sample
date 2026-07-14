<uploaded_files>/app</uploaded_files>

# BM-2214: Credit verification dead-ends on the first bureau; invite intake blocks valid borrowers

Ops ticket, `loangen-agent` backend. A cluster of related field reports from the
SMB credit-connect journey. All of these are backend behavior; the frontend is
out of scope.

## Identity verification gives up too early

When a borrower connects their credit, identity verification is meant to try
TransUnion OTP first, then fall back to Experian KBA, then Equifax SMFA, and
give up only once **every** configured bureau has been tried. Today it stops the
moment the first bureau reports it has no questions for that identity — even
though a later bureau could have verified the same person. Support is seeing
"we couldn't verify your identity" for borrowers who are perfectly verifiable on
the second or third method.

Two concrete reports:

- A borrower whose OTP can't be started (the bureau returns "no questions for
  this identity") is dropped on the spot instead of continuing to KBA.
- The same dead-end happens on the "refresh my credit" flow for a returning
  borrower, not just the first-time connect.

Verification should only report the terminal "we couldn't verify you after
trying every method" outcome once all configured bureaus are exhausted.

## The verification screen shows the wrong step

When verification does begin on a fallback method, the response still says
"a verification code has been sent to your phone" (the OTP copy) while the
borrower is actually in KBA or SMFA. The connect and refresh responses need to
carry an `isTransition` flag — false on a normal first-method start, true when
verification actually began on a later method after an earlier one couldn't
start — so the UI can show copy that matches the active step.

## Malformed SSNs reach the bureau

Borrowers enter their SSN with dashes or spaces (e.g. `123-45-6789`,
`123 45 6789`) or with the wrong number of digits, and it is forwarded to the
bureau verbatim and rejected there. The connect request should accept the
punctuated forms but retain exactly nine digits, and it should reject any value
that is not nine digits.

## The invite landing can't tell new borrowers from returning ones

When someone opens an invite link, the resolve response should report an
`is_existing_user` flag so the auth screen can decide between "create a password"
and "enter your existing password".

## New borrowers can lock in a typo'd password

On the invite auth step, a brand-new borrower can submit a confirmation password
that doesn't match the password they typed, and the account is still created
with the first value. When a confirmation value is supplied and does not match,
a brand-new user must be rejected with HTTP 400 (`PASSWORD_MISMATCH`) before any
account is created. The confirmation value is currently dropped before it ever
reaches that check.

## Skipping a data source or document traps the borrower

In the guided invite intake, a borrower who chooses to skip a data source (for
example a bank connection they don't want to link) is re-prompted for that same
source forever and can never reach review/submit. Skipping a source should let
the conversation move on to the next requirement, and the progress summary must
stop counting a skipped source as still pending. A skipped **document** has the
same problem: once skipped, it should drop out of the "still needed" list rather
than lingering as outstanding.

---

Verify with the offline backend suite (hermetic — no network, no live database):

```
cd /app/loangen-agent && python -m pytest tests -q
```
