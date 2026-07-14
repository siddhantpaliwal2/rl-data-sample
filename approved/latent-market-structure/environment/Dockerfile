# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image for the CRE market / deal-structure / lender-match math.
# The qualification suite is deterministic, fully offline, and needs no secrets
# beyond the JWT_SECRET_KEY already baked into loangenus-repo:v1.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset to the clean base HEAD, then plant the subtle boundary defects into the
# working tree. Every existing test still passes with these applied; only
# untested exact-threshold / empty / zero-denominator inputs are wrong.
RUN git reset --hard 04b8abc5515c22bdb7a2da32bf2719c8ac702174 && git clean -fdq

RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/loangen-agent/agent/services/cre_qualification/lender_match.py b/loangen-agent/agent/services/cre_qualification/lender_match.py
index 8204048..d3cdbe5 100644
--- a/loangen-agent/agent/services/cre_qualification/lender_match.py
+++ b/loangen-agent/agent/services/cre_qualification/lender_match.py
@@ -152,7 +152,7 @@ def compute_lender_match_score(
     elif business_state:
         components["geography"] = 70.0
 
-    if product.min_amount <= loan_amount <= product.max_amount:
+    if product.min_amount <= loan_amount < product.max_amount:
         components["loan_size"] = 100.0
     else:
         components["loan_size"] = 20.0
diff --git a/loangen-agent/agent/services/cre_qualification/market.py b/loangen-agent/agent/services/cre_qualification/market.py
index 3c467c4..a49194c 100644
--- a/loangen-agent/agent/services/cre_qualification/market.py
+++ b/loangen-agent/agent/services/cre_qualification/market.py
@@ -41,7 +41,7 @@ MARKET_SCORE_WEIGHTS = {
 def resolve_state(business: Dict[str, Any], owner: Dict[str, Any]) -> str:
     for src in (business, owner):
         st = str(src.get("state") or src.get("State") or "").strip().upper()
-        if len(st) == 2:
+        if len(st) >= 2:
             return st
     return ""
 
diff --git a/loangen-agent/agent/services/cre_qualification/structure.py b/loangen-agent/agent/services/cre_qualification/structure.py
index f6d7c09..c2faa55 100644
--- a/loangen-agent/agent/services/cre_qualification/structure.py
+++ b/loangen-agent/agent/services/cre_qualification/structure.py
@@ -14,7 +14,7 @@ _EXIT_KEYWORDS = ("sale", "refinance", "stabilized", "permanent", "hold")
 
 def _purpose_score(loan_purpose: str, loan_type: str) -> Optional[float]:
     text = f"{loan_purpose} {loan_type}".lower()
-    if not text.strip():
+    if not text:
         return None
     if any(k in text for k in _PERMANENT_KEYWORDS):
         return 85.0
@@ -40,7 +40,7 @@ def compute_interest_coverage(
     interest_expense: Optional[float],
     annual_debt_service: Optional[float],
 ) -> Optional[float]:
-    if noi is None or noi <= 0:
+    if noi is None or noi < 0:
         return None
     if interest_expense and interest_expense > 0:
         return noi / interest_expense
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Collapse history: planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
