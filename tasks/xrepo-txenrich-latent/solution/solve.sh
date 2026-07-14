#!/bin/sh
# Oracle solution — restores the correct boundary / structural handling in the
# HDFC and ICICI bank scripts. The repository files use CRLF line endings, so
# the reversal is done as an exact byte-level replacement (CRLF-agnostic) rather
# than a git patch: each planted single-token slip is rewritten back to its
# correct form.
set -eu
cd /app
python3 - <<'FIX_EOF'
import sys
BASE = "/app/categorizationapp/categorizationapp/BankScripts"
HDFC, ICICI = f"{BASE}/HDFC.py", f"{BASE}/ICICI.py"
# (file, planted, correct) -- reverse of the planted defects
FIXES = [
    (HDFC, b'transactions.remark.str.len().eq(15)',
           b'transactions.remark.str.len().eq(16)'),
    (HDFC, b'transactions.type.eq("CREDIT") & (accountType=="SAVINGS") , "SALARY"',
           b'transactions.type.eq("CREDIT") & (accountType=="SAVING") , "SALARY"'),
    (HDFC, b'transactions.description.eq(transactions.description.shift(periods=2)) & transactions.description.str.contains("IMPS|NEFT|',
           b'transactions.description.eq(transactions.description.shift(periods=1)) & transactions.description.str.contains("IMPS|NEFT|'),
    (ICICI, b'pat="TRFR (TO|FROM):(.*)", index=0',
            b'pat="TRFR (TO|FROM):(.*)", index=1'),
    (ICICI, b'transactions.description.str.count("/").eq(3)  , sep_by_(transactions.description,2,3)',
            b'transactions.description.str.count("/").eq(3)  , sep_by_(transactions.description,3,4)'),
]
buf = {}
for p in {HDFC, ICICI}:
    buf[p] = open(p, "rb").read()
for p, planted, correct in FIXES:
    if buf[p].count(planted) != 1:
        print("ABORT anchor", p, planted[:60]); sys.exit(2)
    buf[p] = buf[p].replace(planted, correct)
for p, data in buf.items():
    open(p, "wb").write(data)
print("restored correct boundary/structural handling")
FIX_EOF
