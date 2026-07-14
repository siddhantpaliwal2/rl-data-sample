#!/bin/sh
# Oracle solution — applies the fix diff at base_commit.
set -eu
cd /app
git apply --check - <<'SOLUTION_PATCH_EOF' && git apply - <<'SOLUTION_PATCH_EOF'
diff --git a/loangen-agent/agent/context_builder.py b/loangen-agent/agent/context_builder.py
index 4178338..c381048 100644
--- a/loangen-agent/agent/context_builder.py
+++ b/loangen-agent/agent/context_builder.py
@@ -25,6 +25,7 @@ from agent.tools.plaid_bank import PlaidBankService
 from agent.tools.quickbooks import QuickBooksService
 from agent.tools.qualification_engine import QualificationEngine
 from agent.prompts.prompt_manager import prompt_manager
+from agent.core.config import settings
 
 logger = logging.getLogger("loangen.context_builder")
 
@@ -33,6 +34,7 @@ PROMPTS_DIR = Path(__file__).parent / "prompts"
 # ── Intent → required data sources mapping ────────────────────────────────────
 # Which data sources must be connected for a complete answer per intent.
 INTENT_DATA_REQUIREMENTS: dict[str, list[str]] = {
+    "qb_financials": ["quickbooks"],
     "qualification": ["credit", "quickbooks"],
     "gap_coaching":  ["credit", "quickbooks", "bank"],
     "cross_sell":    ["bank", "quickbooks"],
@@ -157,7 +159,7 @@ class ContextBuilder:
         # ── 1. Credit data (Array via MongoDB analytics) ───────────────────────
         try:
             from agent.analytics.services.credit_bureau_analytics import CreditBureauAnalyticsService
-            credit_svc = CreditBureauAnalyticsService()
+            credit_svc = CreditBureauAnalyticsService(live=settings.data_mode == "live")
             credit_result = await credit_svc.get_analytics(user_id)
             if credit_result:
                 context["has_credit"] = True
@@ -173,8 +175,8 @@ class ContextBuilder:
         # ── 2. Bank data (Plaid via MongoDB analytics) ─────────────────────────
         try:
             from agent.analytics.services.plaid_analytics import PlaidAnalyticsService
-            bank_svc = PlaidAnalyticsService()
-            bank_result = await bank_svc.get_analytics(user_id)
+            bank_svc = PlaidAnalyticsService(live=settings.data_mode == "live")
+            bank_result = await bank_svc.get_analytics(smb_id=user_id, user_id=user_id)
             if bank_result:
                 context["has_bank"] = True
                 context["bank_data"] = self._map_bank_analytics(bank_result)
@@ -189,7 +191,7 @@ class ContextBuilder:
         # ── 3. QuickBooks data (via MongoDB analytics) ─────────────────────────
         try:
             from agent.analytics.services.quickbooks_analytics import QuickBooksAnalyticsService
-            qb_svc = QuickBooksAnalyticsService()
+            qb_svc = QuickBooksAnalyticsService(live=settings.data_mode == "live")
             qb_result = await qb_svc.get_analytics(user_id)
             if qb_result:
                 context["has_qb"] = True
@@ -330,7 +332,9 @@ class ContextBuilder:
         else:
             return {}
 
-        company = d.get("company_profile") or d.get("company", {}) or {}
+        company = d.get("company_profile") or d.get("company") or {}
+        if hasattr(company, "model_dump"):
+            company = company.model_dump()
         return {
             "company_name":    company.get("company_name") or d.get("company_name"),
             "industry":        company.get("industry"),
@@ -342,7 +346,11 @@ class ContextBuilder:
         }
 
     def _map_qb_financials(self, result: Any) -> dict:
-        """Map QuickBooksAnalyticsService result to financials dict."""
+        """Map QuickBooksAnalyticsService result to financials dict.
+
+        QBAnalyticsResult uses income_statement.total_income (not total_revenue),
+        balance_sheet.cash_and_bank, and top-level revenue, net_income, dscr, etc.
+        """
         if hasattr(result, "model_dump"):
             d = result.model_dump()
         elif isinstance(result, dict):
@@ -354,19 +362,50 @@ class ContextBuilder:
         balance = d.get("balance_sheet") or {}
         ratios = d.get("key_metrics") or {}
 
+        revenue = (
+            income.get("total_income")
+            or income.get("total_revenue")
+            or income.get("revenue")
+            or d.get("revenue", 0)
+        )
+        net_income = income.get("net_income") or d.get("net_income", 0)
+        profit_margin = (
+            income.get("profit_margin_pct")
+            or income.get("profit_margin")
+            or d.get("profit_margin", 0)
+        )
+        current_ratio = (
+            balance.get("current_ratio")
+            or ratios.get("current_ratio")
+            or d.get("current_ratio", 0)
+        )
+        debt_to_equity = (
+            balance.get("debt_to_equity")
+            or ratios.get("debt_to_equity")
+            or d.get("debt_to_equity", 0)
+        )
+        cash_on_hand = (
+            balance.get("cash_and_bank")
+            or balance.get("cash")
+            or balance.get("cash_on_hand")
+            or d.get("cash_on_hand", 0)
+        )
+        dscr = d.get("dscr") or ratios.get("dscr")
+        runway_months = d.get("runway_months") or ratios.get("runway_months")
+
         return {
-            "period":          income.get("period"),
-            "revenue":         income.get("total_revenue") or income.get("revenue", 0),
-            "net_income":      income.get("net_income", 0),
-            "profit_margin":   income.get("profit_margin", 0),
-            "revenue_growth_yoy": income.get("revenue_growth_yoy", 0),
-            "current_ratio":   balance.get("current_ratio") or ratios.get("current_ratio", 0),
-            "debt_to_equity":  balance.get("debt_to_equity") or ratios.get("debt_to_equity", 0),
-            "cash_on_hand":    balance.get("cash") or balance.get("cash_on_hand", 0),
-            "monthly_burn_rate": income.get("monthly_burn_rate", 0),
-            "accounts_receivable": balance.get("accounts_receivable", 0),
-            "dscr":            ratios.get("dscr"),
-            "runway_months":   ratios.get("runway_months"),
+            "period": income.get("period"),
+            "revenue": revenue,
+            "net_income": net_income,
+            "profit_margin": profit_margin,
+            "revenue_growth_yoy": income.get("revenue_growth_yoy") or d.get("revenue_growth_yoy", 0),
+            "current_ratio": current_ratio,
+            "debt_to_equity": debt_to_equity,
+            "cash_on_hand": cash_on_hand,
+            "monthly_burn_rate": income.get("monthly_burn_rate") or d.get("monthly_burn_rate", 0),
+            "accounts_receivable": balance.get("accounts_receivable") or d.get("accounts_receivable", 0),
+            "dscr": dscr,
+            "runway_months": runway_months,
         }
 
     def _describe_available_analysis(self, context: dict, intent: str) -> str:
@@ -420,15 +459,28 @@ class ContextBuilder:
             nsf_count = sum(s.get("nsf_overdraft_count", 0) for s in snapshots)
 
         from datetime import datetime
-        year_established = company.get("year_established", datetime.now().year)
-        years_in_business = datetime.now().year - year_established
+        _now_year = datetime.now().year
+        try:
+            year_established = company.get("year_established")
+            year_established = _now_year if year_established is None else int(year_established)
+        except (TypeError, ValueError):
+            year_established = _now_year
+        years_in_business = _now_year - year_established
 
         annual_revenue = financials.get("revenue", 0)
         net_income = financials.get("net_income", 0)
         total_debt = personal_credit.get("total_debt", 0)
 
+        def _num(v: Any) -> float:
+            if v is None:
+                return 0.0
+            try:
+                return float(v)
+            except (TypeError, ValueError):
+                return 0.0
+
         monthly_debt_service = sum(
-            t.get("monthly_payment", 0)
+            _num(t.get("monthly_payment"))
             for t in personal_credit.get("tradelines", [])
             if t.get("status") != "closed"
         )
diff --git a/loangen-agent/agent/pipeline.py b/loangen-agent/agent/pipeline.py
index 1f99403..b23d64e 100644
--- a/loangen-agent/agent/pipeline.py
+++ b/loangen-agent/agent/pipeline.py
@@ -22,6 +22,44 @@ logger = logging.getLogger("loangen-pipeline")
 
 
 INTENT_PATTERNS = {
+    # ── Personalised data intents ────────────────────────────────────────────
+    "personal_credit": [
+        r"\bmy credit score\b",
+        r"\bmy fico\b",
+        r"\bmy experian\b",
+        r"\bmy equifax\b",
+        r"\bmy transunion\b",
+        r"\bmy credit report\b",
+    ],
+    "bank_cashflow": [
+        r"\bmy cash ?flow\b",
+        r"\bcashflow\b",
+        r"\bbank (statements?|accounts?)\b",
+        r"\boverdraft\b",
+        r"\bnsf\b",
+        r"\bnegative balance\b",
+    ],
+    "qb_financials": [
+        r"\bmy revenue\b",
+        r"\bmy profit\b",
+        r"\bnet income\b",
+        r"\bprofit and loss\b|\bp&l\b",
+        r"\bbalance sheet\b",
+        r"\bquickbooks?\b|\bqb\b",
+        r"\bquickbook\s+(data|analysis|report)\b",
+        r"\b(my\s+)?(quickbooks?|qb)\s+(data|analysis|report)",
+        r"\b(analysis|data|report)s?\s+.*(quickbooks?|qb)",
+        r"\b(quickbooks?|qb)\s+.*(analysis|data|report)",
+        r"\b(as\s+)?per\s+my\s+quickbook",
+        r"\bdscr\b",
+    ],
+    "applications_overview": [
+        r"\bmy (loan )?applications?\b",
+        r"\bapplication status\b",
+        r"\bstatus of my application\b",
+        r"\blist my applications\b",
+    ],
+    # ── Existing intents ─────────────────────────────────────────────────────
     "qualification": [
         r"do i qualify",
         r"can i get",
@@ -213,6 +251,129 @@ class LoanGenPipeline:
                 enrichment = self.context_builder.build_cross_sell_prompt(opportunities)
                 logger.info(f"Enriching with {len(opportunities)} cross-sell opportunities")
                 return enrichment, None
+        # ── Personalised one-shot views (authenticated user only) ─────────────
+        if use_user_id:
+            if intent == "personal_credit":
+                credit = context.get("credit_personal") or {}
+                if credit:
+                    score = credit.get("fico_score")
+                    bureau = credit.get("bureau", "Experian")
+                    util = credit.get("credit_utilization")
+                    total_debt = credit.get("total_debt")
+                    delinq = credit.get("delinquencies")
+                    inquiries = credit.get("inquiries_last_12_months")
+
+                    parts: list[str] = []
+                    if score:
+                        parts.append(f"Personal credit score: {score} (bureau: {bureau}).")
+                    if util is not None:
+                        if total_debt is not None:
+                            parts.append(
+                                f"Revolving utilization is about {util}% with total revolving debt around ${total_debt:,.0f}."
+                            )
+                        else:
+                            parts.append(f"Revolving utilization is about {util}%.")
+                    detail_bits: list[str] = []
+                    if delinq is not None:
+                        detail_bits.append(f"{delinq} past delinquencies")
+                    if inquiries is not None:
+                        detail_bits.append(f"{inquiries} hard inquiries in the last 12 months")
+                    if detail_bits:
+                        parts.append("Risk flags: " + ", ".join(detail_bits) + ".")
+
+                    enrichment = " ".join(parts) if parts else None
+                    if enrichment:
+                        logger.info("Enriching with personal credit context")
+                        return enrichment, None
+
+            elif intent == "bank_cashflow":
+                bank = context.get("bank_data") or {}
+                metrics = bank.get("cash_flow_analysis") or {}
+                cash_flow_score = bank.get("cash_flow_score")
+
+                if metrics or cash_flow_score is not None:
+                    avg_in = metrics.get("average_monthly_income")
+                    avg_out = metrics.get("average_monthly_expenses")
+                    seasonality = metrics.get("seasonality_index")
+                    volatility = metrics.get("income_volatility")
+
+                    parts = []
+                    if avg_in is not None and avg_out is not None:
+                        parts.append(
+                            f"Bank cash-flow summary: average monthly inflows about ${avg_in:,.0f} and outflows about ${avg_out:,.0f}."
+                        )
+                    if cash_flow_score is not None:
+                        parts.append(f"Overall cash-flow score is {cash_flow_score}.")
+                    extras: list[str] = []
+                    if seasonality is not None:
+                        extras.append(f"seasonality index {seasonality}")
+                    if volatility is not None:
+                        extras.append(f"income volatility {volatility}")
+                    if extras:
+                        parts.append("Additional signals: " + ", ".join(extras) + ".")
+
+                    enrichment = " ".join(parts) if parts else None
+                    if enrichment:
+                        logger.info("Enriching with bank cash-flow context")
+                        return enrichment, None
+
+            elif intent == "qb_financials":
+                financials = context.get("financials") or {}
+                company = context.get("company") or {}
+                has_qb = context.get("has_qb", False)
+
+                if has_qb or financials or company:
+                    revenue = financials.get("revenue")
+                    net_income = financials.get("net_income")
+                    profit_margin = financials.get("profit_margin")
+                    current_ratio = financials.get("current_ratio")
+                    dte = financials.get("debt_to_equity")
+                    dscr = financials.get("dscr")
+                    cash_on_hand = financials.get("cash_on_hand")
+                    runway_months = financials.get("runway_months")
+                    company_name = company.get("company_name")
+
+                    parts = []
+                    if company_name:
+                        parts.append(f"QuickBooks financial summary for {company_name}:")
+                    elif has_qb:
+                        parts.append("QuickBooks is connected. ")
+                    if revenue is not None and revenue != 0:
+                        rev_line = f"annual revenue around ${revenue:,.0f}."
+                        if net_income is not None and net_income != 0:
+                            rev_line = f"annual revenue around ${revenue:,.0f} with net income about ${net_income:,.0f}."
+                        parts.append(rev_line)
+                    elif net_income is not None and net_income != 0:
+                        parts.append(f"net income about ${net_income:,.0f}.")
+                    if profit_margin is not None and profit_margin != 0:
+                        parts.append(f"Profit margin is roughly {profit_margin}%.")
+                    ratio_bits: list[str] = []
+                    if current_ratio is not None and current_ratio != 0:
+                        ratio_bits.append(f"current ratio {current_ratio}")
+                    if dte is not None and dte != 0:
+                        ratio_bits.append(f"debt-to-equity {dte}")
+                    if ratio_bits:
+                        parts.append("Key balance sheet ratios: " + ", ".join(ratio_bits) + ".")
+                    if dscr is not None and dscr != 0:
+                        parts.append(f"Debt service coverage ratio (DSCR) is approximately {dscr}.")
+                    if cash_on_hand is not None and cash_on_hand != 0:
+                        parts.append(f"Cash on hand: ${cash_on_hand:,.0f}.")
+                    if runway_months is not None and runway_months != 0:
+                        parts.append(f"Runway: about {runway_months} months.")
+
+                    enrichment = " ".join(parts) if parts else None
+                    if enrichment:
+                        logger.info("Enriching with QuickBooks financial context")
+                        return enrichment, None
+                    if has_qb:
+                        # QB connected but no metrics parsed yet; still tell LLM so it doesn't say "no data"
+                        enrichment = (
+                            "QuickBooks is connected for this user. "
+                            "Summarise that we have QB data (revenue, P&L, balance sheet) and suggest "
+                            "they check the Pre-Qualify or Dashboard for the full breakdown."
+                        )
+                        logger.info("Enriching with QuickBooks connected (sparse metrics)")
+                        return enrichment, None
 
         return None, None
 
diff --git a/loangen-agent/agent/tools/qualification_engine.py b/loangen-agent/agent/tools/qualification_engine.py
index 941a9d0..dd22178 100644
--- a/loangen-agent/agent/tools/qualification_engine.py
+++ b/loangen-agent/agent/tools/qualification_engine.py
@@ -13,6 +13,16 @@ from typing import Any
 logger = logging.getLogger("loangen-qualification")
 
 
+def _safe_num(v: Any) -> float:
+    """Coerce to float for use in sums; None or invalid -> 0."""
+    if v is None:
+        return 0.0
+    try:
+        return float(v)
+    except (TypeError, ValueError):
+        return 0.0
+
+
 def compute_dscr(
     net_income: float,
     monthly_debt_payments: float,
@@ -56,13 +66,18 @@ class QualificationEngine:
 
         fico = personal_credit.get("fico_score", 0)
         revenue = financials.get("revenue", 0)
-        year_est = company.get("year_established", datetime.now().year)
-        years_in_biz = datetime.now().year - year_est
+        _now_year = datetime.now().year
+        try:
+            year_est = company.get("year_established")
+            year_est = _now_year if year_est is None else int(year_est)
+        except (TypeError, ValueError):
+            year_est = _now_year
+        years_in_biz = _now_year - year_est
         d_to_e = financials.get("debt_to_equity", 0)
         net_income = financials.get("net_income", 0)
 
         monthly_debt = sum(
-            t.get("monthly_payment", 0)
+            _safe_num(t.get("monthly_payment"))
             for t in personal_credit.get("tradelines", [])
             if t.get("status") != "closed"
         )
@@ -155,12 +170,17 @@ class QualificationEngine:
 
         fico = personal_credit.get("fico_score", 0)
         revenue = financials.get("revenue", 0)
-        year_est = company.get("year_established", datetime.now().year)
-        months_in_biz = (datetime.now().year - year_est) * 12
+        _now_year = datetime.now().year
+        try:
+            year_est = company.get("year_established")
+            year_est = _now_year if year_est is None else int(year_est)
+        except (TypeError, ValueError):
+            year_est = _now_year
+        months_in_biz = (_now_year - year_est) * 12
 
         net_income = financials.get("net_income", 0)
         monthly_debt = sum(
-            t.get("monthly_payment", 0)
+            _safe_num(t.get("monthly_payment"))
             for t in personal_credit.get("tradelines", [])
             if t.get("status") != "closed"
         )
SOLUTION_PATCH_EOF
diff --git a/loangen-agent/agent/context_builder.py b/loangen-agent/agent/context_builder.py
index 4178338..c381048 100644
--- a/loangen-agent/agent/context_builder.py
+++ b/loangen-agent/agent/context_builder.py
@@ -25,6 +25,7 @@ from agent.tools.plaid_bank import PlaidBankService
 from agent.tools.quickbooks import QuickBooksService
 from agent.tools.qualification_engine import QualificationEngine
 from agent.prompts.prompt_manager import prompt_manager
+from agent.core.config import settings
 
 logger = logging.getLogger("loangen.context_builder")
 
@@ -33,6 +34,7 @@ PROMPTS_DIR = Path(__file__).parent / "prompts"
 # ── Intent → required data sources mapping ────────────────────────────────────
 # Which data sources must be connected for a complete answer per intent.
 INTENT_DATA_REQUIREMENTS: dict[str, list[str]] = {
+    "qb_financials": ["quickbooks"],
     "qualification": ["credit", "quickbooks"],
     "gap_coaching":  ["credit", "quickbooks", "bank"],
     "cross_sell":    ["bank", "quickbooks"],
@@ -157,7 +159,7 @@ class ContextBuilder:
         # ── 1. Credit data (Array via MongoDB analytics) ───────────────────────
         try:
             from agent.analytics.services.credit_bureau_analytics import CreditBureauAnalyticsService
-            credit_svc = CreditBureauAnalyticsService()
+            credit_svc = CreditBureauAnalyticsService(live=settings.data_mode == "live")
             credit_result = await credit_svc.get_analytics(user_id)
             if credit_result:
                 context["has_credit"] = True
@@ -173,8 +175,8 @@ class ContextBuilder:
         # ── 2. Bank data (Plaid via MongoDB analytics) ─────────────────────────
         try:
             from agent.analytics.services.plaid_analytics import PlaidAnalyticsService
-            bank_svc = PlaidAnalyticsService()
-            bank_result = await bank_svc.get_analytics(user_id)
+            bank_svc = PlaidAnalyticsService(live=settings.data_mode == "live")
+            bank_result = await bank_svc.get_analytics(smb_id=user_id, user_id=user_id)
             if bank_result:
                 context["has_bank"] = True
                 context["bank_data"] = self._map_bank_analytics(bank_result)
@@ -189,7 +191,7 @@ class ContextBuilder:
         # ── 3. QuickBooks data (via MongoDB analytics) ─────────────────────────
         try:
             from agent.analytics.services.quickbooks_analytics import QuickBooksAnalyticsService
-            qb_svc = QuickBooksAnalyticsService()
+            qb_svc = QuickBooksAnalyticsService(live=settings.data_mode == "live")
             qb_result = await qb_svc.get_analytics(user_id)
             if qb_result:
                 context["has_qb"] = True
@@ -330,7 +332,9 @@ class ContextBuilder:
         else:
             return {}
 
-        company = d.get("company_profile") or d.get("company", {}) or {}
+        company = d.get("company_profile") or d.get("company") or {}
+        if hasattr(company, "model_dump"):
+            company = company.model_dump()
         return {
             "company_name":    company.get("company_name") or d.get("company_name"),
             "industry":        company.get("industry"),
@@ -342,7 +346,11 @@ class ContextBuilder:
         }
 
     def _map_qb_financials(self, result: Any) -> dict:
-        """Map QuickBooksAnalyticsService result to financials dict."""
+        """Map QuickBooksAnalyticsService result to financials dict.
+
+        QBAnalyticsResult uses income_statement.total_income (not total_revenue),
+        balance_sheet.cash_and_bank, and top-level revenue, net_income, dscr, etc.
+        """
         if hasattr(result, "model_dump"):
             d = result.model_dump()
         elif isinstance(result, dict):
@@ -354,19 +362,50 @@ class ContextBuilder:
         balance = d.get("balance_sheet") or {}
         ratios = d.get("key_metrics") or {}
 
+        revenue = (
+            income.get("total_income")
+            or income.get("total_revenue")
+            or income.get("revenue")
+            or d.get("revenue", 0)
+        )
+        net_income = income.get("net_income") or d.get("net_income", 0)
+        profit_margin = (
+            income.get("profit_margin_pct")
+            or income.get("profit_margin")
+            or d.get("profit_margin", 0)
+        )
+        current_ratio = (
+            balance.get("current_ratio")
+            or ratios.get("current_ratio")
+            or d.get("current_ratio", 0)
+        )
+        debt_to_equity = (
+            balance.get("debt_to_equity")
+            or ratios.get("debt_to_equity")
+            or d.get("debt_to_equity", 0)
+        )
+        cash_on_hand = (
+            balance.get("cash_and_bank")
+            or balance.get("cash")
+            or balance.get("cash_on_hand")
+            or d.get("cash_on_hand", 0)
+        )
+        dscr = d.get("dscr") or ratios.get("dscr")
+        runway_months = d.get("runway_months") or ratios.get("runway_months")
+
         return {
-            "period":          income.get("period"),
-            "revenue":         income.get("total_revenue") or income.get("revenue", 0),
-            "net_income":      income.get("net_income", 0),
-            "profit_margin":   income.get("profit_margin", 0),
-            "revenue_growth_yoy": income.get("revenue_growth_yoy", 0),
-            "current_ratio":   balance.get("current_ratio") or ratios.get("current_ratio", 0),
-            "debt_to_equity":  balance.get("debt_to_equity") or ratios.get("debt_to_equity", 0),
-            "cash_on_hand":    balance.get("cash") or balance.get("cash_on_hand", 0),
-            "monthly_burn_rate": income.get("monthly_burn_rate", 0),
-            "accounts_receivable": balance.get("accounts_receivable", 0),
-            "dscr":            ratios.get("dscr"),
-            "runway_months":   ratios.get("runway_months"),
+            "period": income.get("period"),
+            "revenue": revenue,
+            "net_income": net_income,
+            "profit_margin": profit_margin,
+            "revenue_growth_yoy": income.get("revenue_growth_yoy") or d.get("revenue_growth_yoy", 0),
+            "current_ratio": current_ratio,
+            "debt_to_equity": debt_to_equity,
+            "cash_on_hand": cash_on_hand,
+            "monthly_burn_rate": income.get("monthly_burn_rate") or d.get("monthly_burn_rate", 0),
+            "accounts_receivable": balance.get("accounts_receivable") or d.get("accounts_receivable", 0),
+            "dscr": dscr,
+            "runway_months": runway_months,
         }
 
     def _describe_available_analysis(self, context: dict, intent: str) -> str:
@@ -420,15 +459,28 @@ class ContextBuilder:
             nsf_count = sum(s.get("nsf_overdraft_count", 0) for s in snapshots)
 
         from datetime import datetime
-        year_established = company.get("year_established", datetime.now().year)
-        years_in_business = datetime.now().year - year_established
+        _now_year = datetime.now().year
+        try:
+            year_established = company.get("year_established")
+            year_established = _now_year if year_established is None else int(year_established)
+        except (TypeError, ValueError):
+            year_established = _now_year
+        years_in_business = _now_year - year_established
 
         annual_revenue = financials.get("revenue", 0)
         net_income = financials.get("net_income", 0)
         total_debt = personal_credit.get("total_debt", 0)
 
+        def _num(v: Any) -> float:
+            if v is None:
+                return 0.0
+            try:
+                return float(v)
+            except (TypeError, ValueError):
+                return 0.0
+
         monthly_debt_service = sum(
-            t.get("monthly_payment", 0)
+            _num(t.get("monthly_payment"))
             for t in personal_credit.get("tradelines", [])
             if t.get("status") != "closed"
         )
diff --git a/loangen-agent/agent/pipeline.py b/loangen-agent/agent/pipeline.py
index 1f99403..b23d64e 100644
--- a/loangen-agent/agent/pipeline.py
+++ b/loangen-agent/agent/pipeline.py
@@ -22,6 +22,44 @@ logger = logging.getLogger("loangen-pipeline")
 
 
 INTENT_PATTERNS = {
+    # ── Personalised data intents ────────────────────────────────────────────
+    "personal_credit": [
+        r"\bmy credit score\b",
+        r"\bmy fico\b",
+        r"\bmy experian\b",
+        r"\bmy equifax\b",
+        r"\bmy transunion\b",
+        r"\bmy credit report\b",
+    ],
+    "bank_cashflow": [
+        r"\bmy cash ?flow\b",
+        r"\bcashflow\b",
+        r"\bbank (statements?|accounts?)\b",
+        r"\boverdraft\b",
+        r"\bnsf\b",
+        r"\bnegative balance\b",
+    ],
+    "qb_financials": [
+        r"\bmy revenue\b",
+        r"\bmy profit\b",
+        r"\bnet income\b",
+        r"\bprofit and loss\b|\bp&l\b",
+        r"\bbalance sheet\b",
+        r"\bquickbooks?\b|\bqb\b",
+        r"\bquickbook\s+(data|analysis|report)\b",
+        r"\b(my\s+)?(quickbooks?|qb)\s+(data|analysis|report)",
+        r"\b(analysis|data|report)s?\s+.*(quickbooks?|qb)",
+        r"\b(quickbooks?|qb)\s+.*(analysis|data|report)",
+        r"\b(as\s+)?per\s+my\s+quickbook",
+        r"\bdscr\b",
+    ],
+    "applications_overview": [
+        r"\bmy (loan )?applications?\b",
+        r"\bapplication status\b",
+        r"\bstatus of my application\b",
+        r"\blist my applications\b",
+    ],
+    # ── Existing intents ─────────────────────────────────────────────────────
     "qualification": [
         r"do i qualify",
         r"can i get",
@@ -213,6 +251,129 @@ class LoanGenPipeline:
                 enrichment = self.context_builder.build_cross_sell_prompt(opportunities)
                 logger.info(f"Enriching with {len(opportunities)} cross-sell opportunities")
                 return enrichment, None
+        # ── Personalised one-shot views (authenticated user only) ─────────────
+        if use_user_id:
+            if intent == "personal_credit":
+                credit = context.get("credit_personal") or {}
+                if credit:
+                    score = credit.get("fico_score")
+                    bureau = credit.get("bureau", "Experian")
+                    util = credit.get("credit_utilization")
+                    total_debt = credit.get("total_debt")
+                    delinq = credit.get("delinquencies")
+                    inquiries = credit.get("inquiries_last_12_months")
+
+                    parts: list[str] = []
+                    if score:
+                        parts.append(f"Personal credit score: {score} (bureau: {bureau}).")
+                    if util is not None:
+                        if total_debt is not None:
+                            parts.append(
+                                f"Revolving utilization is about {util}% with total revolving debt around ${total_debt:,.0f}."
+                            )
+                        else:
+                            parts.append(f"Revolving utilization is about {util}%.")
+                    detail_bits: list[str] = []
+                    if delinq is not None:
+                        detail_bits.append(f"{delinq} past delinquencies")
+                    if inquiries is not None:
+                        detail_bits.append(f"{inquiries} hard inquiries in the last 12 months")
+                    if detail_bits:
+                        parts.append("Risk flags: " + ", ".join(detail_bits) + ".")
+
+                    enrichment = " ".join(parts) if parts else None
+                    if enrichment:
+                        logger.info("Enriching with personal credit context")
+                        return enrichment, None
+
+            elif intent == "bank_cashflow":
+                bank = context.get("bank_data") or {}
+                metrics = bank.get("cash_flow_analysis") or {}
+                cash_flow_score = bank.get("cash_flow_score")
+
+                if metrics or cash_flow_score is not None:
+                    avg_in = metrics.get("average_monthly_income")
+                    avg_out = metrics.get("average_monthly_expenses")
+                    seasonality = metrics.get("seasonality_index")
+                    volatility = metrics.get("income_volatility")
+
+                    parts = []
+                    if avg_in is not None and avg_out is not None:
+                        parts.append(
+                            f"Bank cash-flow summary: average monthly inflows about ${avg_in:,.0f} and outflows about ${avg_out:,.0f}."
+                        )
+                    if cash_flow_score is not None:
+                        parts.append(f"Overall cash-flow score is {cash_flow_score}.")
+                    extras: list[str] = []
+                    if seasonality is not None:
+                        extras.append(f"seasonality index {seasonality}")
+                    if volatility is not None:
+                        extras.append(f"income volatility {volatility}")
+                    if extras:
+                        parts.append("Additional signals: " + ", ".join(extras) + ".")
+
+                    enrichment = " ".join(parts) if parts else None
+                    if enrichment:
+                        logger.info("Enriching with bank cash-flow context")
+                        return enrichment, None
+
+            elif intent == "qb_financials":
+                financials = context.get("financials") or {}
+                company = context.get("company") or {}
+                has_qb = context.get("has_qb", False)
+
+                if has_qb or financials or company:
+                    revenue = financials.get("revenue")
+                    net_income = financials.get("net_income")
+                    profit_margin = financials.get("profit_margin")
+                    current_ratio = financials.get("current_ratio")
+                    dte = financials.get("debt_to_equity")
+                    dscr = financials.get("dscr")
+                    cash_on_hand = financials.get("cash_on_hand")
+                    runway_months = financials.get("runway_months")
+                    company_name = company.get("company_name")
+
+                    parts = []
+                    if company_name:
+                        parts.append(f"QuickBooks financial summary for {company_name}:")
+                    elif has_qb:
+                        parts.append("QuickBooks is connected. ")
+                    if revenue is not None and revenue != 0:
+                        rev_line = f"annual revenue around ${revenue:,.0f}."
+                        if net_income is not None and net_income != 0:
+                            rev_line = f"annual revenue around ${revenue:,.0f} with net income about ${net_income:,.0f}."
+                        parts.append(rev_line)
+                    elif net_income is not None and net_income != 0:
+                        parts.append(f"net income about ${net_income:,.0f}.")
+                    if profit_margin is not None and profit_margin != 0:
+                        parts.append(f"Profit margin is roughly {profit_margin}%.")
+                    ratio_bits: list[str] = []
+                    if current_ratio is not None and current_ratio != 0:
+                        ratio_bits.append(f"current ratio {current_ratio}")
+                    if dte is not None and dte != 0:
+                        ratio_bits.append(f"debt-to-equity {dte}")
+                    if ratio_bits:
+                        parts.append("Key balance sheet ratios: " + ", ".join(ratio_bits) + ".")
+                    if dscr is not None and dscr != 0:
+                        parts.append(f"Debt service coverage ratio (DSCR) is approximately {dscr}.")
+                    if cash_on_hand is not None and cash_on_hand != 0:
+                        parts.append(f"Cash on hand: ${cash_on_hand:,.0f}.")
+                    if runway_months is not None and runway_months != 0:
+                        parts.append(f"Runway: about {runway_months} months.")
+
+                    enrichment = " ".join(parts) if parts else None
+                    if enrichment:
+                        logger.info("Enriching with QuickBooks financial context")
+                        return enrichment, None
+                    if has_qb:
+                        # QB connected but no metrics parsed yet; still tell LLM so it doesn't say "no data"
+                        enrichment = (
+                            "QuickBooks is connected for this user. "
+                            "Summarise that we have QB data (revenue, P&L, balance sheet) and suggest "
+                            "they check the Pre-Qualify or Dashboard for the full breakdown."
+                        )
+                        logger.info("Enriching with QuickBooks connected (sparse metrics)")
+                        return enrichment, None
 
         return None, None
 
diff --git a/loangen-agent/agent/tools/qualification_engine.py b/loangen-agent/agent/tools/qualification_engine.py
index 941a9d0..dd22178 100644
--- a/loangen-agent/agent/tools/qualification_engine.py
+++ b/loangen-agent/agent/tools/qualification_engine.py
@@ -13,6 +13,16 @@ from typing import Any
 logger = logging.getLogger("loangen-qualification")
 
 
+def _safe_num(v: Any) -> float:
+    """Coerce to float for use in sums; None or invalid -> 0."""
+    if v is None:
+        return 0.0
+    try:
+        return float(v)
+    except (TypeError, ValueError):
+        return 0.0
+
+
 def compute_dscr(
     net_income: float,
     monthly_debt_payments: float,
@@ -56,13 +66,18 @@ class QualificationEngine:
 
         fico = personal_credit.get("fico_score", 0)
         revenue = financials.get("revenue", 0)
-        year_est = company.get("year_established", datetime.now().year)
-        years_in_biz = datetime.now().year - year_est
+        _now_year = datetime.now().year
+        try:
+            year_est = company.get("year_established")
+            year_est = _now_year if year_est is None else int(year_est)
+        except (TypeError, ValueError):
+            year_est = _now_year
+        years_in_biz = _now_year - year_est
         d_to_e = financials.get("debt_to_equity", 0)
         net_income = financials.get("net_income", 0)
 
         monthly_debt = sum(
-            t.get("monthly_payment", 0)
+            _safe_num(t.get("monthly_payment"))
             for t in personal_credit.get("tradelines", [])
             if t.get("status") != "closed"
         )
@@ -155,12 +170,17 @@ class QualificationEngine:
 
         fico = personal_credit.get("fico_score", 0)
         revenue = financials.get("revenue", 0)
-        year_est = company.get("year_established", datetime.now().year)
-        months_in_biz = (datetime.now().year - year_est) * 12
+        _now_year = datetime.now().year
+        try:
+            year_est = company.get("year_established")
+            year_est = _now_year if year_est is None else int(year_est)
+        except (TypeError, ValueError):
+            year_est = _now_year
+        months_in_biz = (_now_year - year_est) * 12
 
         net_income = financials.get("net_income", 0)
         monthly_debt = sum(
-            t.get("monthly_payment", 0)
+            _safe_num(t.get("monthly_payment"))
             for t in personal_credit.get("tradelines", [])
             if t.get("status") != "closed"
         )
SOLUTION_PATCH_EOF
