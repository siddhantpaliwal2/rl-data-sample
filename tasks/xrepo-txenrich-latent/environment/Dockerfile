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
# only untested exact-length, adjacency, account-type and fixed-layout string
# inputs (a specific reference length, an offsetting row, a savings-salary path,
# a capture-group / segment slice) come out wrong.
RUN python3 - <<'PLANT_EOF'
import sys
BASE = "/app/categorizationapp/categorizationapp/BankScripts"
HDFC, ICICI = f"{BASE}/HDFC.py", f"{BASE}/ICICI.py"
EDITS = [
    (HDFC, b'transactions.remark.str.len().eq(16)',
           b'transactions.remark.str.len().eq(15)'),
    (HDFC, b'transactions.type.eq("CREDIT") & (accountType=="SAVING") , "SALARY"',
           b'transactions.type.eq("CREDIT") & (accountType=="SAVINGS") , "SALARY"'),
    (HDFC, b'transactions.description.eq(transactions.description.shift(periods=1)) & transactions.description.str.contains("IMPS|NEFT|',
           b'transactions.description.eq(transactions.description.shift(periods=2)) & transactions.description.str.contains("IMPS|NEFT|'),
    (ICICI, b'pat="TRFR (TO|FROM):(.*)", index=1',
            b'pat="TRFR (TO|FROM):(.*)", index=0'),
    (ICICI, b'transactions.description.str.count("/").eq(3)  , sep_by_(transactions.description,3,4)',
            b'transactions.description.str.count("/").eq(3)  , sep_by_(transactions.description,2,3)'),
]
buf = {}
for p in {HDFC, ICICI}:
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
