# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect (LATENT-BUG) task image for the LinkShortner FastAPI backend.
#
# The base is the clean repo image: a python:3.11-slim layer with the backend
# subtree at /app and a curated, security-reviewed dependency set pre-installed
# (see the repo image build; the repo's own requirements.txt is UTF-16 and lists
# several typosquat-shaped packages that no code under test imports, so it is
# NOT installed verbatim). Locally this is `linkshort-repo:v1`; on the platform
# replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/linkshort-xxxxx:v1@sha256:...
FROM linkshort-repo:v1

USER root
WORKDIR /app

# Plant the five latent single-token boundary defects into the clean working
# tree (config.py x2, main.py, services.py x2), and remove the ONE visible test
# (tests/test_links.py::test_paginated_list) that the list_links offset defect
# would otherwise turn red — so the agent-visible suite stays fully green. That
# test's removal, like the defects themselves, is invisible once history is
# collapsed below. The gold boundary suite enters the tree only at grade time,
# via tests/config.json's test_patch.
COPY defects_code.patch /tmp/defects_code.patch
COPY remove_pagination_test.patch /tmp/remove_pagination_test.patch
RUN git apply /tmp/defects_code.patch \
 && git apply /tmp/remove_pagination_test.patch \
 && rm -f /tmp/defects_code.patch /tmp/remove_pagination_test.patch

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

# The only runtime input the boundary suite needs: constructing Settings /
# importing link_shortener.main requires LINK_SHORTENER_DATABASE_URL. Not a
# secret — an in-memory SQLite URL is sufficient for the deterministic suite.
ENV LINK_SHORTENER_DATABASE_URL=sqlite://

WORKDIR /app
