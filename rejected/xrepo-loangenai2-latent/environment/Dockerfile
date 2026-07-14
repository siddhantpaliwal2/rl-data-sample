# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect (LATENT-BUG) task image for the loan-genai-backend loan-offer
# generation math. The five defects are single-token boundary slips in pure,
# deterministic helpers (credit-tier rate lookup, zero-interest payment guard,
# written-magnitude parse-failure detection, invalid-amount default guard, and
# income-band credit scoring). Every existing behavior still holds with them
# applied; only untested exact-edge inputs are wrong. This task reuses the same
# repo image as the sibling loan-amount/OTP task but plants a DISJOINT set of
# defects in a different module. On the platform, replace the FROM with the
# approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenai-xxxxx:v1@sha256:...
FROM loangenai-repo:v1

USER root
WORKDIR /app

# Reset any prior working-tree state, then plant the subtle boundary defects.
RUN git checkout -- . 2>/dev/null || true

RUN cat > /tmp/defects.patch <<'PATCH_EOF'
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
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Collapse history: planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app
