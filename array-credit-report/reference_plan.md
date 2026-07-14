# Reference plan (author only — not shown to the agent)

Mined from real fix commit `10042f322fb57d1859b776d870c448c7c78edede`
("fix bug of the array credit report") on the boostmoney `loangenus` repo.
Base commit `894425990cd42bb4d37b813db52e14c43d8106a1` is its parent — the last
broken state. The commit also touched `loangen-app/` (Next.js frontend); those
files are irrelevant to the backend verifier and are EXCLUDED from the solution
patch.

## Root cause (author only)

The commit is a cross-cutting fix over the Array credit-connect flow that a
borrower reaches through an SMB invite. Two loosely-coupled subsystems change
together:

1. **Array bureau cascade (`agent/array/`).**
   - `service.create_user_and_get_questions` / `start_refresh_and_get_questions`
     only ever tried TransUnion OTP (`_providers_for_step("otp")`) at the start.
     A bureau that answered HTTP 204 ("can't generate questions for this
     identity") raised and aborted the whole flow — no fallback to KBA/SMFA.
   - The client had no non-raising variant of `retrieve_questions`, so the
     service could not probe a bureau and move on.
   - `CreateArrayUserRequest.ssn` allowed 4–11 chars with no digit validation,
     forwarding malformed SSNs to Array.
   - Responses had no `isTransition` flag and always used OTP copy.

2. **SMB invite flow (`agent/services/smbinvites/`).**
   - `resolve_invite` did not report whether the invited email already existed.
   - `invite_auth` took only `(raw_token, password)` — no confirm-password
     guard for brand-new users; the router did not forward a confirmation value.
   - `_next_prompt` / `_build_tracking` had no notion of a *skipped* data source,
     so a borrower who skipped one was re-prompted forever and could never reach
     review/submit.

## Oracle fix

- `client.py`: new `try_retrieve_questions` (returns `None` on 204, re-raises
  otherwise); richer 204 logging/`details`.
- `schemas.py` (array): `ssn` tightened to 9 digits with a `field_validator`
  that strips non-digits; new `isTransition` on `CreateUserAndQuestionsResponse`
  and `isTransition`/`message` on `RefreshStartResponse`.
- `service.py` (array): new `_initiate_verification_with_cascade` walking
  `_VERIFICATION_FALLBACK_ORDER` (OTP→KBA→SMFA), returning
  `(resp, failed_methods, is_transition)`; create/refresh/submit-fallback all
  route through it; new `_verification_start_message` / `_initial_cascade_message`
  copy helpers; existing-profile reuse + Array-409 recovery.
- `smbinvites/schemas.py`: `InviteResolveResponse.is_existing_user`,
  `InviteAuthRequest.confirm_password`.
- `smbinvites/service.py`: `resolve_invite` sets `is_existing_user`; `invite_auth`
  gains `confirm_password` and the `PASSWORD_MISMATCH` 400 for new users;
  `_build_tracking` / `_next_prompt` / `reply_invite_conversation` honor
  `skipped_sources`.
- `smbinvites/router.py`: `invite_auth_route` forwards `payload.confirm_password`.

`solution/solve.sh` applies the source diff restricted to the six
`loangen-agent/agent/` files above.

## Verifier

- Gold tests are authored from scratch (the fix commit touched no test files):
  `tests/test_array_credit_verification.py` and `tests/test_smb_invite_flow.py`,
  in the repo's `unittest` + `AsyncMock`/`MagicMock` style, fully offline. All
  `agent.*` imports live inside test bodies so the files collect at base and
  every test fails individually (per-test FAILED lines, no collection ERROR).
- **10 fail_to_pass** spanning all three layers of the array fix and all three
  layers of the invite fix:
  - array client: `try_retrieve_questions` returns `None` on 204.
  - array schema: dashed SSN normalized to 9 digits; short SSN rejected.
  - array service: cascade skips a 204 bureau (`failed=['otp']`, transition);
    all-204 raises `status_code=204`; first-bureau success is not a transition.
  - invite schema: `InviteResolveResponse.is_existing_user`.
  - invite router→service: `invite_auth_route` forwards `confirm_password`
    (called with 3 positional args).
  - invite service: `_next_prompt` skips a skipped source (reaches
    `review_submit`); `_build_tracking` excludes it from `pending_sources`.
- **9 pass_to_pass**: 4 stable behaviors in the two new files
  (`_normalize_auth_method`, `_providers_for_step`, `InviteAuthRequest` password
  length, an unhandled source still reported pending) + 5 unrelated, stable
  `test_required_docs.py` tests (the same stable extra file used by the
  canonical task).
- Environment sets `BUREAU_TRANSUNION/EQUIFAX/EXPERIAN=true` and a dummy
  `ARRAY_APP_KEY`. The Array HTTP client is mocked in every test, so no network
  is used; the bureau flags only matter to code paths the suite patches around.
  Verified in docker: null = 10 fail / 9 pass (reward 0), oracle = 19/19 pass
  (reward 1), suite runs in <2s with no network.

## Fairness note

The instruction names the new module paths, method names, and signatures
(`try_retrieve_questions`, `_initiate_verification_with_cascade`,
`is_existing_user`, `confirm_password`, the `skipped_sources` semantics) because
the gold tests import/call them directly — this is API contract, the same
pattern used by the canonical task. It states the observable outcomes (204→None,
cascade order, `(resp, failed, is_transition)` shape, the `PASSWORD_MISMATCH`
400) but not the implementation: the fallback-order data structure, the
`is_transition` comparison, the profile-reuse / Array-409 recovery, the exact
cascade copy strings, and the state-dict plumbing for skipped sources are left
for the solver to derive.
