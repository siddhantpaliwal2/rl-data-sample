<uploaded_files>/app</uploaded_files>

# Inbound return calls ring the wrong browser (or a browser that can't answer)

## Issue details

When a lender's SMB borrower calls back the lender's Twilio number, the
`loangen-agent` backend is supposed to ring the **exact browser tab that placed
the last outbound call** to that borrower — and only a tab that is actually able
to receive a Twilio Voice call. Operations has reported three related problems
with inbound (PSTN → browser) routing:

1. **Calls ring tabs that cannot answer.** `pick_inbound_target_session` selects
   the first "available" browser session for the lender, but a session is only
   able to receive an inbound Client dial once its browser has registered with
   the Twilio Voice SDK. Sessions that are merely marked available (heartbeating)
   but have **not** registered for voice still get chosen, so the inbound call
   rings a tab that silently drops it and the borrower hears nothing.

2. **The wrong tab rings.** Even among usable sessions, routing does not prefer
   the tab that actually placed the last outbound call. A lender with several
   open tabs sees the return call ring an arbitrary one instead of the tab where
   the agent was already working with that borrower.

3. **The route never records who dialed.** `resolve_inbound_route` builds an
   `InboundRoute` from the last outbound `CallSession` but drops the browser
   session that initiated it, so nothing downstream can prefer that tab.

Underlying cause of (1): the presence records the backend stores never carry a
"voice registered" signal at all, so there is no way to tell an answerable tab
from an unanswerable one.

## Expected outcome

- A browser tab reports, on its presence heartbeat, whether it has registered
  with the Twilio Voice SDK for inbound calls. The backend must persist this
  signal on the session's presence record and preserve the last known value when
  a heartbeat does not include it (so a status-only heartbeat does not silently
  clear voice registration).
- `pick_inbound_target_session` must consider a session eligible only when it is
  **voice-registered** *and* its status is available (or AI-only). Non-registered
  sessions are skipped entirely, even if available.
- When the session that placed the last outbound call is among the eligible
  sessions, it must be chosen in preference to any other eligible session.
  Otherwise the first eligible session is used; if none are eligible the caller
  hears the lender's "unavailable" message.
- `resolve_inbound_route` must carry the browser session id that initiated the
  last outbound call, and `build_inbound_twiml` must route the inbound ring to
  that preferred session when it is still eligible.

## Public API (backend code and the test-suite import these)

- Module `agent.services.calls.inbound`:
  - dataclass `InboundRoute` — add field
    `last_outbound_initiator_session_id: str` (populated by
    `resolve_inbound_route`; empty string when unknown).
  - `pick_inbound_target_session(lender_id: str, *, preferred_session_id: Optional[str] = None) -> Optional[str]`
    — keyword-only `preferred_session_id`.
- Module `agent.services.calls.presence`:
  - `set_presence(lender_id, session_id, status, call_session_id=None, voice_registered: Optional[bool] = None) -> None`
    — `voice_registered=None` means "leave the stored value unchanged".
- Module `agent.services.calls.schemas`:
  - `PresenceHeartbeatRequest` — add field `voice_registered: bool = False`.
- Module `agent.services.calls.service`:
  - `heartbeat(..., voice_registered: bool = False)` threads the flag through to
    presence; `build_inbound_twiml(*, caller_raw, twilio_call_sid)` passes the
    last dialer's session as the preferred inbound target.

## Affected areas

The inbound-call routing and agent-presence subsystem of `loangen-agent`
(`agent/services/calls/`). Do not modify anything under `loangen-agent/tests/`.

## Testing

Run the backend unit test suite from `/app/loangen-agent`:

    python -m pytest tests -v

Tests are hermetic — no database, Redis, Twilio, or other external service is
required.
