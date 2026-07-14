#!/bin/sh
# Oracle solution — reverse-applies the planted defect patch at base_commit,
# restoring the correct boundary math in the CRE document field extractors
# (loangen-agent/agent/documents/extractors/cre_fields.py).
set -eu
cd /app
git apply -R --check - <<'DEFECT_PATCH_EOF' && git apply -R - <<'DEFECT_PATCH_EOF'
diff --git a/loangen-agent/agent/documents/extractors/cre_fields.py b/loangen-agent/agent/documents/extractors/cre_fields.py
index 1ae0715..1d9899d 100644
--- a/loangen-agent/agent/documents/extractors/cre_fields.py
+++ b/loangen-agent/agent/documents/extractors/cre_fields.py
@@ -51,7 +51,7 @@ def _sum_rent_amounts(text: str) -> Optional[float]:
             if amt is not None and 100 < amt < 5_000_000:
                 total += amt
                 count += 1
-    return total if count >= 2 else None
+    return total if count >= 3 else None
 
 
 def _parse_money(s: str) -> Optional[float]:
@@ -68,7 +68,7 @@ def _sanitize_value_amount(val: Optional[float], *, min_amount: float = 100_000)
         f = float(val)
     except (TypeError, ValueError):
         return None
-    return f if f >= min_amount else None
+    return f if f > min_amount else None
 
 
 def extract_appraisal_fields(text: str) -> Dict[str, Any]:
@@ -336,7 +336,7 @@ def extract_hud_fields(text: str) -> Dict[str, Any]:
     for key, patterns in mappings:
         val = _find_labeled_amount(text, patterns)
         if val is not None:
-            if key == "hud_loan_amount" and val < _MIN_HUD_LOAN_AMOUNT:
+            if key == "hud_loan_amount" and val <= _MIN_HUD_LOAN_AMOUNT:
                 continue
             facts[key] = val
     if "hud_loan_amount" in facts:
@@ -774,7 +774,7 @@ def extract_credit_report_fields(text: str) -> Dict[str, Any]:
         m = re.search(pat, text, re.IGNORECASE)
         if m:
             score = int(m.group(1))
-            if 300 <= score <= 850:
+            if 300 <= score < 850:
                 bureau_scores[bureau] = score
 
     if not bureau_scores:
DEFECT_PATCH_EOF
diff --git a/loangen-agent/agent/documents/extractors/cre_fields.py b/loangen-agent/agent/documents/extractors/cre_fields.py
index 1ae0715..1d9899d 100644
--- a/loangen-agent/agent/documents/extractors/cre_fields.py
+++ b/loangen-agent/agent/documents/extractors/cre_fields.py
@@ -51,7 +51,7 @@ def _sum_rent_amounts(text: str) -> Optional[float]:
             if amt is not None and 100 < amt < 5_000_000:
                 total += amt
                 count += 1
-    return total if count >= 2 else None
+    return total if count >= 3 else None
 
 
 def _parse_money(s: str) -> Optional[float]:
@@ -68,7 +68,7 @@ def _sanitize_value_amount(val: Optional[float], *, min_amount: float = 100_000)
         f = float(val)
     except (TypeError, ValueError):
         return None
-    return f if f >= min_amount else None
+    return f if f > min_amount else None
 
 
 def extract_appraisal_fields(text: str) -> Dict[str, Any]:
@@ -336,7 +336,7 @@ def extract_hud_fields(text: str) -> Dict[str, Any]:
     for key, patterns in mappings:
         val = _find_labeled_amount(text, patterns)
         if val is not None:
-            if key == "hud_loan_amount" and val < _MIN_HUD_LOAN_AMOUNT:
+            if key == "hud_loan_amount" and val <= _MIN_HUD_LOAN_AMOUNT:
                 continue
             facts[key] = val
     if "hud_loan_amount" in facts:
@@ -774,7 +774,7 @@ def extract_credit_report_fields(text: str) -> Dict[str, Any]:
         m = re.search(pat, text, re.IGNORECASE)
         if m:
             score = int(m.group(1))
-            if 300 <= score <= 850:
+            if 300 <= score < 850:
                 bureau_scores[bureau] = score
 
     if not bureau_scores:
DEFECT_PATCH_EOF
