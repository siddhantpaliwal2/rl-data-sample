#!/bin/sh
# Oracle solution — restores the correct boundary / structural handling in the
# PNB and Canara bank scripts. The repository files use CRLF line endings, so
# the reversal is done as an exact byte-level replacement (CRLF-agnostic) rather
# than a git patch: each planted single-token slip is rewritten back to its
# correct form.
set -eu
cd /app
python3 - <<'FIX_EOF'
import sys
BASE = "/app/categorizationapp/categorizationapp/BankScripts"
PNB, CAN = f"{BASE}/PNB.py", f"{BASE}/Canara.py"
# (file, planted, correct) -- reverse of the planted defects
FIXES = [
    (PNB, b'"^[0-9]{5}$", na=False, case=False) & transactions.type.eq("DEBIT") , "CHEQUE_PAID"',
          b'"^[0-9]{5,6}$", na=False, case=False) & transactions.type.eq("DEBIT") , "CHEQUE_PAID"'),
    (PNB, b'py_extract(transactions.description, pat="NEFT (.*)", index=1)',
          b'py_extract(transactions.description, pat="NEFT (.*)", index=0)'),
    (CAN, b'"^CHQ PAID-", na=False, case=False), sep_by_dash(transactions.description,1,2)',
          b'"^CHQ PAID-", na=False, case=False), sep_by_dash(transactions.description,2,3)'),
    (CAN, b'BANK_VERIF, na=False, case=False) &  transactions.amount.lt(1) , "ACCOUNT_VERIFICATION"',
          b'BANK_VERIF, na=False, case=False) &  transactions.amount.lt(2) , "ACCOUNT_VERIFICATION"'),
    (CAN, b'"^UPI/[CD]R", na=False, case=False) , sep_by_(transactions.description,2,3)',
          b'"^UPI/[CD]R", na=False, case=False) , sep_by_(transactions.description,3,4)'),
]
buf = {}
for p in {PNB, CAN}:
    buf[p] = open(p, "rb").read()
for p, planted, correct in FIXES:
    if buf[p].count(planted) != 1:
        print("ABORT anchor", p, planted[:60]); sys.exit(2)
    buf[p] = buf[p].replace(planted, correct)
for p, data in buf.items():
    open(p, "wb").write(data)
print("restored correct boundary/structural handling")
FIX_EOF
