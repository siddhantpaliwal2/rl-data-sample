#!/bin/sh
# Oracle solution — applies the fix diff at base_commit.
set -eu
cd /app
git apply --check - <<'SOLUTION_PATCH_EOF' && git apply - <<'SOLUTION_PATCH_EOF'
diff --git a/loangen-agent/agent/plaid/report_service.py b/loangen-agent/agent/plaid/report_service.py
index 9bca3d3..907dbc4 100644
--- a/loangen-agent/agent/plaid/report_service.py
+++ b/loangen-agent/agent/plaid/report_service.py
@@ -1,9 +1,10 @@
 from __future__ import annotations

+import logging
 from datetime import datetime, timezone
 from typing import Any

-from agent.analytics.models.plaid import PlaidTransactionsResponse
+from agent.analytics.models.plaid import PlaidDataDocument, PlaidTransactionsResponse
 from agent.analytics.services.plaid_analytics import compute_plaid_analytics
 from agent.plaid.models import PlaidAccount, PlaidItem, PlaidTransaction
 from agent.plaid.schemas import (
@@ -15,6 +16,9 @@ from agent.plaid.schemas import (
 )


+logger = logging.getLogger(__name__)
+
+
 class BankReportNotFoundError(Exception):
     """Raised when a bank report cannot be generated due to missing data."""

@@ -26,7 +30,12 @@ async def build_bank_report_view(
     user_last_name: str | None = None,
     business_name: str | None = None,
 ) -> BankReportViewResponse:
-    """Build a complete bank report payload from normalized Plaid collections."""
+    """Build a complete bank report payload from normalized Plaid data.
+
+    Uses ``PlaidTransaction`` rows when present (production Plaid sync path).
+    Falls back to ``PlaidDataDocument.raw_json`` only when normalized
+    transactions are missing but seeded raw data exists (trial/UAT users).
+    """

     accounts = await PlaidAccount.find(
         PlaidAccount.user_id == user_id,
@@ -50,6 +59,15 @@ async def build_bank_report_view(
     ).sort(-PlaidTransaction.id).to_list()

     if not transactions:
+        fallback_report = await _build_bank_report_view_from_plaid_data_document(
+            user_id=user_id,
+            primary_account_id=primary_account.account_id,
+            user_first_name=user_first_name,
+            user_last_name=user_last_name,
+            business_name=business_name,
+        )
+        if fallback_report is not None:
+            return fallback_report
         raise BankReportNotFoundError(
             "No bank transactions found for the selected primary account."
         )
@@ -271,6 +289,75 @@ def build_bank_report_view_from_preview_payload(
     )


+async def _build_bank_report_view_from_plaid_data_document(
+    *,
+    user_id: str,
+    primary_account_id: str,
+    user_first_name: str | None,
+    user_last_name: str | None,
+    business_name: str | None,
+) -> BankReportViewResponse | None:
+    """
+    Build a bank report from seeded raw Plaid JSON when normalized transactions
+    are missing.
+
+    Trial/UAT signups store transactions in ``PlaidDataDocument`` but not always
+    in ``PlaidTransaction``. Production users with a completed Plaid sync have
+    normalized rows and never reach this path.
+    """
+    doc = await PlaidDataDocument.find_one(PlaidDataDocument.smb_id == user_id)
+    if doc is None or not doc.raw_json:
+        return None
+
+    raw_json = doc.raw_json
+    raw_accounts = raw_json.get("accounts")
+    raw_transactions = raw_json.get("transactions")
+    if not isinstance(raw_accounts, list) or not raw_accounts:
+        return None
+    if not isinstance(raw_transactions, list) or not raw_transactions:
+        return None
+
+    account_transactions = [
+        txn
+        for txn in raw_transactions
+        if isinstance(txn, dict) and txn.get("account_id") == primary_account_id
+    ]
+    if not account_transactions:
+        return None
+
+    raw_item = raw_json.get("item")
+    institution_name = (
+        raw_item.get("institution_name")
+        if isinstance(raw_item, dict)
+        else None
+    )
+
+    logger.info(
+        "Building bank report from PlaidDataDocument fallback | user_id=%s account_id=%s txn_count=%s",
+        user_id,
+        primary_account_id,
+        len(account_transactions),
+    )
+
+    return build_bank_report_view_from_preview_payload(
+        payload=BankReportPreviewDownloadRequest(
+            accounts=raw_accounts,
+            transactions=raw_transactions,
+            total_transactions=raw_json.get("total_transactions") or len(raw_transactions),
+            request_id=raw_json.get("request_id") or "",
+            item=raw_item if isinstance(raw_item, dict) else None,
+            selected_account_id=primary_account_id,
+            institution_name=institution_name,
+            user_name=_build_user_name(user_first_name, user_last_name),
+            business_name=business_name,
+        ),
+        user_id=user_id,
+        user_first_name=user_first_name,
+        user_last_name=user_last_name,
+        business_name=business_name,
+    )
+
+
 def _resolve_primary_account(accounts: list[PlaidAccount]) -> PlaidAccount:
     selected = [account for account in accounts if account.selected]
     if selected:
SOLUTION_PATCH_EOF
diff --git a/loangen-agent/agent/plaid/report_service.py b/loangen-agent/agent/plaid/report_service.py
index 9bca3d3..907dbc4 100644
--- a/loangen-agent/agent/plaid/report_service.py
+++ b/loangen-agent/agent/plaid/report_service.py
@@ -1,9 +1,10 @@
 from __future__ import annotations

+import logging
 from datetime import datetime, timezone
 from typing import Any

-from agent.analytics.models.plaid import PlaidTransactionsResponse
+from agent.analytics.models.plaid import PlaidDataDocument, PlaidTransactionsResponse
 from agent.analytics.services.plaid_analytics import compute_plaid_analytics
 from agent.plaid.models import PlaidAccount, PlaidItem, PlaidTransaction
 from agent.plaid.schemas import (
@@ -15,6 +16,9 @@ from agent.plaid.schemas import (
 )


+logger = logging.getLogger(__name__)
+
+
 class BankReportNotFoundError(Exception):
     """Raised when a bank report cannot be generated due to missing data."""

@@ -26,7 +30,12 @@ async def build_bank_report_view(
     user_last_name: str | None = None,
     business_name: str | None = None,
 ) -> BankReportViewResponse:
-    """Build a complete bank report payload from normalized Plaid collections."""
+    """Build a complete bank report payload from normalized Plaid data.
+
+    Uses ``PlaidTransaction`` rows when present (production Plaid sync path).
+    Falls back to ``PlaidDataDocument.raw_json`` only when normalized
+    transactions are missing but seeded raw data exists (trial/UAT users).
+    """

     accounts = await PlaidAccount.find(
         PlaidAccount.user_id == user_id,
@@ -50,6 +59,15 @@ async def build_bank_report_view(
     ).sort(-PlaidTransaction.id).to_list()

     if not transactions:
+        fallback_report = await _build_bank_report_view_from_plaid_data_document(
+            user_id=user_id,
+            primary_account_id=primary_account.account_id,
+            user_first_name=user_first_name,
+            user_last_name=user_last_name,
+            business_name=business_name,
+        )
+        if fallback_report is not None:
+            return fallback_report
         raise BankReportNotFoundError(
             "No bank transactions found for the selected primary account."
         )
@@ -271,6 +289,75 @@ def build_bank_report_view_from_preview_payload(
     )


+async def _build_bank_report_view_from_plaid_data_document(
+    *,
+    user_id: str,
+    primary_account_id: str,
+    user_first_name: str | None,
+    user_last_name: str | None,
+    business_name: str | None,
+) -> BankReportViewResponse | None:
+    """
+    Build a bank report from seeded raw Plaid JSON when normalized transactions
+    are missing.
+
+    Trial/UAT signups store transactions in ``PlaidDataDocument`` but not always
+    in ``PlaidTransaction``. Production users with a completed Plaid sync have
+    normalized rows and never reach this path.
+    """
+    doc = await PlaidDataDocument.find_one(PlaidDataDocument.smb_id == user_id)
+    if doc is None or not doc.raw_json:
+        return None
+
+    raw_json = doc.raw_json
+    raw_accounts = raw_json.get("accounts")
+    raw_transactions = raw_json.get("transactions")
+    if not isinstance(raw_accounts, list) or not raw_accounts:
+        return None
+    if not isinstance(raw_transactions, list) or not raw_transactions:
+        return None
+
+    account_transactions = [
+        txn
+        for txn in raw_transactions
+        if isinstance(txn, dict) and txn.get("account_id") == primary_account_id
+    ]
+    if not account_transactions:
+        return None
+
+    raw_item = raw_json.get("item")
+    institution_name = (
+        raw_item.get("institution_name")
+        if isinstance(raw_item, dict)
+        else None
+    )
+
+    logger.info(
+        "Building bank report from PlaidDataDocument fallback | user_id=%s account_id=%s txn_count=%s",
+        user_id,
+        primary_account_id,
+        len(account_transactions),
+    )
+
+    return build_bank_report_view_from_preview_payload(
+        payload=BankReportPreviewDownloadRequest(
+            accounts=raw_accounts,
+            transactions=raw_transactions,
+            total_transactions=raw_json.get("total_transactions") or len(raw_transactions),
+            request_id=raw_json.get("request_id") or "",
+            item=raw_item if isinstance(raw_item, dict) else None,
+            selected_account_id=primary_account_id,
+            institution_name=institution_name,
+            user_name=_build_user_name(user_first_name, user_last_name),
+            business_name=business_name,
+        ),
+        user_id=user_id,
+        user_first_name=user_first_name,
+        user_last_name=user_last_name,
+        business_name=business_name,
+    )
+
+
 def _resolve_primary_account(accounts: list[PlaidAccount]) -> PlaidAccount:
     selected = [account for account in accounts if account.selected]
     if selected:
SOLUTION_PATCH_EOF
