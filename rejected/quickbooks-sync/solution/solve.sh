#!/bin/sh
# Oracle solution — applies the fix diff at base_commit.
set -eu
cd /app
git apply --check - <<'SOLUTION_PATCH_EOF' && git apply - <<'SOLUTION_PATCH_EOF'
diff --git a/loangen-agent/agent/integrations/quickbooks/router.py b/loangen-agent/agent/integrations/quickbooks/router.py
index 02fcded..a65964b 100644
--- a/loangen-agent/agent/integrations/quickbooks/router.py
+++ b/loangen-agent/agent/integrations/quickbooks/router.py
@@ -55,6 +55,7 @@ from agent.integrations.quickbooks.schemas import (
 from agent.integrations.quickbooks.service import (
     build_auth_url,
     disconnect,
+    get_state_context,
     get_company_info,
     get_connection_status,
     handle_oauth_callback,
@@ -67,6 +68,11 @@ logger = logging.getLogger("loangen-qb-router")
 
 router = APIRouter(prefix="/api/v1/quickbooks", tags=["QuickBooks"])
 
+
+def _invite_redirect_url(invite_token: str, *, success: bool) -> str:
+    base = f"{settings.frontend_url}/start/invite/{invite_token}/advisor"
+    return _with_query_param(base, "qb_success" if success else "qb_error", "1")
+
 def _with_query_param(url: str, key: str, value: str) -> str:
     """
     Return `url` with query param (key=value) set if not already present.
@@ -111,6 +117,8 @@ async def qb_status(
     ),
 )
 async def qb_connect(
+    flow: str | None = Query(default=None, description="Optional flow context (invite/default)"),
+    invite_token: str | None = Query(default=None, description="Invite token when flow=invite"),
     user=Depends(get_current_user),
 ) -> QBConnectURLResponse:
     """
@@ -123,6 +131,8 @@ async def qb_connect(
         4. Intuit redirects to /oauth/callback — the connection is stored automatically.
         5. Your browser will be redirected to the QUICKBOOKS_OAUTH_SUCCESS_REDIRECT URL.
     """
+    if flow == "invite" and invite_token:
+        return build_auth_url(str(user.id), flow="invite", invite_token=invite_token)
     return build_auth_url(str(user.id))
 
 
@@ -152,19 +162,28 @@ async def qb_callback(
     On success: redirects to QUICKBOOKS_OAUTH_SUCCESS_REDIRECT (frontend URL).
     On failure: redirects to QUICKBOOKS_OAUTH_ERROR_REDIRECT.
     """
+    state_context = get_state_context(state)
+    flow = str(state_context.get("flow") or "").strip().lower()
+    invite_token = str(state_context.get("invite_token") or "").strip()
     try:
-        conn = await handle_oauth_callback(
+        _conn, state_context = await handle_oauth_callback(
             state=state,
             code=code,
             realm_id=realm_id,
         )
         logger.info("QB OAuth callback success.")
-        # Frontend uses qb_success=1 to auto-trigger the initial sync and show the sync loader.
-        redirect_url = _with_query_param(settings.quickbooks_oauth_success_redirect, "qb_success", "1")
+        if flow == "invite" and invite_token:
+            redirect_url = _invite_redirect_url(invite_token, success=True)
+        else:
+            # Frontend uses qb_success=1 to auto-trigger the initial sync and show the sync loader.
+            redirect_url = _with_query_param(settings.quickbooks_oauth_success_redirect, "qb_success", "1")
         return RedirectResponse(url=redirect_url)
     except Exception as exc:
         logger.error("QB OAuth callback failed: %s", exc)
-        redirect_url = _with_query_param(settings.quickbooks_oauth_error_redirect, "qb_error", "1")
+        if flow == "invite" and invite_token:
+            redirect_url = _invite_redirect_url(invite_token, success=False)
+        else:
+            redirect_url = _with_query_param(settings.quickbooks_oauth_error_redirect, "qb_error", "1")
         return RedirectResponse(url=redirect_url)
 
 
diff --git a/loangen-agent/agent/integrations/quickbooks/service.py b/loangen-agent/agent/integrations/quickbooks/service.py
index 234c66c..29f4fb3 100644
--- a/loangen-agent/agent/integrations/quickbooks/service.py
+++ b/loangen-agent/agent/integrations/quickbooks/service.py
@@ -96,14 +96,19 @@ POINT_IN_TIME_REPORTS = {"BalanceSheet", "AgedReceivables", "AgedPayables"}
 # The HMAC is computed with the JWT secret so it cannot be forged.
 
 
-def _build_state(user_id: str) -> str:
+def _build_state(user_id: str, *, flow: Optional[str] = None, invite_token: Optional[str] = None) -> str:
     """
     Build a signed state token that embeds the user_id.
 
     Structure:  <base64url(payload)>.<base64url(hmac-sha256)>
     """
     nonce = secrets.token_urlsafe(12)
-    payload_bytes = json.dumps({"uid": user_id, "n": nonce}, separators=(",", ":")).encode()
+    payload: Dict[str, Any] = {"uid": user_id, "n": nonce}
+    if flow == "invite" and invite_token:
+        payload["flow"] = "invite"
+        payload["invite_token"] = invite_token
+
+    payload_bytes = json.dumps(payload, separators=(",", ":")).encode()
     payload_b64 = base64.urlsafe_b64encode(payload_bytes).rstrip(b"=").decode()
 
     sig = hmac.new(
@@ -116,16 +121,16 @@ def _build_state(user_id: str) -> str:
     return f"{payload_b64}.{sig_b64}"
 
 
-def _decode_state(state: str) -> Tuple[str, bool]:
+def _decode_state(state: str) -> Tuple[Dict[str, Any], bool]:
     """
     Verify the state signature and return (user_id, is_valid).
 
-    Returns (user_id, True) on success, ("", False) on tampered/malformed state.
+    Returns (payload, True) on success, ({}, False) on tampered/malformed state.
     """
     try:
         payload_b64, sig_b64 = state.rsplit(".", 1)
     except ValueError:
-        return "", False
+        return {}, False
 
     # Verify HMAC
     expected_sig = hmac.new(
@@ -136,21 +141,33 @@ def _decode_state(state: str) -> Tuple[str, bool]:
     expected_b64 = base64.urlsafe_b64encode(expected_sig).rstrip(b"=").decode()
 
     if not hmac.compare_digest(expected_b64, sig_b64):
-        return "", False
+        return {}, False
 
     # Decode payload
     try:
         padding = "=" * (4 - len(payload_b64) % 4)
         payload = json.loads(base64.urlsafe_b64decode(payload_b64 + padding))
-        return str(payload["uid"]), True
+        if not isinstance(payload, dict) or not payload.get("uid"):
+            return {}, False
+        return payload, True
     except Exception:
-        return "", False
+        return {}, False
+
+
+def get_state_context(state: str) -> Dict[str, Any]:
+    payload, valid = _decode_state(state)
+    if not valid:
+        return {}
+    return {
+        "flow": payload.get("flow"),
+        "invite_token": payload.get("invite_token"),
+    }
 
 
 # â”€â”€ OAuth helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
 
 
-def build_auth_url(user_id: str) -> QBConnectURLResponse:
+def build_auth_url(user_id: str, *, flow: Optional[str] = None, invite_token: Optional[str] = None) -> QBConnectURLResponse:
     """
     Build the Intuit OAuth 2.0 authorization URL for the given user.
 
@@ -158,7 +175,7 @@ def build_auth_url(user_id: str) -> QBConnectURLResponse:
     knows which user to bind the QB connection to without needing an extra
     query parameter (Intuit only forwards code, state, and realmId).
     """
-    state = _build_state(user_id)
+    state = _build_state(user_id, flow=flow, invite_token=invite_token)
     params = {
         "client_id": settings.quickbooks_client_id,
         "scope": " ".join(QB_SCOPES),
@@ -271,7 +288,7 @@ async def ensure_valid_token(conn: QBConnection) -> QBConnection:
 
 async def handle_oauth_callback(
     state: str, code: str, realm_id: str
-) -> QBConnection:
+) -> tuple[QBConnection, Dict[str, Any]]:
     """
     Exchange the authorization code for tokens and upsert a QBConnection.
 
@@ -281,7 +298,8 @@ async def handle_oauth_callback(
     Called from the OAuth callback endpoint after Intuit redirects the user back.
     If the user already has a QBConnection, it is replaced with the new tokens.
     """
-    user_id, valid = _decode_state(state)
+    state_payload, valid = _decode_state(state)
+    user_id = str(state_payload.get("uid", "")).strip()
     if not valid or not user_id:
         logger.warning(f"QB callback: invalid or tampered state token received.")
         raise HTTPException(
@@ -345,7 +363,11 @@ async def handle_oauth_callback(
         await conn.insert()
 
     logger.info("QB connection established.")
-    return conn
+    context: Dict[str, Any] = {
+        "flow": state_payload.get("flow"),
+        "invite_token": state_payload.get("invite_token"),
+    }
+    return conn, context
 
 
 async def get_connection_status(user_id: str) -> QBConnectionStatusResponse:
SOLUTION_PATCH_EOF
diff --git a/loangen-agent/agent/integrations/quickbooks/router.py b/loangen-agent/agent/integrations/quickbooks/router.py
index 02fcded..a65964b 100644
--- a/loangen-agent/agent/integrations/quickbooks/router.py
+++ b/loangen-agent/agent/integrations/quickbooks/router.py
@@ -55,6 +55,7 @@ from agent.integrations.quickbooks.schemas import (
 from agent.integrations.quickbooks.service import (
     build_auth_url,
     disconnect,
+    get_state_context,
     get_company_info,
     get_connection_status,
     handle_oauth_callback,
@@ -67,6 +68,11 @@ logger = logging.getLogger("loangen-qb-router")
 
 router = APIRouter(prefix="/api/v1/quickbooks", tags=["QuickBooks"])
 
+
+def _invite_redirect_url(invite_token: str, *, success: bool) -> str:
+    base = f"{settings.frontend_url}/start/invite/{invite_token}/advisor"
+    return _with_query_param(base, "qb_success" if success else "qb_error", "1")
+
 def _with_query_param(url: str, key: str, value: str) -> str:
     """
     Return `url` with query param (key=value) set if not already present.
@@ -111,6 +117,8 @@ async def qb_status(
     ),
 )
 async def qb_connect(
+    flow: str | None = Query(default=None, description="Optional flow context (invite/default)"),
+    invite_token: str | None = Query(default=None, description="Invite token when flow=invite"),
     user=Depends(get_current_user),
 ) -> QBConnectURLResponse:
     """
@@ -123,6 +131,8 @@ async def qb_connect(
         4. Intuit redirects to /oauth/callback — the connection is stored automatically.
         5. Your browser will be redirected to the QUICKBOOKS_OAUTH_SUCCESS_REDIRECT URL.
     """
+    if flow == "invite" and invite_token:
+        return build_auth_url(str(user.id), flow="invite", invite_token=invite_token)
     return build_auth_url(str(user.id))
 
 
@@ -152,19 +162,28 @@ async def qb_callback(
     On success: redirects to QUICKBOOKS_OAUTH_SUCCESS_REDIRECT (frontend URL).
     On failure: redirects to QUICKBOOKS_OAUTH_ERROR_REDIRECT.
     """
+    state_context = get_state_context(state)
+    flow = str(state_context.get("flow") or "").strip().lower()
+    invite_token = str(state_context.get("invite_token") or "").strip()
     try:
-        conn = await handle_oauth_callback(
+        _conn, state_context = await handle_oauth_callback(
             state=state,
             code=code,
             realm_id=realm_id,
         )
         logger.info("QB OAuth callback success.")
-        # Frontend uses qb_success=1 to auto-trigger the initial sync and show the sync loader.
-        redirect_url = _with_query_param(settings.quickbooks_oauth_success_redirect, "qb_success", "1")
+        if flow == "invite" and invite_token:
+            redirect_url = _invite_redirect_url(invite_token, success=True)
+        else:
+            # Frontend uses qb_success=1 to auto-trigger the initial sync and show the sync loader.
+            redirect_url = _with_query_param(settings.quickbooks_oauth_success_redirect, "qb_success", "1")
         return RedirectResponse(url=redirect_url)
     except Exception as exc:
         logger.error("QB OAuth callback failed: %s", exc)
-        redirect_url = _with_query_param(settings.quickbooks_oauth_error_redirect, "qb_error", "1")
+        if flow == "invite" and invite_token:
+            redirect_url = _invite_redirect_url(invite_token, success=False)
+        else:
+            redirect_url = _with_query_param(settings.quickbooks_oauth_error_redirect, "qb_error", "1")
         return RedirectResponse(url=redirect_url)
 
 
diff --git a/loangen-agent/agent/integrations/quickbooks/service.py b/loangen-agent/agent/integrations/quickbooks/service.py
index 234c66c..29f4fb3 100644
--- a/loangen-agent/agent/integrations/quickbooks/service.py
+++ b/loangen-agent/agent/integrations/quickbooks/service.py
@@ -96,14 +96,19 @@ POINT_IN_TIME_REPORTS = {"BalanceSheet", "AgedReceivables", "AgedPayables"}
 # The HMAC is computed with the JWT secret so it cannot be forged.
 
 
-def _build_state(user_id: str) -> str:
+def _build_state(user_id: str, *, flow: Optional[str] = None, invite_token: Optional[str] = None) -> str:
     """
     Build a signed state token that embeds the user_id.
 
     Structure:  <base64url(payload)>.<base64url(hmac-sha256)>
     """
     nonce = secrets.token_urlsafe(12)
-    payload_bytes = json.dumps({"uid": user_id, "n": nonce}, separators=(",", ":")).encode()
+    payload: Dict[str, Any] = {"uid": user_id, "n": nonce}
+    if flow == "invite" and invite_token:
+        payload["flow"] = "invite"
+        payload["invite_token"] = invite_token
+
+    payload_bytes = json.dumps(payload, separators=(",", ":")).encode()
     payload_b64 = base64.urlsafe_b64encode(payload_bytes).rstrip(b"=").decode()
 
     sig = hmac.new(
@@ -116,16 +121,16 @@ def _build_state(user_id: str) -> str:
     return f"{payload_b64}.{sig_b64}"
 
 
-def _decode_state(state: str) -> Tuple[str, bool]:
+def _decode_state(state: str) -> Tuple[Dict[str, Any], bool]:
     """
     Verify the state signature and return (user_id, is_valid).
 
-    Returns (user_id, True) on success, ("", False) on tampered/malformed state.
+    Returns (payload, True) on success, ({}, False) on tampered/malformed state.
     """
     try:
         payload_b64, sig_b64 = state.rsplit(".", 1)
     except ValueError:
-        return "", False
+        return {}, False
 
     # Verify HMAC
     expected_sig = hmac.new(
@@ -136,21 +141,33 @@ def _decode_state(state: str) -> Tuple[str, bool]:
     expected_b64 = base64.urlsafe_b64encode(expected_sig).rstrip(b"=").decode()
 
     if not hmac.compare_digest(expected_b64, sig_b64):
-        return "", False
+        return {}, False
 
     # Decode payload
     try:
         padding = "=" * (4 - len(payload_b64) % 4)
         payload = json.loads(base64.urlsafe_b64decode(payload_b64 + padding))
-        return str(payload["uid"]), True
+        if not isinstance(payload, dict) or not payload.get("uid"):
+            return {}, False
+        return payload, True
     except Exception:
-        return "", False
+        return {}, False
+
+
+def get_state_context(state: str) -> Dict[str, Any]:
+    payload, valid = _decode_state(state)
+    if not valid:
+        return {}
+    return {
+        "flow": payload.get("flow"),
+        "invite_token": payload.get("invite_token"),
+    }
 
 
 # â”€â”€ OAuth helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
 
 
-def build_auth_url(user_id: str) -> QBConnectURLResponse:
+def build_auth_url(user_id: str, *, flow: Optional[str] = None, invite_token: Optional[str] = None) -> QBConnectURLResponse:
     """
     Build the Intuit OAuth 2.0 authorization URL for the given user.
 
@@ -158,7 +175,7 @@ def build_auth_url(user_id: str) -> QBConnectURLResponse:
     knows which user to bind the QB connection to without needing an extra
     query parameter (Intuit only forwards code, state, and realmId).
     """
-    state = _build_state(user_id)
+    state = _build_state(user_id, flow=flow, invite_token=invite_token)
     params = {
         "client_id": settings.quickbooks_client_id,
         "scope": " ".join(QB_SCOPES),
@@ -271,7 +288,7 @@ async def ensure_valid_token(conn: QBConnection) -> QBConnection:
 
 async def handle_oauth_callback(
     state: str, code: str, realm_id: str
-) -> QBConnection:
+) -> tuple[QBConnection, Dict[str, Any]]:
     """
     Exchange the authorization code for tokens and upsert a QBConnection.
 
@@ -281,7 +298,8 @@ async def handle_oauth_callback(
     Called from the OAuth callback endpoint after Intuit redirects the user back.
     If the user already has a QBConnection, it is replaced with the new tokens.
     """
-    user_id, valid = _decode_state(state)
+    state_payload, valid = _decode_state(state)
+    user_id = str(state_payload.get("uid", "")).strip()
     if not valid or not user_id:
         logger.warning(f"QB callback: invalid or tampered state token received.")
         raise HTTPException(
@@ -345,7 +363,11 @@ async def handle_oauth_callback(
         await conn.insert()
 
     logger.info("QB connection established.")
-    return conn
+    context: Dict[str, Any] = {
+        "flow": state_payload.get("flow"),
+        "invite_token": state_payload.get("invite_token"),
+    }
+    return conn, context
 
 
 async def get_connection_status(user_id: str) -> QBConnectionStatusResponse:
SOLUTION_PATCH_EOF
