# Reference plan (author only — not shown to the agent)

Mined from real fix commit `efab77902089a80507468f84b0d8d87c571fec6c`
("fix changes") on the boostmoney `loangenus` repo. Base commit
`5ea5f7533f01495f0259d11a0ff7384d4871857b` is its parent — the last broken
state.

## Root cause (author only)

The QuickBooks OAuth `state` token only carried `{"uid", "n"}`, so there was no
way to route a QuickBooks connect that was started from inside an invite flow
back to the invite advisor page. Intuit only echoes `code`/`state`/`realmId`, so
the signed state is the sole durable channel. The callback always redirected to
the generic success/error redirect.

## Oracle fix (scope = `loangen-agent/agent/integrations/quickbooks/`)

- `service.py`:
  - `_build_state(user_id, *, flow=None, invite_token=None)` embeds
    `flow="invite"` + `invite_token` into the signed JSON payload **only when
    both** `flow == "invite"` and a truthy `invite_token` are present.
  - `_decode_state` now returns `(payload_dict, valid)` and rejects payloads
    that are not a dict or lack `uid`.
  - New public `get_state_context(state) -> dict` returns
    `{"flow": ..., "invite_token": ...}` for a valid state (values `None` when
    absent) and `{}` for invalid/tampered/malformed state.
  - `build_auth_url(user_id, *, flow=None, invite_token=None)` threads the new
    kwargs into `_build_state`.
  - `handle_oauth_callback` now returns `(conn, context)` and extracts `uid`
    from the decoded payload dict.
- `router.py`:
  - `qb_connect` accepts `flow` / `invite_token` query params and forwards them
    to `build_auth_url` only when `flow == "invite" and invite_token`.
  - `qb_callback` reads `get_state_context(state)` up front, unpacks the
    `(conn, context)` tuple from `handle_oauth_callback`, and redirects to
    `_invite_redirect_url(invite_token, success=...)` (→
    `<frontend_url>/start/invite/<token>/advisor?qb_success=1|qb_error=1`) when a
    valid invite context is present, otherwise the existing generic redirect.

`solution/solve.sh` applies the source diff restricted to
`loangen-agent/agent/integrations/quickbooks/` (the commit's `loangen-app/`
frontend changes are irrelevant to the verifier).

## Verifier

- Gold tests are authored (the fix commit shipped no backend tests, and the
  `loangen-agent/tests/` tree does not exist at this base). One new file
  `tests/test_quickbooks_oauth_state.py`, entered only via `config.json`'s
  `test_patch`. Every `agent.*` import is inside a test body so the file
  collects at base and each f2p emits a per-test FAILED line.
- 12 fail_to_pass across 2 source files (service + router):
  - state round-trip: default has no invite context; invite flow round-trips;
    invite requires a token; an empty-string token carries no context; only the
    `"invite"` flow value is carried; a signature-tail tamper and a
    payload-segment tamper both yield `{}`; a malformed state yields `{}`;
    `auth_url` embeds the signed state.
  - callback distance (2 hops: state → `get_state_context` → redirect): invite
    success and invite failure return to `/start/invite/<token>/advisor` with
    the right `qb_success` / `qb_error` marker; a state whose invite context
    fails verification falls back to the generic redirect (no invite hijack).
- 3 pass_to_pass on state construction that the fix leaves unchanged
  (`auth_url` carries client/response_type; state has two signed parts;
  distinct users get distinct state).
- Verified in docker: null = 12 failed / 3 passed → reward 0 (each f2p FAILED
  individually, no collection errors); oracle = 15/15 → reward 1; suite < 2s,
  no network.
- Hardening (round 2): the initial 9 f2p gated Sonnet 0/5 (pass) but Opus 7/10
  (above the internal Opus ≤6/10 bar). Added 3 under-constrained permutations —
  empty-string invite token (both-required guard), payload-segment tamper
  (signature binds the invite context), and the callback fall-back-to-generic
  on a forged state — all derivable from the published contract, no new names.

## Fairness note

The instruction publishes only the two service functions the gold tests import
(`build_auth_url` new signature, `get_state_context`) plus the redirect contract
a gold test asserts — the same API-contract exception the canonical task used.
It does not reveal the both-required embedding guard, the tamper handling, the
HMAC/JSON payload structure, or how the callback wires the context into the two
redirect branches.

Alternative-implementation audit: (A) oracle embeds `flow`+`invite_token` keys
in the JSON payload; (B) an impl that keyed purely off `invite_token` presence.
Both satisfy the *published* `get_state_context` contract (keys `flow` and
`invite_token`, `None` when absent; `{}` when invalid), so no hidden test
asserts one impl over the other beyond the stated contract. The redirect target
and the `qb_success`/`qb_error` markers are likewise published, so the router
tests assert contract, not implementation. The one collaborator mocked in the
callback tests (`handle_oauth_callback`) is the module's public service function
that any correct router must call; it is replaced with an explicit
`SimpleNamespace(user_id=...)` return (no bare MagicMock), and the redirect
decision is driven by the *real* `get_state_context` over a *real*
`build_auth_url` state.
