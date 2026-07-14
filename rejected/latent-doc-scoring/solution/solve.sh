#!/bin/sh
# Oracle solution — restores the correct boundary math in the document
# layout-extraction / report-assembly / portfolio-aggregation modules by
# reversing each planted single-token slip (zero-amount inclusion, table-cell
# column bound, the minimum-chartable-amounts gate, the card-return cap, and
# the occupancy-weight division guard). Robust to whitespace: each edit targets
# a unique substring.
set -eu
cd /app
python3 - <<'PYEOF'
edits = [
    ("agent/documents/extraction/table_text.py",
     "if value > 0:",
     "if value >= 0:"),
    ("agent/documents/extraction/table_text.py",
     "0 <= col_idx <= column_count",
     "0 <= col_idx < column_count"),
    ("agent/documents/report/builders.py",
     "if len(chart_points) > 2:",
     "if len(chart_points) >= 2:"),
    ("agent/documents/report/builders.py",
     "if len(cards) > limit:",
     "if len(cards) >= limit:"),
    ("agent/documents/deal_summary/portfolio.py",
     "if occ_weight >= 0:",
     "if occ_weight > 0:"),
]
base = "/app/loangen-agent/"
for rel, bad, good in edits:
    p = base + rel
    with open(p) as f:
        s = f.read()
    assert s.count(bad) == 1, (rel, bad, s.count(bad))
    with open(p, "w") as f:
        f.write(s.replace(bad, good, 1))
print("restored", len(edits), "boundaries")
PYEOF
