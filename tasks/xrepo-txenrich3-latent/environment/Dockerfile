# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image for the bank-transaction enrichment engine.
# The per-bank categorization logic is deterministic and fully offline; no
# secrets or network are required. Locally this is the repo image built from
# the transaction-enrichment-python tree (python 3.11-slim + pinned numpy/pandas
# so the 2022-era np.select logic runs unchanged). On the platform, replace with
# the approved registry reference, e.g.
# FROM <your-registry>/repo-images/txenrich-xxxxx:v1@sha256:...
FROM txenrich-repo:v1

USER root
WORKDIR /app
RUN git config --global --add safe.directory /app

# Plant the subtle boundary / structural defects into the working tree, plus a
# small substrate normalization that is NOT a defect. Byte level replacement
# preserves the files' original CRLF endings, so only the changed lines differ.
# Every ordinary transaction still enriches correctly; only untested exact-width,
# sentinel-amount, account-type and fixed-layout inputs come out wrong.
#
# DEFECTS (reverted by the oracle) are the five single-token slips below.
# SUBSTRATE (present in BOTH planted and correct states, never reverted) rewrites
# the two adjacent account-verification sibling lines from string-sentinel
# `amount.isin(["1"...])` to numeric `amount.eq(1)/isin([1,-1])`. Those siblings
# fire on no test input either way (they gate on BANK_VER text / a DEBIT type that
# the sentinel rows do not carry), so this changes no observable output; it only
# removes a string-vs-numeric decoy that was diverting solvers into "fixing" the
# siblings' dtype instead of the planted eq-sentinel slip on the mandate line.
RUN python3 - <<'PLANT_EOF'
import sys
BASE = "/app/categorizationapp/categorizationapp/BankScripts"
IDBI, INDUS = f"{BASE}/IDBI.py", f"{BASE}/Indusind.py"
# Substrate normalization (NOT defects): numeric sentinel form on the two
# adjacent account-verification siblings, so the mandate line's correct eq(1) is
# pinned by an identical adjacent twin and there is no dtype anomaly to chase.
SUBSTRATE = [
    (INDUS, b'transactions.amount.isin(["1","-1"])',
            b'transactions.amount.isin([1,-1])'),
    (INDUS, b'transactions.amount.isin(["1"]) & transactions.type.eq("DEBIT")',
            b'transactions.amount.eq(1) & transactions.type.eq("DEBIT")'),
]
EDITS = [
    (INDUS, b'"^[0-9]{5,6}$",na=False, case=False) & transactions.type.eq("DEBIT") , "CHEQUE_PAID"',
            b'"^[0-9]{5}$",na=False, case=False) & transactions.type.eq("DEBIT") , "CHEQUE_PAID"'),
    (INDUS, b'transactions.amount.eq(1) & transactions.description.str.contains("MANDATE|Mandate"',
            b'transactions.amount.eq(2) & transactions.description.str.contains("MANDATE|Mandate"'),
    (INDUS, b'(accountType=="SAVING") , "CARD_PAYMENT_REVERSAL"',
            b'(accountType=="SAVINGS") , "CARD_PAYMENT_REVERSAL"'),
    (IDBI, b'"^ACH-BD-NACH", na=False, case=False) , sep_by_dash(transactions.description,3,4)',
           b'"^ACH-BD-NACH", na=False, case=False) , sep_by_dash(transactions.description,2,3)'),
    (IDBI, b'pat="[0-9]{10,} (.*)", index=0',
           b'pat="[0-9]{10,} (.*)", index=1'),
]
buf = {}
for p in {IDBI, INDUS}:
    buf[p] = open(p, "rb").read()
# Apply substrate normalization first, then plant the defects.
for p, old, new in SUBSTRATE + EDITS:
    if buf[p].count(old) != 1:
        print("ABORT anchor", p, old[:60]); sys.exit(2)
    buf[p] = buf[p].replace(old, new)
for p, data in buf.items():
    open(p, "wb").write(data)
print("planted 5 defects + 2 substrate normalizations OK")
PLANT_EOF

# Collapse history: planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git categorizationapp/*.egg-info categorizationapp/categorizationapp.egg-info \
 && git init -qb main && git config user.email t@t && git config user.name t \
 && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app
