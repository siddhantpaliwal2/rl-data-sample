#!/bin/sh
# Oracle solution — applies the fix diff at base_commit.
set -eu
cd /app
git apply --check - <<'SOLUTION_PATCH_EOF' && git apply - <<'SOLUTION_PATCH_EOF'
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
SOLUTION_PATCH_EOF
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
SOLUTION_PATCH_EOF
