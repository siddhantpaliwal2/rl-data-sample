# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image for the financial-data analysis tools.
# The bank / credit-bureau / accounting analytics math is deterministic, fully
# offline, and needs no secrets beyond the JWT_SECRET_KEY already baked into
# loangenus-repo:v1.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM <your-registry>/repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset to the clean base HEAD, then plant the subtle boundary defects into the
# working tree. Every existing test still passes with these applied; only
# untested exact-threshold / minimal-window / even-sized-set inputs are wrong.
RUN git reset --hard 04b8abc5515c22bdb7a2da32bf2719c8ac702174 && git clean -fdq

RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/loangen-agent/agent/analytics/services/credit_bureau_analytics.py b/loangen-agent/agent/analytics/services/credit_bureau_analytics.py
index f57991a..547bffc 100644
--- a/loangen-agent/agent/analytics/services/credit_bureau_analytics.py
+++ b/loangen-agent/agent/analytics/services/credit_bureau_analytics.py
@@ -94,7 +94,7 @@ def _safe_float(val: str | None, default: float | None = None) -> float | None:
         return default
     try:
         v = float(val)
-        if v in (-3.0, -4.0, -5.0):
+        if v in (-3.0, -4.0):
             return default
         return v
     except (ValueError, TypeError):
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
index 580d220..2a34475 100644
--- a/loangen-agent/agent/analytics/services/plaid_analytics.py
+++ b/loangen-agent/agent/analytics/services/plaid_analytics.py
@@ -54,7 +54,7 @@ def _parse_month(date_str: str) -> str:
 
 
 def _compute_volatility(values: list[float]) -> float:
-    if len(values) < 2:
+    if len(values) <= 2:
         return 0.0
     mean = statistics.mean(values)
     if mean == 0:
@@ -403,7 +403,7 @@ def build_bank_analytics_checklist_v1(plaid_analytics_payload: dict[str, Any]) -
     limits = [float(a.get("credit_limit") or 0) for a in credit_accounts if a.get("credit_limit")]
     total_credit_limit = round(sum(limits), 2)
     near_limit_count = sum(
-        1 for a in credit_accounts if float(a.get("utilization_pct") or 0) >= 75.0
+        1 for a in credit_accounts if float(a.get("utilization_pct") or 0) > 75.0
     )
     utilizations = [float(a.get("utilization_pct") or 0) for a in credit_accounts if a.get("utilization_pct") is not None]
     overall_util = round(sum(utilizations) / len(utilizations), 1) if utilizations else None
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
 
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Collapse history: planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
