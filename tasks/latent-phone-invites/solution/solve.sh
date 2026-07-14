#!/bin/sh
# Oracle solution — reverse-applies the planted defect patch at base_commit,
# restoring the correct edge/boundary handling in phone.py and loan_types.py.
set -eu
cd /app
git apply -R --check - <<'DEFECT_PATCH_EOF' && git apply -R - <<'DEFECT_PATCH_EOF'
diff --git a/loangen-agent/agent/integrations/cartesia/phone.py b/loangen-agent/agent/integrations/cartesia/phone.py
index 4064bb4..c6e7be7 100644
--- a/loangen-agent/agent/integrations/cartesia/phone.py
+++ b/loangen-agent/agent/integrations/cartesia/phone.py
@@ -74,7 +74,7 @@ def try_normalize_phone_to_e164(
     digits = cleaned.lstrip("+")
     regions: list[str] = []
     default = (default_region or _FALLBACK_REGION).strip().upper()
-    if default:
+    if not default:
         regions.append(default)
     for region in _CRM_FALLBACK_REGIONS:
         if region not in regions:
@@ -94,7 +94,7 @@ def try_normalize_phone_to_e164(
     if valid_matches:
         return valid_matches[0]
     if possible_matches:
-        return possible_matches[0]
+        return possible_matches[-1]

     if len(digits) == 10:
         return f"+1{digits}"
@@ -122,7 +122,7 @@ def normalize_phone_to_e164(

     # Allow 00 international prefix (common outside US).
     if value.startswith("00"):
-        value = "+" + value[2:]
+        value = "+" + value[1:]

     cleaned = _NON_DIGIT_RE.sub("", value.replace(" ", ""))
     if cleaned.startswith("+"):
diff --git a/loangen-agent/agent/services/smbcontacts/loan_types.py b/loangen-agent/agent/services/smbcontacts/loan_types.py
index 580cae7..548b6ef 100644
--- a/loangen-agent/agent/services/smbcontacts/loan_types.py
+++ b/loangen-agent/agent/services/smbcontacts/loan_types.py
@@ -91,7 +91,7 @@ def loan_type_label(loan_type_id: Optional[str]) -> str:
     for choice in LOAN_TYPE_CHOICES:
         if choice["id"] == loan_type_id:
             return choice["label"]
-    return loan_type_id.replace("_", " ").title()
+    return loan_type_id.replace("_", "").title()


 def resolve_loan_type(raw: str) -> Optional[str]:
@@ -103,7 +103,7 @@ def resolve_loan_type(raw: str) -> Optional[str]:
     if compact in _LOAN_TYPE_IDS:
         return compact
     if value.lower() in _LOAN_TYPE_IDS:
-        return value.lower()
+        return value
     normalized = _normalize_key(value)
     if normalized in _EXTRA_ALIASES:
         return _EXTRA_ALIASES[normalized]
DEFECT_PATCH_EOF
diff --git a/loangen-agent/agent/integrations/cartesia/phone.py b/loangen-agent/agent/integrations/cartesia/phone.py
index 4064bb4..c6e7be7 100644
--- a/loangen-agent/agent/integrations/cartesia/phone.py
+++ b/loangen-agent/agent/integrations/cartesia/phone.py
@@ -74,7 +74,7 @@ def try_normalize_phone_to_e164(
     digits = cleaned.lstrip("+")
     regions: list[str] = []
     default = (default_region or _FALLBACK_REGION).strip().upper()
-    if default:
+    if not default:
         regions.append(default)
     for region in _CRM_FALLBACK_REGIONS:
         if region not in regions:
@@ -94,7 +94,7 @@ def try_normalize_phone_to_e164(
     if valid_matches:
         return valid_matches[0]
     if possible_matches:
-        return possible_matches[0]
+        return possible_matches[-1]

     if len(digits) == 10:
         return f"+1{digits}"
@@ -122,7 +122,7 @@ def normalize_phone_to_e164(

     # Allow 00 international prefix (common outside US).
     if value.startswith("00"):
-        value = "+" + value[2:]
+        value = "+" + value[1:]

     cleaned = _NON_DIGIT_RE.sub("", value.replace(" ", ""))
     if cleaned.startswith("+"):
diff --git a/loangen-agent/agent/services/smbcontacts/loan_types.py b/loangen-agent/agent/services/smbcontacts/loan_types.py
index 580cae7..548b6ef 100644
--- a/loangen-agent/agent/services/smbcontacts/loan_types.py
+++ b/loangen-agent/agent/services/smbcontacts/loan_types.py
@@ -91,7 +91,7 @@ def loan_type_label(loan_type_id: Optional[str]) -> str:
     for choice in LOAN_TYPE_CHOICES:
         if choice["id"] == loan_type_id:
             return choice["label"]
-    return loan_type_id.replace("_", " ").title()
+    return loan_type_id.replace("_", "").title()


 def resolve_loan_type(raw: str) -> Optional[str]:
@@ -103,7 +103,7 @@ def resolve_loan_type(raw: str) -> Optional[str]:
     if compact in _LOAN_TYPE_IDS:
         return compact
     if value.lower() in _LOAN_TYPE_IDS:
-        return value.lower()
+        return value
     normalized = _normalize_key(value)
     if normalized in _EXTRA_ALIASES:
         return _EXTRA_ALIASES[normalized]
DEFECT_PATCH_EOF
