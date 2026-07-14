# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image for the BRE rule-evaluation engine.
# The targeted logic is pure, deterministic and offline; importing the target
# modules needs no live database or network (pymongo/dateutil import cleanly
# and connect only lazily inside methods that these boundary paths never call).
# Locally the base is the repo image built from a plain python:3.11-slim +
# `COPY . /app`. On the platform, replace with the approved registry reference,
# e.g. FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/bre-xxxxx:v1@sha256:...
FROM bre-repo:v1

USER root
WORKDIR /app

# Plant the subtle boundary defects into the working tree. Nothing in the
# codebase exercises these exact-edge inputs, so the change is latent.
RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/bre_engine/engine/custom_functions/zype_functions.py b/bre_engine/engine/custom_functions/zype_functions.py
index d24ac74..3854d1e 100644
--- a/bre_engine/engine/custom_functions/zype_functions.py
+++ b/bre_engine/engine/custom_functions/zype_functions.py
@@ -146,7 +146,7 @@ class AmountOverdueThresholdCheckFunction(CustomFunction):
                     if overdue_amount > max_overdue_amount:
                         max_overdue_amount = overdue_amount
                     
-                    if overdue_amount > threshold:
+                    if overdue_amount >= threshold:
                         overdue_accounts.append({
                             'lender': account.get('lender'),
                             'account_type': account.get('accountType'),
@@ -234,7 +234,7 @@ class ActiveAccountsCheckFunction(CustomFunction):
                         amount = float(str(sanctioned_amount).replace(',', ''))
                         
                         # Check if amount is within limit (up to max_limit)
-                        if 0 < amount <= max_limit:
+                        if 0 < amount < max_limit:
                             qualifying_accounts.append({
                                 'lender': account.get('lender'),
                                 'account_type': account_type,
diff --git a/bre_engine/engine/field_extractor.py b/bre_engine/engine/field_extractor.py
index 478bc6c..ed57cb1 100644
--- a/bre_engine/engine/field_extractor.py
+++ b/bre_engine/engine/field_extractor.py
@@ -46,7 +46,7 @@ class FieldExtractor:
             elif isinstance(value, list) and key.isdigit():
                 # Support array indexing: 'items.0.name'
                 index = int(key)
-                value = value[index] if 0 <= index < len(value) else default
+                value = value[index] if 0 < index < len(value) else default
             else:
                 return default
         
diff --git a/bre_engine/engine/operator_handler.py b/bre_engine/engine/operator_handler.py
index 8ba6f26..0e92dc4 100644
--- a/bre_engine/engine/operator_handler.py
+++ b/bre_engine/engine/operator_handler.py
@@ -43,7 +43,7 @@ class OperatorHandler:
             '<=': lambda a, e: self._safe_compare(a, e, lambda x, y: x <= y),
             'in': lambda a, e: a in e if e else False,
             'not_in': lambda a, e: a not in e if e else True,
-            'between': lambda a, e: e[0] <= a <= e[1] if len(e) == 2 else False,
+            'between': lambda a, e: e[0] < a <= e[1] if len(e) == 2 else False,
             'contains': lambda a, e: e in str(a),
             'startswith': lambda a, e: str(a).startswith(str(e)),
             'endswith': lambda a, e: str(a).endswith(str(e)),
diff --git a/intelligent_recommendation_engine/services/rule_evaluation_service.py b/intelligent_recommendation_engine/services/rule_evaluation_service.py
index b24fcb5..6df221e 100644
--- a/intelligent_recommendation_engine/services/rule_evaluation_service.py
+++ b/intelligent_recommendation_engine/services/rule_evaluation_service.py
@@ -196,7 +196,7 @@ class RuleEvaluationService:
                 "value": None
             }
         
-        if credit_score >= threshold:
+        if credit_score > threshold:
             status = "PASS"
             message = f"Credit score {credit_score} meets minimum requirement of {threshold}"
         elif credit_score >= threshold - 50:
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Collapse history: planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app
