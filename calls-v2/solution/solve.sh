#!/bin/sh
# Oracle solution — applies the full upstream fix (all loangen-agent source files)
# from the "fix messaging and bugs" commit at the base state.
set -eu
cd /app
git apply --check - <<'SOLUTION_PATCH_EOF' && git apply - <<'SOLUTION_PATCH_EOF'
diff --git a/loangen-agent/agent/chat_server.py b/loangen-agent/agent/chat_server.py
index f6d4f1f..36d4852 100644
--- a/loangen-agent/agent/chat_server.py
+++ b/loangen-agent/agent/chat_server.py
@@ -119,27 +119,17 @@ from agent.integrations.quickbooks.internal_router import router as quickbooks_i
 
 load_dotenv()
 
-logger = logging.getLogger("loangen-chat")
-logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
-
-
-class _QuietPollingAccessLogFilter(logging.Filter):
-    """Suppress successful access logs for high-frequency call workspace polling."""
-
-    _QUIET_PATHS = (
-        "/api/v1/services/calls/presence/heartbeat",
-        "/api/v1/services/calls/workspace",
-    )
-
-    def filter(self, record: logging.LogRecord) -> bool:
-        message = record.getMessage()
-        if not any(path in message for path in self._QUIET_PATHS):
-            return True
-        # Uvicorn: 127.0.0.1:50604 - "POST ... HTTP/1.1" 200 OK
-        return " 200 OK" not in message
+from agent.core.logging_setup import (
+    get_uvicorn_log_config,
+    install_quiet_polling_access_log_filter,
+    patch_uvicorn_logging_setup,
+)
 
+patch_uvicorn_logging_setup()
 
-logging.getLogger("uvicorn.access").addFilter(_QuietPollingAccessLogFilter())
+logger = logging.getLogger("loangen-chat")
+logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
+install_quiet_polling_access_log_filter()
 
 # ── App — MongoDB connects on startup, disconnects on shutdown ─────────────────
 app = FastAPI(
@@ -1310,7 +1300,12 @@ if __name__ == "__main__":
     import asyncio, uvicorn
 
     port = int(os.getenv("PORT", 8081))
-    config = uvicorn.Config(app, host="0.0.0.0", port=port)
+    config = uvicorn.Config(
+        app,
+        host="0.0.0.0",
+        port=port,
+        log_config=get_uvicorn_log_config(),
+    )
     server = uvicorn.Server(config)
     asyncio.run(server.serve())
 
diff --git a/loangen-agent/agent/core/database.py b/loangen-agent/agent/core/database.py
index fc39836..4612c90 100644
--- a/loangen-agent/agent/core/database.py
+++ b/loangen-agent/agent/core/database.py
@@ -262,6 +262,14 @@ async def lifespan(app):  # type: ignore[type-arg]
     Usage:
         app = FastAPI(lifespan=lifespan)
     """
+    from agent.core.logging_setup import (
+        install_quiet_polling_access_log_filter,
+        install_windows_asyncio_exception_handler,
+    )
+
+    install_quiet_polling_access_log_filter()
+    install_windows_asyncio_exception_handler()
+
     await connect_db()
     await init_redis()
 
diff --git a/loangen-agent/agent/core/logging_setup.py b/loangen-agent/agent/core/logging_setup.py
new file mode 100644
index 0000000..24545c2
--- /dev/null
+++ b/loangen-agent/agent/core/logging_setup.py
@@ -0,0 +1,109 @@
+"""Shared logging helpers for the API server."""
+
+from __future__ import annotations
+
+import asyncio
+import copy
+import logging
+import re
+import sys
+from typing import Any
+
+# High-frequency call workspace polling — log errors only, never success.
+_QUIET_POLL_PATHS = (
+    "/api/v1/services/calls/presence/heartbeat",
+    "/api/v1/services/calls/workspace",
+    "/api/v1/services/calls/voice-client-token",
+)
+
+_SUCCESS_STATUS_RE = re.compile(r'HTTP/1\.\d"\s+([23]\d{2})\b')
+_PATCHED_UVICORN_SETUP = False
+
+
+class QuietPollingAccessLogFilter(logging.Filter):
+    """Drop successful access logs for high-frequency call workspace polling."""
+
+    def filter(self, record: logging.LogRecord) -> bool:
+        message = record.getMessage()
+        if not any(path in message for path in _QUIET_POLL_PATHS):
+            return True
+        match = _SUCCESS_STATUS_RE.search(message)
+        if match is None:
+            return True
+        # Suppress 2xx/3xx; keep 4xx/5xx.
+        return int(match.group(1)) >= 400
+
+
+def install_quiet_polling_access_log_filter() -> None:
+    """Attach the polling filter to uvicorn access logs (safe to call repeatedly)."""
+    access_logger = logging.getLogger("uvicorn.access")
+    access_logger.filters = [
+        f for f in access_logger.filters if not isinstance(f, QuietPollingAccessLogFilter)
+    ]
+    access_logger.addFilter(QuietPollingAccessLogFilter())
+
+
+def patch_uvicorn_logging_setup() -> None:
+    """Re-apply the access filter after uvicorn configures logging."""
+    global _PATCHED_UVICORN_SETUP
+    if _PATCHED_UVICORN_SETUP:
+        return
+
+    import uvicorn.config
+
+    method_name = "configure_logging"
+    if not hasattr(uvicorn.config.Config, method_name):
+        # Older uvicorn releases used setup_logging.
+        method_name = "setup_logging"
+    if not hasattr(uvicorn.config.Config, method_name):
+        return
+
+    original_setup = getattr(uvicorn.config.Config, method_name)
+
+    def patched_setup(self: Any) -> None:
+        original_setup(self)
+        install_quiet_polling_access_log_filter()
+
+    setattr(uvicorn.config.Config, method_name, patched_setup)
+    _PATCHED_UVICORN_SETUP = True
+
+
+def get_uvicorn_log_config() -> dict[str, Any]:
+    """Uvicorn logging config with quiet polling on access logs."""
+    from uvicorn.config import LOGGING_CONFIG
+
+    config = copy.deepcopy(LOGGING_CONFIG)
+    config.setdefault("filters", {})
+    config["filters"]["quiet_polling"] = {
+        "()": "agent.core.logging_setup.QuietPollingAccessLogFilter",
+    }
+    access_logger = config.setdefault("loggers", {}).setdefault("uvicorn.access", {})
+    access_logger["filters"] = ["quiet_polling"]
+    return config
+
+
+def _is_windows_client_disconnect(exc: BaseException | None) -> bool:
+    if exc is None:
+        return False
+    if isinstance(exc, ConnectionResetError):
+        return True
+    return isinstance(exc, OSError) and getattr(exc, "winerror", None) == 10054
+
+
+def install_windows_asyncio_exception_handler() -> None:
+    """Suppress noisy Windows proactor disconnect errors from asyncio."""
+    if sys.platform != "win32":
+        return
+
+    loop = asyncio.get_running_loop()
+    previous_handler = loop.get_exception_handler()
+
+    def handler(inner_loop: asyncio.AbstractEventLoop, context: dict[str, Any]) -> None:
+        if _is_windows_client_disconnect(context.get("exception")):
+            return
+        if previous_handler is not None:
+            previous_handler(inner_loop, context)
+        else:
+            inner_loop.default_exception_handler(context)
+
+    loop.set_exception_handler(handler)
diff --git a/loangen-agent/agent/services/calls/inbound.py b/loangen-agent/agent/services/calls/inbound.py
index 088622f..784b335 100644
--- a/loangen-agent/agent/services/calls/inbound.py
+++ b/loangen-agent/agent/services/calls/inbound.py
@@ -44,6 +44,7 @@ class InboundRoute:
     last_outbound_call_type: str
     last_outbound_call_session_id: str
     last_outbound_at: datetime
+    last_outbound_initiator_session_id: str
 
 
 class InboundRouteError(Exception):
@@ -157,6 +158,7 @@ async def resolve_inbound_route(caller_e164: str) -> InboundRoute:
         last_outbound_call_type=last_outbound.call_type.value,
         last_outbound_call_session_id=str(last_outbound.id),
         last_outbound_at=last_outbound.created_at,
+        last_outbound_initiator_session_id=(last_outbound.initiated_by_session_id or "").strip(),
     )
 
 
@@ -214,15 +216,29 @@ async def _lender_business_name(lender_id: str) -> str:
     return (lender.business_name or "").strip()
 
 
-async def pick_inbound_target_session(lender_id: str) -> Optional[str]:
-    """First browser session available to receive an inbound Client dial."""
+async def pick_inbound_target_session(
+    lender_id: str,
+    *,
+    preferred_session_id: Optional[str] = None,
+) -> Optional[str]:
+    """
+    First browser session that is voice-registered and available for inbound Client dial.
+
+    Prefers the session that placed the last outbound call when it is registered and online.
+    """
     online = await presence_mod.list_online_sessions(lender_id)
     available: list[str] = []
     for session_id, data in online:
+        if not data.get("voice_registered"):
+            continue
         status = data.get("status")
         if status in (
             AgentPresenceStatus.AVAILABLE.value,
             AgentPresenceStatus.ON_AI_ONLY.value,
         ):
             available.append(session_id)
+
+    preferred = (preferred_session_id or "").strip()
+    if preferred and preferred in available:
+        return preferred
     return available[0] if available else None
diff --git a/loangen-agent/agent/services/calls/presence.py b/loangen-agent/agent/services/calls/presence.py
index 404e8ea..3f2e99a 100644
--- a/loangen-agent/agent/services/calls/presence.py
+++ b/loangen-agent/agent/services/calls/presence.py
@@ -30,13 +30,21 @@ async def set_presence(
     session_id: str,
     status: AgentPresenceStatus,
     call_session_id: Optional[str] = None,
+    voice_registered: Optional[bool] = None,
 ) -> None:
     redis = get_redis_client()
     if redis is None:
         return
+
+    voice_registered_flag = voice_registered
+    if voice_registered_flag is None:
+        existing = await get_presence(lender_id, session_id)
+        voice_registered_flag = bool(existing.get("voice_registered")) if existing else False
+
     payload: dict[str, Any] = {
         "status": status.value,
         "call_session_id": call_session_id,
+        "voice_registered": bool(voice_registered_flag),
         "updated_at": datetime.now(timezone.utc).isoformat(),
     }
     try:
diff --git a/loangen-agent/agent/services/calls/router.py b/loangen-agent/agent/services/calls/router.py
index 8ef0a06..695977f 100644
--- a/loangen-agent/agent/services/calls/router.py
+++ b/loangen-agent/agent/services/calls/router.py
@@ -61,6 +61,7 @@ async def presence_heartbeat(
         lender_id=ctx.lender_id,
         session_id=ctx.session_id or (payload.client_session_id or client_session_id or ""),
         client_session_id=payload.client_session_id or client_session_id,
+        voice_registered=payload.voice_registered,
     )
 
 
diff --git a/loangen-agent/agent/services/calls/schemas.py b/loangen-agent/agent/services/calls/schemas.py
index cfd50c6..f90c7b3 100644
--- a/loangen-agent/agent/services/calls/schemas.py
+++ b/loangen-agent/agent/services/calls/schemas.py
@@ -93,6 +93,10 @@ class PresenceHeartbeatRequest(BaseModel):
         None,
         description="Fallback device id when JWT has no session_id (legacy tokens).",
     )
+    voice_registered: bool = Field(
+        False,
+        description="True when this browser has registered with Twilio Voice SDK for inbound calls.",
+    )
 
 
 class PresenceHeartbeatResponse(BaseModel):
diff --git a/loangen-agent/agent/services/calls/service.py b/loangen-agent/agent/services/calls/service.py
index a40195c..8649a36 100644
--- a/loangen-agent/agent/services/calls/service.py
+++ b/loangen-agent/agent/services/calls/service.py
@@ -944,6 +944,7 @@ async def heartbeat(
     lender_id: str,
     session_id: str,
     client_session_id: Optional[str] = None,
+    voice_registered: bool = False,
 ) -> PresenceHeartbeatResponse:
     effective_session = session_id or (client_session_id or "").strip()
     if not effective_session:
@@ -988,6 +989,7 @@ async def heartbeat(
         session_id=effective_session,
         status=status_val,
         call_session_id=call_id,
+        voice_registered=voice_registered,
     )
 
     await process_expired_rings(lender_id)
@@ -1565,7 +1567,7 @@ async def get_voice_client_token(
             status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
             detail={
                 "error": "DIRECT_CALLS_NOT_CONFIGURED",
-                "message": "Direct calling is not configured on this server.",
+                "message": "Phone calling is not available right now. Please contact support.",
             },
         )
 
@@ -1604,7 +1606,10 @@ async def build_inbound_twiml(*, caller_raw: str, twilio_call_sid: str) -> str:
 
     unavailable_msg = format_unavailable_message(business_name=route.lender_business_name or None)
 
-    target_session = await pick_inbound_target_session(route.lender_id)
+    target_session = await pick_inbound_target_session(
+        route.lender_id,
+        preferred_session_id=route.last_outbound_initiator_session_id or None,
+    )
     if not target_session:
         logger.info(
             "Inbound call — last dialer not available | lender=%s from=%s last_outbound=%s",
diff --git a/loangen-agent/agent/services/smbcontacts/service.py b/loangen-agent/agent/services/smbcontacts/service.py
index 1d02c55..8169d70 100644
--- a/loangen-agent/agent/services/smbcontacts/service.py
+++ b/loangen-agent/agent/services/smbcontacts/service.py
@@ -321,9 +321,8 @@ async def initiate_ai_call(
             detail={
                 "error": "CARTESIA_US_OUTBOUND_ONLY",
                 "message": (
-                    f"AI outbound calls to {to_number} require a US (+1) number with the "
-                    "current Cartesia caller ID. Use Direct Call for international numbers, "
-                    "or set CARTESIA_OUTBOUND_US_ONLY=false with a Twilio-imported Cartesia number."
+                    "AI outbound calls from this account can only dial US numbers (+1). "
+                    "Use Direct Call for international numbers."
                 ),
             },
         )
@@ -413,8 +412,8 @@ async def initiate_direct_call(
             detail={
                 "error": "DIRECT_CALLS_NOT_CONFIGURED",
                 "message": (
-                    "Direct calling is not configured. Enable CALLS_DIRECT_ENABLED, Twilio Voice, "
-                    "PUBLIC_API_BASE_URL, and TWILIO_OUTBOUND_CALLER_ID on the server."
+                    "Phone calling is not available on this account right now. "
+                    "Please contact support."
                 ),
             },
         )
SOLUTION_PATCH_EOF
diff --git a/loangen-agent/agent/chat_server.py b/loangen-agent/agent/chat_server.py
index f6d4f1f..36d4852 100644
--- a/loangen-agent/agent/chat_server.py
+++ b/loangen-agent/agent/chat_server.py
@@ -119,27 +119,17 @@ from agent.integrations.quickbooks.internal_router import router as quickbooks_i
 
 load_dotenv()
 
-logger = logging.getLogger("loangen-chat")
-logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
-
-
-class _QuietPollingAccessLogFilter(logging.Filter):
-    """Suppress successful access logs for high-frequency call workspace polling."""
-
-    _QUIET_PATHS = (
-        "/api/v1/services/calls/presence/heartbeat",
-        "/api/v1/services/calls/workspace",
-    )
-
-    def filter(self, record: logging.LogRecord) -> bool:
-        message = record.getMessage()
-        if not any(path in message for path in self._QUIET_PATHS):
-            return True
-        # Uvicorn: 127.0.0.1:50604 - "POST ... HTTP/1.1" 200 OK
-        return " 200 OK" not in message
+from agent.core.logging_setup import (
+    get_uvicorn_log_config,
+    install_quiet_polling_access_log_filter,
+    patch_uvicorn_logging_setup,
+)
 
+patch_uvicorn_logging_setup()
 
-logging.getLogger("uvicorn.access").addFilter(_QuietPollingAccessLogFilter())
+logger = logging.getLogger("loangen-chat")
+logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
+install_quiet_polling_access_log_filter()
 
 # ── App — MongoDB connects on startup, disconnects on shutdown ─────────────────
 app = FastAPI(
@@ -1310,7 +1300,12 @@ if __name__ == "__main__":
     import asyncio, uvicorn
 
     port = int(os.getenv("PORT", 8081))
-    config = uvicorn.Config(app, host="0.0.0.0", port=port)
+    config = uvicorn.Config(
+        app,
+        host="0.0.0.0",
+        port=port,
+        log_config=get_uvicorn_log_config(),
+    )
     server = uvicorn.Server(config)
     asyncio.run(server.serve())
 
diff --git a/loangen-agent/agent/core/database.py b/loangen-agent/agent/core/database.py
index fc39836..4612c90 100644
--- a/loangen-agent/agent/core/database.py
+++ b/loangen-agent/agent/core/database.py
@@ -262,6 +262,14 @@ async def lifespan(app):  # type: ignore[type-arg]
     Usage:
         app = FastAPI(lifespan=lifespan)
     """
+    from agent.core.logging_setup import (
+        install_quiet_polling_access_log_filter,
+        install_windows_asyncio_exception_handler,
+    )
+
+    install_quiet_polling_access_log_filter()
+    install_windows_asyncio_exception_handler()
+
     await connect_db()
     await init_redis()
 
diff --git a/loangen-agent/agent/core/logging_setup.py b/loangen-agent/agent/core/logging_setup.py
new file mode 100644
index 0000000..24545c2
--- /dev/null
+++ b/loangen-agent/agent/core/logging_setup.py
@@ -0,0 +1,109 @@
+"""Shared logging helpers for the API server."""
+
+from __future__ import annotations
+
+import asyncio
+import copy
+import logging
+import re
+import sys
+from typing import Any
+
+# High-frequency call workspace polling — log errors only, never success.
+_QUIET_POLL_PATHS = (
+    "/api/v1/services/calls/presence/heartbeat",
+    "/api/v1/services/calls/workspace",
+    "/api/v1/services/calls/voice-client-token",
+)
+
+_SUCCESS_STATUS_RE = re.compile(r'HTTP/1\.\d"\s+([23]\d{2})\b')
+_PATCHED_UVICORN_SETUP = False
+
+
+class QuietPollingAccessLogFilter(logging.Filter):
+    """Drop successful access logs for high-frequency call workspace polling."""
+
+    def filter(self, record: logging.LogRecord) -> bool:
+        message = record.getMessage()
+        if not any(path in message for path in _QUIET_POLL_PATHS):
+            return True
+        match = _SUCCESS_STATUS_RE.search(message)
+        if match is None:
+            return True
+        # Suppress 2xx/3xx; keep 4xx/5xx.
+        return int(match.group(1)) >= 400
+
+
+def install_quiet_polling_access_log_filter() -> None:
+    """Attach the polling filter to uvicorn access logs (safe to call repeatedly)."""
+    access_logger = logging.getLogger("uvicorn.access")
+    access_logger.filters = [
+        f for f in access_logger.filters if not isinstance(f, QuietPollingAccessLogFilter)
+    ]
+    access_logger.addFilter(QuietPollingAccessLogFilter())
+
+
+def patch_uvicorn_logging_setup() -> None:
+    """Re-apply the access filter after uvicorn configures logging."""
+    global _PATCHED_UVICORN_SETUP
+    if _PATCHED_UVICORN_SETUP:
+        return
+
+    import uvicorn.config
+
+    method_name = "configure_logging"
+    if not hasattr(uvicorn.config.Config, method_name):
+        # Older uvicorn releases used setup_logging.
+        method_name = "setup_logging"
+    if not hasattr(uvicorn.config.Config, method_name):
+        return
+
+    original_setup = getattr(uvicorn.config.Config, method_name)
+
+    def patched_setup(self: Any) -> None:
+        original_setup(self)
+        install_quiet_polling_access_log_filter()
+
+    setattr(uvicorn.config.Config, method_name, patched_setup)
+    _PATCHED_UVICORN_SETUP = True
+
+
+def get_uvicorn_log_config() -> dict[str, Any]:
+    """Uvicorn logging config with quiet polling on access logs."""
+    from uvicorn.config import LOGGING_CONFIG
+
+    config = copy.deepcopy(LOGGING_CONFIG)
+    config.setdefault("filters", {})
+    config["filters"]["quiet_polling"] = {
+        "()": "agent.core.logging_setup.QuietPollingAccessLogFilter",
+    }
+    access_logger = config.setdefault("loggers", {}).setdefault("uvicorn.access", {})
+    access_logger["filters"] = ["quiet_polling"]
+    return config
+
+
+def _is_windows_client_disconnect(exc: BaseException | None) -> bool:
+    if exc is None:
+        return False
+    if isinstance(exc, ConnectionResetError):
+        return True
+    return isinstance(exc, OSError) and getattr(exc, "winerror", None) == 10054
+
+
+def install_windows_asyncio_exception_handler() -> None:
+    """Suppress noisy Windows proactor disconnect errors from asyncio."""
+    if sys.platform != "win32":
+        return
+
+    loop = asyncio.get_running_loop()
+    previous_handler = loop.get_exception_handler()
+
+    def handler(inner_loop: asyncio.AbstractEventLoop, context: dict[str, Any]) -> None:
+        if _is_windows_client_disconnect(context.get("exception")):
+            return
+        if previous_handler is not None:
+            previous_handler(inner_loop, context)
+        else:
+            inner_loop.default_exception_handler(context)
+
+    loop.set_exception_handler(handler)
diff --git a/loangen-agent/agent/services/calls/inbound.py b/loangen-agent/agent/services/calls/inbound.py
index 088622f..784b335 100644
--- a/loangen-agent/agent/services/calls/inbound.py
+++ b/loangen-agent/agent/services/calls/inbound.py
@@ -44,6 +44,7 @@ class InboundRoute:
     last_outbound_call_type: str
     last_outbound_call_session_id: str
     last_outbound_at: datetime
+    last_outbound_initiator_session_id: str
 
 
 class InboundRouteError(Exception):
@@ -157,6 +158,7 @@ async def resolve_inbound_route(caller_e164: str) -> InboundRoute:
         last_outbound_call_type=last_outbound.call_type.value,
         last_outbound_call_session_id=str(last_outbound.id),
         last_outbound_at=last_outbound.created_at,
+        last_outbound_initiator_session_id=(last_outbound.initiated_by_session_id or "").strip(),
     )
 
 
@@ -214,15 +216,29 @@ async def _lender_business_name(lender_id: str) -> str:
     return (lender.business_name or "").strip()
 
 
-async def pick_inbound_target_session(lender_id: str) -> Optional[str]:
-    """First browser session available to receive an inbound Client dial."""
+async def pick_inbound_target_session(
+    lender_id: str,
+    *,
+    preferred_session_id: Optional[str] = None,
+) -> Optional[str]:
+    """
+    First browser session that is voice-registered and available for inbound Client dial.
+
+    Prefers the session that placed the last outbound call when it is registered and online.
+    """
     online = await presence_mod.list_online_sessions(lender_id)
     available: list[str] = []
     for session_id, data in online:
+        if not data.get("voice_registered"):
+            continue
         status = data.get("status")
         if status in (
             AgentPresenceStatus.AVAILABLE.value,
             AgentPresenceStatus.ON_AI_ONLY.value,
         ):
             available.append(session_id)
+
+    preferred = (preferred_session_id or "").strip()
+    if preferred and preferred in available:
+        return preferred
     return available[0] if available else None
diff --git a/loangen-agent/agent/services/calls/presence.py b/loangen-agent/agent/services/calls/presence.py
index 404e8ea..3f2e99a 100644
--- a/loangen-agent/agent/services/calls/presence.py
+++ b/loangen-agent/agent/services/calls/presence.py
@@ -30,13 +30,21 @@ async def set_presence(
     session_id: str,
     status: AgentPresenceStatus,
     call_session_id: Optional[str] = None,
+    voice_registered: Optional[bool] = None,
 ) -> None:
     redis = get_redis_client()
     if redis is None:
         return
+
+    voice_registered_flag = voice_registered
+    if voice_registered_flag is None:
+        existing = await get_presence(lender_id, session_id)
+        voice_registered_flag = bool(existing.get("voice_registered")) if existing else False
+
     payload: dict[str, Any] = {
         "status": status.value,
         "call_session_id": call_session_id,
+        "voice_registered": bool(voice_registered_flag),
         "updated_at": datetime.now(timezone.utc).isoformat(),
     }
     try:
diff --git a/loangen-agent/agent/services/calls/router.py b/loangen-agent/agent/services/calls/router.py
index 8ef0a06..695977f 100644
--- a/loangen-agent/agent/services/calls/router.py
+++ b/loangen-agent/agent/services/calls/router.py
@@ -61,6 +61,7 @@ async def presence_heartbeat(
         lender_id=ctx.lender_id,
         session_id=ctx.session_id or (payload.client_session_id or client_session_id or ""),
         client_session_id=payload.client_session_id or client_session_id,
+        voice_registered=payload.voice_registered,
     )
 
 
diff --git a/loangen-agent/agent/services/calls/schemas.py b/loangen-agent/agent/services/calls/schemas.py
index cfd50c6..f90c7b3 100644
--- a/loangen-agent/agent/services/calls/schemas.py
+++ b/loangen-agent/agent/services/calls/schemas.py
@@ -93,6 +93,10 @@ class PresenceHeartbeatRequest(BaseModel):
         None,
         description="Fallback device id when JWT has no session_id (legacy tokens).",
     )
+    voice_registered: bool = Field(
+        False,
+        description="True when this browser has registered with Twilio Voice SDK for inbound calls.",
+    )
 
 
 class PresenceHeartbeatResponse(BaseModel):
diff --git a/loangen-agent/agent/services/calls/service.py b/loangen-agent/agent/services/calls/service.py
index a40195c..8649a36 100644
--- a/loangen-agent/agent/services/calls/service.py
+++ b/loangen-agent/agent/services/calls/service.py
@@ -944,6 +944,7 @@ async def heartbeat(
     lender_id: str,
     session_id: str,
     client_session_id: Optional[str] = None,
+    voice_registered: bool = False,
 ) -> PresenceHeartbeatResponse:
     effective_session = session_id or (client_session_id or "").strip()
     if not effective_session:
@@ -988,6 +989,7 @@ async def heartbeat(
         session_id=effective_session,
         status=status_val,
         call_session_id=call_id,
+        voice_registered=voice_registered,
     )
 
     await process_expired_rings(lender_id)
@@ -1565,7 +1567,7 @@ async def get_voice_client_token(
             status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
             detail={
                 "error": "DIRECT_CALLS_NOT_CONFIGURED",
-                "message": "Direct calling is not configured on this server.",
+                "message": "Phone calling is not available right now. Please contact support.",
             },
         )
 
@@ -1604,7 +1606,10 @@ async def build_inbound_twiml(*, caller_raw: str, twilio_call_sid: str) -> str:
 
     unavailable_msg = format_unavailable_message(business_name=route.lender_business_name or None)
 
-    target_session = await pick_inbound_target_session(route.lender_id)
+    target_session = await pick_inbound_target_session(
+        route.lender_id,
+        preferred_session_id=route.last_outbound_initiator_session_id or None,
+    )
     if not target_session:
         logger.info(
             "Inbound call — last dialer not available | lender=%s from=%s last_outbound=%s",
diff --git a/loangen-agent/agent/services/smbcontacts/service.py b/loangen-agent/agent/services/smbcontacts/service.py
index 1d02c55..8169d70 100644
--- a/loangen-agent/agent/services/smbcontacts/service.py
+++ b/loangen-agent/agent/services/smbcontacts/service.py
@@ -321,9 +321,8 @@ async def initiate_ai_call(
             detail={
                 "error": "CARTESIA_US_OUTBOUND_ONLY",
                 "message": (
-                    f"AI outbound calls to {to_number} require a US (+1) number with the "
-                    "current Cartesia caller ID. Use Direct Call for international numbers, "
-                    "or set CARTESIA_OUTBOUND_US_ONLY=false with a Twilio-imported Cartesia number."
+                    "AI outbound calls from this account can only dial US numbers (+1). "
+                    "Use Direct Call for international numbers."
                 ),
             },
         )
@@ -413,8 +412,8 @@ async def initiate_direct_call(
             detail={
                 "error": "DIRECT_CALLS_NOT_CONFIGURED",
                 "message": (
-                    "Direct calling is not configured. Enable CALLS_DIRECT_ENABLED, Twilio Voice, "
-                    "PUBLIC_API_BASE_URL, and TWILIO_OUTBOUND_CALLER_ID on the server."
+                    "Phone calling is not available on this account right now. "
+                    "Please contact support."
                 ),
             },
         )
SOLUTION_PATCH_EOF
