#!/bin/sh
# Oracle solution — applies the fix diff at base_commit.
set -eu
cd /app
git apply --check - <<'SOLUTION_PATCH_EOF' && git apply - <<'SOLUTION_PATCH_EOF'
diff --git a/loangen-agent/agent/core/config.py b/loangen-agent/agent/core/config.py
index d307117..dae1b58 100644
--- a/loangen-agent/agent/core/config.py
+++ b/loangen-agent/agent/core/config.py
@@ -171,6 +171,10 @@ class Settings(BaseSettings):
     ingestion_worker_embedded: bool = True
     """When true, chat_server starts the ingestion worker in-process (local dev only). Set false for UAT/prod and run agent.documents.ingestion.worker separately."""
     ingestion_max_retries: int = 3
+    ingestion_stale_job_minutes: int = 15
+    """Mark queued/processing jobs stale after this many minutes and re-queue them."""
+    ingestion_stale_reaper_interval_seconds: int = 300
+    """How often the ingestion worker scans for stale jobs (default 5 min)."""
     document_ingestion_max_pages: int = 500
     document_ingestion_chunk_size: int = 600
     document_ingestion_chunk_overlap: int = 80
@@ -188,6 +192,8 @@ class Settings(BaseSettings):
     document_qa_excerpt_max_chars: int = 900
     document_qa_cache_ttl_seconds: int = 86400
     document_qa_block_until_ready: bool = True
+    document_qa_failed_docs_non_blocking: bool = True
+    """When true, failed ingestion does not block Document Q&A gating (ready + failed = unblocked)."""
 
     # Redact SSN / account numbers before persisting chunks and extractions
     document_pii_redaction_enabled: bool = True
@@ -672,6 +678,8 @@ class Settings(BaseSettings):
     @field_validator(
         "ingestion_worker_concurrency",
         "ingestion_max_retries",
+        "ingestion_stale_job_minutes",
+        "ingestion_stale_reaper_interval_seconds",
         "document_ingestion_max_pages",
         "document_ingestion_chunk_size",
         "document_ingestion_chunk_overlap",
diff --git a/loangen-agent/agent/documents/ingestion/readiness.py b/loangen-agent/agent/documents/ingestion/readiness.py
index 774efd6..d3ea3b1 100644
--- a/loangen-agent/agent/documents/ingestion/readiness.py
+++ b/loangen-agent/agent/documents/ingestion/readiness.py
@@ -123,10 +123,12 @@ async def build_application_ingestion_status(application_id: str) -> Dict[str, A
     Full ingestion status for lender/SMB UI banners.
 
     When ingestion or document Q&A gating is off, all_ready is True and pending is empty.
+    Automatically recovers stale queued/processing jobs for this application.
     """
     ingestion_enabled = settings.document_ingestion_enabled
     qa_enabled = settings.document_qa_enabled
     block_until_ready = settings.document_qa_block_until_ready
+    failed_non_blocking = settings.document_qa_failed_docs_non_blocking
 
     base: Dict[str, Any] = {
         "application_id": application_id,
@@ -138,6 +140,9 @@ async def build_application_ingestion_status(application_id: str) -> Dict[str, A
         "total_document_count": 0,
         "ready_document_count": 0,
         "has_failures": False,
+        "has_stale_jobs": False,
+        "can_retry": False,
+        "failed_document_count": 0,
     }
 
     if not ingestion_enabled:
@@ -151,6 +156,10 @@ async def build_application_ingestion_status(application_id: str) -> Dict[str, A
 
     await prune_stale_application_document_ids(app)
 
+    from agent.documents.ingestion.stale_recovery import recover_stale_documents_for_application
+
+    await recover_stale_documents_for_application(application_id)
+
     doc_ids = await get_application_document_ids(app)
     base["total_document_count"] = len(doc_ids)
     if not doc_ids:
@@ -162,13 +171,14 @@ async def build_application_ingestion_status(application_id: str) -> Dict[str, A
         if doc is None or doc.is_deleted:
             pending.append({"document_id": doc_id, "status": "missing"})
             continue
-        status = getattr(doc, "ingestion_status", IngestionStatus.NOT_QUEUED)
-        if isinstance(status, str):
-            try:
-                status = IngestionStatus(status)
-            except ValueError:
-                status = IngestionStatus.NOT_QUEUED
+        from agent.documents.ingestion.stale_recovery import (
+            is_stale_ingestion_document,
+            normalize_ingestion_status,
+        )
+
+        status = normalize_ingestion_status(doc)
         if status != IngestionStatus.READY:
+            stale = is_stale_ingestion_document(doc)
             pending.append(
                 {
                     "document_id": doc_id,
@@ -176,21 +186,48 @@ async def build_application_ingestion_status(application_id: str) -> Dict[str, A
                     "document_type": doc.document_type.value,
                     "status": status.value,
                     "error": getattr(doc, "ingestion_error", None),
+                    "is_stale": stale,
                 }
             )
 
     ready_count = len(doc_ids) - len(pending)
     has_failures = any(p.get("status") == IngestionStatus.FAILED.value for p in pending)
+    has_stale_jobs = any(
+        p.get("is_stale") and p.get("status") in (IngestionStatus.QUEUED.value, IngestionStatus.PROCESSING.value)
+        for p in pending
+    )
+    failed_count = sum(1 for p in pending if p.get("status") == IngestionStatus.FAILED.value)
 
     gating_active = qa_enabled and block_until_ready
-    all_ready = len(pending) == 0 if gating_active else True
+    if gating_active and failed_non_blocking:
+        blocking_pending = [
+            p
+            for p in pending
+            if p.get("status") not in (IngestionStatus.FAILED.value,)
+        ]
+    else:
+        blocking_pending = pending
+    all_ready = len(blocking_pending) == 0 if gating_active else True
+
+    can_retry = bool(
+        has_failures
+        or has_stale_jobs
+        or any(
+            p.get("status") in (IngestionStatus.QUEUED.value, IngestionStatus.PROCESSING.value)
+            for p in pending
+        )
+        or any(p.get("status") == IngestionStatus.NOT_QUEUED.value for p in pending)
+    )
 
     base.update(
         {
             "all_ready": all_ready,
-            "pending_documents": pending if gating_active else [],
+            "pending_documents": pending if (gating_active or has_failures or has_stale_jobs) else [],
             "ready_document_count": ready_count,
             "has_failures": has_failures,
+            "has_stale_jobs": has_stale_jobs,
+            "can_retry": can_retry,
+            "failed_document_count": failed_count,
         }
     )
     return base
diff --git a/loangen-agent/agent/documents/ingestion/service.py b/loangen-agent/agent/documents/ingestion/service.py
index 10a43cc..28f6fdd 100644
--- a/loangen-agent/agent/documents/ingestion/service.py
+++ b/loangen-agent/agent/documents/ingestion/service.py
@@ -18,6 +18,10 @@ from agent.documents.extractors.generic import extract_structured_fields
 from agent.documents.ingestion.chunking import chunk_text
 from agent.documents.ingestion.embeddings import EmbeddingService
 from agent.documents.ingestion.queue import IngestionQueue
+from agent.documents.ingestion.stale_recovery import (
+    is_stale_ingestion_document,
+    normalize_ingestion_status,
+)
 from agent.documents.intelligence_models import (
     DocumentChunk,
     DocumentExtraction,
@@ -101,6 +105,8 @@ class IngestionService:
         application_id: str,
         user_id: str,
         document_ids: List[str],
+        *,
+        force: bool = False,
     ) -> int:
         count = 0
         for doc_id in document_ids:
@@ -111,14 +117,16 @@ class IngestionService:
                 doc.used_in_applications = list(doc.used_in_applications) + [application_id]
                 await doc.save()
 
-            status = getattr(doc, "ingestion_status", IngestionStatus.NOT_QUEUED)
-            if isinstance(status, str):
-                try:
-                    status = IngestionStatus(status)
-                except ValueError:
-                    status = IngestionStatus.NOT_QUEUED
+            status = normalize_ingestion_status(doc)
 
             if status in {IngestionStatus.QUEUED, IngestionStatus.PROCESSING}:
+                if force or is_stale_ingestion_document(doc):
+                    if await self.re_enqueue_stale_document(
+                        doc,
+                        application_id=application_id,
+                        force=force,
+                    ):
+                        count += 1
                 continue
 
             from agent.documents.intelligence_models import DocumentChunk
@@ -128,19 +136,88 @@ class IngestionService:
                 DocumentChunk.application_id == application_id,
             ).count()
 
-            if status == IngestionStatus.READY and indexed_for_app > 0:
+            if status == IngestionStatus.READY and indexed_for_app > 0 and not force:
                 continue
 
-            force = status == IngestionStatus.READY and indexed_for_app == 0
+            should_force = force or (status == IngestionStatus.READY and indexed_for_app == 0)
+            if status == IngestionStatus.FAILED:
+                should_force = True
             job_id = await self.enqueue_document(
                 doc_id,
                 application_id=application_id,
-                force=force,
+                force=should_force,
             )
             if job_id is not None:
                 count += 1
         return count
 
+    async def re_enqueue_stale_document(
+        self,
+        doc: UserDocument,
+        *,
+        application_id: Optional[str] = None,
+        force: bool = False,
+    ) -> bool:
+        """
+        Re-push a queued/processing document to Redis.
+
+        When ``force`` is false, only documents past the stale threshold are re-queued.
+        """
+        if not settings.document_ingestion_enabled:
+            return False
+
+        status = normalize_ingestion_status(doc)
+        if status not in {IngestionStatus.QUEUED, IngestionStatus.PROCESSING}:
+            return False
+        if not force and not is_stale_ingestion_document(doc):
+            return False
+
+        app_id = application_id or (
+            doc.used_in_applications[0] if doc.used_in_applications else None
+        )
+        version = int(getattr(doc, "ingestion_version", 0) or 1)
+
+        jobs = (
+            await DocumentIngestionJob.find(
+                DocumentIngestionJob.document_id == str(doc.id),
+            )
+            .sort(-DocumentIngestionJob.created_at)
+            .limit(1)
+            .to_list()
+        )
+        job = jobs[0] if jobs else None
+
+        if job and job.attempt_count < job.max_attempts:
+            payload = {
+                "job_id": str(job.id),
+                "document_id": str(doc.id),
+                "application_id": app_id or job.application_id,
+                "ingestion_version": version,
+            }
+            queued = await self._queue.enqueue(payload)
+            if queued:
+                doc.ingestion_status = IngestionStatus.QUEUED
+                doc.ingestion_error = (
+                    "Re-queued manually for ingestion retry."
+                    if force
+                    else "Re-queued after stale ingestion job recovery."
+                )
+                doc.ingestion_updated_at = datetime.now(timezone.utc)
+                await doc.save()
+                job.status = IngestionStatus.QUEUED
+                job.error_message = None
+                job.updated_at = datetime.now(timezone.utc)
+                await job.save()
+                logger.info("Re-queued stale ingestion job document_id=%s", doc.id)
+                return True
+
+        job_id = await self.enqueue_document(
+            str(doc.id),
+            application_id=app_id,
+            force=True,
+        )
+        return job_id is not None
+
     async def process_job_payload(self, payload: Dict[str, Any]) -> None:
         job_id = payload.get("job_id")
         job = await DocumentIngestionJob.get(job_id) if job_id else None
diff --git a/loangen-agent/agent/documents/ingestion/stale_recovery.py b/loangen-agent/agent/documents/ingestion/stale_recovery.py
new file mode 100644
index 0000000..9f64de6
--- /dev/null
+++ b/loangen-agent/agent/documents/ingestion/stale_recovery.py
@@ -0,0 +1,129 @@
+"""Detect and recover document ingestion jobs stuck in queued/processing."""
+
+from __future__ import annotations
+
+import logging
+from datetime import datetime, timezone
+from typing import TYPE_CHECKING, Optional
+
+from agent.core.config import settings
+from agent.documents.enums import IngestionStatus
+from agent.documents.models import UserDocument
+
+if TYPE_CHECKING:
+    from agent.documents.ingestion.service import IngestionService
+
+logger = logging.getLogger("loangen-documents.ingestion.stale_recovery")
+
+
+def ingestion_stale_after_seconds() -> int:
+    return max(60, int(settings.ingestion_stale_job_minutes) * 60)
+
+
+def normalize_ingestion_status(doc: UserDocument) -> IngestionStatus:
+    status = getattr(doc, "ingestion_status", IngestionStatus.NOT_QUEUED)
+    if isinstance(status, IngestionStatus):
+        return status
+    try:
+        return IngestionStatus(status)
+    except ValueError:
+        return IngestionStatus.NOT_QUEUED
+
+
+def document_status_updated_at(doc: UserDocument) -> datetime:
+    updated = getattr(doc, "ingestion_updated_at", None)
+    if isinstance(updated, datetime):
+        if updated.tzinfo is None:
+            return updated.replace(tzinfo=timezone.utc)
+        return updated
+    uploaded = getattr(doc, "uploaded_at", None)
+    if isinstance(uploaded, datetime):
+        if uploaded.tzinfo is None:
+            return uploaded.replace(tzinfo=timezone.utc)
+        return uploaded
+    return datetime.now(timezone.utc)
+
+
+def is_stale_ingestion_document(doc: UserDocument) -> bool:
+    """True when a queued/processing document has not progressed within the stale window."""
+    status = normalize_ingestion_status(doc)
+    if status not in {IngestionStatus.QUEUED, IngestionStatus.PROCESSING}:
+        return False
+    age_seconds = (datetime.now(timezone.utc) - document_status_updated_at(doc)).total_seconds()
+    return age_seconds >= ingestion_stale_after_seconds()
+
+
+async def recover_stale_documents_for_application(
+    application_id: str,
+    *,
+    service: Optional["IngestionService"] = None,
+) -> int:
+    """Re-queue stale jobs for one application. Returns number of documents recovered."""
+    if not settings.document_ingestion_enabled:
+        return 0
+
+    from agent.documents.ingestion.readiness import get_application_document_ids
+    from agent.services.smbapplications.models import SMBApplication
+
+    app = await SMBApplication.get(application_id)
+    if app is None:
+        return 0
+
+    if service is None:
+        from agent.documents.ingestion.service import IngestionService
+
+        svc = IngestionService()
+    else:
+        svc = service
+    doc_ids = await get_application_document_ids(app)
+    recovered = 0
+    for doc_id in doc_ids:
+        doc = await UserDocument.get(doc_id)
+        if doc is None or doc.is_deleted:
+            continue
+        if not is_stale_ingestion_document(doc):
+            continue
+        if await svc.re_enqueue_stale_document(doc, application_id=application_id):
+            recovered += 1
+    if recovered:
+        logger.info(
+            "Recovered %s stale ingestion job(s) for application_id=%s",
+            recovered,
+            application_id,
+        )
+    return recovered
+
+
+async def recover_all_stale_documents(
+    *,
+    limit: int = 500,
+    service: Optional["IngestionService"] = None,
+) -> int:
+    """Scan recent non-ready documents and re-queue stale ones (worker reaper)."""
+    if not settings.document_ingestion_enabled:
+        return 0
+
+    if service is None:
+        from agent.documents.ingestion.service import IngestionService
+
+        svc = IngestionService()
+    else:
+        svc = service
+    cursor = UserDocument.find(
+        {
+            "is_deleted": False,
+            "ingestion_status": {"$in": [IngestionStatus.QUEUED.value, IngestionStatus.PROCESSING.value]},
+        }
+    ).limit(max(1, limit))
+
+    docs = await cursor.to_list()
+    recovered = 0
+    for doc in docs:
+        if not is_stale_ingestion_document(doc):
+            continue
+        app_id = doc.used_in_applications[0] if doc.used_in_applications else None
+        if await svc.re_enqueue_stale_document(doc, application_id=app_id):
+            recovered += 1
+    if recovered:
+        logger.info("Stale ingestion reaper recovered %s document(s)", recovered)
+    return recovered
diff --git a/loangen-agent/agent/documents/ingestion/worker.py b/loangen-agent/agent/documents/ingestion/worker.py
index c47790e..1358389 100644
--- a/loangen-agent/agent/documents/ingestion/worker.py
+++ b/loangen-agent/agent/documents/ingestion/worker.py
@@ -58,7 +58,27 @@ class EmbeddedIngestionWorker:
         sem = asyncio.Semaphore(concurrency)
         logger.info("Ingestion worker started (concurrency=%s)", concurrency)
 
+        from agent.documents.ingestion.stale_recovery import recover_all_stale_documents
+
+        try:
+            recovered = await recover_all_stale_documents(service=service)
+            if recovered:
+                logger.info("Startup stale ingestion recovery: %s document(s)", recovered)
+        except Exception as exc:
+            logger.error("Startup stale ingestion recovery failed: %s", exc)
+
+        last_reaper_at = asyncio.get_event_loop().time()
+        reaper_interval = max(60, int(settings.ingestion_stale_reaper_interval_seconds))
+
         while not self._shutdown.is_set():
+            now = asyncio.get_event_loop().time()
+            if now - last_reaper_at >= reaper_interval:
+                last_reaper_at = now
+                try:
+                    await recover_all_stale_documents(service=service)
+                except Exception as exc:
+                    logger.error("Stale ingestion reaper failed: %s", exc)
+
             try:
                 payload = await queue.dequeue(timeout_seconds=5)
             except Exception as exc:
diff --git a/loangen-agent/agent/documents/schemas.py b/loangen-agent/agent/documents/schemas.py
index 6e2b2c1..e317a81 100644
--- a/loangen-agent/agent/documents/schemas.py
+++ b/loangen-agent/agent/documents/schemas.py
@@ -99,6 +99,9 @@ class ApplicationIngestionStatusResponse(BaseModel):
     total_document_count: int = 0
     ready_document_count: int = 0
     has_failures: bool = False
+    has_stale_jobs: bool = False
+    can_retry: bool = False
+    failed_document_count: int = 0
 
 
 class DocumentListResponse(BaseModel):
diff --git a/loangen-agent/agent/services/smbapplications/router.py b/loangen-agent/agent/services/smbapplications/router.py
index deabc81..261aa32 100644
--- a/loangen-agent/agent/services/smbapplications/router.py
+++ b/loangen-agent/agent/services/smbapplications/router.py
@@ -1232,6 +1232,7 @@ async def lender_application_ingestion_status(
 )
 async def retry_lender_application_ingestion(
     application_id: str,
+    force: int | None = Query(1, description="1 = re-queue stuck/failed docs (default)"),
     lender: Lender = Depends(get_current_lender),
 ):
     from agent.documents.ingestion.readiness import get_application_document_ids
@@ -1248,8 +1249,13 @@ async def retry_lender_application_ingestion(
 
     svc = IngestionService()
     doc_ids = await get_application_document_ids(app)
-    count = await svc.enqueue_application_documents(application_id, app.user_id, doc_ids)
-    return {"enqueued": count, "application_id": application_id}
+    count = await svc.enqueue_application_documents(
+        application_id,
+        app.user_id,
+        doc_ids,
+        force=force == 1,
+    )
+    return {"enqueued": count, "application_id": application_id, "force": force == 1}
 
 
 @router.post(
@@ -1411,6 +1417,7 @@ async def smb_application_ingestion_status(
 )
 async def retry_smb_application_ingestion(
     application_id: str,
+    force: int | None = Query(1, description="1 = re-queue stuck/failed docs (default)"),
     current_user: User = Depends(get_current_user),
 ):
     from agent.documents.ingestion.readiness import get_application_document_ids
@@ -1424,5 +1431,10 @@ async def retry_smb_application_ingestion(
 
     svc = IngestionService()
     doc_ids = await get_application_document_ids(app)
-    count = await svc.enqueue_application_documents(application_id, str(current_user.id), doc_ids)
-    return {"enqueued": count, "application_id": application_id}
+    count = await svc.enqueue_application_documents(
+        application_id,
+        str(current_user.id),
+        doc_ids,
+        force=force == 1,
+    )
+    return {"enqueued": count, "application_id": application_id, "force": force == 1}
SOLUTION_PATCH_EOF
diff --git a/loangen-agent/agent/core/config.py b/loangen-agent/agent/core/config.py
index d307117..dae1b58 100644
--- a/loangen-agent/agent/core/config.py
+++ b/loangen-agent/agent/core/config.py
@@ -171,6 +171,10 @@ class Settings(BaseSettings):
     ingestion_worker_embedded: bool = True
     """When true, chat_server starts the ingestion worker in-process (local dev only). Set false for UAT/prod and run agent.documents.ingestion.worker separately."""
     ingestion_max_retries: int = 3
+    ingestion_stale_job_minutes: int = 15
+    """Mark queued/processing jobs stale after this many minutes and re-queue them."""
+    ingestion_stale_reaper_interval_seconds: int = 300
+    """How often the ingestion worker scans for stale jobs (default 5 min)."""
     document_ingestion_max_pages: int = 500
     document_ingestion_chunk_size: int = 600
     document_ingestion_chunk_overlap: int = 80
@@ -188,6 +192,8 @@ class Settings(BaseSettings):
     document_qa_excerpt_max_chars: int = 900
     document_qa_cache_ttl_seconds: int = 86400
     document_qa_block_until_ready: bool = True
+    document_qa_failed_docs_non_blocking: bool = True
+    """When true, failed ingestion does not block Document Q&A gating (ready + failed = unblocked)."""
 
     # Redact SSN / account numbers before persisting chunks and extractions
     document_pii_redaction_enabled: bool = True
@@ -672,6 +678,8 @@ class Settings(BaseSettings):
     @field_validator(
         "ingestion_worker_concurrency",
         "ingestion_max_retries",
+        "ingestion_stale_job_minutes",
+        "ingestion_stale_reaper_interval_seconds",
         "document_ingestion_max_pages",
         "document_ingestion_chunk_size",
         "document_ingestion_chunk_overlap",
diff --git a/loangen-agent/agent/documents/ingestion/readiness.py b/loangen-agent/agent/documents/ingestion/readiness.py
index 774efd6..d3ea3b1 100644
--- a/loangen-agent/agent/documents/ingestion/readiness.py
+++ b/loangen-agent/agent/documents/ingestion/readiness.py
@@ -123,10 +123,12 @@ async def build_application_ingestion_status(application_id: str) -> Dict[str, A
     Full ingestion status for lender/SMB UI banners.
 
     When ingestion or document Q&A gating is off, all_ready is True and pending is empty.
+    Automatically recovers stale queued/processing jobs for this application.
     """
     ingestion_enabled = settings.document_ingestion_enabled
     qa_enabled = settings.document_qa_enabled
     block_until_ready = settings.document_qa_block_until_ready
+    failed_non_blocking = settings.document_qa_failed_docs_non_blocking
 
     base: Dict[str, Any] = {
         "application_id": application_id,
@@ -138,6 +140,9 @@ async def build_application_ingestion_status(application_id: str) -> Dict[str, A
         "total_document_count": 0,
         "ready_document_count": 0,
         "has_failures": False,
+        "has_stale_jobs": False,
+        "can_retry": False,
+        "failed_document_count": 0,
     }
 
     if not ingestion_enabled:
@@ -151,6 +156,10 @@ async def build_application_ingestion_status(application_id: str) -> Dict[str, A
 
     await prune_stale_application_document_ids(app)
 
+    from agent.documents.ingestion.stale_recovery import recover_stale_documents_for_application
+
+    await recover_stale_documents_for_application(application_id)
+
     doc_ids = await get_application_document_ids(app)
     base["total_document_count"] = len(doc_ids)
     if not doc_ids:
@@ -162,13 +171,14 @@ async def build_application_ingestion_status(application_id: str) -> Dict[str, A
         if doc is None or doc.is_deleted:
             pending.append({"document_id": doc_id, "status": "missing"})
             continue
-        status = getattr(doc, "ingestion_status", IngestionStatus.NOT_QUEUED)
-        if isinstance(status, str):
-            try:
-                status = IngestionStatus(status)
-            except ValueError:
-                status = IngestionStatus.NOT_QUEUED
+        from agent.documents.ingestion.stale_recovery import (
+            is_stale_ingestion_document,
+            normalize_ingestion_status,
+        )
+
+        status = normalize_ingestion_status(doc)
         if status != IngestionStatus.READY:
+            stale = is_stale_ingestion_document(doc)
             pending.append(
                 {
                     "document_id": doc_id,
@@ -176,21 +186,48 @@ async def build_application_ingestion_status(application_id: str) -> Dict[str, A
                     "document_type": doc.document_type.value,
                     "status": status.value,
                     "error": getattr(doc, "ingestion_error", None),
+                    "is_stale": stale,
                 }
             )
 
     ready_count = len(doc_ids) - len(pending)
     has_failures = any(p.get("status") == IngestionStatus.FAILED.value for p in pending)
+    has_stale_jobs = any(
+        p.get("is_stale") and p.get("status") in (IngestionStatus.QUEUED.value, IngestionStatus.PROCESSING.value)
+        for p in pending
+    )
+    failed_count = sum(1 for p in pending if p.get("status") == IngestionStatus.FAILED.value)
 
     gating_active = qa_enabled and block_until_ready
-    all_ready = len(pending) == 0 if gating_active else True
+    if gating_active and failed_non_blocking:
+        blocking_pending = [
+            p
+            for p in pending
+            if p.get("status") not in (IngestionStatus.FAILED.value,)
+        ]
+    else:
+        blocking_pending = pending
+    all_ready = len(blocking_pending) == 0 if gating_active else True
+
+    can_retry = bool(
+        has_failures
+        or has_stale_jobs
+        or any(
+            p.get("status") in (IngestionStatus.QUEUED.value, IngestionStatus.PROCESSING.value)
+            for p in pending
+        )
+        or any(p.get("status") == IngestionStatus.NOT_QUEUED.value for p in pending)
+    )
 
     base.update(
         {
             "all_ready": all_ready,
-            "pending_documents": pending if gating_active else [],
+            "pending_documents": pending if (gating_active or has_failures or has_stale_jobs) else [],
             "ready_document_count": ready_count,
             "has_failures": has_failures,
+            "has_stale_jobs": has_stale_jobs,
+            "can_retry": can_retry,
+            "failed_document_count": failed_count,
         }
     )
     return base
diff --git a/loangen-agent/agent/documents/ingestion/service.py b/loangen-agent/agent/documents/ingestion/service.py
index 10a43cc..28f6fdd 100644
--- a/loangen-agent/agent/documents/ingestion/service.py
+++ b/loangen-agent/agent/documents/ingestion/service.py
@@ -18,6 +18,10 @@ from agent.documents.extractors.generic import extract_structured_fields
 from agent.documents.ingestion.chunking import chunk_text
 from agent.documents.ingestion.embeddings import EmbeddingService
 from agent.documents.ingestion.queue import IngestionQueue
+from agent.documents.ingestion.stale_recovery import (
+    is_stale_ingestion_document,
+    normalize_ingestion_status,
+)
 from agent.documents.intelligence_models import (
     DocumentChunk,
     DocumentExtraction,
@@ -101,6 +105,8 @@ class IngestionService:
         application_id: str,
         user_id: str,
         document_ids: List[str],
+        *,
+        force: bool = False,
     ) -> int:
         count = 0
         for doc_id in document_ids:
@@ -111,14 +117,16 @@ class IngestionService:
                 doc.used_in_applications = list(doc.used_in_applications) + [application_id]
                 await doc.save()
 
-            status = getattr(doc, "ingestion_status", IngestionStatus.NOT_QUEUED)
-            if isinstance(status, str):
-                try:
-                    status = IngestionStatus(status)
-                except ValueError:
-                    status = IngestionStatus.NOT_QUEUED
+            status = normalize_ingestion_status(doc)
 
             if status in {IngestionStatus.QUEUED, IngestionStatus.PROCESSING}:
+                if force or is_stale_ingestion_document(doc):
+                    if await self.re_enqueue_stale_document(
+                        doc,
+                        application_id=application_id,
+                        force=force,
+                    ):
+                        count += 1
                 continue
 
             from agent.documents.intelligence_models import DocumentChunk
@@ -128,19 +136,88 @@ class IngestionService:
                 DocumentChunk.application_id == application_id,
             ).count()
 
-            if status == IngestionStatus.READY and indexed_for_app > 0:
+            if status == IngestionStatus.READY and indexed_for_app > 0 and not force:
                 continue
 
-            force = status == IngestionStatus.READY and indexed_for_app == 0
+            should_force = force or (status == IngestionStatus.READY and indexed_for_app == 0)
+            if status == IngestionStatus.FAILED:
+                should_force = True
             job_id = await self.enqueue_document(
                 doc_id,
                 application_id=application_id,
-                force=force,
+                force=should_force,
             )
             if job_id is not None:
                 count += 1
         return count
 
+    async def re_enqueue_stale_document(
+        self,
+        doc: UserDocument,
+        *,
+        application_id: Optional[str] = None,
+        force: bool = False,
+    ) -> bool:
+        """
+        Re-push a queued/processing document to Redis.
+
+        When ``force`` is false, only documents past the stale threshold are re-queued.
+        """
+        if not settings.document_ingestion_enabled:
+            return False
+
+        status = normalize_ingestion_status(doc)
+        if status not in {IngestionStatus.QUEUED, IngestionStatus.PROCESSING}:
+            return False
+        if not force and not is_stale_ingestion_document(doc):
+            return False
+
+        app_id = application_id or (
+            doc.used_in_applications[0] if doc.used_in_applications else None
+        )
+        version = int(getattr(doc, "ingestion_version", 0) or 1)
+
+        jobs = (
+            await DocumentIngestionJob.find(
+                DocumentIngestionJob.document_id == str(doc.id),
+            )
+            .sort(-DocumentIngestionJob.created_at)
+            .limit(1)
+            .to_list()
+        )
+        job = jobs[0] if jobs else None
+
+        if job and job.attempt_count < job.max_attempts:
+            payload = {
+                "job_id": str(job.id),
+                "document_id": str(doc.id),
+                "application_id": app_id or job.application_id,
+                "ingestion_version": version,
+            }
+            queued = await self._queue.enqueue(payload)
+            if queued:
+                doc.ingestion_status = IngestionStatus.QUEUED
+                doc.ingestion_error = (
+                    "Re-queued manually for ingestion retry."
+                    if force
+                    else "Re-queued after stale ingestion job recovery."
+                )
+                doc.ingestion_updated_at = datetime.now(timezone.utc)
+                await doc.save()
+                job.status = IngestionStatus.QUEUED
+                job.error_message = None
+                job.updated_at = datetime.now(timezone.utc)
+                await job.save()
+                logger.info("Re-queued stale ingestion job document_id=%s", doc.id)
+                return True
+
+        job_id = await self.enqueue_document(
+            str(doc.id),
+            application_id=app_id,
+            force=True,
+        )
+        return job_id is not None
+
     async def process_job_payload(self, payload: Dict[str, Any]) -> None:
         job_id = payload.get("job_id")
         job = await DocumentIngestionJob.get(job_id) if job_id else None
diff --git a/loangen-agent/agent/documents/ingestion/stale_recovery.py b/loangen-agent/agent/documents/ingestion/stale_recovery.py
new file mode 100644
index 0000000..9f64de6
--- /dev/null
+++ b/loangen-agent/agent/documents/ingestion/stale_recovery.py
@@ -0,0 +1,129 @@
+"""Detect and recover document ingestion jobs stuck in queued/processing."""
+
+from __future__ import annotations
+
+import logging
+from datetime import datetime, timezone
+from typing import TYPE_CHECKING, Optional
+
+from agent.core.config import settings
+from agent.documents.enums import IngestionStatus
+from agent.documents.models import UserDocument
+
+if TYPE_CHECKING:
+    from agent.documents.ingestion.service import IngestionService
+
+logger = logging.getLogger("loangen-documents.ingestion.stale_recovery")
+
+
+def ingestion_stale_after_seconds() -> int:
+    return max(60, int(settings.ingestion_stale_job_minutes) * 60)
+
+
+def normalize_ingestion_status(doc: UserDocument) -> IngestionStatus:
+    status = getattr(doc, "ingestion_status", IngestionStatus.NOT_QUEUED)
+    if isinstance(status, IngestionStatus):
+        return status
+    try:
+        return IngestionStatus(status)
+    except ValueError:
+        return IngestionStatus.NOT_QUEUED
+
+
+def document_status_updated_at(doc: UserDocument) -> datetime:
+    updated = getattr(doc, "ingestion_updated_at", None)
+    if isinstance(updated, datetime):
+        if updated.tzinfo is None:
+            return updated.replace(tzinfo=timezone.utc)
+        return updated
+    uploaded = getattr(doc, "uploaded_at", None)
+    if isinstance(uploaded, datetime):
+        if uploaded.tzinfo is None:
+            return uploaded.replace(tzinfo=timezone.utc)
+        return uploaded
+    return datetime.now(timezone.utc)
+
+
+def is_stale_ingestion_document(doc: UserDocument) -> bool:
+    """True when a queued/processing document has not progressed within the stale window."""
+    status = normalize_ingestion_status(doc)
+    if status not in {IngestionStatus.QUEUED, IngestionStatus.PROCESSING}:
+        return False
+    age_seconds = (datetime.now(timezone.utc) - document_status_updated_at(doc)).total_seconds()
+    return age_seconds >= ingestion_stale_after_seconds()
+
+
+async def recover_stale_documents_for_application(
+    application_id: str,
+    *,
+    service: Optional["IngestionService"] = None,
+) -> int:
+    """Re-queue stale jobs for one application. Returns number of documents recovered."""
+    if not settings.document_ingestion_enabled:
+        return 0
+
+    from agent.documents.ingestion.readiness import get_application_document_ids
+    from agent.services.smbapplications.models import SMBApplication
+
+    app = await SMBApplication.get(application_id)
+    if app is None:
+        return 0
+
+    if service is None:
+        from agent.documents.ingestion.service import IngestionService
+
+        svc = IngestionService()
+    else:
+        svc = service
+    doc_ids = await get_application_document_ids(app)
+    recovered = 0
+    for doc_id in doc_ids:
+        doc = await UserDocument.get(doc_id)
+        if doc is None or doc.is_deleted:
+            continue
+        if not is_stale_ingestion_document(doc):
+            continue
+        if await svc.re_enqueue_stale_document(doc, application_id=application_id):
+            recovered += 1
+    if recovered:
+        logger.info(
+            "Recovered %s stale ingestion job(s) for application_id=%s",
+            recovered,
+            application_id,
+        )
+    return recovered
+
+
+async def recover_all_stale_documents(
+    *,
+    limit: int = 500,
+    service: Optional["IngestionService"] = None,
+) -> int:
+    """Scan recent non-ready documents and re-queue stale ones (worker reaper)."""
+    if not settings.document_ingestion_enabled:
+        return 0
+
+    if service is None:
+        from agent.documents.ingestion.service import IngestionService
+
+        svc = IngestionService()
+    else:
+        svc = service
+    cursor = UserDocument.find(
+        {
+            "is_deleted": False,
+            "ingestion_status": {"$in": [IngestionStatus.QUEUED.value, IngestionStatus.PROCESSING.value]},
+        }
+    ).limit(max(1, limit))
+
+    docs = await cursor.to_list()
+    recovered = 0
+    for doc in docs:
+        if not is_stale_ingestion_document(doc):
+            continue
+        app_id = doc.used_in_applications[0] if doc.used_in_applications else None
+        if await svc.re_enqueue_stale_document(doc, application_id=app_id):
+            recovered += 1
+    if recovered:
+        logger.info("Stale ingestion reaper recovered %s document(s)", recovered)
+    return recovered
diff --git a/loangen-agent/agent/documents/ingestion/worker.py b/loangen-agent/agent/documents/ingestion/worker.py
index c47790e..1358389 100644
--- a/loangen-agent/agent/documents/ingestion/worker.py
+++ b/loangen-agent/agent/documents/ingestion/worker.py
@@ -58,7 +58,27 @@ class EmbeddedIngestionWorker:
         sem = asyncio.Semaphore(concurrency)
         logger.info("Ingestion worker started (concurrency=%s)", concurrency)
 
+        from agent.documents.ingestion.stale_recovery import recover_all_stale_documents
+
+        try:
+            recovered = await recover_all_stale_documents(service=service)
+            if recovered:
+                logger.info("Startup stale ingestion recovery: %s document(s)", recovered)
+        except Exception as exc:
+            logger.error("Startup stale ingestion recovery failed: %s", exc)
+
+        last_reaper_at = asyncio.get_event_loop().time()
+        reaper_interval = max(60, int(settings.ingestion_stale_reaper_interval_seconds))
+
         while not self._shutdown.is_set():
+            now = asyncio.get_event_loop().time()
+            if now - last_reaper_at >= reaper_interval:
+                last_reaper_at = now
+                try:
+                    await recover_all_stale_documents(service=service)
+                except Exception as exc:
+                    logger.error("Stale ingestion reaper failed: %s", exc)
+
             try:
                 payload = await queue.dequeue(timeout_seconds=5)
             except Exception as exc:
diff --git a/loangen-agent/agent/documents/schemas.py b/loangen-agent/agent/documents/schemas.py
index 6e2b2c1..e317a81 100644
--- a/loangen-agent/agent/documents/schemas.py
+++ b/loangen-agent/agent/documents/schemas.py
@@ -99,6 +99,9 @@ class ApplicationIngestionStatusResponse(BaseModel):
     total_document_count: int = 0
     ready_document_count: int = 0
     has_failures: bool = False
+    has_stale_jobs: bool = False
+    can_retry: bool = False
+    failed_document_count: int = 0
 
 
 class DocumentListResponse(BaseModel):
diff --git a/loangen-agent/agent/services/smbapplications/router.py b/loangen-agent/agent/services/smbapplications/router.py
index deabc81..261aa32 100644
--- a/loangen-agent/agent/services/smbapplications/router.py
+++ b/loangen-agent/agent/services/smbapplications/router.py
@@ -1232,6 +1232,7 @@ async def lender_application_ingestion_status(
 )
 async def retry_lender_application_ingestion(
     application_id: str,
+    force: int | None = Query(1, description="1 = re-queue stuck/failed docs (default)"),
     lender: Lender = Depends(get_current_lender),
 ):
     from agent.documents.ingestion.readiness import get_application_document_ids
@@ -1248,8 +1249,13 @@ async def retry_lender_application_ingestion(
 
     svc = IngestionService()
     doc_ids = await get_application_document_ids(app)
-    count = await svc.enqueue_application_documents(application_id, app.user_id, doc_ids)
-    return {"enqueued": count, "application_id": application_id}
+    count = await svc.enqueue_application_documents(
+        application_id,
+        app.user_id,
+        doc_ids,
+        force=force == 1,
+    )
+    return {"enqueued": count, "application_id": application_id, "force": force == 1}
 
 
 @router.post(
@@ -1411,6 +1417,7 @@ async def smb_application_ingestion_status(
 )
 async def retry_smb_application_ingestion(
     application_id: str,
+    force: int | None = Query(1, description="1 = re-queue stuck/failed docs (default)"),
     current_user: User = Depends(get_current_user),
 ):
     from agent.documents.ingestion.readiness import get_application_document_ids
@@ -1424,5 +1431,10 @@ async def retry_smb_application_ingestion(
 
     svc = IngestionService()
     doc_ids = await get_application_document_ids(app)
-    count = await svc.enqueue_application_documents(application_id, str(current_user.id), doc_ids)
-    return {"enqueued": count, "application_id": application_id}
+    count = await svc.enqueue_application_documents(
+        application_id,
+        str(current_user.id),
+        doc_ids,
+        force=force == 1,
+    )
+    return {"enqueued": count, "application_id": application_id, "force": force == 1}
SOLUTION_PATCH_EOF
