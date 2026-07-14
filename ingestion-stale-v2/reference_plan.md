# Reference plan (author only — not shown to the agent)

Breadth-hardened variant of `silver-tasks/ingestion-stale-blocker/`. Same real
fix commit `a6f2dd0` ("fix the blocker queue doc upload"), same base commit
`ba5fa0a3e27c5b5a74e86d26a77271bfca1d661d` (its parent — the last broken state),
same oracle source diff (`solution/solve.sh` is byte-identical). Only the
verifier suite and the instruction change.

## Why v2 exists (round-1 gate data)

Round-1 on `ingestion-stale-blocker` showed a fairness/difficulty cliff around
the service re-queue method name:

- With `re_enqueue_stale_document` NOT published, opus/sonnet scored 0/10 — the
  recover test asserts `service.re_enqueue_stale_document(...)` is awaited and
  that name is fix-invented and underivable → unfair.
- With `re_enqueue_stale_document` published (round-3 instruction), sonnet went
  3/4 — a strong agent could mechanically implement the instruction's enumerated
  permutation matrix (the explicit `can_retry` truth-table, the per-doc field
  list, the per-function behavioral notes) → too easy.

v2 fix: **keep the published public API for fairness, defeat checklist-solving
with hidden breadth.** The instruction now states the goal + the API contract
(module path, function signatures, return semantics, response field names) but
NOT the permutation matrix. The hidden suite gains breadth tests at the public
service seams covering permutations the symptom report only implies. An agent
that implements the literal reported example but skips a permutation fails ≥1
hidden test.

## Root cause / oracle fix

Unchanged from round 1 — see the source diff in `solution/solve.sh`:
- New module `agent/documents/ingestion/stale_recovery.py`: status
  normalization, stale detection (queued/processing past a window; `ready` never
  stale; `ingestion_updated_at` with `uploaded_at` fallback; naive→UTC),
  per-application recovery, and a global reaper.
- `readiness.py`: normalize statuses, auto-recover stale docs when building
  status, compute `has_stale_jobs` / `can_retry` / `failed_document_count` /
  per-doc `is_stale`, exclude `failed` from blocking when
  `document_qa_failed_docs_non_blocking` is set.
- `service.py` gains `re_enqueue_stale_document`; `config.py` gains the window /
  reaper-interval / failed-non-blocking settings; `worker.py` gets the startup +
  periodic reaper; `schemas.py` / router surface the new payload fields.

## Verifier

Starting suite = the two round-1 gold test files (9 f2p + 8 p2p), unchanged.
Added: `tests/test_ingestion_stale_breadth.py` — 8 new hidden f2p tests at the
published public seams:

- `recover_stale_documents_for_application` (stale_recovery.py):
  - multiple stale docs recovered in one sweep (count == 3, one re-queue per
    doc, order-independent) — catches an impl that stops after the first.
  - mixed fresh+stale+ready population — only the stale doc is recovered.
  - `failed` document is NOT auto-recovered (terminal state, not "stale").
  - repeated recovery is idempotent — after a re-queue refreshes the progress
    timestamp the doc is no longer stale, so the second pass recovers 0.
  - inert (returns 0, no re-queue) when ingestion is disabled.
- `recover_all_stale_documents` (reaper): recovers the stale docs and skips the
  fresh one — catches an impl that re-queues every queued/processing row without
  re-checking staleness.
- `IngestionService.re_enqueue_stale_document` (service.py): returns False for a
  `ready` document and never enqueues it (re-queuing a finished doc is always
  wrong).
- `build_application_ingestion_status` (readiness.py): a stuck queued doc is
  reported with `has_stale_jobs=True`, `can_retry=True`, `all_ready=False`, and a
  pending entry with `status="queued"` and `is_stale=True`.

Totals: **17 f2p, 8 p2p** across `stale_recovery.py`, `service.py`,
`readiness.py`, and `config.py` (defaults). `test_config_document_intelligence.py::test_defaults_disable_ingestion_and_qa`
is deliberately excluded from p2p — it asserts ingestion is off by default, which
conflicts with the task environment enabling it.

## Fairness note (rule 4 alternative-implementation audit)

Every new test was run against a materially different but behaviorally-correct
alternative `stale_recovery.py` (different `normalize` via member iteration,
different progress-time resolution, `timedelta`-based staleness with a 60s floor,
a `_resolve_service` helper, list-comprehension query construction). All 8
breadth tests plus the 9 round-1 gold tests pass unchanged against that
alternative — the suite asserts observable behavior, not the oracle's internal
structure. The one service-seam assertion kept is `ready → False`, which is
universal (re-queuing a completed document corrupts state); the "fresh queued →
False" case was deliberately dropped because a correct implementation may rely on
the caller's staleness pre-filter rather than re-checking inside the method.
Collaborators are patched at their DEFINING modules
(`SMBApplication.get`, `UserDocument.get/find`, `DocumentIngestionJob.find`) and
fakes are `SimpleNamespace` with explicit attributes (including explicit `None`s
and `is_deleted=False`) so no bare `MagicMock` leaks into staleness or pydantic
logic.

## Key construction lessons carried over

- The environment must set `DOCUMENT_INGESTION_ENABLED=true`,
  `DOCUMENT_QA_ENABLED=true`, and dummy Azure/Qdrant/LLM values: the upstream
  readiness tests patch the wrong settings target
  (`patch("agent.core.config.settings")` replaces the module attribute, but
  `readiness`/`service` already bound the real singleton at import), so the real
  Settings gate must be open. Tests that need a specific flag use
  `patch.object(settings_singleton, ...)`.
- Imports of the base-missing module (`stale_recovery`) and of
  `IngestionService.re_enqueue_stale_document` live inside test bodies so the
  breadth file collects at base and every test emits a per-test FAILED line
  (never a file-level collection ERROR).
- Beanie field expressions (`DocumentIngestionJob.document_id == x`) raise
  `AttributeError` without `init_beanie`, so service-seam tests only exercise the
  `re_enqueue_stale_document` guards that return BEFORE the job-lookup `find`.
- The Dockerfile flattens git history to a single import commit
  (`rm -rf .git && git init ...`) so the descendant fix commit, reflog, and
  stashes cannot leak the solution.
