# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image for the correlation scoring / formatting math.
# The graded suite exercises only pure, stdlib-only modules
# (Service/Correlation_Decisioning.py, Service/Get_Transactions_Custom_Logic.py):
# it is deterministic, fully offline, and needs no secrets.
# Locally this is the repo image built from scratchpad Dockerfile.repo.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/correlation-core-xxxxx:v1@sha256:...
FROM correlation-repo:v1

USER root
WORKDIR /app

# Plant the subtle boundary defects into the working tree. No ordinary input
# errors or changes; only untested exact-threshold / extreme-of-range /
# full-containment inputs come out wrong.
RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/Service/Correlation_Decisioning.py b/Service/Correlation_Decisioning.py
index 3ff4872..c9134f8 100644
--- a/Service/Correlation_Decisioning.py
+++ b/Service/Correlation_Decisioning.py
@@ -110,9 +110,9 @@ class CorrelationDecision:
             # Check if all words in source name are present in target name or vice versa
             common_words = source_name_words.intersection(target_name_words)
 
-            if len(common_words) == len(source_name_words) or len(common_words) == len(target_name_words):
+            if len(common_words) == len(source_name_words) and len(common_words) == len(target_name_words):
                 name_score = 100  # Full match (all words match)
-            elif len(common_words) > 0:
+            elif len(common_words) > 1:
                 name_score = 70  # Partial match (some words match)
             else:
                 name_score = 30  # No significant match
@@ -124,7 +124,7 @@ class CorrelationDecision:
         syntactic_similarity = target['correlation_details'].get('syntactic_similarity', 0)
 
         # Scale semantic similarity score out of 100
-        if 0 <= semantic_similarity <= 1:
+        if 0 <= semantic_similarity < 1:
             semantic_score = semantic_similarity * 100  # You can adjust the scaling if needed
         # else:
         #     semantic_score = 0  # Default score if not in valid range
@@ -150,7 +150,7 @@ class CorrelationDecision:
     @staticmethod
     def is_valid_correlation(source, target, threshold=70):
         score = CorrelationDecision.calculate_score(source, target)
-        return score >= threshold, score
+        return score > threshold, score
 
     @staticmethod
     def process_json(json_data, threshold=70):
diff --git a/Service/Get_Transactions_Custom_Logic.py b/Service/Get_Transactions_Custom_Logic.py
index 92dd7e7..5f16100 100644
--- a/Service/Get_Transactions_Custom_Logic.py
+++ b/Service/Get_Transactions_Custom_Logic.py
@@ -100,7 +100,7 @@ class GetTransactionsCustom:
         if day and month_name and year:
             # Get the appropriate suffix for the day
             day = int(day)
-            if 4 <= day <= 20 or 24 <= day <= 30:
+            if 4 <= day <= 20 or 23 <= day <= 30:
                 suffix = "th"
             else:
                 suffix = ["st", "nd", "rd"][day % 10 - 1]
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Collapse history: planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app
