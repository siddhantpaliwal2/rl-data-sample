# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset the working tree to the broken base state the agent starts from
RUN git reset --hard 2a36b03d4b42746716af8a41e409460aa0e481ab && git clean -fdq

# No task-specific env is required: the CRE qualification tests call the
# engine, recommendation, and schema code directly and pass with the image's
# baked-in JWT/LIVEKIT stubs alone. The suite is fully deterministic and offline.

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
