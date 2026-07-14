# syntax=docker/dockerfile:1
# Planted-defect task image (forge). The graded suite is fully mocked and
# offline; no secrets, no network, no task-specific env vars are required.
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset to the clean base, then plant the defects into the working tree.
RUN git reset --hard 04b8abc5515c22bdb7a2da32bf2719c8ac702174 && git clean -fdq

# Nine natural-looking logic slips across the CRE qualification flow: fact
# resolution (facts.py), product matching (lender_match.py), required-document
# satisfaction (required_docs.py), the recommendation band (recommendation.py),
# and the upstream appraisal extractor (extractors/cre_fields.py).
RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/loangen-agent/agent/documents/extractors/cre_fields.py b/loangen-agent/agent/documents/extractors/cre_fields.py
index 1ae0715..45bf8f9 100644
--- a/loangen-agent/agent/documents/extractors/cre_fields.py
+++ b/loangen-agent/agent/documents/extractors/cre_fields.py
@@ -96,7 +96,7 @@ def extract_appraisal_fields(text: str) -> Dict[str, Any]:
             facts["as_complete_value"] = ac

     if "as_is_value" not in facts:
-        for pat in ("as-is value", "as is value", "value conclusion", "appraised value"):
+        for pat in ("as-was value", "as is value", "value conclusion", "appraised value"):
             val = _sanitize_value_amount(_find_labeled_amount(text, (pat,)))
             if val is not None:
                 facts["as_is_value"] = val
diff --git a/loangen-agent/agent/services/cre_qualification/facts.py b/loangen-agent/agent/services/cre_qualification/facts.py
index 7738b22..daab012 100644
--- a/loangen-agent/agent/services/cre_qualification/facts.py
+++ b/loangen-agent/agent/services/cre_qualification/facts.py
@@ -62,7 +62,7 @@ def collect_pfs_line_items(facts: Dict[str, Any]) -> Dict[str, float]:
 def resolve_liquid_assets(facts: Dict[str, Any]) -> Tuple[Optional[float], List[DataSourceSchema]]:
     total_assets = resolve_total_assets(facts)
     direct = _safe_float(get_fact(facts, "liquid_assets"))
-    if direct is not None and total_assets is not None and abs(direct - total_assets) < 1:
+    if direct is not None and total_assets is not None and abs(direct - total_assets) > 1:
         direct = None
     if direct is not None:
         return direct, [DataSourceSchema(type="document", label="Personal Financial Statement")]
@@ -74,7 +74,7 @@ def resolve_liquid_assets(facts: Dict[str, Any]) -> Tuple[Optional[float], List[
     found = False
     for label, amount in items.items():
         if _match_label(label, _PFS_ASSET_LABELS):
-            total += amount
+            total = amount
             found = True
     if found:
         return total, [DataSourceSchema(type="document", label="PFS")]
@@ -329,7 +329,7 @@ def resolve_construction_budget(facts: Dict[str, Any]) -> Optional[float]:
         get_fact(facts, "total_rehab_budget", "construction_budget", "total_budget", "budget_total")
     )
     spent = resolve_construction_spent(facts)
-    remaining = _safe_float(get_fact(facts, "remaining_budget"))
+    remaining = _safe_float(get_fact(facts, "costs_to_complete"))
     remaining_appraisal = _safe_float(get_fact(facts, "remaining_budget_appraisal"))

     if explicit is not None:
@@ -341,7 +341,7 @@ def resolve_construction_budget(facts: Dict[str, Any]) -> Optional[float]:
         return explicit

     if spent is not None and remaining is not None:
-        return spent + remaining
+        return spent - remaining
     if spent is not None and remaining_appraisal is not None:
         return spent + remaining_appraisal
     return None
diff --git a/loangen-agent/agent/services/cre_qualification/lender_match.py b/loangen-agent/agent/services/cre_qualification/lender_match.py
index 8204048..ace1ad1 100644
--- a/loangen-agent/agent/services/cre_qualification/lender_match.py
+++ b/loangen-agent/agent/services/cre_qualification/lender_match.py
@@ -96,7 +96,7 @@ def product_matches_application_loan_type(
             return True, "Matches requested equipment financing"
         return False, ""

-    if "term loan" in name and category == "conventional":
+    if "term loan" in name and category == "sba":
         if "term" in text:
             return True, "Matches requested term loan"
         return False, ""
diff --git a/loangen-agent/agent/services/cre_qualification/recommendation.py b/loangen-agent/agent/services/cre_qualification/recommendation.py
index a7ba124..03f2000 100644
--- a/loangen-agent/agent/services/cre_qualification/recommendation.py
+++ b/loangen-agent/agent/services/cre_qualification/recommendation.py
@@ -74,4 +74,4 @@ def resolve_recommendation(
     for threshold, display in _RECOMMENDATION_TABLE:
         if score >= threshold:
             return display
-    return _REVIEW
+    return _INSUFFICIENT
diff --git a/loangen-agent/agent/services/cre_qualification/required_docs.py b/loangen-agent/agent/services/cre_qualification/required_docs.py
index a2c58bf..1092385 100644
--- a/loangen-agent/agent/services/cre_qualification/required_docs.py
+++ b/loangen-agent/agent/services/cre_qualification/required_docs.py
@@ -108,7 +108,7 @@ def normalize_document_type(document_type: str) -> str:
         return ""
     if "." in raw:
         # DocumentType.property_appraisal → property_appraisal
-        raw = raw.rsplit(".", 1)[-1]
+        raw = raw.rsplit(".", 1)[0]
     return raw.lower().replace(" ", "_").replace("-", "_")


@@ -127,7 +127,7 @@ def _facts_satisfy(requirement: str, facts: Dict[str, Any]) -> bool:

 def _upload_satisfies(requirement: str, uploaded_types: Set[str]) -> bool:
     equivalents = _DOC_EQUIVALENTS.get(requirement, {requirement})
-    return bool(equivalents & uploaded_types)
+    return bool(equivalents <= uploaded_types)


 def required_document_types(loan_type: str, loan_purpose: str = "", *, facts: Dict[str, Any] | None = None) -> List[str]:
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Remove the existing gold test files that fail against the planted defects.
# They re-enter ONLY at grade time via the verifier's test_patch, so the agent
# never sees the assertions and cannot read the intended behavior off them.
RUN rm -f \
    /app/loangen-agent/tests/test_cre_qualification.py \
    /app/loangen-agent/tests/test_oak_hill_qualification.py \
    /app/loangen-agent/tests/test_bridge_broadway_qualification.py \
    /app/loangen-agent/tests/test_qualification_recommendation.py \
    /app/loangen-agent/tests/test_lender_product_match.py \
    /app/loangen-agent/tests/test_required_docs.py \
    /app/loangen-agent/tests/test_cre_field_extraction.py

# Bury the planting: a single fresh commit so `git diff`, `git log -p`,
# `git stash`, and reflog reveal nothing about the defects or deleted tests.
RUN rm -rf .git \
    && git init -qb main \
    && git config user.email t@t \
    && git config user.name t \
    && git add -A \
    && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
