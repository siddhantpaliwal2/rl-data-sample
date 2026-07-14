# check=skip=SecretsUsedInArgOrEnv
# Flagged ENV values are dummy test-only stubs — the suite is mocked and offline.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset the working tree to the broken base state the agent starts from
RUN git reset --hard e8e4a09379eeee13cc9ea058b87054b77b3b338d && git clean -fdq

# Collapse all git history into a single "import codebase" commit so the planted
# base state cannot be mined via reflog, dangling objects, or the original
# fix commit. test.sh only needs *a* .git root to apply the gold test patch.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

# This task's gold tests exercise agent.plaid.report_service with all database
# access mocked; importing it needs no extra runtime configuration beyond the
# credentials already baked into the base repo image. No task-specific env vars
# are required.

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
