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

# Test-only dependency: an in-memory Mongo so the verifier can exercise the
# real persistence-backed service entry points fully offline (no live database).
RUN pip install --no-cache-dir --root-user-action=ignore mongomock_motor==0.0.35

# Re-key the repository so the planted (base) state is a single opaque commit:
# no fix commit, no diff, no reflog for the agent to mine.
RUN rm -rf .git \
    && git init -qb main \
    && git config user.email t@t \
    && git config user.name t \
    && git add -A \
    && git commit -qm "import codebase"

# Test-only environment: enable all three credit bureaus so the verification
# cascade has providers to try. All values are dummies — the Array HTTP client
# is injected as a fake and the suite is fully offline.
ENV BUREAU_TRANSUNION=true \
    BUREAU_EQUIFAX=true \
    BUREAU_EXPERIAN=true \
    ARRAY_APP_KEY=test-array-key

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
