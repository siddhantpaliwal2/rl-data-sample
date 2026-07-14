# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image for the document layout-extraction / report-assembly
# / portfolio-aggregation math. The graded suite exercises pure, deterministic,
# fully-offline functions under agent/documents/ (extraction/table_text.py,
# report/builders.py, deal_summary/portfolio.py). No secrets beyond the
# JWT_SECRET_KEY already baked into loangenus-repo:v1 are required.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset to the clean base HEAD, then plant the subtle boundary defects into the
# working tree. Every existing test still passes with these applied; only
# untested exact-boundary inputs (a zero-valued amount, a cell one past the
# table width, the minimum number of chartable amounts, the card-return cap,
# and a zero occupancy-weight denominator) come out wrong.
RUN git reset --hard 04b8abc5515c22bdb7a2da32bf2719c8ac702174 && git clean -fdq

RUN python3 - <<'PYEOF'
edits = [
    ("agent/documents/extraction/table_text.py",
     "if value >= 0:",
     "if value > 0:"),
    ("agent/documents/extraction/table_text.py",
     "0 <= col_idx < column_count",
     "0 <= col_idx <= column_count"),
    ("agent/documents/report/builders.py",
     "if len(chart_points) >= 2:",
     "if len(chart_points) > 2:"),
    ("agent/documents/report/builders.py",
     "if len(cards) >= limit:",
     "if len(cards) > limit:"),
    ("agent/documents/deal_summary/portfolio.py",
     "if occ_weight > 0:",
     "if occ_weight >= 0:"),
]
base = "/app/loangen-agent/"
for rel, old, new in edits:
    p = base + rel
    with open(p) as f:
        s = f.read()
    assert s.count(old) == 1, (rel, old, s.count(old))
    with open(p, "w") as f:
        f.write(s.replace(old, new, 1))
print("planted", len(edits), "defects")
PYEOF

# Collapse history: planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
