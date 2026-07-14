# syntax=docker/dockerfile:1
# Base repo image for the meeting-notes-app pure-library boundary task.
#
# This is a clean, isolated, fully-offline slice of the meeting-notes-app repo:
# the pure frontend formatting helpers (frontend/src/lib/format.ts) and the pure
# backend keyword-search layer (backend/src/services/search.services.ts), plus
# small offline test doubles for the search service's data-source collaborators
# (Firestore / embeddings / vector store / usage) so the search entrypoint can
# be exercised with no network. Nothing here needs `bun install` — the code has
# no third-party runtime dependencies and the gold suite uses only `bun:test`.
#
# Produces meetnotes-repo:v1. The task image (../Dockerfile) builds FROM this,
# plants the defects, and seals git history.
FROM oven/bun:1

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends git python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY app/ /app/
