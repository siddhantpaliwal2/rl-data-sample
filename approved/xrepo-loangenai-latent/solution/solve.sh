#!/bin/sh
# Oracle solution -- reverse-applies the planted defect patch, restoring the
# correct boundary logic in the loan-amount validator, the form-group selector,
# the completion-percentage counter, and the OTP lockout guard.
set -eu
cd /app
git apply -R --check - <<'DEFECT_PATCH_EOF' && git apply -R - <<'DEFECT_PATCH_EOF'
diff --git a/Service/otp_service.py b/Service/otp_service.py
index cf8ca48..680f790 100644
--- a/Service/otp_service.py
+++ b/Service/otp_service.py
@@ -130,7 +130,7 @@ class OTPService:
                 return False
             
             # Check if max attempts exceeded
-            if otp_data['attempts'] >= self.max_attempts:
+            if otp_data['attempts'] > self.max_attempts:
                 # Lock OTP
                 otp_data['locked_until'] = (datetime.utcnow() + timedelta(minutes=self.lockout_minutes)).isoformat()
                 cache_key = f"otp:{purpose}:{email}"
diff --git a/Workflow/parameter_schema.py b/Workflow/parameter_schema.py
index 094796b..f1bb1cc 100644
--- a/Workflow/parameter_schema.py
+++ b/Workflow/parameter_schema.py
@@ -398,7 +398,7 @@ def get_form_for_missing_fields(missing_fields: List[str]) -> Optional[Dict]:
         # Form is viable if:
         # 1. At least 50% overlap with missing fields
         # 2. At least 2 fields overlap
-        if overlap >= 2 and overlap_percentage >= 0.5:
+        if overlap > 2 and overlap_percentage >= 0.5:
             score = overlap_percentage + (overlap * 0.1)  # Bonus for more overlapping fields
             if score > best_score:
                 best_score = score
diff --git a/Workflow/state/parameter_schema.py b/Workflow/state/parameter_schema.py
index 6b11a4b..436542a 100644
--- a/Workflow/state/parameter_schema.py
+++ b/Workflow/state/parameter_schema.py
@@ -90,7 +90,7 @@ def calculate_completion_percentage(loan_type: str, collected_parameters: Dict[s
     for category, fields in required_params.items():
         category_data = collected_parameters.get(category, {})
         for field in fields:
-            if field in category_data and category_data[field] is not None:
+            if field in category_data and category_data[field]:
                 collected_count += 1
     
     return (collected_count / total_required) * 100.0
diff --git a/Workflow/state/validation_rules.py b/Workflow/state/validation_rules.py
index 79501c4..87b9c8d 100644
--- a/Workflow/state/validation_rules.py
+++ b/Workflow/state/validation_rules.py
@@ -43,13 +43,13 @@ def validate_loan_amount(loan_type: str, amount: float) -> Dict[str, Any]:
     if not rules:
         return {"is_valid": False, "message": f"Unknown loan type: {loan_type}"}
     
-    if amount < rules["min_amount"]:
+    if amount <= rules["min_amount"]:
         return {
             "is_valid": False, 
             "message": f"Minimum amount for {loan_type} loan is ${rules['min_amount']:,}"
         }
     
-    if amount > rules["max_amount"]:
+    if amount >= rules["max_amount"]:
         return {
             "is_valid": False,
             "message": f"Maximum amount for {loan_type} loan is ${rules['max_amount']:,}"
DEFECT_PATCH_EOF
diff --git a/Service/otp_service.py b/Service/otp_service.py
index cf8ca48..680f790 100644
--- a/Service/otp_service.py
+++ b/Service/otp_service.py
@@ -130,7 +130,7 @@ class OTPService:
                 return False
             
             # Check if max attempts exceeded
-            if otp_data['attempts'] >= self.max_attempts:
+            if otp_data['attempts'] > self.max_attempts:
                 # Lock OTP
                 otp_data['locked_until'] = (datetime.utcnow() + timedelta(minutes=self.lockout_minutes)).isoformat()
                 cache_key = f"otp:{purpose}:{email}"
diff --git a/Workflow/parameter_schema.py b/Workflow/parameter_schema.py
index 094796b..f1bb1cc 100644
--- a/Workflow/parameter_schema.py
+++ b/Workflow/parameter_schema.py
@@ -398,7 +398,7 @@ def get_form_for_missing_fields(missing_fields: List[str]) -> Optional[Dict]:
         # Form is viable if:
         # 1. At least 50% overlap with missing fields
         # 2. At least 2 fields overlap
-        if overlap >= 2 and overlap_percentage >= 0.5:
+        if overlap > 2 and overlap_percentage >= 0.5:
             score = overlap_percentage + (overlap * 0.1)  # Bonus for more overlapping fields
             if score > best_score:
                 best_score = score
diff --git a/Workflow/state/parameter_schema.py b/Workflow/state/parameter_schema.py
index 6b11a4b..436542a 100644
--- a/Workflow/state/parameter_schema.py
+++ b/Workflow/state/parameter_schema.py
@@ -90,7 +90,7 @@ def calculate_completion_percentage(loan_type: str, collected_parameters: Dict[s
     for category, fields in required_params.items():
         category_data = collected_parameters.get(category, {})
         for field in fields:
-            if field in category_data and category_data[field] is not None:
+            if field in category_data and category_data[field]:
                 collected_count += 1
     
     return (collected_count / total_required) * 100.0
diff --git a/Workflow/state/validation_rules.py b/Workflow/state/validation_rules.py
index 79501c4..87b9c8d 100644
--- a/Workflow/state/validation_rules.py
+++ b/Workflow/state/validation_rules.py
@@ -43,13 +43,13 @@ def validate_loan_amount(loan_type: str, amount: float) -> Dict[str, Any]:
     if not rules:
         return {"is_valid": False, "message": f"Unknown loan type: {loan_type}"}
     
-    if amount < rules["min_amount"]:
+    if amount <= rules["min_amount"]:
         return {
             "is_valid": False, 
             "message": f"Minimum amount for {loan_type} loan is ${rules['min_amount']:,}"
         }
     
-    if amount > rules["max_amount"]:
+    if amount >= rules["max_amount"]:
         return {
             "is_valid": False,
             "message": f"Maximum amount for {loan_type} loan is ${rules['max_amount']:,}"
DEFECT_PATCH_EOF
