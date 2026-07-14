#!/bin/sh
# Oracle solution -- reverse-applies the planted defect patch, restoring the
# correct boundary handling in the operator handler, the field extractor, the
# Zype eligibility-check functions, and the rule-evaluation service.
set -eu
cd /app
git apply -R --check - <<'DEFECT_PATCH_EOF' && git apply -R - <<'DEFECT_PATCH_EOF'
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
DEFECT_PATCH_EOF
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
DEFECT_PATCH_EOF
