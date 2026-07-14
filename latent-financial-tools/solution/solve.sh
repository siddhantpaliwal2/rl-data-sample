#!/bin/sh
# Oracle solution — reverse-applies the planted defect patch at base_commit,
# restoring the correct boundary math in the bank, credit-bureau and accounting
# analytics services (plaid_analytics.py, credit_bureau_analytics.py,
# quickbooks_analytics.py).
set -eu
cd /app
git apply -R --check - <<'DEFECT_PATCH_EOF' && git apply -R - <<'DEFECT_PATCH_EOF'
diff --git a/loangen-agent/agent/analytics/services/credit_bureau_analytics.py b/loangen-agent/agent/analytics/services/credit_bureau_analytics.py
index f57991a..2e62210 100644
--- a/loangen-agent/agent/analytics/services/credit_bureau_analytics.py
+++ b/loangen-agent/agent/analytics/services/credit_bureau_analytics.py
@@ -437,7 +437,7 @@ def build_credit_analytics_checklist_v1(
     severe_delinquency_count = sum(
         1
         for t in tradelines
-        if (int(t.get("late_90") or 0) > 0) or bool(t.get("is_chargeoff"))
+        if (int(t.get("late_90") or 0) > 1) or bool(t.get("is_chargeoff"))
     )
     delinquent_open_count = sum(
         1
diff --git a/loangen-agent/agent/analytics/services/plaid_analytics.py b/loangen-agent/agent/analytics/services/plaid_analytics.py
index 580d220..1f96eb8 100644
--- a/loangen-agent/agent/analytics/services/plaid_analytics.py
+++ b/loangen-agent/agent/analytics/services/plaid_analytics.py
@@ -54,7 +54,7 @@ def _parse_month(date_str: str) -> str:
 
 
 def _compute_volatility(values: list[float]) -> float:
-    if len(values) < 2:
+    if len(values) <= 2:
         return 0.0
     mean = statistics.mean(values)
     if mean == 0:
@@ -403,14 +403,14 @@ def build_bank_analytics_checklist_v1(plaid_analytics_payload: dict[str, Any]) -
     limits = [float(a.get("credit_limit") or 0) for a in credit_accounts if a.get("credit_limit")]
     total_credit_limit = round(sum(limits), 2)
     near_limit_count = sum(
-        1 for a in credit_accounts if float(a.get("utilization_pct") or 0) >= 75.0
+        1 for a in credit_accounts if float(a.get("utilization_pct") or 0) > 75.0
     )
     utilizations = [float(a.get("utilization_pct") or 0) for a in credit_accounts if a.get("utilization_pct") is not None]
     overall_util = round(sum(utilizations) / len(utilizations), 1) if utilizations else None
 
     months_observed = sorted({str(m.get("month")) for m in monthly if m.get("month")})
     expected: list[str] = []
-    if len(months_observed) >= 2:
+    if len(months_observed) >= 3:
         expected = _enumerate_months_inclusive(months_observed[0], months_observed[-1])
     missing_months = sorted(set(expected) - set(months_observed)) if expected else []
 
diff --git a/loangen-agent/agent/analytics/services/quickbooks_analytics.py b/loangen-agent/agent/analytics/services/quickbooks_analytics.py
index 0ddbad3..acf7ea9 100644
--- a/loangen-agent/agent/analytics/services/quickbooks_analytics.py
+++ b/loangen-agent/agent/analytics/services/quickbooks_analytics.py
@@ -80,7 +80,7 @@ def _extract_monthly_from_summary(section: dict | None, num_months: int) -> list
         return []
     summary = section.get("Summary", {})
     col_data = summary.get("ColData", [])
-    if len(col_data) < num_months + 2:
+    if len(col_data) <= num_months + 2:
         return []
     return [_safe_float(col_data[i].get("value", "0")) for i in range(1, num_months + 1)]
 
DEFECT_PATCH_EOF
diff --git a/loangen-agent/agent/analytics/services/credit_bureau_analytics.py b/loangen-agent/agent/analytics/services/credit_bureau_analytics.py
index f57991a..2e62210 100644
--- a/loangen-agent/agent/analytics/services/credit_bureau_analytics.py
+++ b/loangen-agent/agent/analytics/services/credit_bureau_analytics.py
@@ -437,7 +437,7 @@ def build_credit_analytics_checklist_v1(
     severe_delinquency_count = sum(
         1
         for t in tradelines
-        if (int(t.get("late_90") or 0) > 0) or bool(t.get("is_chargeoff"))
+        if (int(t.get("late_90") or 0) > 1) or bool(t.get("is_chargeoff"))
     )
     delinquent_open_count = sum(
         1
diff --git a/loangen-agent/agent/analytics/services/plaid_analytics.py b/loangen-agent/agent/analytics/services/plaid_analytics.py
index 580d220..1f96eb8 100644
--- a/loangen-agent/agent/analytics/services/plaid_analytics.py
+++ b/loangen-agent/agent/analytics/services/plaid_analytics.py
@@ -54,7 +54,7 @@ def _parse_month(date_str: str) -> str:
 
 
 def _compute_volatility(values: list[float]) -> float:
-    if len(values) < 2:
+    if len(values) <= 2:
         return 0.0
     mean = statistics.mean(values)
     if mean == 0:
@@ -403,14 +403,14 @@ def build_bank_analytics_checklist_v1(plaid_analytics_payload: dict[str, Any]) -
     limits = [float(a.get("credit_limit") or 0) for a in credit_accounts if a.get("credit_limit")]
     total_credit_limit = round(sum(limits), 2)
     near_limit_count = sum(
-        1 for a in credit_accounts if float(a.get("utilization_pct") or 0) >= 75.0
+        1 for a in credit_accounts if float(a.get("utilization_pct") or 0) > 75.0
     )
     utilizations = [float(a.get("utilization_pct") or 0) for a in credit_accounts if a.get("utilization_pct") is not None]
     overall_util = round(sum(utilizations) / len(utilizations), 1) if utilizations else None
 
     months_observed = sorted({str(m.get("month")) for m in monthly if m.get("month")})
     expected: list[str] = []
-    if len(months_observed) >= 2:
+    if len(months_observed) >= 3:
         expected = _enumerate_months_inclusive(months_observed[0], months_observed[-1])
     missing_months = sorted(set(expected) - set(months_observed)) if expected else []
 
diff --git a/loangen-agent/agent/analytics/services/quickbooks_analytics.py b/loangen-agent/agent/analytics/services/quickbooks_analytics.py
index 0ddbad3..acf7ea9 100644
--- a/loangen-agent/agent/analytics/services/quickbooks_analytics.py
+++ b/loangen-agent/agent/analytics/services/quickbooks_analytics.py
@@ -80,7 +80,7 @@ def _extract_monthly_from_summary(section: dict | None, num_months: int) -> list
         return []
     summary = section.get("Summary", {})
     col_data = summary.get("ColData", [])
-    if len(col_data) < num_months + 2:
+    if len(col_data) <= num_months + 2:
         return []
     return [_safe_float(col_data[i].get("value", "0")) for i in range(1, num_months + 1)]
 
DEFECT_PATCH_EOF
