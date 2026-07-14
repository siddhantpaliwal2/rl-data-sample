<uploaded_files>/app</uploaded_files>

# QuickBooks connect from an invite dumps the user on the wrong page

## Issue details

Small-business borrowers can be sent an invite link that walks them through an
onboarding flow (`/start/invite/<token>/advisor`). Part of that flow lets them
connect their QuickBooks so the advisor can read their financials.

The connect handshake goes out to Intuit and comes back to our OAuth callback.
Intuit only echoes back three things: `code`, `state`, and `realmId` — so the
signed `state` token is the *only* channel we control across the round-trip.

Operations has reported two problems for borrowers who connect QuickBooks from
inside an invite:

1. **They lose their place.** After authorizing in Intuit, the borrower is
   dropped on the generic app dashboard instead of being returned to the invite
   advisor page they started from. The same thing happens on failure — they land
   on the generic error page with no way back into their invite. Example: a
   borrower opens `/start/invite/abc123/advisor`, clicks "Connect QuickBooks",
   authorizes, and ends up at the dashboard rather than back at
   `/start/invite/abc123/advisor`.
2. **There is nowhere to put the invite context.** The connect endpoint has no
   way to say "this connect belongs to invite `abc123`", and even if it did, the
   value would have to survive the Intuit redirect. The only durable channel is
   the signed `state` token, which today carries just the user id.

A borrower who connects QuickBooks the normal way (not from an invite) must keep
working exactly as before: success returns them to the configured success
redirect with `qb_success=1`, failure to the configured error redirect with
`qb_error=1`.

## Expected outcome

- The connect step must be able to accept an optional invite context (a flow
  marker and an invite token) and thread it through the signed `state` token so
  it comes back intact on the callback. The invite context must only be carried
  when the flow is actually the invite flow **and** an invite token is present;
  a partial/absent context must not be embedded.
- The signed `state` remains tamper-evident: a modified or malformed token must
  yield no usable context (and must never be mistaken for an invite).
- On the callback, when the round-trip carries a valid invite context, redirect
  the browser back to `<frontend_url>/start/invite/<invite_token>/advisor` — with
  `qb_success=1` on success and `qb_error=1` on failure. When there is no invite
  context, keep the existing behavior (success/error redirects with
  `qb_success=1` / `qb_error=1`).

## Public API the surrounding code (and tests) rely on

Other backend code imports these from
`agent.integrations.quickbooks.service`, so the names and shapes are contract:

- `build_auth_url(user_id, *, flow=None, invite_token=None) -> QBConnectURLResponse`
  — builds the Intuit authorization URL; the returned `.state` is the signed
  token and `.auth_url` embeds it as the `state` query parameter.
- `get_state_context(state) -> dict` — decodes a signed `state` and returns the
  invite context. For any **valid** state it returns a dict with exactly the keys
  `flow` and `invite_token` (each `None` when the state carries no invite
  context). For a **missing, malformed, or tampered** state it returns an empty
  dict `{}`.

The OAuth callback continues to be reachable as the `qb_callback` handler in
`agent.integrations.quickbooks.router`.

## Affected areas

The QuickBooks OAuth integration of `loangen-agent` (state token construction /
decoding and the OAuth callback redirect). Do not modify anything under
`loangen-agent/tests/`.

## Testing

Run the backend unit test suite from `/app/loangen-agent`:

    python -m pytest tests -v

Tests are hermetic — no database, network, or Intuit sandbox is required.
