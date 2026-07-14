# syntax=docker/dockerfile:1
# Planted-defect task image. The suite is fully mocked and offline; no secrets.
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset to the clean base, then plant the defects into the working tree.
RUN git reset --hard 04b8abc5515c22bdb7a2da32bf2719c8ac702174 && git clean -fdq

RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/loangen-agent/agent/documents/credit_pdf/bureau_router.py b/loangen-agent/agent/documents/credit_pdf/bureau_router.py
index 010dc4e..c800ed5 100644
--- a/loangen-agent/agent/documents/credit_pdf/bureau_router.py
+++ b/loangen-agent/agent/documents/credit_pdf/bureau_router.py
@@ -61,7 +61,7 @@ def _assign_tradelines(
     for tl in tradelines:
         tags = set(tl.reported_bureaus or [])
         if tags:
-            if bureau in tags:
+            if bureau not in tags:
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
index 1ae0715..33c1d1b 100644
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
@@ -336,7 +336,7 @@ def extract_hud_fields(text: str) -> Dict[str, Any]:
     for key, patterns in mappings:
         val = _find_labeled_amount(text, patterns)
         if val is not None:
-            if key == "hud_loan_amount" and val < _MIN_HUD_LOAN_AMOUNT:
+            if key == "hud_loan_amount" and val > _MIN_HUD_LOAN_AMOUNT:
                 continue
             facts[key] = val
     if "hud_loan_amount" in facts:
diff --git a/loangen-agent/agent/integrations/cartesia/phone.py b/loangen-agent/agent/integrations/cartesia/phone.py
index 4064bb4..15e5586 100644
--- a/loangen-agent/agent/integrations/cartesia/phone.py
+++ b/loangen-agent/agent/integrations/cartesia/phone.py
@@ -16,7 +16,7 @@ from phonenumbers import NumberParseException, PhoneNumberFormat
 _NON_DIGIT_RE = re.compile(r"[^\d+]+")
 _FALLBACK_REGION = "US"
 # Regions tried when no + country code is provided (default region first).
-_CRM_FALLBACK_REGIONS = ("US", "CA", "IN", "GB", "AU", "MX", "DE", "FR")
+_CRM_FALLBACK_REGIONS = ("US", "CA", "GB", "AU", "MX", "DE", "FR")
 
 
 def _format_parsed_number(parsed: phonenumbers.PhoneNumber, *, require_valid: bool) -> Optional[str]:
diff --git a/loangen-agent/agent/services/cre_qualification/facts.py b/loangen-agent/agent/services/cre_qualification/facts.py
index 7738b22..7af8689 100644
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
diff --git a/loangen-agent/agent/services/smbcontacts/loan_types.py b/loangen-agent/agent/services/smbcontacts/loan_types.py
index 580cae7..19a4301 100644
--- a/loangen-agent/agent/services/smbcontacts/loan_types.py
+++ b/loangen-agent/agent/services/smbcontacts/loan_types.py
@@ -109,7 +109,7 @@ def resolve_loan_type(raw: str) -> Optional[str]:
         return _EXTRA_ALIASES[normalized]
     for choice in LOAN_TYPE_CHOICES:
         if _normalize_key(choice["label"]) == normalized:
-            return choice["id"]
+            return choice["label"]
         if _normalize_key(choice["id"]) == normalized:
             return choice["id"]
     return None
diff --git a/loangen-agent/agent/services/smbinvites/schemas.py b/loangen-agent/agent/services/smbinvites/schemas.py
index 6213f16..078b65f 100644
--- a/loangen-agent/agent/services/smbinvites/schemas.py
+++ b/loangen-agent/agent/services/smbinvites/schemas.py
@@ -19,7 +19,7 @@ class CreateInviteRequest(BaseModel):
         if v is None or not str(v).strip():
             return None
         resolved = resolve_loan_type(str(v))
-        if not resolved:
+        if resolved:
             raise ValueError(
                 "loan_type_id is not recognized. Choose a loan type from the CRM list."
             )
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
