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

# Plant five subtle boundary / structural defects into the working tree. Byte
# level replacement preserves the files' original CRLF endings, so only the
# changed lines differ. Every ordinary transaction still enriches correctly;
# only untested exact-width, single-capture-group, fixed-layout, and
# sentinel-amount inputs come out wrong. The five single-token slips are:
#   1. PNB cheque-by-remark width  ^[0-9]{5,6}$ -> ^[0-9]{5}$  (DEBIT rule only)
#   2. PNB NEFT payee capture-group  index=0 -> index=1  (single-group pattern)
#   3. Canara cleared-cheque payee slice  sep_by_dash(...,2,3) -> (...,1,2)
#   4. Canara account-verification sentinel  amount.lt(2) -> amount.lt(1)
#   5. Canara UPI person-to-person payee slice  sep_by_(...,3,4) -> (...,2,3)
RUN python3 - <<'PLANT_EOF'
import sys
BASE = "/app/categorizationapp/categorizationapp/BankScripts"
PNB, CAN = f"{BASE}/PNB.py", f"{BASE}/Canara.py"
EDITS = [
    (PNB, b'"^[0-9]{5,6}$", na=False, case=False) & transactions.type.eq("DEBIT") , "CHEQUE_PAID"',
          b'"^[0-9]{5}$", na=False, case=False) & transactions.type.eq("DEBIT") , "CHEQUE_PAID"'),
    (PNB, b'py_extract(transactions.description, pat="NEFT (.*)", index=0)',
          b'py_extract(transactions.description, pat="NEFT (.*)", index=1)'),
    (CAN, b'"^CHQ PAID-", na=False, case=False), sep_by_dash(transactions.description,2,3)',
          b'"^CHQ PAID-", na=False, case=False), sep_by_dash(transactions.description,1,2)'),
    (CAN, b'BANK_VERIF, na=False, case=False) &  transactions.amount.lt(2) , "ACCOUNT_VERIFICATION"',
          b'BANK_VERIF, na=False, case=False) &  transactions.amount.lt(1) , "ACCOUNT_VERIFICATION"'),
    (CAN, b'"^UPI/[CD]R", na=False, case=False) , sep_by_(transactions.description,3,4)',
          b'"^UPI/[CD]R", na=False, case=False) , sep_by_(transactions.description,2,3)'),
]
buf = {}
for p in {PNB, CAN}:
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
