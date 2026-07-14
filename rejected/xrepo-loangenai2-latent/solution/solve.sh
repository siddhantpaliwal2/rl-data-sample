#!/bin/sh
# Oracle solution -- reverse-applies the planted defect patch, restoring the
# correct boundary logic in the loan-offer generation math: the top credit
# tier, the zero-interest payment guard, the thousand-multiplier parse check,
# the invalid-amount default guard, and the top income scoring band.
set -eu
cd /app
git apply -R --check - <<'DEFECT_PATCH_EOF' && git apply -R - <<'DEFECT_PATCH_EOF'
diff --git a/Workflow/v1/agents/loan_offer_generator_v1.py b/Workflow/v1/agents/loan_offer_generator_v1.py
--- a/Workflow/v1/agents/loan_offer_generator_v1.py
+++ b/Workflow/v1/agents/loan_offer_generator_v1.py
@@ -244,7 +244,7 @@
         return True
     
     # If original text has 'k' or 'thousand' but parsed value doesn't reflect it
-    if any(indicator in original_lower for indicator in ['k', 'thousand']) and parsed_value < 1000:
+    if any(indicator in original_lower for indicator in ['k', 'thousand']) and parsed_value <= 1000:
         return True
     
     return False
@@ -284,7 +284,7 @@
         annual_income = clean_number(raw_income)
         
         # Apply defaults if parsing failed
-        if loan_amount <= 0:
+        if loan_amount < 0:
             loan_amount = 10000.0
         if annual_income <= 0:
             annual_income = 50000.0
@@ -668,7 +668,7 @@
 
 def get_personal_loan_base_rates(credit_score: int) -> Dict[str, float]:
     """Get base interest rate ranges for personal loans based on credit score"""
-    if credit_score >= 750:
+    if credit_score > 750:
         return {"min": 6.99, "max": 12.99}
     elif credit_score >= 700:
         return {"min": 8.99, "max": 16.99}
@@ -715,7 +715,7 @@
     
     # Adjust based on income
     annual_income = float(collected_parameters.get("annual_income", 50000))
-    if annual_income >= 100000:
+    if annual_income > 100000:
         base_score += 30
     elif annual_income >= 75000:
         base_score += 15
@@ -737,7 +737,7 @@
 
 def calculate_monthly_payment(principal: float, annual_rate: float, months: int) -> float:
     """Calculate monthly payment using standard loan formula"""
-    if annual_rate == 0:
+    if annual_rate < 0:
         return principal / months
     
     monthly_rate = annual_rate / 100 / 12
DEFECT_PATCH_EOF
diff --git a/Workflow/v1/agents/loan_offer_generator_v1.py b/Workflow/v1/agents/loan_offer_generator_v1.py
--- a/Workflow/v1/agents/loan_offer_generator_v1.py
+++ b/Workflow/v1/agents/loan_offer_generator_v1.py
@@ -244,7 +244,7 @@
         return True
     
     # If original text has 'k' or 'thousand' but parsed value doesn't reflect it
-    if any(indicator in original_lower for indicator in ['k', 'thousand']) and parsed_value < 1000:
+    if any(indicator in original_lower for indicator in ['k', 'thousand']) and parsed_value <= 1000:
         return True
     
     return False
@@ -284,7 +284,7 @@
         annual_income = clean_number(raw_income)
         
         # Apply defaults if parsing failed
-        if loan_amount <= 0:
+        if loan_amount < 0:
             loan_amount = 10000.0
         if annual_income <= 0:
             annual_income = 50000.0
@@ -668,7 +668,7 @@
 
 def get_personal_loan_base_rates(credit_score: int) -> Dict[str, float]:
     """Get base interest rate ranges for personal loans based on credit score"""
-    if credit_score >= 750:
+    if credit_score > 750:
         return {"min": 6.99, "max": 12.99}
     elif credit_score >= 700:
         return {"min": 8.99, "max": 16.99}
@@ -715,7 +715,7 @@
     
     # Adjust based on income
     annual_income = float(collected_parameters.get("annual_income", 50000))
-    if annual_income >= 100000:
+    if annual_income > 100000:
         base_score += 30
     elif annual_income >= 75000:
         base_score += 15
@@ -737,7 +737,7 @@
 
 def calculate_monthly_payment(principal: float, annual_rate: float, months: int) -> float:
     """Calculate monthly payment using standard loan formula"""
-    if annual_rate == 0:
+    if annual_rate < 0:
         return principal / months
     
     monthly_rate = annual_rate / 100 / 12
DEFECT_PATCH_EOF
