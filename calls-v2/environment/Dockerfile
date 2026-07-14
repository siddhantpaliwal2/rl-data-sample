# check=skip=SecretsUsedInArgOrEnv
# Flagged ENV values are dummy test-only stubs — the suite is mocked and offline.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset the working tree to the broken base state the agent starts from, then
# NEUTRALIZE git history so the upstream fix commit cannot be recovered from the
# object store / reflog / log. After this the repo is a single "import codebase"
# commit whose tree is exactly the base state; test.sh only needs *a* .git to
# locate the repo root and apply the gold test patch.
RUN git reset --hard 9c4590385df3bac827fc5b3082b25c70e274da39 \
 && git clean -fdq \
 && rm -rf .git \
 && git init -qb main \
 && git config user.email t@t \
 && git config user.name t \
 && git add -A \
 && git commit -qm "import codebase"

# Test-only environment: these flags open the direct/inbound calling code paths so
# the routing logic runs instead of the "not accepting calls" short-circuit, and
# they satisfy the pydantic Settings validation when the calls / smbcontacts
# services import. Every credential is a dummy stub — the suite is fully mocked
# and offline (no Twilio or Cartesia client is ever constructed).
ENV CALLS_INBOUND_ENABLED=true \
    CALLS_DIRECT_ENABLED=true \
    TWILIO_CALLS_ENABLED=true \
    TWILIO_ACCOUNT_SID=ACtest0000000000000000000000000000 \
    TWILIO_AUTH_TOKEN=test-auth-token \
    TWILIO_API_KEY_SID=SKtest0000000000000000000000000000 \
    TWILIO_API_KEY_SECRET=test-api-secret \
    TWILIO_TWIML_APP_SID=APtest0000000000000000000000000000 \
    PUBLIC_API_BASE_URL=https://api.test.invalid \
    TWILIO_OUTBOUND_CALLER_ID=+15550001111

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
