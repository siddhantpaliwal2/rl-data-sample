# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image for the bank-transaction enrichment engine.
# The per-bank categorization logic is deterministic and fully offline; no
# secrets or network are required. Locally this is the repo image built from
# the transaction-enrichment-python tree (python 3.11-slim + pinned numpy/pandas
# so the 2022-era np.select logic runs unchanged). On the platform, replace with
# the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/txenrich-xxxxx:v1@sha256:...
FROM txenrich-repo:v1

USER root
WORKDIR /app
RUN git config --global --add safe.directory /app

# Plant the subtle boundary / structural defects into the working tree. Byte
# level replacement preserves the files' original CRLF endings, so only the five
# changed lines differ. Every ordinary transaction still enriches correctly;
# only untested exact-width, sentinel-amount, fixed-layout and account-type
# inputs come out wrong.
RUN python3 - <<'PLANT_EOF'
import sys
BASE = "/app/categorizationapp/categorizationapp/BankScripts"
KOTAK, SBI = f"{BASE}/Kotak.py", f"{BASE}/SBI.py"
EDITS = [
    (KOTAK, b'transactions.remark.str.contains("^[0-9]{3,5}$", na=False, case=False) & transactions.type.eq("CREDIT") , "CHEQUE_DEPOSIT"',
            b'transactions.remark.str.contains("^[0-9]{3,4}$", na=False, case=False) & transactions.type.eq("CREDIT") , "CHEQUE_DEPOSIT"'),
    (KOTAK, b'transactions.description.str.contains("^Received from [A-Z]", na=False, case=False) & transactions.type.eq("CREDIT") & transactions.amount.eq(1)',
            b'transactions.description.str.contains("^Received from [A-Z]", na=False, case=False) & transactions.type.eq("CREDIT") & transactions.amount.eq(2)'),
    (KOTAK, b'transactions.description.str.contains("^NACH-SAL-CR-SAL-", na=False, case=False)   , sep_by_dash(transactions.description,4,5)',
            b'transactions.description.str.contains("^NACH-SAL-CR-SAL-", na=False, case=False)   , sep_by_dash(transactions.description,3,4)'),
    (SBI, b'(accountType == "SAVING"), sep_by_dash(transactions.description,1,2)',
          b'(accountType == "SAVINGS"), sep_by_dash(transactions.description,1,2)'),
    (SBI, b'py_extract(transactions.description, pat="TO TRANSFER INB (.*)", index=0)',
          b'py_extract(transactions.description, pat="TO TRANSFER INB (.*)", index=1)'),
]
buf = {}
for p in {KOTAK, SBI}:
    buf[p] = open(p, "rb").read()
for p, old, new in EDITS:
    if buf[p].count(old) != 1:
        print("ABORT anchor", p, old[:60]); sys.exit(2)
    buf[p] = buf[p].replace(old, new)
for p, data in buf.items():
    open(p, "wb").write(data)
print("planted 5 defects OK")
PLANT_EOF

# Collapse history: planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git categorizationapp/*.egg-info categorizationapp/categorizationapp.egg-info \
 && git init -qb main && git config user.email t@t && git config user.name t \
 && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app
