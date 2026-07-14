<uploaded_files>/app</uploaded_files>

# The loanGen chat assistant is giving wrong, mislabeled, and under-informed answers

The `loangen-agent` conversation pipeline — the layer that reads a user's chat
message, works out what they're asking about, pulls the right pre-processed
financial data, and composes the assistant's reply — has started behaving
wrongly in several user-visible ways. Support and operations have collected the
reports below. None of these is caught by the existing automated tests: each bug
is correct on the common, obvious inputs and only goes wrong on cases the test
suite (and quick manual spot checks) never happen to feed, so everything looks
green while some borrowers see the wrong thing.

## Observed misbehavior

- **Some loan amounts are scaled wrong.** The dollar figure the assistant acts
  on is sometimes off by an order of magnitude. It depends on exactly how the
  borrower writes the amount: the everyday ways of stating a figure come through
  fine, but certain other ways of writing the same amount are mis-scaled, so the
  qualification analysis runs against the wrong number.

- **Credit questions sometimes get generic coaching instead of the user's real
  numbers.** When a user asks about something that clearly refers to their own
  credit or to a specific business ratio they expect us to compute, the
  assistant sometimes answers with generic "here's how to improve" coaching
  rather than reaching for that user's actual data. Questions that refer to only
  one topic are routed correctly; the misrouting clusters on questions whose
  wording touches more than one topic.

- **The opening greeting is sometimes wrong about what's connected.** For certain
  data-connection states the welcome message misrepresents the user's situation —
  it can describe access to data the user has not actually linked. Other
  connection states greet correctly.

- **The "connect your data to continue" prompt points at the wrong sources.** In
  the guided flow, when a required data source is not linked, the prompt that
  asks the user to connect it can name the wrong thing — flagging an
  already-connected source as the missing one, listing the wrong set as already
  connected, or asking for a connection when nothing required is actually
  missing.

- **Full credit reports are ignored in favor of a thin summary.** Even when a
  user's complete credit report is on file, credit questions only ever get a
  short one-line summary instead of the full report we hold for them.

## Expected outcome

Restore correct behavior for every case above, matching what the pipeline was
always meant to do, and without regressing any input that is already handled
correctly. The fixes are in the deterministic, side-effect-free routing /
extraction / formatting logic and the associated configuration default — no
external service, database, or network is involved.

Do not modify anything under `loangen-agent/tests/`.

## Testing

Run the backend unit test suite from `/app/loangen-agent`:

    python -m pytest tests -v

Tests are hermetic — no database, queue, or external service is required.
