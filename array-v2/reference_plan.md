# Reference plan (author only — not shown to the agent)

Rebuild of `silver-tasks/array-credit-report/` at **public seams only**. Round 1
was too easy because its gold tests asserted private methods
(`_initiate_verification_with_cascade`, `_configured_bureaus`, …), which forced
the instruction to publish exact signatures — a checklist. This version drives
the same fix through the entry points a router actually calls and asserts only
observable API contract (response fields and raised errors), so the instruction
can stay a symptom report.

## Provenance

Two real fix commits on the boostmoney `loangenus` repo, both by the same
author on the Array credit-connect flow:

- `10042f322fb57d1859b776d870c448c7c78edede` ("fix bug of the array credit report")
- `2e4c15f371de36ac7f4faa19ce950f58924dfeab` ("fix the smb invite flow skip issue
  while submit the application") — a follow-up that also excludes a *skipped
  document* from the pending list in the tracking summary.

Base commit `894425990cd42bb4d37b813db52e14c43d8106a1` is the parent of the
first fix (the last fully-broken state). Both commits also touch `loangen-app/`
(Next.js frontend); those files are irrelevant to the backend verifier and are
EXCLUDED from the solution patch. The solution patch is
`git diff <base> <2e4c15f>` restricted to the six `loangen-agent/agent/**`
source files below.

## Root cause (author only)

Two loosely-coupled subsystems that ship together:

1. **Array bureau cascade (`agent/array/`).**
   - `create_user_and_get_questions` / `start_refresh_and_get_questions` only
     ever tried TransUnion OTP at the start. A bureau that answered HTTP 204
     ("can't generate questions for this identity") aborted the whole flow — no
     fallback to KBA/SMFA.
   - The client had no non-raising variant of `retrieve_questions`, so the
     service could not probe a bureau and move on.
   - `CreateArrayUserRequest.ssn` allowed 4–11 chars with no digit validation.
   - Responses had no `isTransition` flag and always used OTP copy.

2. **SMB invite flow (`agent/services/smbinvites/`).**
   - `resolve_invite` did not report whether the invited email already existed.
   - `invite_auth` took only `(raw_token, password)` — no confirm-password guard
     for brand-new users; the router dropped the confirmation value.
   - `_next_prompt` / `_build_tracking` had no notion of a *skipped* data source,
     so a borrower who skipped one was re-prompted forever; and (from 2e4c15f)
     `_build_tracking` still listed a *skipped document* as pending.

## Oracle fix

The two-commit source diff over six files:
`array/client.py` (new `try_retrieve_questions`), `array/schemas.py` (9-digit
`ssn` validator; `isTransition` on the create/refresh responses),
`array/service.py` (bureau cascade OTP→KBA→SMFA routed through create/refresh/
submit-fallback; profile reuse + Array-409 recovery; cascade copy),
`smbinvites/schemas.py` (`is_existing_user`, `confirm_password`),
`smbinvites/router.py` (forward `confirm_password`), `smbinvites/service.py`
(`resolve_invite` existing-user hint; `invite_auth` PASSWORD_MISMATCH guard;
`skipped_sources`/`skipped_documents` honored by next-prompt and tracking).
`solution/solve.sh` applies exactly this diff at base.

## Verifier design

Two new gold-test files, authored from scratch (the fix commits touched no test
files), in the repo's `unittest` style, fully offline:

- `tests/test_array_verification_cascade.py`
- `tests/test_smb_invite_public_flow.py`

**Public seams only.** The cascade is driven through
`ArrayService.create_user_and_get_questions` and `start_refresh_and_get_questions`
(the methods the Array router calls); the invite behavior through
`resolve_invite`, `invite_auth_route`→`invite_auth`, and
`reply_invite_conversation`/`start_invite_conversation`. Assertions are on the
public response objects (`CreateUserAndQuestionsResponse.isTransition`/
`.authMethod`, `RefreshStartResponse.can_refresh`/`.isTransition`,
`InviteResolveResponse.is_existing_user`, the `PASSWORD_MISMATCH` 400, the
returned conversation `prompt`/`tracking`) and on raised `ArrayClientError`s —
never on private method names, tuple shapes, or call counts.

**Persistence.** The service entry points build beanie query expressions and
persist beanie Documents, which need an initialized client. Tests initialize
beanie against an in-memory Mongo (`mongomock_motor`, installed at image build)
so the *real* service code path — profile staging, token persistence, response
assembly, conversation-state save — executes end to end with no live database.
A one-line compatibility shim lets mongomock ignore the `authorizedCollections`/
`nameOnly` kwargs beanie 2.x passes to `list_collection_names`.

**Array HTTP client.** Injected through the `ArrayService(client=…)` constructor
as an explicit fake (no MagicMock). Its per-bureau outcome sequence is drawn from
one shared iterator by both the raising (`retrieve_questions`) and non-raising
(`try_retrieve_questions`) entry points, so the fake behaves identically whether
an implementation adds a helper method or inlines the 204 try/except.

- **19 fail_to_pass** across six source files: SSN normalization/rejection (4);
  connect-flow cascade — single fallback, two-failure walk to the last bureau,
  first-bureau-not-a-transition, only-KBA-configured, only-SMFA-configured (5);
  refresh-flow cascade — fallback + first-bureau-not-a-transition (2); invite
  resolve existing/new (2); invite auth confirm-forwarded + PASSWORD_MISMATCH (2);
  conversation skip-source (single / all / one-of-two) + skip-document (4).
- **10 pass_to_pass**: 5 stable guards in the two new files (valid 9-digit SSN
  accepted, all-bureaus-exhausted still raises, refresh-without-profile
  unavailable, short-password rejected, an untouched source still pending) + the
  same 5 stable `test_required_docs.py` tests the round-1 task used.

Verified in the built image: NULL = 10/29 required passed (reward 0), every f2p
reporting a per-test FAILED line; ORACLE = 29/29 (reward 1); array-only PARTIAL
fix = 21/29 (reward 0). In-image git history length 1, empty diff, no fix commit.

## Fairness note & alternative-implementation audit

Two materially different correct cascade implementations were checked against
the hidden tests:

1. **Client helper** (oracle): add `try_retrieve_questions` and a private
   `_initiate_verification_with_cascade` walking a fallback-order table.
2. **Inline retry**: loop over configured bureaus directly inside the create/
   refresh methods, catching `ArrayClientError(status_code=204)` around
   `retrieve_questions` and continuing.

Both satisfy every f2p and p2p: the fake client's shared outcome iterator serves
either call style, and no test references the fallback table, the tuple shape,
the helper name, or a call count. `isTransition` is asserted per the stated
contract — true only when an *attempted* method failed before success, so an
unconfigured bureau that is skipped is (correctly) not a transition. The
router-forwarding test accepts the confirmation value positionally or by keyword.
SSN and PASSWORD_MISMATCH assertions are contract-level (normalized value / 400
code), independent of how the validator or guard is written. The instruction
names only API contract a competent dev could not derive from the codebase —
the `isTransition`/`is_existing_user` response fields, the `PASSWORD_MISMATCH`
code, the OTP→KBA→SMFA product order, and the nine-digit SSN rule — and never a
module path, method signature, return shape, or defect count.
