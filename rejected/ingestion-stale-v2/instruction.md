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
   submitting. Example: a bank statement left `queued` for 40 minutes after a
   worker redeploy is never picked up again.
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
  `INGESTION_STALE_JOB_MINUTES`) is considered **stale** and must be
  automatically re-queued. Building the application ingestion status must
  recover that application's stale documents, and the background worker must
  also recover stale documents at startup and re-scan for them periodically
  (interval env `INGESTION_STALE_REAPER_INTERVAL_SECONDS`, default 300).
- With failed documents treated as non-blocking (the default), a document in
  `failed` status must NOT prevent `all_ready` from becoming true; documents
  that are missing, queued, processing, or not yet queued still block.
- The status payload from `build_application_ingestion_status` must additionally
  report `has_stale_jobs` (bool), `can_retry` (bool), and `failed_document_count`
  (int), and each pending document entry must carry an `is_stale` flag.
  `can_retry` tells the UI whether offering a retry makes sense — it is true
  whenever any document still needs ingestion or has failed. Stale and failed
  documents must be surfaced in `pending_documents` (with their `status` and
  `is_stale` flag) so the banner can list them and offer a retry even when Q&A
  gating is not currently blocking submission.
- Expose the recovery logic as a new module
  `agent.documents.ingestion.stale_recovery` with this public API (other backend
  code imports these):
  - `normalize_ingestion_status(doc) -> IngestionStatus`
  - `is_stale_ingestion_document(doc) -> bool` — a document that has finished
    ingesting is never stale.
  - `recover_stale_documents_for_application(application_id, *, service=None) -> int`
    — returns the number of documents re-queued.
  - `recover_all_stale_documents(*, limit=500, service=None) -> int` — the
    background worker's reaper.
  Both `recover_*` functions are inert (return 0) when document ingestion is
  disabled.
- Re-queueing a document must go through the ingestion service so retry
  bookkeeping stays consistent: the ingestion service must expose
  `re_enqueue_stale_document(doc, *, application_id=None) -> bool` (True when the
  document was re-queued), and the recovery functions must invoke it once per
  recovered document — including when a caller supplies the service instance via
  the `service` parameter.

## Affected areas

The document ingestion subsystem of `loangen-agent` (readiness/status building,
the background worker) and application settings. Do not modify anything under
`loangen-agent/tests/`.

## Testing

Run the backend unit test suite from `/app/loangen-agent`:

    python -m pytest tests -v

Tests are hermetic — no database, queue, or external service is required.
