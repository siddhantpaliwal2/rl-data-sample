# check=skip=SecretsUsedInArgOrEnv
# Flagged ENV values are dummy test-only stubs — the suite is mocked and offline.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset the working tree to the broken base state the agent starts from
RUN git reset --hard 894425990cd42bb4d37b813db52e14c43d8106a1 && git clean -fdq

# Test-only environment: enable all three credit bureaus so the verification
# cascade has providers to try. All values are dummies — the Array HTTP client
# is mocked and the suite is fully offline.
ENV BUREAU_TRANSUNION=true \
    BUREAU_EQUIFAX=true \
    BUREAU_EXPERIAN=true \
    ARRAY_APP_KEY=test-array-key

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
