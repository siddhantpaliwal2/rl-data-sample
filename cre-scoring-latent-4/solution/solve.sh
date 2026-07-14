#!/bin/sh
# Oracle solution — reverse-applies the planted defect patch at base_commit,
# restoring the correct boundary math in facts.py and scoring.py.
set -eu
cd /app
git apply -R --check - <<'DEFECT_PATCH_EOF' && git apply -R - <<'DEFECT_PATCH_EOF'
diff --git a/loangen-agent/agent/services/cre_qualification/facts.py b/loangen-agent/agent/services/cre_qualification/facts.py
index 7738b22..7a305fe 100644
--- a/loangen-agent/agent/services/cre_qualification/facts.py
+++ b/loangen-agent/agent/services/cre_qualification/facts.py
@@ -146,7 +146,7 @@ def resolve_appraisal_value(facts: Dict[str, Any]) -> Optional[float]:
         "as_complete_value",
     ):
         v = _safe_float(get_fact(facts, key))
-        if v is not None and v >= 100_000:
+        if v is not None and v > 100_000:
             return v
     return None
 
@@ -164,7 +164,7 @@ def resolve_document_fico(facts: Dict[str, Any]) -> Optional[int]:
     if isinstance(bureau, dict) and bureau:
         scores = sorted(int(v) for v in bureau.values() if isinstance(v, (int, float)) and 300 <= v <= 850)
         if scores:
-            return scores[len(scores) // 2]
+            return scores[(len(scores) - 1) // 2]
     return None
 
 
@@ -297,7 +297,7 @@ def resolve_tenant_concentration(facts: Dict[str, Any]) -> Optional[float]:
     v = _safe_float(get_fact(facts, "tenant_concentration", "largest_tenant_pct"))
     if v is None:
         return None
-    return v / 100.0 if v > 1 else v
+    return v / 100.0 if v >= 1 else v
 
 
 def resolve_annual_debt_service(facts: Dict[str, Any]) -> Optional[float]:
diff --git a/loangen-agent/agent/services/cre_qualification/scoring.py b/loangen-agent/agent/services/cre_qualification/scoring.py
index de67db5..5618eee 100644
--- a/loangen-agent/agent/services/cre_qualification/scoring.py
+++ b/loangen-agent/agent/services/cre_qualification/scoring.py
@@ -42,7 +42,7 @@ def weighted_score(components: Dict[str, Optional[float]], weights: Dict[str, fl
         if val is None:
             continue
         total_w += weight
-        total += weight * clamp(val)
+        total += weight * val
     if total_w <= 0:
         return None
     return round(total / total_w, 1)
DEFECT_PATCH_EOF
diff --git a/loangen-agent/agent/services/cre_qualification/facts.py b/loangen-agent/agent/services/cre_qualification/facts.py
index 7738b22..7a305fe 100644
--- a/loangen-agent/agent/services/cre_qualification/facts.py
+++ b/loangen-agent/agent/services/cre_qualification/facts.py
@@ -146,7 +146,7 @@ def resolve_appraisal_value(facts: Dict[str, Any]) -> Optional[float]:
         "as_complete_value",
     ):
         v = _safe_float(get_fact(facts, key))
-        if v is not None and v >= 100_000:
+        if v is not None and v > 100_000:
             return v
     return None
 
@@ -164,7 +164,7 @@ def resolve_document_fico(facts: Dict[str, Any]) -> Optional[int]:
     if isinstance(bureau, dict) and bureau:
         scores = sorted(int(v) for v in bureau.values() if isinstance(v, (int, float)) and 300 <= v <= 850)
         if scores:
-            return scores[len(scores) // 2]
+            return scores[(len(scores) - 1) // 2]
     return None
 
 
@@ -297,7 +297,7 @@ def resolve_tenant_concentration(facts: Dict[str, Any]) -> Optional[float]:
     v = _safe_float(get_fact(facts, "tenant_concentration", "largest_tenant_pct"))
     if v is None:
         return None
-    return v / 100.0 if v > 1 else v
+    return v / 100.0 if v >= 1 else v
 
 
 def resolve_annual_debt_service(facts: Dict[str, Any]) -> Optional[float]:
diff --git a/loangen-agent/agent/services/cre_qualification/scoring.py b/loangen-agent/agent/services/cre_qualification/scoring.py
index de67db5..5618eee 100644
--- a/loangen-agent/agent/services/cre_qualification/scoring.py
+++ b/loangen-agent/agent/services/cre_qualification/scoring.py
@@ -42,7 +42,7 @@ def weighted_score(components: Dict[str, Optional[float]], weights: Dict[str, fl
         if val is None:
             continue
         total_w += weight
-        total += weight * clamp(val)
+        total += weight * val
     if total_w <= 0:
         return None
     return round(total / total_w, 1)
DEFECT_PATCH_EOF
