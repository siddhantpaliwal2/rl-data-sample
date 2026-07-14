# Reference plan — calls-v2

Hardened rebuild of `inbound-call-routing` (round-1 verdict: sonnet 5/5, TOO
EASY — the instruction published a function-level contract). This version uses
the **full defect surface** of the source commit and a **symptom-only**
instruction.

## Source

- Fix commit: `768b4c873606a1ee8e6f9e192167359abc35b5ab` ("fix messaging and bugs").
- Base (buggy) state: `768b4c8^` = `9c4590385df3bac827fc5b3082b25c70e274da39`.
- Solution patch = `git diff 768b4c8^ 768b4c8 -- loangen-agent/agent/` (every
  agent-source file the commit touched). `loangen-app/**` (frontend) is out of
  scope. The oracle is the full upstream backend fix.

## Root cause (four coupled defect areas)

1. **Inbound return-call routing** (`services/calls/inbound.py`,
   `services/calls/service.py::build_inbound_twiml`).
   - `pick_inbound_target_session` selects the first "available" browser session
     and ignores whether that session is actually registered for browser voice,
     so return calls are handed to tabs that cannot answer.
   - It does not prefer the tab that placed the last outbound call, so an
     arbitrary open tab rings.
   - The resolved inbound route never carries the initiating browser session, so
     nothing downstream can express that preference.

2. **Voice-presence persistence** (`services/calls/presence.py`,
   `services/calls/schemas.py`, `services/calls/router.py`,
   `services/calls/service.py::heartbeat`).
   - Presence records carry no "registered for voice" signal at all. The
     heartbeat request has no `voice_registered` field; `heartbeat` doesn't
     thread it; `set_presence` doesn't store it. And because presence is rewritten
     on every status update / call-state change, a tab that *was* registered for
     voice loses that flag on the next ordinary update ("goes deaf"). Fix:
     add `voice_registered` to the wire + presence record and **preserve** the
     stored value when an update doesn't carry it.

3. **User-facing error copy** (`services/smbcontacts/service.py`,
   `services/calls/service.py::get_voice_client_token`). Three error messages are
   written for an operator: they quote the raw dialed number, name the internal
   voice vendor, and list server environment variables. Fix: plain,
   user-appropriate copy.

4. **Access-log noise** (`core/logging_setup.py` [new], `chat_server.py`,
   `core/database.py`). The old inline uvicorn access filter covered only two of
   the three polling endpoints and only the exact `" 200 OK"` string. Fix: a
   shared `QuietPollingAccessLogFilter` that drops 2xx/3xx for all three polling
   endpoints and keeps 4xx/5xx (and every other route).

## Verifier design (behavior-level, fairness-first)

`fail_to_pass` (14) exercise observable behavior, never the oracle's internal
names, so a materially different but correct implementation passes:

- Routing: `pick_inbound_target_session` is tested only through its base
  positional signature and the published `voice_registered` presence key
  (skip-unregistered, no-eligible-target). Preference/fallback are tested
  end-to-end through `build_inbound_twiml`'s emitted TwiML (`<Client>…`), driving
  the real `resolve_inbound_route` + real `pick` with the DB/redis boundaries
  mocked — so the initiator field name and the `pick` preference kwarg are the
  candidate's choice, never asserted.
- Presence: `set_presence` / `get_presence` over a small in-memory fake redis —
  stores `voice_registered`, preserves it across a flag-less update, and clears
  it on explicit deregistration. Only the published `voice_registered` key is
  referenced.
- Messaging: the three error paths are driven to their rejection and the raised
  message is asserted to **not contain** the leaked tokens (raw number, vendor
  name, env-var names, "server"). Any user-appropriate rewrite passes.
- Logging: the commit's own `test_logging_setup.py`, with the base-missing import
  moved into the test bodies (collection succeeds at base; each test fails with a
  per-test line).

`pass_to_pass` (18): the untouched hermetic tests in `test_inbound_calls.py`
(config helpers, dial-TwiML, resolve raises/routes, unknown caller, dial-complete,
mark-answered) plus five stable `test_required_docs.py` anchors that exist at
base and are unaffected by the commit.

Two base tests that constructed `InboundRoute` positionally were replaced by the
end-to-end routing tests, because the oracle adds a required dataclass field and
a direct constructor call would pin that field name.

## Leak controls

- **Git (rule 1):** the Dockerfile resets to base, then `rm -rf .git && git init`
  + single "import codebase" commit. In-image: history length 1, `git diff`
  empty, fix commit unreachable (`git cat-file -t 768b4c8` → absent).
- **Visible tests (rule 2):** the three new test files enter only via
  `config.json.test_patch`; the agent-visible base suite (`test_inbound_calls.py`
  + `test_required_docs.py`) is green at base (20 passed).
- **Instruction (rule 3):** symptom report only — no file paths, function names,
  defect counts/shape, or fix mechanism. The only published names are the wire
  field `voice_registered` and the test-imported `QuietPollingAccessLogFilter`
  class, both underivable from the base codebase and both referenced by hidden
  tests (rule-3 exception).
- **Fairness (rule 4):** collaborators are patched at their defining module or
  faked with explicit attributes; the alternative-implementation audit (different
  field/kwarg names, comprehension filter, different preserve logic, different
  copy, string-parsing log filter) yields reward 1 on all 32 tests.

## Difficulty (rule 5)

- Breadth: 14 hidden f2p spanning 5 source files / 4 subsystems.
- Distance: the voice-registration write (heartbeat → presence) surfaces as a
  routing outcome (`build_inbound_twiml` TwiML) ≥2 hops away.
- Interaction: the read side (routing filter/preference) and write side
  (presence store/preserve) share the `voice_registered` data path — fixing one
  without the other still fails ≥2 tests. Verified: a messaging-only partial fix
  scores 20/32, reward 0.
