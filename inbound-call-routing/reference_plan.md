# Reference plan (author only — not shown to the agent)

Mined from real fix commit `768b4c873606a1ee8e6f9e192167359abc35b5ab`
("fix messaging and bugs") on the boostmoney `loangenus` repo. This is a
multi-defect commit; this task scopes **only** the inbound-call routing / agent
presence defect. Base commit
`9c4590385df3bac827fc5b3082b25c70e274da39` is its parent — the last broken state.

## Root cause (author only)

1. `inbound.pick_inbound_target_session` picked the first browser session whose
   presence status was `available`/`on_ai_only`, with no notion of whether the
   tab had registered with the Twilio Voice SDK. Presence records carried no
   voice-registration signal at all, so an inbound Client dial could be routed
   to a tab that cannot receive it (call silently dropped).
2. Routing did not prefer the tab that placed the last outbound call, so a
   lender with multiple open tabs got the return call on an arbitrary one.
3. `InboundRoute` / `resolve_inbound_route` discarded the initiating browser
   session id of the last outbound call, so there was nothing to prefer on.

## Oracle fix (scope = `agent/services/calls/` only)

- `inbound.py`: `InboundRoute` gains `last_outbound_initiator_session_id`;
  `resolve_inbound_route` populates it from
  `last_outbound.initiated_by_session_id`. `pick_inbound_target_session` gains a
  keyword-only `preferred_session_id`, skips sessions without
  `data["voice_registered"]`, and returns the preferred session when it is among
  the eligible ones.
- `presence.py`: `set_presence` gains `voice_registered: Optional[bool]`; when
  `None` it reads the existing record and preserves the last value, otherwise it
  persists the bool on the presence payload.
- `schemas.py`: `PresenceHeartbeatRequest` gains `voice_registered: bool = False`.
- `service.py`: `heartbeat` threads `voice_registered` into `set_presence`;
  `build_inbound_twiml` passes `route.last_outbound_initiator_session_id` as the
  preferred inbound target. (The same commit also reworded one unrelated
  Direct-Call config error string in `service.py`; it rides along in the patch
  and is not asserted by any test.)
- `router.py`: the presence heartbeat endpoint forwards
  `payload.voice_registered` into `service.heartbeat`.

`solution/solve.sh` applies the source diff restricted to these five
`agent/services/calls/` files. The same commit's `chat_server.py`,
`core/database.py`, `core/logging_setup.py`, `smbcontacts/service.py`, and the
entire `loangen-app/` frontend are out of scope and excluded; the gold tests do
not import them and pass without them (verified: oracle = 22/22).

## Verifier

- Gold tests = the fix commit's `tests/test_inbound_calls.py`, used **verbatim**
  (the file already exists at base and collects there; the only cross-module
  import, `pick_inbound_target_session`, is already inside the test bodies, so no
  hardening edits were needed).
- 5 fail_to_pass (all fail individually at base with per-test FAILED lines):
  - `ResolveInboundRouteTests::test_routes_to_last_dialer_lender`
    (AttributeError: `InboundRoute` has no `last_outbound_initiator_session_id`)
  - `PickInboundTargetSessionTests::test_skips_sessions_without_voice_registration`
    (returns the non-registered `sess_a` instead of `sess_b`)
  - `PickInboundTargetSessionTests::test_prefers_last_outbound_dialer_session`
    (TypeError: no `preferred_session_id` kwarg)
  - `BuildInboundTwimlTests::test_rings_last_dialer_not_other_lender`
    (TypeError: `InboundRoute.__init__` rejects the new kwarg)
  - `BuildInboundTwimlTests::test_last_dialer_offline_plays_unavailable` (same)
- 17 pass_to_pass: the other 12 `test_inbound_calls.py` tests + 5
  `test_required_docs.py` tests (`test_required_docs.py` is untouched by the
  commit and exists at base — a stable cross-file anchor).

## Known issue and how it was handled (IMPORTANT)

At the fix commit itself, three `BuildInboundTwimlTests` tests
(`test_unknown_caller_plays_message`, `test_rings_last_dialer_not_other_lender`,
`test_last_dialer_offline_plays_unavailable`) FAIL under a bare environment —
they short-circuit to `build_inbound_twiml`'s `"This number is not accepting
calls right now."` branch. Root cause: `service.build_inbound_twiml` calls the
bare name `inbound_calls_enabled()` (imported into the `service` module
namespace), but the tests patch `agent.services.calls.inbound.inbound_calls_enabled`
— the wrong binding — so the **real** gate runs and returns False because the
direct/inbound calling settings are off by default.

This is the same class of issue as the canonical task (upstream tests patch the
wrong target, so the real Settings gate must be opened by the environment).
**Resolution: open the real gate via environment, do NOT edit any test
expectation.** The Dockerfile sets `CALLS_INBOUND_ENABLED`, `CALLS_DIRECT_ENABLED`,
`TWILIO_CALLS_ENABLED` and dummy Twilio credentials
(`TWILIO_ACCOUNT_SID/AUTH_TOKEN/API_KEY_SID/API_KEY_SECRET/TWILIO_TWIML_APP_SID`,
`PUBLIC_API_BASE_URL`, `TWILIO_OUTBOUND_CALLER_ID`) so `inbound_calls_enabled()`
(= `calls_inbound_enabled and direct_call_configured()`) is True. With the gate
open, `build_inbound_twiml` runs its real routing logic and the three tests
assert the actual fixed behavior. No gold test byte was changed from the commit.

Verified in docker: with these env vars, null (base + gold tests) = 5 failed /
17 passed with a per-test FAILED line for every fail_to_pass; oracle (base +
solution + gold tests) = 22/22 passed; suite runs in <1s with no network.

## Fairness note

The instruction names the module paths and public signatures the gold tests
import (dataclass field, `pick_inbound_target_session`'s `preferred_session_id`
kwarg, the presence/heartbeat `voice_registered` plumbing) because the tests
depend on that contract — the same precedent as route/table specs in approved
tasks. It describes the observable routing outcome (skip non-registered, prefer
last dialer, preserve the stored flag) but not the presence-payload shape, the
eligibility set arithmetic, or the redis/get_presence read-back structure.
