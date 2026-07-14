#!/bin/sh
# Oracle solution -- applies the CRE qualification fix diff at base_commit.
set -eu
cd /app
git apply --check - <<'SOLUTION_PATCH_EOF' && git apply - <<'SOLUTION_PATCH_EOF'
diff --git a/loangen-agent/agent/services/cre_qualification/constants.py b/loangen-agent/agent/services/cre_qualification/constants.py
index 61fcd44..d043ab7 100644
--- a/loangen-agent/agent/services/cre_qualification/constants.py
+++ b/loangen-agent/agent/services/cre_qualification/constants.py
@@ -79,6 +79,11 @@ STRUCTURE_SCORE_WEIGHTS: dict[str, float] = {
     "exit_strategy": 0.10,
 }
 
+# Deal-score recommendation bands (lender hero UI + PDF)
+RECOMMENDATION_STRONG_PROCEED_MIN = 80.0
+RECOMMENDATION_PROCEED_MIN = 60.0
+RECOMMENDATION_MANUAL_UW_MIN = 40.0
+
 # Decision layer thresholds (Word doc §6)
 DECISION_DSCR_MIN = 1.20
 DECISION_LTV_MAX = 0.80
diff --git a/loangen-agent/agent/services/cre_qualification/engine.py b/loangen-agent/agent/services/cre_qualification/engine.py
index b8fb17f..bfc2034 100644
--- a/loangen-agent/agent/services/cre_qualification/engine.py
+++ b/loangen-agent/agent/services/cre_qualification/engine.py
@@ -34,6 +34,7 @@ from agent.services.cre_qualification.lender_match import (
     product_matches_application_loan_type,
 )
 from agent.services.cre_qualification.market import compute_market_intelligence
+from agent.services.cre_qualification.recommendation import resolve_recommendation
 from agent.services.cre_qualification.recommended_terms import compute_recommended_terms
 from agent.services.cre_qualification.required_docs import (
     collect_uploaded_document_types,
@@ -1706,11 +1707,19 @@ def run_qualification_engine(ctx: QualificationContext) -> QualificationAnalysis
         product_fit=product_fit,
     )
 
+    recommendation = resolve_recommendation(
+        deal_score=deal_score,
+        deal_score_available=deal_score is not None,
+    )
+
     overall = OverallQualificationSchema(
         deal_score=deal_score,
         deal_score_available=deal_score is not None,
         confidence_score=confidence,
         decision=decision,
+        recommendation_band=recommendation.band,  # type: ignore[arg-type]
+        recommendation_label=recommendation.label,
+        recommendation_color=recommendation.color,
         decision_rules=decision_rules,
         pd_pct=pd,
         lgd_pct=lgd,
diff --git a/loangen-agent/agent/services/cre_qualification/qualification_report_pdf.py b/loangen-agent/agent/services/cre_qualification/qualification_report_pdf.py
index f830ee8..4747f19 100644
--- a/loangen-agent/agent/services/cre_qualification/qualification_report_pdf.py
+++ b/loangen-agent/agent/services/cre_qualification/qualification_report_pdf.py
@@ -8,6 +8,7 @@ from datetime import datetime
 from typing import Any, List, Optional
 
 from reportlab.lib import colors
+from reportlab.lib.colors import HexColor
 from reportlab.lib.enums import TA_CENTER, TA_LEFT
 from reportlab.lib.pagesizes import letter
 from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
@@ -392,9 +393,8 @@ def _build_cover(
     elements.append(meta_table)
     elements.append(Spacer(1, 16))
 
-    decision = analysis.overall.decision
-    dec_color = DECISION_COLORS.get(decision, BRAND_SLATE)
-    dec_label = DECISION_LABELS.get(decision, decision.replace("_", " ").title())
+    dec_label = analysis.overall.recommendation_label
+    dec_color = HexColor(analysis.overall.recommendation_color)
 
     dec_table = Table(
         [[Paragraph(dec_label, styles["decision"])]],
diff --git a/loangen-agent/agent/services/cre_qualification/recommendation.py b/loangen-agent/agent/services/cre_qualification/recommendation.py
new file mode 100644
index 0000000..a7ba124
--- /dev/null
+++ b/loangen-agent/agent/services/cre_qualification/recommendation.py
@@ -0,0 +1,77 @@
+"""Deal-score recommendation bands for lender qualification hero (UI + PDF)."""
+
+from __future__ import annotations
+
+from dataclasses import dataclass
+from typing import Optional
+
+from agent.services.cre_qualification.constants import (
+    RECOMMENDATION_MANUAL_UW_MIN,
+    RECOMMENDATION_PROCEED_MIN,
+    RECOMMENDATION_STRONG_PROCEED_MIN,
+)
+
+RecommendationBand = str
+
+
+@dataclass(frozen=True)
+class RecommendationDisplay:
+    band: RecommendationBand
+    label: str
+    color: str
+
+
+_RECOMMENDATION_TABLE: tuple[tuple[float, RecommendationDisplay], ...] = (
+    (
+        RECOMMENDATION_STRONG_PROCEED_MIN,
+        RecommendationDisplay(
+            band="strong_proceed",
+            label="Strong Proceed",
+            color="#047857",
+        ),
+    ),
+    (
+        RECOMMENDATION_PROCEED_MIN,
+        RecommendationDisplay(
+            band="proceed",
+            label="Proceed",
+            color="#34d399",
+        ),
+    ),
+    (
+        RECOMMENDATION_MANUAL_UW_MIN,
+        RecommendationDisplay(
+            band="manual_uw",
+            label="Manual UW",
+            color="#f59e0b",
+        ),
+    ),
+)
+
+_INSUFFICIENT = RecommendationDisplay(
+    band="insufficient_data",
+    label="Insufficient Data",
+    color="#64748b",
+)
+
+_REVIEW = RecommendationDisplay(
+    band="review",
+    label="Review Required",
+    color="#eab308",
+)
+
+
+def resolve_recommendation(
+    *,
+    deal_score: Optional[float],
+    deal_score_available: bool,
+) -> RecommendationDisplay:
+    """Map deal score to underwriting recommendation display (score bands only)."""
+    if not deal_score_available or deal_score is None:
+        return _INSUFFICIENT
+
+    score = float(deal_score)
+    for threshold, display in _RECOMMENDATION_TABLE:
+        if score >= threshold:
+            return display
+    return _REVIEW
diff --git a/loangen-agent/agent/services/cre_qualification/schemas.py b/loangen-agent/agent/services/cre_qualification/schemas.py
index 00281bf..9c77192 100644
--- a/loangen-agent/agent/services/cre_qualification/schemas.py
+++ b/loangen-agent/agent/services/cre_qualification/schemas.py
@@ -4,7 +4,9 @@ from __future__ import annotations
 
 from typing import Any, List, Literal, Optional
 
-from pydantic import BaseModel, Field
+from pydantic import BaseModel, Field, model_validator
+
+from agent.services.cre_qualification.recommendation import resolve_recommendation
 
 VariableStatus = Literal["computed", "missing_data", "not_applicable", "conflict"]
 HeadStatus = Literal["computed", "partial", "not_applicable", "insufficient_data"]
@@ -15,6 +17,13 @@ DecisionAction = Literal[
     "insufficient_data",
     "manual_underwriting",
 ]
+RecommendationBand = Literal[
+    "strong_proceed",
+    "proceed",
+    "manual_uw",
+    "review",
+    "insufficient_data",
+]
 
 
 class DataSourceSchema(BaseModel):
@@ -100,11 +109,26 @@ class OverallQualificationSchema(BaseModel):
     deal_score_available: bool = False
     confidence_score: Optional[float] = None
     decision: DecisionAction
+    recommendation_band: RecommendationBand = "insufficient_data"
+    recommendation_label: str = "Insufficient Data"
+    recommendation_color: str = "#64748b"
     decision_rules: List[DecisionRuleSchema] = Field(default_factory=list)
     pd_pct: Optional[float] = None
     lgd_pct: Optional[float] = None
     summary_message: Optional[str] = None
 
+    @model_validator(mode="after")
+    def sync_recommendation_from_deal_score(self) -> "OverallQualificationSchema":
+        """Keep hero/PDF bands aligned with deal score (incl. cached snapshots)."""
+        rec = resolve_recommendation(
+            deal_score=self.deal_score,
+            deal_score_available=self.deal_score_available,
+        )
+        self.recommendation_band = rec.band  # type: ignore[assignment]
+        self.recommendation_label = rec.label
+        self.recommendation_color = rec.color
+        return self
+
 
 class QualificationAnalysisResponse(BaseModel):
     application_id: str
SOLUTION_PATCH_EOF
diff --git a/loangen-agent/agent/services/cre_qualification/constants.py b/loangen-agent/agent/services/cre_qualification/constants.py
index 61fcd44..d043ab7 100644
--- a/loangen-agent/agent/services/cre_qualification/constants.py
+++ b/loangen-agent/agent/services/cre_qualification/constants.py
@@ -79,6 +79,11 @@ STRUCTURE_SCORE_WEIGHTS: dict[str, float] = {
     "exit_strategy": 0.10,
 }
 
+# Deal-score recommendation bands (lender hero UI + PDF)
+RECOMMENDATION_STRONG_PROCEED_MIN = 80.0
+RECOMMENDATION_PROCEED_MIN = 60.0
+RECOMMENDATION_MANUAL_UW_MIN = 40.0
+
 # Decision layer thresholds (Word doc §6)
 DECISION_DSCR_MIN = 1.20
 DECISION_LTV_MAX = 0.80
diff --git a/loangen-agent/agent/services/cre_qualification/engine.py b/loangen-agent/agent/services/cre_qualification/engine.py
index b8fb17f..bfc2034 100644
--- a/loangen-agent/agent/services/cre_qualification/engine.py
+++ b/loangen-agent/agent/services/cre_qualification/engine.py
@@ -34,6 +34,7 @@ from agent.services.cre_qualification.lender_match import (
     product_matches_application_loan_type,
 )
 from agent.services.cre_qualification.market import compute_market_intelligence
+from agent.services.cre_qualification.recommendation import resolve_recommendation
 from agent.services.cre_qualification.recommended_terms import compute_recommended_terms
 from agent.services.cre_qualification.required_docs import (
     collect_uploaded_document_types,
@@ -1706,11 +1707,19 @@ def run_qualification_engine(ctx: QualificationContext) -> QualificationAnalysis
         product_fit=product_fit,
     )
 
+    recommendation = resolve_recommendation(
+        deal_score=deal_score,
+        deal_score_available=deal_score is not None,
+    )
+
     overall = OverallQualificationSchema(
         deal_score=deal_score,
         deal_score_available=deal_score is not None,
         confidence_score=confidence,
         decision=decision,
+        recommendation_band=recommendation.band,  # type: ignore[arg-type]
+        recommendation_label=recommendation.label,
+        recommendation_color=recommendation.color,
         decision_rules=decision_rules,
         pd_pct=pd,
         lgd_pct=lgd,
diff --git a/loangen-agent/agent/services/cre_qualification/qualification_report_pdf.py b/loangen-agent/agent/services/cre_qualification/qualification_report_pdf.py
index f830ee8..4747f19 100644
--- a/loangen-agent/agent/services/cre_qualification/qualification_report_pdf.py
+++ b/loangen-agent/agent/services/cre_qualification/qualification_report_pdf.py
@@ -8,6 +8,7 @@ from datetime import datetime
 from typing import Any, List, Optional
 
 from reportlab.lib import colors
+from reportlab.lib.colors import HexColor
 from reportlab.lib.enums import TA_CENTER, TA_LEFT
 from reportlab.lib.pagesizes import letter
 from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
@@ -392,9 +393,8 @@ def _build_cover(
     elements.append(meta_table)
     elements.append(Spacer(1, 16))
 
-    decision = analysis.overall.decision
-    dec_color = DECISION_COLORS.get(decision, BRAND_SLATE)
-    dec_label = DECISION_LABELS.get(decision, decision.replace("_", " ").title())
+    dec_label = analysis.overall.recommendation_label
+    dec_color = HexColor(analysis.overall.recommendation_color)
 
     dec_table = Table(
         [[Paragraph(dec_label, styles["decision"])]],
diff --git a/loangen-agent/agent/services/cre_qualification/recommendation.py b/loangen-agent/agent/services/cre_qualification/recommendation.py
new file mode 100644
index 0000000..a7ba124
--- /dev/null
+++ b/loangen-agent/agent/services/cre_qualification/recommendation.py
@@ -0,0 +1,77 @@
+"""Deal-score recommendation bands for lender qualification hero (UI + PDF)."""
+
+from __future__ import annotations
+
+from dataclasses import dataclass
+from typing import Optional
+
+from agent.services.cre_qualification.constants import (
+    RECOMMENDATION_MANUAL_UW_MIN,
+    RECOMMENDATION_PROCEED_MIN,
+    RECOMMENDATION_STRONG_PROCEED_MIN,
+)
+
+RecommendationBand = str
+
+
+@dataclass(frozen=True)
+class RecommendationDisplay:
+    band: RecommendationBand
+    label: str
+    color: str
+
+
+_RECOMMENDATION_TABLE: tuple[tuple[float, RecommendationDisplay], ...] = (
+    (
+        RECOMMENDATION_STRONG_PROCEED_MIN,
+        RecommendationDisplay(
+            band="strong_proceed",
+            label="Strong Proceed",
+            color="#047857",
+        ),
+    ),
+    (
+        RECOMMENDATION_PROCEED_MIN,
+        RecommendationDisplay(
+            band="proceed",
+            label="Proceed",
+            color="#34d399",
+        ),
+    ),
+    (
+        RECOMMENDATION_MANUAL_UW_MIN,
+        RecommendationDisplay(
+            band="manual_uw",
+            label="Manual UW",
+            color="#f59e0b",
+        ),
+    ),
+)
+
+_INSUFFICIENT = RecommendationDisplay(
+    band="insufficient_data",
+    label="Insufficient Data",
+    color="#64748b",
+)
+
+_REVIEW = RecommendationDisplay(
+    band="review",
+    label="Review Required",
+    color="#eab308",
+)
+
+
+def resolve_recommendation(
+    *,
+    deal_score: Optional[float],
+    deal_score_available: bool,
+) -> RecommendationDisplay:
+    """Map deal score to underwriting recommendation display (score bands only)."""
+    if not deal_score_available or deal_score is None:
+        return _INSUFFICIENT
+
+    score = float(deal_score)
+    for threshold, display in _RECOMMENDATION_TABLE:
+        if score >= threshold:
+            return display
+    return _REVIEW
diff --git a/loangen-agent/agent/services/cre_qualification/schemas.py b/loangen-agent/agent/services/cre_qualification/schemas.py
index 00281bf..9c77192 100644
--- a/loangen-agent/agent/services/cre_qualification/schemas.py
+++ b/loangen-agent/agent/services/cre_qualification/schemas.py
@@ -4,7 +4,9 @@ from __future__ import annotations
 
 from typing import Any, List, Literal, Optional
 
-from pydantic import BaseModel, Field
+from pydantic import BaseModel, Field, model_validator
+
+from agent.services.cre_qualification.recommendation import resolve_recommendation
 
 VariableStatus = Literal["computed", "missing_data", "not_applicable", "conflict"]
 HeadStatus = Literal["computed", "partial", "not_applicable", "insufficient_data"]
@@ -15,6 +17,13 @@ DecisionAction = Literal[
     "insufficient_data",
     "manual_underwriting",
 ]
+RecommendationBand = Literal[
+    "strong_proceed",
+    "proceed",
+    "manual_uw",
+    "review",
+    "insufficient_data",
+]
 
 
 class DataSourceSchema(BaseModel):
@@ -100,11 +109,26 @@ class OverallQualificationSchema(BaseModel):
     deal_score_available: bool = False
     confidence_score: Optional[float] = None
     decision: DecisionAction
+    recommendation_band: RecommendationBand = "insufficient_data"
+    recommendation_label: str = "Insufficient Data"
+    recommendation_color: str = "#64748b"
     decision_rules: List[DecisionRuleSchema] = Field(default_factory=list)
     pd_pct: Optional[float] = None
     lgd_pct: Optional[float] = None
     summary_message: Optional[str] = None
 
+    @model_validator(mode="after")
+    def sync_recommendation_from_deal_score(self) -> "OverallQualificationSchema":
+        """Keep hero/PDF bands aligned with deal score (incl. cached snapshots)."""
+        rec = resolve_recommendation(
+            deal_score=self.deal_score,
+            deal_score_available=self.deal_score_available,
+        )
+        self.recommendation_band = rec.band  # type: ignore[assignment]
+        self.recommendation_label = rec.label
+        self.recommendation_color = rec.color
+        return self
+
 
 class QualificationAnalysisResponse(BaseModel):
     application_id: str
SOLUTION_PATCH_EOF
