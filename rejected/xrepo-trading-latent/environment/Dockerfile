# syntax=docker/dockerfile:1
# Planted-defect task image for the native trading display formatters.
#
# This is a minimal, self-contained workspace: rather than install the whole
# TradingApp monorepo, it carries only apps/native/lib/formatters.ts and its
# existing test into a tiny package so `bun test` runs the formatters fully
# offline with no third-party dependencies. The build context (this directory)
# supplies the already-planted source, the visible test, and package.json.
#
# The verifier harness needs git (to apply the gold test patch and locate the
# repo root) and python3 (test.sh / parser.py); the oven/bun base ships
# neither, so they are installed at build time. Test execution itself is
# offline and needs no network.
FROM oven/bun:1

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends git python3 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Bring in the ALREADY-PLANTED formatters, the existing visible test, and the
# package manifest. The gold boundary suite is NOT present here — it enters the
# tree only at grade time via tests/config.json's test_patch.
COPY package.json /app/package.json
COPY lib/formatters.ts /app/lib/formatters.ts
COPY test/formatters.test.ts /app/test/formatters.test.ts

# Collapse history: the planted state is the single committed state, so the
# defects are not recoverable via git diff / log / reflog. A fresh .git also
# gives test.sh a repo root to apply the gold patch into.
RUN rm -rf .git \
 && git init -qb main \
 && git config user.email t@t \
 && git config user.name t \
 && git add -A \
 && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app
