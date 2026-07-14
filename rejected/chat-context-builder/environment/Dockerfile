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
RUN git reset --hard 2dac686ab097d5fd3d8094e98159a9475efc802b \
    && git clean -fdq \
    && rm -rf .git \
    && git init -qb main \
    && git config user.email t@t \
    && git config user.name t \
    && git add -A \
    && git commit -qm "import codebase"

# The advisor chat context/qualification suite is fully mocked and offline;
# JWT_SECRET_KEY and LIVEKIT_* are already baked into the base image and no
# additional environment is required to import or exercise the tested code.

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
