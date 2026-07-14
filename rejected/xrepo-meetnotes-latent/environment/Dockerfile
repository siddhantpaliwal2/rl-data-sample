# syntax=docker/dockerfile:1
# Planted-defect task image for the meeting-notes-app pure library utilities.
# The targeted code is deterministic and fully offline; no secrets, no network.
# Locally this is built from the base image produced by ./base/Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/meetnotes-xxxxx:v1@sha256:...
FROM meetnotes-repo:v1

USER root
WORKDIR /app

# Plant the five subtle boundary defects into the clean working tree by exact
# single-token byte-substring replacement (CRLF-safe; no diff-context matching).
# Each target must occur exactly once, or the build aborts — a silent mis-plant
# is impossible. Every mid-range assertion in the gold suite still passes with
# these applied; only untested edge inputs (a duration exactly on the hour, a
# megabyte-scale size, a case-mismatched keyword, a match set larger than the
# limit, a match at the very start of a transcript) come out wrong.
RUN cat > /tmp/plant.py <<'PLANT_EOF'
import sys
ROOT = "/app"
FMT = ROOT + "/frontend/src/lib/format.ts"
SRCH = ROOT + "/backend/src/services/search.services.ts"
EDITS = [
    (FMT, "if (minutes >= 60) {", "if (minutes > 60) {"),
    (FMT, "(bytes / (1024 * 1024)).toFixed(1)", "(bytes / (1024 * 1024)).toFixed(0)"),
    (SRCH, "value.toLowerCase().includes(query)", "value.includes(query)"),
    (SRCH, "return results.slice(0, limit);", "return results.slice(0, limit + 1);"),
    (SRCH, "if (index < 0) {", "if (index <= 0) {"),
]
for path, old, new in EDITS:
    data = open(path, "r", encoding="utf-8", newline="").read()
    n = data.count(old)
    if n != 1:
        raise SystemExit("plant: expected exactly 1 of %r in %s, found %d" % (old, path, n))
    open(path, "w", encoding="utf-8", newline="").write(data.replace(old, new, 1))
    print("planted %s" % path)
PLANT_EOF
RUN python3 /tmp/plant.py && rm -f /tmp/plant.py

# Collapse history: the planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app
