<uploaded_files>/app</uploaded_files>

The document Q&A retrieval tools — the ones that turn a user's question and the
uploaded application documents into keyword search terms, ranked chunk results,
and extracted labelled amounts — return wrong results for certain inputs, even
though the whole test suite is green. The wrong results cluster around **short,
minimal and degenerate inputs**: a search token or phrase at the shortest length
that still counts as meaningful, a labelled statement line whose label is short,
a result set filled right up to its cap, and an item that shows up from more than
one retrieval signal and has to be merged. Away from those edges the results are
correct, which is why the existing tests — they feed ordinary-length terms and
phrases, comfortably long labels, small result sets, and already-distinct
chunks — never surface the problem.

Concretely, a few observed symptoms:

- A short but real search term from the question — a three-letter acronym like
  "LTV" or "ROI" — is dropped from the keyword terms, so a question that hinges on
  it retrieves nothing relevant. Likewise a genuine two-word phrase at its
  shortest form is dropped from the phrase list.
- A labelled statement line whose label is short (e.g. "NOI  250,000") comes back
  with no extracted amount, as if the line were malformed.
- When the same document chunk is surfaced by two different retrieval signals, the
  merged result sometimes keeps the weaker of its two scores instead of the
  stronger one, so a doubly-supported chunk can be under-ranked.

The wrong results show up in the deterministic term/label/scoring math under
`loangen-agent/agent/documents/document_qa/` — principally the hybrid-retrieval
helpers in `retrieval.py` (search-term and phrase extraction, labelled-amount
parsing, and the reciprocal-rank-fusion merge): minimum-length handling, exact
count caps, and roll-ups that merge duplicate items. This is pure,
side-effect-free arithmetic and comparison logic; the bugs are in how the
boundaries themselves are handled, not in any I/O, model, embedding, or vector
store layer.

Correct the boundary handling so these results are right on the short, minimal
and duplicate inputs, without changing behavior anywhere the current tests
already pin. The repository's existing tests all pass and must stay passing;
correctness on the edge/boundary inputs is the bar.

Do not modify anything under `loangen-agent/tests/`.

Verify with:

    cd /app/loangen-agent && python -m pytest tests -v
