# Reference plan (author only — not shown to the agent)

Mined from real fix commit `a6f2dd0` ("fix the blocker queue doc upload") on the
boostmoney `loangenus` repo. Base commit `ba5fa0a3e27c5b5a74e86d26a77271bfca1d661d`
is its parent — the last broken state.

## Root cause (author only)

1. `readiness.build_application_ingestion_status` treated every non-`ready`
   document as blocking and had no notion of job age. A worker crash leaves
   `queued`/`processing` rows that nothing ever touches again (queue entry is
   gone; DB status is the only record), so `all_ready` stays false forever.
2. Gating logic conflated `failed` with in-flight states — a permanent failure
   blocked Q&A with no escape hatch.
3. The status payload had no stale/retry telemetry, so the frontend could not
   distinguish "wait" from "retry".

## Oracle fix

- New module `agent/documents/ingestion/stale_recovery.py`: status
  normalization, stale detection against `ingestion_updated_at` (fallback
  `uploaded_at`, naive→UTC), per-application recovery, and a global reaper.
- `readiness.py`: normalize statuses via the new module, auto-recover stale
  docs when building status, compute `has_stale_jobs` / `can_retry` /
  `failed_document_count` / per-doc `is_stale`, and exclude `failed` from
  blocking when `document_qa_failed_docs_non_blocking` is set.
- `worker.py`: startup recovery pass + periodic reaper (interval setting,
  min 60s).
- `config.py`: `ingestion_stale_job_minutes`, `ingestion_stale_reaper_interval_seconds`,
  `document_qa_failed_docs_non_blocking` settings (+ int coercion validators).
- `service.py` gains `re_enqueue_stale_document`; `schemas.py`/router surface
  the new payload fields.

`solution/solve.sh` applies the source diff restricted to `loangen-agent/agent/`
(the same commit's frontend changes are irrelevant to the verifier).

## Verifier

- Gold tests = the two test files from the fix commit, with one hardening
  change: module-level imports of `stale_recovery` moved inside test bodies so
  the file collects at base and each test fails individually (per-test FAILED
  lines for the parser instead of one file-level collection ERROR).
- 7 fail_to_pass: 5 stale-recovery tests + 2 readiness tests
  (`test_deleted_document_ids_do_not_show_as_missing` patches the new module's
  recovery function; `test_failed_documents_do_not_block_when_non_blocking_enabled`
  asserts the new gating).
- 8 pass_to_pass: 3 untouched readiness tests + 5 `test_required_docs.py`
  tests. `test_config_document_intelligence.py` is deliberately excluded — its
  `test_defaults_disable_ingestion_and_qa` asserts ingestion is off by default,
  which conflicts with the task environment enabling it.
- Difficulty round 1 (opus-4.8 ×10): 0/10 — every agent passed 5–6/7 f2p but the
  recover test failed 10/10 because it patched `stale_recovery.UserDocument` /
  `stale_recovery.settings` as module attributes (oracle-import-style coupling).
  Round-2 hardening: recover test now patches model CLASS methods
  (`SMBApplication.get`, `UserDocument.get/find` at their defining modules) and
  detection tests rely on the documented 15-minute default instead of patching
  settings. Added 2 f2p tests on instruction-stated behaviors (can_retry for
  not_queued; pending_documents visible when gating inactive) to keep the pass
  rate inside 1–4/10. f2p is now 9.
- Difficulty round 2 (opus-4.8 ×10 on hardened tests): 0/10 again, but uniform
  16/17 — only the recover test failed, because it asserts
  `service.re_enqueue_stale_document(...)` is awaited and that method name is
  fix-invented, never published. Round-3 fix: instruction now publishes the
  service re-queue API (name + signature + return semantics). Tests unchanged.
- Environment must set `DOCUMENT_INGESTION_ENABLED=true`,
  `DOCUMENT_QA_ENABLED=true` and dummy Azure/Qdrant/LLM values — the upstream
  tests patch the wrong settings target (`agent.core.config.settings` instead of
  the module binding), so the real Settings gate must be open. Verified: with
  these env vars, null = 7 fail / 8 pass, oracle = 15/15 pass, suite runs in
  <1s with no network.

## Fairness note

The instruction names the module path and public function signatures because
the gold tests import them directly (API contract, same pattern as
route/table specs in approved tasks). It does not reveal the stale-detection
comparison, timezone handling, gating set arithmetic, or reaper structure.
