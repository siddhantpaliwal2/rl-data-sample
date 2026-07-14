#!/bin/sh
# Oracle solution — restores the correct boundary / structural handling in the
# IDBI and Indusind bank scripts. The repository files use CRLF line endings, so
# the reversal is done as an exact byte-level replacement (CRLF-agnostic) rather
# than a git patch: each planted single-token slip is rewritten back to its
# correct form.
set -eu
cd /app
python3 - <<'FIX_EOF'
import sys
BASE = "/app/categorizationapp/categorizationapp/BankScripts"
IDBI, INDUS = f"{BASE}/IDBI.py", f"{BASE}/Indusind.py"
# (file, planted, correct) -- reverse of the planted defects
FIXES = [
    (INDUS, b'"^[0-9]{5}$",na=False, case=False) & transactions.type.eq("DEBIT") , "CHEQUE_PAID"',
            b'"^[0-9]{5,6}$",na=False, case=False) & transactions.type.eq("DEBIT") , "CHEQUE_PAID"'),
    (INDUS, b'transactions.amount.eq(2) & transactions.description.str.contains("MANDATE|Mandate"',
            b'transactions.amount.eq(1) & transactions.description.str.contains("MANDATE|Mandate"'),
    (INDUS, b'(accountType=="SAVINGS") , "CARD_PAYMENT_REVERSAL"',
            b'(accountType=="SAVING") , "CARD_PAYMENT_REVERSAL"'),
    (IDBI, b'"^ACH-BD-NACH", na=False, case=False) , sep_by_dash(transactions.description,2,3)',
           b'"^ACH-BD-NACH", na=False, case=False) , sep_by_dash(transactions.description,3,4)'),
    (IDBI, b'pat="[0-9]{10,} (.*)", index=1',
           b'pat="[0-9]{10,} (.*)", index=0'),
]
buf = {}
for p in {IDBI, INDUS}:
    buf[p] = open(p, "rb").read()
for p, planted, correct in FIXES:
    if buf[p].count(planted) != 1:
        print("ABORT anchor", p, planted[:60]); sys.exit(2)
    buf[p] = buf[p].replace(planted, correct)
for p, data in buf.items():
    open(p, "wb").write(data)
print("restored correct boundary/structural handling")
FIX_EOF
