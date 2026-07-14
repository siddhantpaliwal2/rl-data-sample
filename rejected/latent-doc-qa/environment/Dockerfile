# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image for the document Q&A hybrid-retrieval helpers
# (agent/documents/document_qa/retrieval.py). The search-term / phrase / label
# and reciprocal-rank-fusion math is deterministic, fully offline, and needs no
# secrets beyond the JWT_SECRET_KEY already baked into loangenus-repo:v1.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset to the clean base HEAD, then plant the subtle boundary defects into the
# working tree. Every existing test still passes with these applied; only
# untested minimal-width / exact-minimum-length / degenerate inputs are wrong.
RUN git reset --hard 04b8abc5515c22bdb7a2da32bf2719c8ac702174 && git clean -fdq

RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/loangen-agent/agent/documents/document_qa/retrieval.py b/loangen-agent/agent/documents/document_qa/retrieval.py
index 5fd8fdc..1083f58 100644
--- a/loangen-agent/agent/documents/document_qa/retrieval.py
+++ b/loangen-agent/agent/documents/document_qa/retrieval.py
@@ -154,7 +154,7 @@ def extract_search_terms(question: str) -> Tuple[List[str], List[str]]:
 
         phrase = match.group(1).strip().lower()
 
-        if len(phrase) >= 5 and phrase not in phrases:
+        if len(phrase) > 5 and phrase not in phrases:
 
             phrases.append(phrase)
 
@@ -292,7 +292,7 @@ def extract_search_terms(question: str) -> Tuple[List[str], List[str]]:
 
     }
 
-    terms = [w for w in raw_words if len(w) >= 3 and w not in stop]
+    terms = [w for w in raw_words if len(w) >= 4 and w not in stop]
 
     # Dedupe while preserving order.
 
@@ -422,7 +422,7 @@ def merge_hybrid_hits(
 
             return hit
 
-        existing.vector_score = max(existing.vector_score, hit.vector_score)
+        existing.vector_score = min(existing.vector_score, hit.vector_score)
 
         existing.keyword_score = max(existing.keyword_score, hit.keyword_score)
 
@@ -482,7 +482,7 @@ def extract_labeled_amounts(text: str, *, limit: int = 40) -> Dict[str, float]:
 
         label = re.sub(r"\s+", " ", match.group(1)).strip().lower()
 
-        if len(label) < 3 or label in facts:
+        if len(label) <= 3 or label in facts:
 
             continue
 
@@ -496,7 +496,7 @@ def extract_labeled_amounts(text: str, *, limit: int = 40) -> Dict[str, float]:
 
             continue
 
-        if len(facts) >= limit:
+        if len(facts) > limit:
 
             break
 
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Collapse history: planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
