#!/bin/sh
# Oracle solution — restores the correct boundary logic in the two targeted
# source files by exact single-token byte-substring replacement (the reverse of
# the plant). CRLF-safe; no diff-context matching. This is the minimal correct
# fix; any equivalent boundary correction that satisfies the gold tests also
# passes. Each planted token must occur exactly once, or the script aborts.
set -eu

ROOT=""
for d in /app /testbed; do
    if [ -d "$d/frontend/src/lib" ] && [ -d "$d/backend/src/services" ]; then
        ROOT="$d"
        break
    fi
done
[ -n "$ROOT" ] || { echo "solve.sh: repo root not found" >&2; exit 1; }

python3 - "$ROOT" <<'SOLVE_EOF'
import sys
ROOT = sys.argv[1]
FMT = ROOT + "/frontend/src/lib/format.ts"
SRCH = ROOT + "/backend/src/services/search.services.ts"
# (file, planted-token, correct-token)
EDITS = [
    (FMT, "if (minutes > 60) {", "if (minutes >= 60) {"),
    (FMT, "(bytes / (1024 * 1024)).toFixed(0)", "(bytes / (1024 * 1024)).toFixed(1)"),
    (SRCH, "value.includes(query)", "value.toLowerCase().includes(query)"),
    (SRCH, "return results.slice(0, limit + 1);", "return results.slice(0, limit);"),
    (SRCH, "if (index <= 0) {", "if (index < 0) {"),
]
for path, planted, correct in EDITS:
    data = open(path, "r", encoding="utf-8", newline="").read()
    n = data.count(planted)
    if n != 1:
        raise SystemExit("solve: expected exactly 1 of %r in %s, found %d" % (planted, path, n))
    open(path, "w", encoding="utf-8", newline="").write(data.replace(planted, correct, 1))
    print("fixed %s" % path)
SOLVE_EOF
