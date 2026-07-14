# check=skip=SecretsUsedInArgOrEnv
# Flagged ENV values are dummy test-only stubs — the suite is mocked and offline.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset the working tree to the broken base state the agent starts from, then
# rebuild a fresh single-commit history so the future fix commit (and every
# other real commit) is not discoverable via git log / git show / reflog.
RUN git reset --hard 5ea5f7533f01495f0259d11a0ff7384d4871857b \
    && git clean -fdq \
    && rm -rf .git \
    && git init -qb main \
    && git config user.email t@t \
    && git config user.name t \
    && git add -A \
    && git commit -qm "import codebase"

# Test-only environment: dummy QuickBooks OAuth endpoints so the signed-state
# helpers are deterministic. All values are stubs — the suite is fully mocked
# and offline (JWT_SECRET_KEY is baked into the base image and signs the state).
ENV FRONTEND_URL=https://app.example \
    QUICKBOOKS_CLIENT_ID=test-qb-client \
    QUICKBOOKS_REDIRECT_URI=https://api.test/api/v1/quickbooks/oauth/callback \
    QUICKBOOKS_OAUTH_SUCCESS_REDIRECT=https://app.example/user/dashboard \
    QUICKBOOKS_OAUTH_ERROR_REDIRECT=https://app.example/user/dashboard

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
