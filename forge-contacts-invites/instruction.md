<uploaded_files>/app</uploaded_files>

# SMB CRM contact import, invite sending, and phone handling are broken

## Issue details

Lenders use the `loangen-agent` backend to manage SMB CRM contacts, invite those
contacts to start a loan application, and place outbound calls. Several related
regressions were reported by operations after the last release. None of these
worked this way before.

1. **Loan types entered as their display name are mangled.** When a lender uploads
   a CSV whose `loan_type` column holds the human-readable choice exactly as shown
   in the product — e.g. `SBA 7(a) Loan` or `SBA 504 Loan` — the imported contact
   comes back with a loan type of literally `SBA 7(a) Loan` instead of the stored
   code the rest of the system expects (`sba7a`). The same thing happens when a
   contact is created or edited with one of those display names in the loan-type
   field: the value is accepted but saved in a form nothing downstream recognizes.
   Loan types typed as a code (`sba7a`) or a common alias (`line of credit`) are
   still fine.

2. **Valid invites are rejected and invalid ones slip through.** Sending an
   application invite with a perfectly good loan type fails with
   `loan_type_id is not recognized. Choose a loan type from the CRM list.`, even
   for `sba7a`. Meanwhile an invite with a genuinely bogus loan type (e.g.
   `not-a-real-loan`) is accepted instead of being rejected.

3. **Indian mobile numbers get the wrong country.** A contact mobile entered
   without an international prefix — e.g. `8050306043`, an Indian mobile — used to
   be stored as `+918050306043`. Now creating or updating a contact (or importing
   one via CSV) with that number stores a wrong-country result such as a `+1` or
   `+49` number. Numbers that are already in `+91…` form, and ordinary US numbers,
   are unaffected.

4. **Re-importing a CSV to backfill a missing phone silently does nothing.** When
   a contact already exists with no phone number and the lender re-uploads a CSV
   row for that same email carrying the phone number, the import reports nothing
   updated and the contact still has no phone number saved.

5. **The guided application flow re-asks for things already provided.** In the
   invite applicant's step-by-step flow, data connections the applicant has
   already linked (e.g. their bank account) are still listed as pending/"to do".

6. **The lender's CRM loan-type hint is ignored in the guided flow.** When the
   lender has already set a loan type on the contact, the applicant flow no longer
   pre-seeds that hint, so it never offers the "your lender indicated loan type X —
   is this correct?" confirmation and just asks from scratch.

## Expected outcome

- A loan type supplied as its display label resolves to the same canonical code as
  its alias or code form, everywhere a loan type is accepted (CSV import, contact
  create/edit, and invite creation).
- Invite creation accepts any recognized loan type and rejects only unrecognized
  ones, with the existing error message reserved for the unrecognized case.
- A mobile number without a country code is normalized using the same set of
  common regions as before, so an Indian mobile like `8050306043` becomes
  `+918050306043` again; explicit `+`-prefixed and US numbers keep working.
- Re-importing a CSV row that adds a phone number to an existing contact actually
  saves the number and counts the contact as updated.
- The guided applicant flow reports already-connected data sources as connected
  (not pending) and honors the lender's CRM loan-type hint.

## Affected areas

The SMB CRM contacts, invites, and outbound-call phone handling in
`loangen-agent`. Do not modify anything under `loangen-agent/tests/`.

## Testing

Run the backend unit test suite from `/app/loangen-agent`:

    python -m pytest tests -v

Tests are hermetic — no database, queue, or external service is required.
