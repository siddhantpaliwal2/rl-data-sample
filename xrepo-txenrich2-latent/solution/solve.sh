#!/bin/sh
# Oracle solution — restores the correct boundary / structural handling in the
# Kotak and SBI bank scripts. The repository files use CRLF line endings, so the
# reversal is done as an exact byte-level replacement (CRLF-agnostic) rather than
# a git patch: each planted single-token slip is rewritten back to its correct
# form.
set -eu
cd /app
python3 - <<'FIX_EOF'
import sys
BASE = "/app/categorizationapp/categorizationapp/BankScripts"
KOTAK, SBI = f"{BASE}/Kotak.py", f"{BASE}/SBI.py"
# (file, planted, correct) -- reverse of the planted defects
FIXES = [
    (KOTAK, b'transactions.remark.str.contains("^[0-9]{3,4}$", na=False, case=False) & transactions.type.eq("CREDIT") , "CHEQUE_DEPOSIT"',
            b'transactions.remark.str.contains("^[0-9]{3,5}$", na=False, case=False) & transactions.type.eq("CREDIT") , "CHEQUE_DEPOSIT"'),
    (KOTAK, b'transactions.description.str.contains("^Received from [A-Z]", na=False, case=False) & transactions.type.eq("CREDIT") & transactions.amount.eq(2)',
            b'transactions.description.str.contains("^Received from [A-Z]", na=False, case=False) & transactions.type.eq("CREDIT") & transactions.amount.eq(1)'),
    (KOTAK, b'transactions.description.str.contains("^NACH-SAL-CR-SAL-", na=False, case=False)   , sep_by_dash(transactions.description,3,4)',
            b'transactions.description.str.contains("^NACH-SAL-CR-SAL-", na=False, case=False)   , sep_by_dash(transactions.description,4,5)'),
    (SBI, b'(accountType == "SAVINGS"), sep_by_dash(transactions.description,1,2)',
          b'(accountType == "SAVING"), sep_by_dash(transactions.description,1,2)'),
    (SBI, b'py_extract(transactions.description, pat="TO TRANSFER INB (.*)", index=1)',
          b'py_extract(transactions.description, pat="TO TRANSFER INB (.*)", index=0)'),
]
buf = {}
for p in {KOTAK, SBI}:
    buf[p] = open(p, "rb").read()
for p, planted, correct in FIXES:
    if buf[p].count(planted) != 1:
        print("ABORT anchor", p, planted[:60]); sys.exit(2)
    buf[p] = buf[p].replace(planted, correct)
for p, data in buf.items():
    open(p, "wb").write(data)
print("restored correct boundary/structural handling")
FIX_EOF
