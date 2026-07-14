#!/bin/sh
# Oracle solution — reverses the six planted source defects (source files only).
set -eu
cd /app

cat > /tmp/fix.patch <<'SOLUTION_PATCH_EOF'
diff --git a/loangen-agent/agent/integrations/cartesia/phone.py b/loangen-agent/agent/integrations/cartesia/phone.py
index 15e5586..4064bb4 100644
--- a/loangen-agent/agent/integrations/cartesia/phone.py
+++ b/loangen-agent/agent/integrations/cartesia/phone.py
@@ -16,7 +16,7 @@ from phonenumbers import NumberParseException, PhoneNumberFormat
 _NON_DIGIT_RE = re.compile(r"[^\d+]+")
 _FALLBACK_REGION = "US"
 # Regions tried when no + country code is provided (default region first).
-_CRM_FALLBACK_REGIONS = ("US", "CA", "GB", "AU", "MX", "DE", "FR")
+_CRM_FALLBACK_REGIONS = ("US", "CA", "IN", "GB", "AU", "MX", "DE", "FR")


 def _format_parsed_number(parsed: phonenumbers.PhoneNumber, *, require_valid: bool) -> Optional[str]:
diff --git a/loangen-agent/agent/services/smbcontacts/loan_types.py b/loangen-agent/agent/services/smbcontacts/loan_types.py
index 19a4301..580cae7 100644
--- a/loangen-agent/agent/services/smbcontacts/loan_types.py
+++ b/loangen-agent/agent/services/smbcontacts/loan_types.py
@@ -109,7 +109,7 @@ def resolve_loan_type(raw: str) -> Optional[str]:
         return _EXTRA_ALIASES[normalized]
     for choice in LOAN_TYPE_CHOICES:
         if _normalize_key(choice["label"]) == normalized:
-            return choice["label"]
+            return choice["id"]
         if _normalize_key(choice["id"]) == normalized:
             return choice["id"]
     return None
diff --git a/loangen-agent/agent/services/smbcontacts/service.py b/loangen-agent/agent/services/smbcontacts/service.py
index e2b8c1a..eab3b09 100644
--- a/loangen-agent/agent/services/smbcontacts/service.py
+++ b/loangen-agent/agent/services/smbcontacts/service.py
@@ -215,7 +215,7 @@ def _apply_csv_row_to_contact(
         email=email,
     )
     warnings.extend(mobile_warnings)
-    if mobile_stored and contact.mobile == mobile_stored:
+    if mobile_stored and contact.mobile != mobile_stored:
         contact.mobile = mobile_stored
         changed = True

diff --git a/loangen-agent/agent/services/smbinvites/schemas.py b/loangen-agent/agent/services/smbinvites/schemas.py
index 078b65f..6213f16 100644
--- a/loangen-agent/agent/services/smbinvites/schemas.py
+++ b/loangen-agent/agent/services/smbinvites/schemas.py
@@ -19,7 +19,7 @@ class CreateInviteRequest(BaseModel):
         if v is None or not str(v).strip():
             return None
         resolved = resolve_loan_type(str(v))
-        if resolved:
+        if not resolved:
             raise ValueError(
                 "loan_type_id is not recognized. Choose a loan type from the CRM list."
             )
diff --git a/loangen-agent/agent/services/smbinvites/service.py b/loangen-agent/agent/services/smbinvites/service.py
index 64475f9..975b7af 100644
--- a/loangen-agent/agent/services/smbinvites/service.py
+++ b/loangen-agent/agent/services/smbinvites/service.py
@@ -366,7 +366,7 @@ def _seed_crm_hints(state: dict[str, Any], contact: Optional[SMBContact]) -> boo
     if contact is None:
         return False
     changed = False
-    if contact.loan_type and "crm_hint_loan_type" in state:
+    if contact.loan_type and "crm_hint_loan_type" not in state:
         state["crm_hint_loan_type"] = contact.loan_type
         changed = True
     if contact.monthly_revenue and not state.get("monthly_revenue"):
@@ -405,7 +405,7 @@ def _build_tracking(invite: SMBInviteRequest, state: dict[str, Any]) -> Conversa
     skipped_sources = set(state.get("skipped_sources", []))
     pending_sources = [
         s for s in required_sources
-        if s not in connected_sources or s not in skipped_sources
+        if s not in connected_sources and s not in skipped_sources
     ]

     return ConversationTrackingState(
SOLUTION_PATCH_EOF

git apply --check /tmp/fix.patch && git apply /tmp/fix.patch
rm -f /tmp/fix.patch
