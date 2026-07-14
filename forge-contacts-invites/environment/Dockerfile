# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image (SMB contacts / invites / phone cluster).
# The verified suite is fully mocked and offline; no secrets or network needed.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset the working tree to the clean base, then plant the defects.
RUN git reset --hard 04b8abc5515c22bdb7a2da32bf2719c8ac702174 && git clean -fdq

# ── Planted defects (natural, single-line, type-preserving) ────────────────────
# Six logic slips across the contacts/invites/phone cluster; the visible symptoms
# surface at the CSV-import, invite-create, contact-update, and advisor flows.
RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/loangen-agent/agent/integrations/cartesia/phone.py b/loangen-agent/agent/integrations/cartesia/phone.py
index 4064bb4..15e5586 100644
--- a/loangen-agent/agent/integrations/cartesia/phone.py
+++ b/loangen-agent/agent/integrations/cartesia/phone.py
@@ -16,7 +16,7 @@ from phonenumbers import NumberParseException, PhoneNumberFormat
 _NON_DIGIT_RE = re.compile(r"[^\d+]+")
 _FALLBACK_REGION = "US"
 # Regions tried when no + country code is provided (default region first).
-_CRM_FALLBACK_REGIONS = ("US", "CA", "IN", "GB", "AU", "MX", "DE", "FR")
+_CRM_FALLBACK_REGIONS = ("US", "CA", "GB", "AU", "MX", "DE", "FR")


 def _format_parsed_number(parsed: phonenumbers.PhoneNumber, *, require_valid: bool) -> Optional[str]:
diff --git a/loangen-agent/agent/services/smbcontacts/loan_types.py b/loangen-agent/agent/services/smbcontacts/loan_types.py
index 580cae7..19a4301 100644
--- a/loangen-agent/agent/services/smbcontacts/loan_types.py
+++ b/loangen-agent/agent/services/smbcontacts/loan_types.py
@@ -109,7 +109,7 @@ def resolve_loan_type(raw: str) -> Optional[str]:
         return _EXTRA_ALIASES[normalized]
     for choice in LOAN_TYPE_CHOICES:
         if _normalize_key(choice["label"]) == normalized:
-            return choice["id"]
+            return choice["label"]
         if _normalize_key(choice["id"]) == normalized:
             return choice["id"]
     return None
diff --git a/loangen-agent/agent/services/smbcontacts/service.py b/loangen-agent/agent/services/smbcontacts/service.py
index eab3b09..e2b8c1a 100644
--- a/loangen-agent/agent/services/smbcontacts/service.py
+++ b/loangen-agent/agent/services/smbcontacts/service.py
@@ -215,7 +215,7 @@ def _apply_csv_row_to_contact(
         email=email,
     )
     warnings.extend(mobile_warnings)
-    if mobile_stored and contact.mobile != mobile_stored:
+    if mobile_stored and contact.mobile == mobile_stored:
         contact.mobile = mobile_stored
         changed = True

diff --git a/loangen-agent/agent/services/smbinvites/schemas.py b/loangen-agent/agent/services/smbinvites/schemas.py
index 6213f16..078b65f 100644
--- a/loangen-agent/agent/services/smbinvites/schemas.py
+++ b/loangen-agent/agent/services/smbinvites/schemas.py
@@ -19,7 +19,7 @@ class CreateInviteRequest(BaseModel):
         if v is None or not str(v).strip():
             return None
         resolved = resolve_loan_type(str(v))
-        if not resolved:
+        if resolved:
             raise ValueError(
                 "loan_type_id is not recognized. Choose a loan type from the CRM list."
             )
diff --git a/loangen-agent/agent/services/smbinvites/service.py b/loangen-agent/agent/services/smbinvites/service.py
index 975b7af..64475f9 100644
--- a/loangen-agent/agent/services/smbinvites/service.py
+++ b/loangen-agent/agent/services/smbinvites/service.py
@@ -366,7 +366,7 @@ def _seed_crm_hints(state: dict[str, Any], contact: Optional[SMBContact]) -> boo
     if contact is None:
         return False
     changed = False
-    if contact.loan_type and "crm_hint_loan_type" not in state:
+    if contact.loan_type and "crm_hint_loan_type" in state:
         state["crm_hint_loan_type"] = contact.loan_type
         changed = True
     if contact.monthly_revenue and not state.get("monthly_revenue"):
@@ -405,7 +405,7 @@ def _build_tracking(invite: SMBInviteRequest, state: dict[str, Any]) -> Conversa
     skipped_sources = set(state.get("skipped_sources", []))
     pending_sources = [
         s for s in required_sources
-        if s not in connected_sources and s not in skipped_sources
+        if s not in connected_sources or s not in skipped_sources
     ]

     return ConversationTrackingState(
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# ── Hidden construction ────────────────────────────────────────────────────────
# Remove the repo test files that would fail against the plants; the verifier
# restores them (verbatim + hardened) from config.json's test_patch at grade time.
RUN rm -f \
    loangen-agent/tests/test_smb_contacts_csv_and_update.py \
    loangen-agent/tests/test_smb_invite_schemas.py \
    loangen-agent/tests/test_smb_invite_conversation.py

# Collapse history so the plants are not visible via git diff / log / reflog.
RUN rm -rf .git \
    && git init -qb main \
    && git config user.email t@t \
    && git config user.name t \
    && git add -A \
    && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
