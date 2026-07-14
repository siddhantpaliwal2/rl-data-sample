#!/bin/sh
# Oracle solution -- reverse-applies the planted defect patch at base_commit,
# restoring the correct boundary logic in normalize.py and junk_filter.py.
set -eu
cd /app
git apply -R --check - <<'DEFECT_PATCH_EOF' && git apply -R - <<'DEFECT_PATCH_EOF'
diff --git a/loangen-agent/agent/documents/credit_pdf/junk_filter.py b/loangen-agent/agent/documents/credit_pdf/junk_filter.py
index 181a58e..c7202fb 100644
--- a/loangen-agent/agent/documents/credit_pdf/junk_filter.py
+++ b/loangen-agent/agent/documents/credit_pdf/junk_filter.py
@@ -36,7 +36,7 @@ def is_junk_creditor_name(creditor: str) -> bool:
         return True
     if not is_plausible_creditor_line(name):
         return True
-    if name.lower() in _UNKNOWN_CREDITOR:
+    if name in _UNKNOWN_CREDITOR:
         return True
     for pattern in _JUNK_CREDITOR_PATTERNS:
         if pattern.search(name):
@@ -65,7 +65,7 @@ def dedupe_tradelines(tradelines: List[ParsedTradeline]) -> List[ParsedTradeline
     seen: set[str] = set()
     out: List[ParsedTradeline] = []
     for tl in tradelines:
-        key = f"{(tl.creditor or '').lower()}|{tl.account_number or ''}"
+        key = f"{(tl.creditor or '')}|{tl.account_number or ''}"
         if key in seen:
             continue
         seen.add(key)
diff --git a/loangen-agent/agent/documents/credit_pdf/normalize.py b/loangen-agent/agent/documents/credit_pdf/normalize.py
index 3985c7d..fbfc459 100644
--- a/loangen-agent/agent/documents/credit_pdf/normalize.py
+++ b/loangen-agent/agent/documents/credit_pdf/normalize.py
@@ -82,7 +82,7 @@ def bureau_tags_from_text(text: str) -> Set[str]:
     """Map TUC-B1 / EXP-B1 / EQX-B1 (and comma-separated) to bureau keys."""
     found: Set[str] = set()
     upper = (text or "").upper()
-    for token in re.findall(r"\b(TUC|EXP|EQX|TU|EFX)-B\d*\b", upper):
+    for token in re.findall(r"\b(TUC|EXP|EQX|TU)-B\d*\b", upper):
         prefix = token.split("-")[0]
         bureau = _BUREAU_TAG_MAP.get(prefix)
         if bureau:
@@ -115,7 +115,7 @@ def is_plausible_creditor_line(line: str) -> bool:
         return False
     if re.match(r"^\d{3}[-\s]?\d{2}[-\s]?\d{4}$", line):
         return False
-    if re.match(r"^[\d\$\.,\s%]+$", line):
+    if re.match(r"^[\d\$\.,\s%]+", line):
         return False
     if line.lower().startswith("http"):
         return False
@@ -150,7 +150,7 @@ def is_address_or_contact_line(line: str) -> bool:
     if re.match(r"^\d+\s+\w", text):  # street address
         return True
     if re.match(
-        r"^(blvd|st|street|ave|avenue|dr|drive|rd|road|way|lane|ln|ct|court|ste|suite)\.?$",
+        r"^(blvd|st|street|ave|avenue|dr|drive|rd|road|way|lane|ln|ct|court|ste|suite)\.?",
         text,
         re.I,
     ):
DEFECT_PATCH_EOF
diff --git a/loangen-agent/agent/documents/credit_pdf/junk_filter.py b/loangen-agent/agent/documents/credit_pdf/junk_filter.py
index 181a58e..c7202fb 100644
--- a/loangen-agent/agent/documents/credit_pdf/junk_filter.py
+++ b/loangen-agent/agent/documents/credit_pdf/junk_filter.py
@@ -36,7 +36,7 @@ def is_junk_creditor_name(creditor: str) -> bool:
         return True
     if not is_plausible_creditor_line(name):
         return True
-    if name.lower() in _UNKNOWN_CREDITOR:
+    if name in _UNKNOWN_CREDITOR:
         return True
     for pattern in _JUNK_CREDITOR_PATTERNS:
         if pattern.search(name):
@@ -65,7 +65,7 @@ def dedupe_tradelines(tradelines: List[ParsedTradeline]) -> List[ParsedTradeline
     seen: set[str] = set()
     out: List[ParsedTradeline] = []
     for tl in tradelines:
-        key = f"{(tl.creditor or '').lower()}|{tl.account_number or ''}"
+        key = f"{(tl.creditor or '')}|{tl.account_number or ''}"
         if key in seen:
             continue
         seen.add(key)
diff --git a/loangen-agent/agent/documents/credit_pdf/normalize.py b/loangen-agent/agent/documents/credit_pdf/normalize.py
index 3985c7d..fbfc459 100644
--- a/loangen-agent/agent/documents/credit_pdf/normalize.py
+++ b/loangen-agent/agent/documents/credit_pdf/normalize.py
@@ -82,7 +82,7 @@ def bureau_tags_from_text(text: str) -> Set[str]:
     """Map TUC-B1 / EXP-B1 / EQX-B1 (and comma-separated) to bureau keys."""
     found: Set[str] = set()
     upper = (text or "").upper()
-    for token in re.findall(r"\b(TUC|EXP|EQX|TU|EFX)-B\d*\b", upper):
+    for token in re.findall(r"\b(TUC|EXP|EQX|TU)-B\d*\b", upper):
         prefix = token.split("-")[0]
         bureau = _BUREAU_TAG_MAP.get(prefix)
         if bureau:
@@ -115,7 +115,7 @@ def is_plausible_creditor_line(line: str) -> bool:
         return False
     if re.match(r"^\d{3}[-\s]?\d{2}[-\s]?\d{4}$", line):
         return False
-    if re.match(r"^[\d\$\.,\s%]+$", line):
+    if re.match(r"^[\d\$\.,\s%]+", line):
         return False
     if line.lower().startswith("http"):
         return False
@@ -150,7 +150,7 @@ def is_address_or_contact_line(line: str) -> bool:
     if re.match(r"^\d+\s+\w", text):  # street address
         return True
     if re.match(
-        r"^(blvd|st|street|ave|avenue|dr|drive|rd|road|way|lane|ln|ct|court|ste|suite)\.?$",
+        r"^(blvd|st|street|ave|avenue|dr|drive|rd|road|way|lane|ln|ct|court|ste|suite)\.?",
         text,
         re.I,
     ):
DEFECT_PATCH_EOF
