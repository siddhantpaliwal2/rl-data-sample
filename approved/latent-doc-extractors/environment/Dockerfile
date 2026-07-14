# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image for CRE document field extraction.
# The extraction suite is deterministic, fully offline, and needs no secrets
# beyond the JWT_SECRET_KEY already baked into loangenus-repo:v1.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset to the clean base HEAD, then plant the subtle boundary defects into the
# working tree. Every existing test still passes with these applied; only
# untested exact-threshold / minimum-cardinality inputs are wrong.
RUN git reset --hard 04b8abc5515c22bdb7a2da32bf2719c8ac702174 && git clean -fdq

RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/loangen-agent/agent/documents/extractors/cre_fields.py b/loangen-agent/agent/documents/extractors/cre_fields.py
index 1ae0715..1d9899d 100644
--- a/loangen-agent/agent/documents/extractors/cre_fields.py
+++ b/loangen-agent/agent/documents/extractors/cre_fields.py
@@ -51,7 +51,7 @@ def _sum_rent_amounts(text: str) -> Optional[float]:
             if amt is not None and 100 < amt < 5_000_000:
                 total += amt
                 count += 1
-    return total if count >= 2 else None
+    return total if count >= 3 else None
 
 
 def _parse_money(s: str) -> Optional[float]:
@@ -68,7 +68,7 @@ def _sanitize_value_amount(val: Optional[float], *, min_amount: float = 100_000)
         f = float(val)
     except (TypeError, ValueError):
         return None
-    return f if f >= min_amount else None
+    return f if f > min_amount else None
 
 
 def extract_appraisal_fields(text: str) -> Dict[str, Any]:
@@ -336,7 +336,7 @@ def extract_hud_fields(text: str) -> Dict[str, Any]:
     for key, patterns in mappings:
         val = _find_labeled_amount(text, patterns)
         if val is not None:
-            if key == "hud_loan_amount" and val < _MIN_HUD_LOAN_AMOUNT:
+            if key == "hud_loan_amount" and val <= _MIN_HUD_LOAN_AMOUNT:
                 continue
             facts[key] = val
     if "hud_loan_amount" in facts:
@@ -774,7 +774,7 @@ def extract_credit_report_fields(text: str) -> Dict[str, Any]:
         m = re.search(pat, text, re.IGNORECASE)
         if m:
             score = int(m.group(1))
-            if 300 <= score <= 850:
+            if 300 <= score < 850:
                 bureau_scores[bureau] = score
 
     if not bureau_scores:
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Collapse history: planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
