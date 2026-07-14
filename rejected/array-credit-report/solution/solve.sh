#!/bin/sh
# Oracle solution — applies the fix diff at base_commit.
set -eu
cd /app
git apply --check - <<'SOLUTION_PATCH_EOF' && git apply - <<'SOLUTION_PATCH_EOF'
diff --git a/loangen-agent/agent/array/client.py b/loangen-agent/agent/array/client.py
index a81f508..3cf500a 100644
--- a/loangen-agent/agent/array/client.py
+++ b/loangen-agent/agent/array/client.py
@@ -141,12 +141,13 @@ class ArrayClient:
         if resp.status_code == 204:
             logger.warning(
                 f"Array retrieve_questions returned 204 No Content for userId={user_id} "
-                "— provider could not generate questions for this user."
+                f"providers={providers} — bureau could not generate questions."
             )
             raise ArrayClientError(
                 "The verification provider could not generate questions for this user. "
                 "Please check your personal information and try again.",
                 status_code=204,
+                details={"providers": providers, "response_headers": dict(resp.headers)},
             )
 
         if resp.status_code == 404:
@@ -197,6 +198,24 @@ class ArrayClient:
                 details=resp.text,
             )
 
+    async def try_retrieve_questions(
+        self,
+        user_id: str,
+        providers: List[str],
+    ) -> Dict[str, Any] | None:
+        """
+        Like retrieve_questions but returns None on HTTP 204 instead of raising.
+
+        Used by the bureau cascade (OTP → KBA → SMFA) when a bureau cannot
+        start verification for this identity.
+        """
+        try:
+            return await self.retrieve_questions(user_id=user_id, providers=providers)
+        except ArrayClientError as exc:
+            if exc.status_code == 204:
+                return None
+            raise
+
     async def submit_answers(
         self,
         user_id: str,
diff --git a/loangen-agent/agent/array/schemas.py b/loangen-agent/agent/array/schemas.py
index fc35f36..91f15cf 100644
--- a/loangen-agent/agent/array/schemas.py
+++ b/loangen-agent/agent/array/schemas.py
@@ -3,7 +3,7 @@ from __future__ import annotations
 from datetime import date
 from typing import Any, Dict, List, Optional
 
-from pydantic import BaseModel, Field
+from pydantic import BaseModel, Field, field_validator
 
 from agent.core.config import settings
 
@@ -52,11 +52,19 @@ class CreateArrayUserRequest(BaseModel):
     )
     ssn: str = Field(
         default=settings.array_demo_ssn_number or "666285344",
-        min_length=4,
+        min_length=9,
         max_length=11,
-        description="SSN (full or as required by Array)",
+        description="SSN (9 digits)",
         examples=[settings.array_demo_ssn_number or "666285344"],
     )
+
+    @field_validator("ssn")
+    @classmethod
+    def validate_ssn_digits(cls, value: str) -> str:
+        digits = "".join(ch for ch in value if ch.isdigit())
+        if len(digits) != 9:
+            raise ValueError("Social Security Number must be exactly 9 digits.")
+        return digits
     dob: date = Field(
         default_factory=lambda: date.fromisoformat(
             settings.array_demo_user_dob or "1939-09-20"
@@ -142,6 +150,13 @@ class CreateUserAndQuestionsResponse(BaseModel):
         description="Bureau performing the verification: 'tui', 'efx', or 'exp'.",
         examples=["tui", "efx", "exp"],
     )
+    isTransition: bool = Field(
+        default=False,
+        description=(
+            "True when a prior bureau could not start verification and the user "
+            "is beginning with the next available method (OTP→KBA or KBA→SMFA)."
+        ),
+    )
 
 
 class SubmitAnswersRequest(BaseModel):
@@ -310,6 +325,14 @@ class RefreshStartResponse(BaseModel):
         default=None,
         description="Bureau performing the verification: 'tui', 'efx', or 'exp'.",
     )
+    isTransition: bool = Field(
+        default=False,
+        description="True when refresh started on a fallback bureau after a prior bureau failed.",
+    )
+    message: Optional[str] = Field(
+        default=None,
+        description="Informational message when verification starts via bureau cascade.",
+    )
     error: Optional[str] = Field(
         default=None,
         description="Error message when can_refresh is False due to an API failure.",
diff --git a/loangen-agent/agent/array/service.py b/loangen-agent/agent/array/service.py
index 6fd1ae9..4efb1f4 100644
--- a/loangen-agent/agent/array/service.py
+++ b/loangen-agent/agent/array/service.py
@@ -45,7 +45,8 @@ class ArrayService:
     High-level orchestration around Array's Customer Verification and Credit Report APIs.
 
     Verification flow (OTP → KBA → SMFA cascade):
-      1. create_user_and_get_questions  — creates the Array user, initiates OTP (tui only)
+      1. create_user_and_get_questions  — creates the Array user, initiates verification
+         with bureau cascade when a bureau returns HTTP 204 at start
       2. submit_answers_and_order_report — submits answers; handles all outcomes:
            - HTTP 206: more questions needed (OTP step transition or KBA follow-up)
            - HTTP 202: SMFA link not yet clicked (poll again)
@@ -73,30 +74,60 @@ class ArrayService:
           5. Return questions + authMethod to frontend
         """
         session_id = str(uuid.uuid4())
-        array_user_id = str(uuid.uuid4())
-        user_payload = self._map_create_user_request(req, array_user_id, user_email)
 
-        try:
-            await self.client.create_user(user_payload.model_dump())
-        except ArrayClientError as exc:
-            logger.error(f"Array create_user failed: {exc}")
-            raise
-
-        # Start with TransUnion only so Array always begins with OTP.
-        providers = self._providers_for_step("otp")
-        if not providers:
-            raise ArrayClientError(
-                "Phone verification is not available right now. Please contact support.",
+        existing_profile = await ArrayUserProfile.find_one(
+            ArrayUserProfile.userId == user_id
+        )
+        if existing_profile:
+            array_user_id = existing_profile.arrayUserId
+            logger.info(
+                f"Reusing existing arrayUserId={array_user_id} for userId={user_id}"
             )
+            await self._stage_user_profile(req, user_id, array_user_id)
+        else:
+            array_user_id = str(uuid.uuid4())
+            user_payload = self._map_create_user_request(req, array_user_id, user_email)
+            try:
+                await self.client.create_user(user_payload.model_dump())
+            except ArrayClientError as exc:
+                if exc.status_code == 409:
+                    # Concurrent retry or prior attempt created the Array user already.
+                    raced_profile = await ArrayUserProfile.find_one(
+                        ArrayUserProfile.userId == user_id
+                    )
+                    if raced_profile:
+                        array_user_id = raced_profile.arrayUserId
+                        logger.info(
+                            f"Array 409 — reusing staged arrayUserId={array_user_id} "
+                            f"for userId={user_id}"
+                        )
+                    else:
+                        prior_tokens = (
+                            await ArrayUserToken.find(
+                                ArrayUserToken.userId == user_id,
+                            )
+                            .sort(-ArrayUserToken.createdDate)
+                            .limit(1)
+                            .to_list()
+                        )
+                        if prior_tokens:
+                            array_user_id = prior_tokens[0].arrayUserId
+                            await self._stage_user_profile(req, user_id, array_user_id)
+                            logger.info(
+                                f"Array 409 — recovered arrayUserId={array_user_id} "
+                                f"from prior session for userId={user_id}"
+                            )
+                        else:
+                            logger.error(f"Array create_user failed: {exc}")
+                            raise
+                else:
+                    logger.error(f"Array create_user failed: {exc}")
+                    raise
+            await self._stage_user_profile(req, user_id, array_user_id)
 
-        try:
-            questions_resp = await self.client.retrieve_questions(
-                user_id=array_user_id,
-                providers=providers,
-            )
-        except ArrayClientError as exc:
-            logger.error(f"Array retrieve_questions failed during create flow: {exc}")
-            raise
+        questions_resp, failed_methods, is_transition = await self._initiate_verification_with_cascade(
+            array_user_id=array_user_id,
+        )
 
         questions_resp = await self._maybe_auto_submit_otp_sms(
             array_user_id=array_user_id,
@@ -114,24 +145,23 @@ class ArrayService:
             authToken=auth_token,
             authMethod=auth_method,
             provider=provider,
-            failedMethods=[],
+            failedMethods=failed_methods,
         )
         await token_doc.insert()
 
-        # Stage ArrayUserProfile so refresh can reuse arrayUserId after a successful pull.
-        await self._stage_user_profile(req, user_id, array_user_id)
-
         logger.info(
             f"Verification initiated for userId={user_id} "
-            f"arrayUserId={array_user_id} authMethod={auth_method} provider={provider}"
+            f"arrayUserId={array_user_id} authMethod={auth_method} provider={provider} "
+            f"failedMethods={failed_methods} isTransition={is_transition}"
         )
         return CreateUserAndQuestionsResponse(
             statusCode="SUCCESS",
-            message="A verification code has been sent to your mobile phone.",
+            message=self._initial_cascade_message(failed_methods, auth_method),
             sessionId=session_id,
             questions=questions,
             authMethod=auth_method,
             provider=provider,
+            isTransition=is_transition,
         )
 
     async def start_refresh_and_get_questions(
@@ -156,25 +186,17 @@ class ArrayService:
             logger.info(f"No ArrayUserProfile for userId={user_id} — refresh not available")
             return RefreshStartResponse(can_refresh=False)
 
-        providers = self._providers_for_step("otp")
         session_id = str(uuid.uuid4())
 
-        if not providers:
-            return RefreshStartResponse(
-                can_refresh=False,
-                error="Phone verification is not available right now. Please use the full connect flow.",
-            )
-
         try:
-            questions_resp = await self.client.retrieve_questions(
-                user_id=profile.arrayUserId,
-                providers=providers,
+            questions_resp, failed_methods, is_transition = await self._initiate_verification_with_cascade(
+                array_user_id=profile.arrayUserId,
             )
         except ArrayClientError as exc:
-            logger.error(f"Array retrieve_questions failed during refresh for userId={user_id}: {exc}")
+            logger.error(f"Array verification cascade failed during refresh for userId={user_id}: {exc}")
             return RefreshStartResponse(can_refresh=False, error=str(exc))
-        except Exception as exc:
-            logger.exception(f"Unexpected error in refresh retrieve_questions for userId={user_id}")
+        except Exception:
+            logger.exception(f"Unexpected error in refresh verification cascade for userId={user_id}")
             return RefreshStartResponse(
                 can_refresh=False,
                 error="Unexpected error starting refresh — please try the full credit pull.",
@@ -196,13 +218,14 @@ class ArrayService:
             authToken=auth_token,
             authMethod=auth_method,
             provider=provider,
-            failedMethods=[],
+            failedMethods=failed_methods,
         )
         await token_doc.insert()
 
         logger.info(
             f"Refresh verification started for userId={user_id} "
-            f"arrayUserId={profile.arrayUserId} authMethod={auth_method}"
+            f"arrayUserId={profile.arrayUserId} authMethod={auth_method} "
+            f"failedMethods={failed_methods}"
         )
         return RefreshStartResponse(
             can_refresh=True,
@@ -210,6 +233,8 @@ class ArrayService:
             questions=questions,
             authMethod=auth_method,
             provider=provider,
+            isTransition=is_transition,
+            message=self._initial_cascade_message(failed_methods, auth_method) if is_transition else None,
         )
 
     async def submit_answers_and_order_report(
@@ -339,26 +364,16 @@ class ArrayService:
 
             # OTP or KBA failed → cascade to the next method in the fallback order.
             new_failed = list(token_doc.failedMethods) + [current_method]
-            providers = self._providers_for_fallback(new_failed)
-
-            if not providers:
-                logger.error(
-                    f"All verification methods exhausted for sessionId={req.sessionId}"
-                )
-                raise ArrayClientError(
-                    self._terminal_verification_message(),
-                    status_code=http_status,
-                )
 
             logger.info(
                 f"{current_method.upper()} failed (HTTP {http_status}) for "
-                f"sessionId={req.sessionId} — falling back with providers={providers}"
+                f"sessionId={req.sessionId} — falling back with failedMethods={new_failed}"
             )
 
             try:
-                new_questions_resp = await self.client.retrieve_questions(
-                    user_id=token_doc.arrayUserId,
-                    providers=providers,
+                new_questions_resp, cascade_failed, _ = await self._initiate_verification_with_cascade(
+                    array_user_id=token_doc.arrayUserId,
+                    skip_methods=new_failed,
                 )
             except ArrayClientError as exc:
                 logger.error(
@@ -374,7 +389,7 @@ class ArrayService:
             token_doc.authToken = new_questions_resp.get("authToken", "")
             token_doc.authMethod = new_auth_method
             token_doc.provider = new_provider
-            token_doc.failedMethods = new_failed
+            token_doc.failedMethods = cascade_failed
             token_doc.updatedDate = datetime.now(timezone.utc)
             await token_doc.save()
 
@@ -554,6 +569,102 @@ class ArrayService:
 
     # ── Private helpers ───────────────────────────────────────────────────────
 
+    async def _initiate_verification_with_cascade(
+        self,
+        *,
+        array_user_id: str,
+        skip_methods: Optional[List[str]] = None,
+    ) -> tuple[Dict[str, Any], List[str], bool]:
+        """
+        Try OTP (tui) → KBA (exp) → SMFA (efx) until one bureau returns questions.
+
+        Returns (questions_response, failed_methods, is_transition).
+        is_transition is True when at least one bureau failed before success.
+        """
+        failed: List[str] = [
+            self._normalize_auth_method(m) for m in (skip_methods or [])
+        ]
+        had_prior_failure = len(failed) > 0
+        configured = self._configured_bureaus()
+
+        any_enabled = any(
+            [p for p in providers if p in configured]
+            for _, providers in _VERIFICATION_FALLBACK_ORDER
+        )
+        if not any_enabled:
+            raise ArrayClientError(
+                "Identity verification is not available right now. Please contact support.",
+            )
+
+        for method_name, provider_list in _VERIFICATION_FALLBACK_ORDER:
+            if method_name in failed:
+                continue
+            providers = [p for p in provider_list if p in configured]
+            if not providers:
+                continue
+
+            resp = await self.client.try_retrieve_questions(
+                user_id=array_user_id,
+                providers=providers,
+            )
+            if resp is None:
+                logger.warning(
+                    f"Bureau cascade: {method_name} ({providers}) returned 204 "
+                    f"for arrayUserId={array_user_id}"
+                )
+                failed.append(method_name)
+                continue
+
+            is_transition = had_prior_failure or len(failed) > len(skip_methods or [])
+            return resp, failed, is_transition
+
+        raise ArrayClientError(
+            self._terminal_verification_message(),
+            status_code=204,
+        )
+
+    def _verification_start_message(self, auth_method: str) -> str:
+        method = self._normalize_auth_method(auth_method)
+        if method == "otp":
+            return "A verification code has been sent to your mobile phone."
+        if method == "kba":
+            return "Please answer a few identity verification questions to continue."
+        if method == "smfa":
+            return (
+                "We sent a secure verification link to your phone. "
+                "Open the link, then continue here."
+            )
+        return "Please complete identity verification to continue."
+
+    def _initial_cascade_message(
+        self,
+        failed_methods: List[str],
+        auth_method: str,
+    ) -> str:
+        """User-facing copy when verification starts (including bureau cascade at connect)."""
+        if not failed_methods:
+            return self._verification_start_message(auth_method)
+
+        current = self._normalize_auth_method(auth_method)
+        last_failed = self._normalize_auth_method(failed_methods[-1])
+
+        if last_failed == "otp" and current == "kba":
+            return (
+                "We couldn't start phone verification for this identity. "
+                "Please answer a few identity questions to continue."
+            )
+        if last_failed == "otp" and current == "smfa":
+            return (
+                "We couldn't start phone verification. "
+                "We'll send a secure verification link to your phone instead."
+            )
+        if last_failed == "kba" and current == "smfa":
+            return (
+                "We couldn't verify with identity questions. "
+                "We'll send a secure verification link to your phone instead."
+            )
+        return self._verification_start_message(auth_method)
+
     @staticmethod
     def _normalize_auth_method(method: str) -> str:
         """Normalize Array authMethod values for cascade bookkeeping."""
diff --git a/loangen-agent/agent/services/smbinvites/router.py b/loangen-agent/agent/services/smbinvites/router.py
index 2546635..d58d15a 100644
--- a/loangen-agent/agent/services/smbinvites/router.py
+++ b/loangen-agent/agent/services/smbinvites/router.py
@@ -66,7 +66,7 @@ async def resolve_invite_route(
     summary="Authenticate SMB from invite using password only",
 )
 async def invite_auth_route(payload: InviteAuthRequest) -> InviteAuthResponse:
-    return await invite_auth(payload.token, payload.password)
+    return await invite_auth(payload.token, payload.password, payload.confirm_password)
 
 
 @router.post(
diff --git a/loangen-agent/agent/services/smbinvites/schemas.py b/loangen-agent/agent/services/smbinvites/schemas.py
index 44b9324..bbb5919 100644
--- a/loangen-agent/agent/services/smbinvites/schemas.py
+++ b/loangen-agent/agent/services/smbinvites/schemas.py
@@ -53,11 +53,13 @@ class InviteResolveResponse(BaseModel):
     expires_at: str
     can_start_application: bool = True
     start_block_message: Optional[str] = None
+    is_existing_user: bool = False
 
 
 class InviteAuthRequest(BaseModel):
     token: str = Field(..., min_length=10)
     password: str = Field(..., min_length=8, max_length=128)
+    confirm_password: Optional[str] = Field(default=None, min_length=8, max_length=128)
 
 
 class InviteAuthResponse(BaseModel):
diff --git a/loangen-agent/agent/services/smbinvites/service.py b/loangen-agent/agent/services/smbinvites/service.py
index e21a7a0..c000400 100644
--- a/loangen-agent/agent/services/smbinvites/service.py
+++ b/loangen-agent/agent/services/smbinvites/service.py
@@ -199,7 +199,11 @@ def _build_tracking(invite: SMBInviteRequest, state: dict[str, Any]) -> Conversa
 
     required_sources = list(invite.required_data_sources)
     connected_sources = [s for s in required_sources if s in state.get("connected_sources", [])]
-    pending_sources = [s for s in required_sources if s not in connected_sources]
+    skipped_sources = set(state.get("skipped_sources", []))
+    pending_sources = [
+        s for s in required_sources
+        if s not in connected_sources and s not in skipped_sources
+    ]
 
     return ConversationTrackingState(
         collected_fields=collected_fields,
@@ -281,17 +285,19 @@ def _next_prompt(invite: SMBInviteRequest, state: dict[str, Any]) -> tuple[Conve
         )
 
     connected_sources: list[str] = state.get("connected_sources", [])
+    skipped_sources: set[str] = set(state.get("skipped_sources", []))
     for source in invite.required_data_sources:
-        if source not in connected_sources:
-            return (
-                ConversationPrompt(
-                    step_id=f"source:{source}",
-                    message=f"Kindly connect your {source.replace('_', ' ')}.",
-                    input_type="connect_source",
-                    source_key=source,
-                ),
-                False,
-            )
+        if source in connected_sources or source in skipped_sources:
+            continue
+        return (
+            ConversationPrompt(
+                step_id=f"source:{source}",
+                message=f"Kindly connect your {source.replace('_', ' ')}.",
+                input_type="connect_source",
+                source_key=source,
+            ),
+            False,
+        )
 
     uploaded_docs: list[str] = state.get("uploaded_documents", [])
     skipped_docs: set[str] = set(state.get("skipped_documents", []))
@@ -478,6 +484,9 @@ async def resolve_invite(raw_token: str) -> InviteResolveResponse:
         can_start_application = True
         start_block_message = None
 
+    email_lower = invite.smb_email.lower()
+    existing_user = await User.find_one(User.email == email_lower)
+
     return InviteResolveResponse(
         invite_id=str(invite.id),
         lender_id=invite.lender_id,
@@ -492,10 +501,15 @@ async def resolve_invite(raw_token: str) -> InviteResolveResponse:
         expires_at=invite.expires_at.isoformat(),
         can_start_application=can_start_application,
         start_block_message=start_block_message,
+        is_existing_user=existing_user is not None,
     )
 
 
-async def invite_auth(raw_token: str, password: str) -> InviteAuthResponse:
+async def invite_auth(
+    raw_token: str,
+    password: str,
+    confirm_password: Optional[str] = None,
+) -> InviteAuthResponse:
     invite = await SMBInviteRequest.find_one(SMBInviteRequest.token_hash == hash_token(raw_token))
     if invite is None:
         raise HTTPException(status_code=404, detail={"error": "INVITE_NOT_FOUND", "message": "Invite link is invalid."})
@@ -526,6 +540,14 @@ async def invite_auth(raw_token: str, password: str) -> InviteAuthResponse:
 
     user = await User.find_one(User.email == email_lower)
     if user is None:
+        if confirm_password is not None and confirm_password != password:
+            raise HTTPException(
+                status_code=status.HTTP_400_BAD_REQUEST,
+                detail={
+                    "error": "PASSWORD_MISMATCH",
+                    "message": "Password and confirm password do not match.",
+                },
+            )
         initial_mode = "production" if _is_production_instance() else settings.default_user_mode
         user = User(
             first_name=invite.smb_first_name,
@@ -914,10 +936,22 @@ async def reply_invite_conversation(
                 state["skipped_documents"] = sorted(skipped)
     elif payload.step_id.startswith("source:"):
         source_key = payload.step_id.split("source:", 1)[1]
-        connected_sources = set(state.get("connected_sources", []))
-        if payload.source_status.get(source_key):
-            connected_sources.add(source_key)
-        state["connected_sources"] = sorted(connected_sources)
+        if (payload.value or "").strip().lower() == "skip":
+            skipped = set(state.get("skipped_sources", []))
+            skipped.add(source_key)
+            state["skipped_sources"] = sorted(skipped)
+            connected = set(state.get("connected_sources", []))
+            connected.discard(source_key)
+            state["connected_sources"] = sorted(connected)
+        else:
+            connected_sources = set(state.get("connected_sources", []))
+            if payload.source_status.get(source_key):
+                connected_sources.add(source_key)
+                skipped = set(state.get("skipped_sources", []))
+                if source_key in skipped:
+                    skipped.discard(source_key)
+                    state["skipped_sources"] = sorted(skipped)
+            state["connected_sources"] = sorted(connected_sources)
 
     state["last_step_id"] = payload.step_id
     state["updated_at"] = datetime.now(timezone.utc).isoformat()
SOLUTION_PATCH_EOF
diff --git a/loangen-agent/agent/array/client.py b/loangen-agent/agent/array/client.py
index a81f508..3cf500a 100644
--- a/loangen-agent/agent/array/client.py
+++ b/loangen-agent/agent/array/client.py
@@ -141,12 +141,13 @@ class ArrayClient:
         if resp.status_code == 204:
             logger.warning(
                 f"Array retrieve_questions returned 204 No Content for userId={user_id} "
-                "— provider could not generate questions for this user."
+                f"providers={providers} — bureau could not generate questions."
             )
             raise ArrayClientError(
                 "The verification provider could not generate questions for this user. "
                 "Please check your personal information and try again.",
                 status_code=204,
+                details={"providers": providers, "response_headers": dict(resp.headers)},
             )
 
         if resp.status_code == 404:
@@ -197,6 +198,24 @@ class ArrayClient:
                 details=resp.text,
             )
 
+    async def try_retrieve_questions(
+        self,
+        user_id: str,
+        providers: List[str],
+    ) -> Dict[str, Any] | None:
+        """
+        Like retrieve_questions but returns None on HTTP 204 instead of raising.
+
+        Used by the bureau cascade (OTP → KBA → SMFA) when a bureau cannot
+        start verification for this identity.
+        """
+        try:
+            return await self.retrieve_questions(user_id=user_id, providers=providers)
+        except ArrayClientError as exc:
+            if exc.status_code == 204:
+                return None
+            raise
+
     async def submit_answers(
         self,
         user_id: str,
diff --git a/loangen-agent/agent/array/schemas.py b/loangen-agent/agent/array/schemas.py
index fc35f36..91f15cf 100644
--- a/loangen-agent/agent/array/schemas.py
+++ b/loangen-agent/agent/array/schemas.py
@@ -3,7 +3,7 @@ from __future__ import annotations
 from datetime import date
 from typing import Any, Dict, List, Optional
 
-from pydantic import BaseModel, Field
+from pydantic import BaseModel, Field, field_validator
 
 from agent.core.config import settings
 
@@ -52,11 +52,19 @@ class CreateArrayUserRequest(BaseModel):
     )
     ssn: str = Field(
         default=settings.array_demo_ssn_number or "666285344",
-        min_length=4,
+        min_length=9,
         max_length=11,
-        description="SSN (full or as required by Array)",
+        description="SSN (9 digits)",
         examples=[settings.array_demo_ssn_number or "666285344"],
     )
+
+    @field_validator("ssn")
+    @classmethod
+    def validate_ssn_digits(cls, value: str) -> str:
+        digits = "".join(ch for ch in value if ch.isdigit())
+        if len(digits) != 9:
+            raise ValueError("Social Security Number must be exactly 9 digits.")
+        return digits
     dob: date = Field(
         default_factory=lambda: date.fromisoformat(
             settings.array_demo_user_dob or "1939-09-20"
@@ -142,6 +150,13 @@ class CreateUserAndQuestionsResponse(BaseModel):
         description="Bureau performing the verification: 'tui', 'efx', or 'exp'.",
         examples=["tui", "efx", "exp"],
     )
+    isTransition: bool = Field(
+        default=False,
+        description=(
+            "True when a prior bureau could not start verification and the user "
+            "is beginning with the next available method (OTP→KBA or KBA→SMFA)."
+        ),
+    )
 
 
 class SubmitAnswersRequest(BaseModel):
@@ -310,6 +325,14 @@ class RefreshStartResponse(BaseModel):
         default=None,
         description="Bureau performing the verification: 'tui', 'efx', or 'exp'.",
     )
+    isTransition: bool = Field(
+        default=False,
+        description="True when refresh started on a fallback bureau after a prior bureau failed.",
+    )
+    message: Optional[str] = Field(
+        default=None,
+        description="Informational message when verification starts via bureau cascade.",
+    )
     error: Optional[str] = Field(
         default=None,
         description="Error message when can_refresh is False due to an API failure.",
diff --git a/loangen-agent/agent/array/service.py b/loangen-agent/agent/array/service.py
index 6fd1ae9..4efb1f4 100644
--- a/loangen-agent/agent/array/service.py
+++ b/loangen-agent/agent/array/service.py
@@ -45,7 +45,8 @@ class ArrayService:
     High-level orchestration around Array's Customer Verification and Credit Report APIs.
 
     Verification flow (OTP → KBA → SMFA cascade):
-      1. create_user_and_get_questions  — creates the Array user, initiates OTP (tui only)
+      1. create_user_and_get_questions  — creates the Array user, initiates verification
+         with bureau cascade when a bureau returns HTTP 204 at start
       2. submit_answers_and_order_report — submits answers; handles all outcomes:
            - HTTP 206: more questions needed (OTP step transition or KBA follow-up)
            - HTTP 202: SMFA link not yet clicked (poll again)
@@ -73,30 +74,60 @@ class ArrayService:
           5. Return questions + authMethod to frontend
         """
         session_id = str(uuid.uuid4())
-        array_user_id = str(uuid.uuid4())
-        user_payload = self._map_create_user_request(req, array_user_id, user_email)
 
-        try:
-            await self.client.create_user(user_payload.model_dump())
-        except ArrayClientError as exc:
-            logger.error(f"Array create_user failed: {exc}")
-            raise
-
-        # Start with TransUnion only so Array always begins with OTP.
-        providers = self._providers_for_step("otp")
-        if not providers:
-            raise ArrayClientError(
-                "Phone verification is not available right now. Please contact support.",
+        existing_profile = await ArrayUserProfile.find_one(
+            ArrayUserProfile.userId == user_id
+        )
+        if existing_profile:
+            array_user_id = existing_profile.arrayUserId
+            logger.info(
+                f"Reusing existing arrayUserId={array_user_id} for userId={user_id}"
             )
+            await self._stage_user_profile(req, user_id, array_user_id)
+        else:
+            array_user_id = str(uuid.uuid4())
+            user_payload = self._map_create_user_request(req, array_user_id, user_email)
+            try:
+                await self.client.create_user(user_payload.model_dump())
+            except ArrayClientError as exc:
+                if exc.status_code == 409:
+                    # Concurrent retry or prior attempt created the Array user already.
+                    raced_profile = await ArrayUserProfile.find_one(
+                        ArrayUserProfile.userId == user_id
+                    )
+                    if raced_profile:
+                        array_user_id = raced_profile.arrayUserId
+                        logger.info(
+                            f"Array 409 — reusing staged arrayUserId={array_user_id} "
+                            f"for userId={user_id}"
+                        )
+                    else:
+                        prior_tokens = (
+                            await ArrayUserToken.find(
+                                ArrayUserToken.userId == user_id,
+                            )
+                            .sort(-ArrayUserToken.createdDate)
+                            .limit(1)
+                            .to_list()
+                        )
+                        if prior_tokens:
+                            array_user_id = prior_tokens[0].arrayUserId
+                            await self._stage_user_profile(req, user_id, array_user_id)
+                            logger.info(
+                                f"Array 409 — recovered arrayUserId={array_user_id} "
+                                f"from prior session for userId={user_id}"
+                            )
+                        else:
+                            logger.error(f"Array create_user failed: {exc}")
+                            raise
+                else:
+                    logger.error(f"Array create_user failed: {exc}")
+                    raise
+            await self._stage_user_profile(req, user_id, array_user_id)
 
-        try:
-            questions_resp = await self.client.retrieve_questions(
-                user_id=array_user_id,
-                providers=providers,
-            )
-        except ArrayClientError as exc:
-            logger.error(f"Array retrieve_questions failed during create flow: {exc}")
-            raise
+        questions_resp, failed_methods, is_transition = await self._initiate_verification_with_cascade(
+            array_user_id=array_user_id,
+        )
 
         questions_resp = await self._maybe_auto_submit_otp_sms(
             array_user_id=array_user_id,
@@ -114,24 +145,23 @@ class ArrayService:
             authToken=auth_token,
             authMethod=auth_method,
             provider=provider,
-            failedMethods=[],
+            failedMethods=failed_methods,
         )
         await token_doc.insert()
 
-        # Stage ArrayUserProfile so refresh can reuse arrayUserId after a successful pull.
-        await self._stage_user_profile(req, user_id, array_user_id)
-
         logger.info(
             f"Verification initiated for userId={user_id} "
-            f"arrayUserId={array_user_id} authMethod={auth_method} provider={provider}"
+            f"arrayUserId={array_user_id} authMethod={auth_method} provider={provider} "
+            f"failedMethods={failed_methods} isTransition={is_transition}"
         )
         return CreateUserAndQuestionsResponse(
             statusCode="SUCCESS",
-            message="A verification code has been sent to your mobile phone.",
+            message=self._initial_cascade_message(failed_methods, auth_method),
             sessionId=session_id,
             questions=questions,
             authMethod=auth_method,
             provider=provider,
+            isTransition=is_transition,
         )
 
     async def start_refresh_and_get_questions(
@@ -156,25 +186,17 @@ class ArrayService:
             logger.info(f"No ArrayUserProfile for userId={user_id} — refresh not available")
             return RefreshStartResponse(can_refresh=False)
 
-        providers = self._providers_for_step("otp")
         session_id = str(uuid.uuid4())
 
-        if not providers:
-            return RefreshStartResponse(
-                can_refresh=False,
-                error="Phone verification is not available right now. Please use the full connect flow.",
-            )
-
         try:
-            questions_resp = await self.client.retrieve_questions(
-                user_id=profile.arrayUserId,
-                providers=providers,
+            questions_resp, failed_methods, is_transition = await self._initiate_verification_with_cascade(
+                array_user_id=profile.arrayUserId,
             )
         except ArrayClientError as exc:
-            logger.error(f"Array retrieve_questions failed during refresh for userId={user_id}: {exc}")
+            logger.error(f"Array verification cascade failed during refresh for userId={user_id}: {exc}")
             return RefreshStartResponse(can_refresh=False, error=str(exc))
-        except Exception as exc:
-            logger.exception(f"Unexpected error in refresh retrieve_questions for userId={user_id}")
+        except Exception:
+            logger.exception(f"Unexpected error in refresh verification cascade for userId={user_id}")
             return RefreshStartResponse(
                 can_refresh=False,
                 error="Unexpected error starting refresh — please try the full credit pull.",
@@ -196,13 +218,14 @@ class ArrayService:
             authToken=auth_token,
             authMethod=auth_method,
             provider=provider,
-            failedMethods=[],
+            failedMethods=failed_methods,
         )
         await token_doc.insert()
 
         logger.info(
             f"Refresh verification started for userId={user_id} "
-            f"arrayUserId={profile.arrayUserId} authMethod={auth_method}"
+            f"arrayUserId={profile.arrayUserId} authMethod={auth_method} "
+            f"failedMethods={failed_methods}"
         )
         return RefreshStartResponse(
             can_refresh=True,
@@ -210,6 +233,8 @@ class ArrayService:
             questions=questions,
             authMethod=auth_method,
             provider=provider,
+            isTransition=is_transition,
+            message=self._initial_cascade_message(failed_methods, auth_method) if is_transition else None,
         )
 
     async def submit_answers_and_order_report(
@@ -339,26 +364,16 @@ class ArrayService:
 
             # OTP or KBA failed → cascade to the next method in the fallback order.
             new_failed = list(token_doc.failedMethods) + [current_method]
-            providers = self._providers_for_fallback(new_failed)
-
-            if not providers:
-                logger.error(
-                    f"All verification methods exhausted for sessionId={req.sessionId}"
-                )
-                raise ArrayClientError(
-                    self._terminal_verification_message(),
-                    status_code=http_status,
-                )
 
             logger.info(
                 f"{current_method.upper()} failed (HTTP {http_status}) for "
-                f"sessionId={req.sessionId} — falling back with providers={providers}"
+                f"sessionId={req.sessionId} — falling back with failedMethods={new_failed}"
             )
 
             try:
-                new_questions_resp = await self.client.retrieve_questions(
-                    user_id=token_doc.arrayUserId,
-                    providers=providers,
+                new_questions_resp, cascade_failed, _ = await self._initiate_verification_with_cascade(
+                    array_user_id=token_doc.arrayUserId,
+                    skip_methods=new_failed,
                 )
             except ArrayClientError as exc:
                 logger.error(
@@ -374,7 +389,7 @@ class ArrayService:
             token_doc.authToken = new_questions_resp.get("authToken", "")
             token_doc.authMethod = new_auth_method
             token_doc.provider = new_provider
-            token_doc.failedMethods = new_failed
+            token_doc.failedMethods = cascade_failed
             token_doc.updatedDate = datetime.now(timezone.utc)
             await token_doc.save()
 
@@ -554,6 +569,102 @@ class ArrayService:
 
     # ── Private helpers ───────────────────────────────────────────────────────
 
+    async def _initiate_verification_with_cascade(
+        self,
+        *,
+        array_user_id: str,
+        skip_methods: Optional[List[str]] = None,
+    ) -> tuple[Dict[str, Any], List[str], bool]:
+        """
+        Try OTP (tui) → KBA (exp) → SMFA (efx) until one bureau returns questions.
+
+        Returns (questions_response, failed_methods, is_transition).
+        is_transition is True when at least one bureau failed before success.
+        """
+        failed: List[str] = [
+            self._normalize_auth_method(m) for m in (skip_methods or [])
+        ]
+        had_prior_failure = len(failed) > 0
+        configured = self._configured_bureaus()
+
+        any_enabled = any(
+            [p for p in providers if p in configured]
+            for _, providers in _VERIFICATION_FALLBACK_ORDER
+        )
+        if not any_enabled:
+            raise ArrayClientError(
+                "Identity verification is not available right now. Please contact support.",
+            )
+
+        for method_name, provider_list in _VERIFICATION_FALLBACK_ORDER:
+            if method_name in failed:
+                continue
+            providers = [p for p in provider_list if p in configured]
+            if not providers:
+                continue
+
+            resp = await self.client.try_retrieve_questions(
+                user_id=array_user_id,
+                providers=providers,
+            )
+            if resp is None:
+                logger.warning(
+                    f"Bureau cascade: {method_name} ({providers}) returned 204 "
+                    f"for arrayUserId={array_user_id}"
+                )
+                failed.append(method_name)
+                continue
+
+            is_transition = had_prior_failure or len(failed) > len(skip_methods or [])
+            return resp, failed, is_transition
+
+        raise ArrayClientError(
+            self._terminal_verification_message(),
+            status_code=204,
+        )
+
+    def _verification_start_message(self, auth_method: str) -> str:
+        method = self._normalize_auth_method(auth_method)
+        if method == "otp":
+            return "A verification code has been sent to your mobile phone."
+        if method == "kba":
+            return "Please answer a few identity verification questions to continue."
+        if method == "smfa":
+            return (
+                "We sent a secure verification link to your phone. "
+                "Open the link, then continue here."
+            )
+        return "Please complete identity verification to continue."
+
+    def _initial_cascade_message(
+        self,
+        failed_methods: List[str],
+        auth_method: str,
+    ) -> str:
+        """User-facing copy when verification starts (including bureau cascade at connect)."""
+        if not failed_methods:
+            return self._verification_start_message(auth_method)
+
+        current = self._normalize_auth_method(auth_method)
+        last_failed = self._normalize_auth_method(failed_methods[-1])
+
+        if last_failed == "otp" and current == "kba":
+            return (
+                "We couldn't start phone verification for this identity. "
+                "Please answer a few identity questions to continue."
+            )
+        if last_failed == "otp" and current == "smfa":
+            return (
+                "We couldn't start phone verification. "
+                "We'll send a secure verification link to your phone instead."
+            )
+        if last_failed == "kba" and current == "smfa":
+            return (
+                "We couldn't verify with identity questions. "
+                "We'll send a secure verification link to your phone instead."
+            )
+        return self._verification_start_message(auth_method)
+
     @staticmethod
     def _normalize_auth_method(method: str) -> str:
         """Normalize Array authMethod values for cascade bookkeeping."""
diff --git a/loangen-agent/agent/services/smbinvites/router.py b/loangen-agent/agent/services/smbinvites/router.py
index 2546635..d58d15a 100644
--- a/loangen-agent/agent/services/smbinvites/router.py
+++ b/loangen-agent/agent/services/smbinvites/router.py
@@ -66,7 +66,7 @@ async def resolve_invite_route(
     summary="Authenticate SMB from invite using password only",
 )
 async def invite_auth_route(payload: InviteAuthRequest) -> InviteAuthResponse:
-    return await invite_auth(payload.token, payload.password)
+    return await invite_auth(payload.token, payload.password, payload.confirm_password)
 
 
 @router.post(
diff --git a/loangen-agent/agent/services/smbinvites/schemas.py b/loangen-agent/agent/services/smbinvites/schemas.py
index 44b9324..bbb5919 100644
--- a/loangen-agent/agent/services/smbinvites/schemas.py
+++ b/loangen-agent/agent/services/smbinvites/schemas.py
@@ -53,11 +53,13 @@ class InviteResolveResponse(BaseModel):
     expires_at: str
     can_start_application: bool = True
     start_block_message: Optional[str] = None
+    is_existing_user: bool = False
 
 
 class InviteAuthRequest(BaseModel):
     token: str = Field(..., min_length=10)
     password: str = Field(..., min_length=8, max_length=128)
+    confirm_password: Optional[str] = Field(default=None, min_length=8, max_length=128)
 
 
 class InviteAuthResponse(BaseModel):
diff --git a/loangen-agent/agent/services/smbinvites/service.py b/loangen-agent/agent/services/smbinvites/service.py
index e21a7a0..c000400 100644
--- a/loangen-agent/agent/services/smbinvites/service.py
+++ b/loangen-agent/agent/services/smbinvites/service.py
@@ -199,7 +199,11 @@ def _build_tracking(invite: SMBInviteRequest, state: dict[str, Any]) -> Conversa
 
     required_sources = list(invite.required_data_sources)
     connected_sources = [s for s in required_sources if s in state.get("connected_sources", [])]
-    pending_sources = [s for s in required_sources if s not in connected_sources]
+    skipped_sources = set(state.get("skipped_sources", []))
+    pending_sources = [
+        s for s in required_sources
+        if s not in connected_sources and s not in skipped_sources
+    ]
 
     return ConversationTrackingState(
         collected_fields=collected_fields,
@@ -281,17 +285,19 @@ def _next_prompt(invite: SMBInviteRequest, state: dict[str, Any]) -> tuple[Conve
         )
 
     connected_sources: list[str] = state.get("connected_sources", [])
+    skipped_sources: set[str] = set(state.get("skipped_sources", []))
     for source in invite.required_data_sources:
-        if source not in connected_sources:
-            return (
-                ConversationPrompt(
-                    step_id=f"source:{source}",
-                    message=f"Kindly connect your {source.replace('_', ' ')}.",
-                    input_type="connect_source",
-                    source_key=source,
-                ),
-                False,
-            )
+        if source in connected_sources or source in skipped_sources:
+            continue
+        return (
+            ConversationPrompt(
+                step_id=f"source:{source}",
+                message=f"Kindly connect your {source.replace('_', ' ')}.",
+                input_type="connect_source",
+                source_key=source,
+            ),
+            False,
+        )
 
     uploaded_docs: list[str] = state.get("uploaded_documents", [])
     skipped_docs: set[str] = set(state.get("skipped_documents", []))
@@ -478,6 +484,9 @@ async def resolve_invite(raw_token: str) -> InviteResolveResponse:
         can_start_application = True
         start_block_message = None
 
+    email_lower = invite.smb_email.lower()
+    existing_user = await User.find_one(User.email == email_lower)
+
     return InviteResolveResponse(
         invite_id=str(invite.id),
         lender_id=invite.lender_id,
@@ -492,10 +501,15 @@ async def resolve_invite(raw_token: str) -> InviteResolveResponse:
         expires_at=invite.expires_at.isoformat(),
         can_start_application=can_start_application,
         start_block_message=start_block_message,
+        is_existing_user=existing_user is not None,
     )
 
 
-async def invite_auth(raw_token: str, password: str) -> InviteAuthResponse:
+async def invite_auth(
+    raw_token: str,
+    password: str,
+    confirm_password: Optional[str] = None,
+) -> InviteAuthResponse:
     invite = await SMBInviteRequest.find_one(SMBInviteRequest.token_hash == hash_token(raw_token))
     if invite is None:
         raise HTTPException(status_code=404, detail={"error": "INVITE_NOT_FOUND", "message": "Invite link is invalid."})
@@ -526,6 +540,14 @@ async def invite_auth(raw_token: str, password: str) -> InviteAuthResponse:
 
     user = await User.find_one(User.email == email_lower)
     if user is None:
+        if confirm_password is not None and confirm_password != password:
+            raise HTTPException(
+                status_code=status.HTTP_400_BAD_REQUEST,
+                detail={
+                    "error": "PASSWORD_MISMATCH",
+                    "message": "Password and confirm password do not match.",
+                },
+            )
         initial_mode = "production" if _is_production_instance() else settings.default_user_mode
         user = User(
             first_name=invite.smb_first_name,
@@ -914,10 +936,22 @@ async def reply_invite_conversation(
                 state["skipped_documents"] = sorted(skipped)
     elif payload.step_id.startswith("source:"):
         source_key = payload.step_id.split("source:", 1)[1]
-        connected_sources = set(state.get("connected_sources", []))
-        if payload.source_status.get(source_key):
-            connected_sources.add(source_key)
-        state["connected_sources"] = sorted(connected_sources)
+        if (payload.value or "").strip().lower() == "skip":
+            skipped = set(state.get("skipped_sources", []))
+            skipped.add(source_key)
+            state["skipped_sources"] = sorted(skipped)
+            connected = set(state.get("connected_sources", []))
+            connected.discard(source_key)
+            state["connected_sources"] = sorted(connected)
+        else:
+            connected_sources = set(state.get("connected_sources", []))
+            if payload.source_status.get(source_key):
+                connected_sources.add(source_key)
+                skipped = set(state.get("skipped_sources", []))
+                if source_key in skipped:
+                    skipped.discard(source_key)
+                    state["skipped_sources"] = sorted(skipped)
+            state["connected_sources"] = sorted(connected_sources)
 
     state["last_step_id"] = payload.step_id
     state["updated_at"] = datetime.now(timezone.utc).isoformat()
SOLUTION_PATCH_EOF
