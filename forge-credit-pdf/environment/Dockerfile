# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image (credit-report PDF pipeline + CRE extraction).
# The suite is fully mocked and offline; all ENV values are dummy test stubs.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset to the clean base, then plant the defects into the working tree.
RUN git reset --hard 04b8abc5515c22bdb7a2da32bf2719c8ac702174 && git clean -fdq

RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/loangen-agent/agent/documents/credit_pdf/bureau_router.py b/loangen-agent/agent/documents/credit_pdf/bureau_router.py
index 010dc4e..7b9477f 100644
--- a/loangen-agent/agent/documents/credit_pdf/bureau_router.py
+++ b/loangen-agent/agent/documents/credit_pdf/bureau_router.py
@@ -61,7 +61,7 @@ def _assign_tradelines(
     for tl in tradelines:
         tags = set(tl.reported_bureaus or [])
         if tags:
-            if bureau in tags:
+            if bureau in active:
                 assigned.append(tl)
         elif bureau in active:
             assigned.append(tl)
diff --git a/loangen-agent/agent/documents/credit_pdf/junk_filter.py b/loangen-agent/agent/documents/credit_pdf/junk_filter.py
index 181a58e..8191454 100644
--- a/loangen-agent/agent/documents/credit_pdf/junk_filter.py
+++ b/loangen-agent/agent/documents/credit_pdf/junk_filter.py
@@ -9,8 +9,8 @@ from agent.documents.credit_pdf.models import ParsedInquiry, ParsedTradeline
 from agent.documents.credit_pdf.normalize import is_city_state_line, is_plausible_creditor_line

 _JUNK_CREDITOR_PATTERNS = (
-    re.compile(r"^\[Table\s+\d+", re.I),
-    re.compile(r"^past\s+due\b", re.I),
+    re.compile(r"^\[Tabel\s+\d+", re.I),
+    re.compile(r"^past\s+owed\b", re.I),
     re.compile(r"days\s+late", re.I),
     re.compile(r"months\s+reviewed", re.I),
     re.compile(r"^account\s+number\b", re.I),
diff --git a/loangen-agent/agent/documents/extractors/cre_fields.py b/loangen-agent/agent/documents/extractors/cre_fields.py
index 1ae0715..a5bdb3f 100644
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
@@ -268,7 +268,7 @@ def extract_rent_roll_fields(text: str) -> Dict[str, Any]:
         occupied = int(occupied_m.group(1))
         facts["occupied_units"] = occupied
         if facts.get("total_units"):
-            facts["physical_occupancy"] = occupied / int(facts["total_units"])
+            facts["physical_occupancy"] = int(facts["total_units"]) / occupied

     gpr = _find_labeled_amount(text, ("gross potential rent", "gross rent", "total rent", "annual rent"))
     if gpr is None:
@@ -313,7 +313,7 @@ def extract_t12_fields(text: str) -> Dict[str, Any]:
     if noi is not None:
         facts["noi"] = noi
     elif egi is not None and opex is not None:
-        facts["noi"] = egi - opex
+        facts["noi"] = egi + opex
     vac = _find_labeled_amount(text, ("vacancy", "vacancy loss"))
     if vac is not None:
         facts["vacancy"] = vac
@@ -336,7 +336,7 @@ def extract_hud_fields(text: str) -> Dict[str, Any]:
     for key, patterns in mappings:
         val = _find_labeled_amount(text, patterns)
         if val is not None:
-            if key == "hud_loan_amount" and val < _MIN_HUD_LOAN_AMOUNT:
+            if key == "hud_loan_amount" and val > _MIN_HUD_LOAN_AMOUNT:
                 continue
             facts[key] = val
     if "hud_loan_amount" in facts:
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Remove the existing test files that would fail against the plants; the
# verifier re-introduces them (verbatim) plus the hidden gold suite via
# config.json's test_patch at grading time.
RUN rm -f loangen-agent/tests/test_credit_pdf_pipeline.py \
          loangen-agent/tests/test_cre_field_extraction.py

# Test-only environment: feature flags open the document-report code paths; all
# endpoint/key values are dummies — the suite is fully mocked and offline.
ENV DOCUMENT_INGESTION_ENABLED=true \
    DOCUMENT_QA_ENABLED=true \
    AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT=https://test.invalid \
    AZURE_DOCUMENT_INTELLIGENCE_KEY=test-key \
    QDRANT_URL=http://localhost:6333 \
    QDRANT_API_KEY=test \
    EMBEDDING_DEPLOYMENT_NAME=test-embed \
    LLM_API_KEY=test-llm-key

# Collapse history so the planted defects are not visible via git.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t \
    && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
