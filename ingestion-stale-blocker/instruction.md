<uploaded_files>/app</uploaded_files>

# Document ingestion jobs get stuck forever and block loan applications

## Issue details

Our SMB loan application flow ingests uploaded documents (bank statements, PFS,
appraisals) through a background worker before Document Q&A is allowed to run.
Operations has reported three related problems on the `loangen-agent` backend:

1. **Stuck jobs never recover.** When the ingestion worker is restarted or
   crashes mid-job, documents remain in `queued` or `processing` status
   indefinitely. Nothing ever re-queues them, so the application's ingestion
   status banner shows "processing" forever and the borrower is blocked from
   submitting.
2. **One failed document blocks the whole application.** If a single document
   ends up in `failed` status, `build_application_ingestion_status` reports
   `all_ready: false` permanently, which blocks Document Q&A gating for the
   entire application even though every other document is ready.
3. **The UI has no way to offer a retry.** The status payload returned by
   `build_application_ingestion_status` does not tell the frontend whether
   anything is stale or retryable, so the banner cannot render a retry action
   or a failure count.

## Expected outcome

- A queued/processing document whose ingestion has not progressed within a
  configurable stale window (default **15 minutes**, env
  `INGESTION_STALE_JOB_MINUTES`) is considered **stale**. Building the
  application ingestion status must automatically re-queue stale documents for
  that application. The background worker must also recover stale documents at
  startup and periodically re-scan for them (interval env
  `INGESTION_STALE_REAPER_INTERVAL_SECONDS`, default 300, floored at 60).
- With `DOCUMENT_QA_FAILED_DOCS_NON_BLOCKING` enabled (the default), documents
  in `failed` status must NOT prevent `all_ready` from becoming true; documents
  that are missing, queued, processing, or not queued still block.
- The status payload from `build_application_ingestion_status` must additionally
  report: `has_stale_jobs` (bool), `can_retry` (bool), `failed_document_count`
  (int), and each pending document entry must include an `is_stale` flag.
  `can_retry` must be true whenever any document is failed, stale, or still
  awaiting/undergoing ingestion (`not_queued`, `queued`, or `processing`).
  `pending_documents` must be populated whenever there are failures or stale
  jobs, even if gating is inactive.
- Expose the recovery logic as a module `agent.documents.ingestion.stale_recovery`
  with this public API (other backend code will import these):
  - `normalize_ingestion_status(doc) -> IngestionStatus` — tolerate raw string
    statuses and unknown values (unknown → `NOT_QUEUED`).
  - `is_stale_ingestion_document(doc) -> bool` — never stale for `ready`;
    fall back to `uploaded_at` when `ingestion_updated_at` is missing; treat
    naive datetimes as UTC.
  - `recover_stale_documents_for_application(application_id, *, service=None) -> int`
    — returns the number of documents re-queued; no-op (0) when ingestion is
    disabled or the application does not exist.
  - `recover_all_stale_documents(*, limit=500, service=None) -> int` — reaper
    used by the worker.
- Re-queueing a document must go through the ingestion service so retry
  bookkeeping stays consistent: the ingestion service must expose
  `re_enqueue_stale_document(doc, *, application_id=None) -> bool` (True when
  the document was re-queued), and the recovery functions must invoke it once
  per recovered document — including when a caller supplies the service
  instance via the `service` parameter.

## Affected areas

The document ingestion subsystem of `loangen-agent` (readiness/status building,
the background worker) and application settings. Do not modify anything under
`loangen-agent/tests/`.

## Testing

Run the backend unit test suite from `/app/loangen-agent`:

    python -m pytest tests -v

Tests are hermetic — no database, queue, or external service is required.
