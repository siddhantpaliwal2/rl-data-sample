<uploaded_files>/app</uploaded_files>

# Lender calling: return calls misroute, tabs go deaf, ugly errors, log spam

This is a consolidated bug report from the lender CRM's calling feature (the
`loangen-agent` backend). Support and on-call have filed four related problems.
Please work through all of them.

## 1. Return calls ring the wrong browser tab — or one that can't pick up

Lenders reach borrowers from the CRM (an AI call or a "Direct Call"). When the
borrower later calls the lender's number back, the backend is supposed to ring
the borrower straight through to the **same browser tab the lender used to place
that last outbound call**, and only to a tab that is actually able to answer a
browser voice call.

What's happening instead:

- **A borrower calls back and the lender's phone in the browser never rings —
  the borrower just hears silence and then the call drops.** This happens when
  the lender has a CRM tab open and "available," but that tab has not actually
  come up on the browser voice connection (for example a tab that's logged in
  and heartbeating but where the in-browser calling device hasn't finished
  connecting). The return call is handed to that tab and dies there.

- **The return call rings a random one of the lender's open tabs**, not the tab
  where the agent was already mid-conversation with that borrower. Example: an
  agent runs a Direct Call from tab A, then also has tabs B and C open on the
  dashboard; the borrower calls back thirty seconds later and it rings tab C, so
  the agent misses the callback they were expecting in tab A.

When none of the lender's tabs can actually take the call, the borrower should
hear the lender's normal "unavailable, try later" greeting — not ring a dead tab.

## 2. A tab that was ready for calls quietly stops receiving them

Even after tab A is correctly connected for voice, agents report it "goes deaf"
after a little while of normal use: it stops being offered return calls despite
staying open and online. It correlates with the tab doing other things — taking
or ending a call, or just its normal background polling. Once a tab is connected
for voice, that readiness must **stick** until the browser actually goes away or
explicitly disconnects; ordinary presence/status updates must not silently reset
it.

## 3. Error messages expose server internals to end users

When calling can't be used, the message shown in the CRM is written for a
back-end operator, not the person using the app. Two examples users have
screenshotted:

- Trying an AI call to a non-US number shows a message that quotes the raw
  phone number, names our internal voice vendor, and even tells the user to flip
  a server environment variable.
- When calling isn't enabled on the account, the message lists several server
  configuration/environment settings by name and says the feature "is not
  configured on this server."

These should read as short, plain, user-appropriate messages (what's wrong and
what to do — e.g. use the other call type, or contact support). They must not
name environment variables, server configuration, or internal vendors.

## 4. The API access log is drowning in successful polling

The call workspace polls a few endpoints several times a second per open tab. In
production the access log is almost entirely successful (2xx/3xx) lines for that
polling, which buries everything else. Successful polling on those high-frequency
call endpoints should be dropped from the access log, while **failures on those
same endpoints (4xx/5xx) and every other route must still be logged.** The
current suppression is incomplete — it misses one of the polling endpoints and
only catches one exact success status.

## Expected outcome

All four behaviors above are corrected, the existing hermetic backend test suite
keeps passing, and no external service (database, Redis, Twilio, Cartesia) is
required to run the tests.

## Contract notes (the hidden test suite depends on these names)

Only the following names are fixed by contract — everything else about the
implementation is your choice:

- The browser's presence/heartbeat carries a boolean **`voice_registered`**
  (true once that tab is connected for inbound browser voice), and a lender
  presence record stores that flag under the key **`voice_registered`**. A
  presence update that does not carry the flag must leave the previously stored
  value unchanged.
- The access-log filter that suppresses successful call-polling lines is
  importable as **`agent.core.logging_setup.QuietPollingAccessLogFilter`**
  (a `logging.Filter` whose `.filter(record)` returns `False` to drop a line).

## Testing

Run the backend unit test suite from `/app/loangen-agent`:

    python -m pytest tests -v

Tests are hermetic — no database, Redis, Twilio, or other external service is
required. Do not modify anything under `loangen-agent/tests/`.
