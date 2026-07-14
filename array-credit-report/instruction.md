<uploaded_files>/app</uploaded_files>

# BM-2214: Array credit verification dead-ends; invite flow blocks valid borrowers

Ops ticket, `loangen-agent` backend. Cluster of related field reports:

- Identity verification for credit pulls dies whenever the first bureau
  returns HTTP 204 (no questions for that identity), even though other
  configured bureaus could verify the same person. Order should be
  OTP (`tui`) → KBA (`exp`) → SMFA (`efx`); give up only when every
  configured bureau is exhausted (raise `ArrayClientError` with
  `status_code=204`). Applies to both the create and refresh entry points.
- When verification does start on a later bureau, the response doesn't say
  so — users get OTP copy ("a code was sent to your phone") while actually
  in KBA/SMFA. Responses need an `isTransition: bool` flag (default false)
  and copy that matches the active method.
- SSNs with dashes/spaces or wrong length reach Array verbatim and get
  rejected downstream. Must be validated/normalized to exactly nine digits
  at the request schema.
- The invite landing page can't distinguish new vs. returning borrowers:
  resolving an invite should report `is_existing_user: bool`.
- Brand-new invitees can set a typo'd password: when a `confirm_password`
  is supplied and doesn't match, reject with HTTP 400 (`PASSWORD_MISMATCH`).
  The `invite-auth` route must forward the confirmation value.
- Skipping a data source (e.g. a bank connection) leaves the guided
  conversation re-prompting for it forever, and the tracking summary never
  treats it as handled (`skipped_sources` ignored by next-step logic and
  `pending_sources`).

Interface requirements (other services import these):

- `agent.array.client.ArrayClient.try_retrieve_questions(self, user_id, providers) -> dict | None`
  — like `retrieve_questions` but returns `None` on HTTP 204; re-raises other errors.
- `agent.array.service.ArrayService._initiate_verification_with_cascade(self, *, array_user_id, skip_methods=None) -> (questions_response, failed_methods, is_transition)`
  — `failed_methods` = methods that returned 204 before success;
  `is_transition` = verification did not start on the first attempted method.

Only modify `agent/array/` and `agent/services/smbinvites/`. Do not touch
`loangen-agent/tests/`.

Verify: `cd /app/loangen-agent && python -m pytest tests -v` (hermetic, offline).
