# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image for the CRE qualification scoring math.
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
# untested exact-threshold / even-cardinality inputs are wrong.
RUN git reset --hard 04b8abc5515c22bdb7a2da32bf2719c8ac702174 && git clean -fdq

RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/loangen-agent/agent/services/cre_qualification/facts.py b/loangen-agent/agent/services/cre_qualification/facts.py
index 7738b22..3687ed7 100644
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
 
@@ -156,7 +156,7 @@ def resolve_document_fico(facts: Dict[str, Any]) -> Optional[int]:
     if primary is not None:
         try:
             score = int(float(primary))
-            if 300 <= score <= 850:
+            if 300 <= score < 850:
                 return score
         except (TypeError, ValueError):
             pass
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
@@ -334,7 +334,7 @@ def resolve_construction_budget(facts: Dict[str, Any]) -> Optional[float]:
 
     if explicit is not None:
         # Reject CTC-only totals mistakenly stored as total budget when spent exceeds it.
-        if spent is not None and spent > explicit and remaining is not None:
+        if spent is not None and spent >= explicit and remaining is not None:
             return spent + remaining
         if spent is not None and remaining_appraisal is not None and spent > explicit:
             return spent + remaining_appraisal
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
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Collapse history: planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
