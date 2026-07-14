# check=skip=SecretsUsedInArgOrEnv
# Flagged ENV values are dummy test-only stubs — the suite is mocked and offline.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset the working tree to the broken base state the agent starts from
RUN git reset --hard ba5fa0a3e27c5b5a74e86d26a77271bfca1d661d && git clean -fdq

# Test-only environment: feature flags open the ingestion code paths; all
# endpoint/key values are dummies — the suite is fully mocked and offline.
ENV DOCUMENT_INGESTION_ENABLED=true \
    DOCUMENT_QA_ENABLED=true \
    AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT=https://test.invalid \
    AZURE_DOCUMENT_INTELLIGENCE_KEY=test-key \
    QDRANT_URL=http://localhost:6333 \
    QDRANT_API_KEY=test \
    EMBEDDING_DEPLOYMENT_NAME=test-embed \
    LLM_API_KEY=test-llm-key

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
