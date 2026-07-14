# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image for the loanGen chat pipeline (intent routing,
# loan-amount extraction, contextual greeting, missing-data response, and the
# credit-enrichment default). Fully offline and deterministic; needs no secrets
# beyond the JWT_SECRET_KEY already baked into loangenus-repo:v1.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset to the clean base HEAD, then plant the defects into the working tree.
# Every existing test still passes with these applied, and correct behavior on
# the common inputs is preserved; the corruption bites only inputs the visible
# suite (and casual spot checks) never feed.
RUN git reset --hard 04b8abc5515c22bdb7a2da32bf2719c8ac702174 && git clean -fdq

RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/loangen-agent/agent/context_builder.py b/loangen-agent/agent/context_builder.py
index c3d0fbf..3fedb80 100644
--- a/loangen-agent/agent/context_builder.py
+++ b/loangen-agent/agent/context_builder.py
@@ -260,14 +260,14 @@ class ContextBuilder:
         missing_keys = context.get("missing_sources", [])
 
         # Which required sources are actually missing?
-        missing_required = [k for k in required if k in missing_keys]
+        missing_required = [k for k in required if k not in missing_keys]
         if not missing_required:
             return None   # All required data is available — proceed normally
 
         # Build the response structure
         missing_sources = [SOURCE_META[k] for k in missing_required if k in SOURCE_META]
 
-        connected_keys = [k for k in ["credit", "bank", "quickbooks"] if k not in missing_keys]
+        connected_keys = [k for k in ["credit", "bank", "quickbooks"] if k in missing_keys]
         connected_names = [SOURCE_META[k]["label"] for k in connected_keys if k in SOURCE_META]
 
         # Describe what can and can't be analysed
diff --git a/loangen-agent/agent/core/config.py b/loangen-agent/agent/core/config.py
index 2734229..bc1b12e 100644
--- a/loangen-agent/agent/core/config.py
+++ b/loangen-agent/agent/core/config.py
@@ -348,7 +348,7 @@ class Settings(BaseSettings):
     # When true, ``personal_credit`` chat enrichment loads the latest raw credit
     # JSON from Mongo (credit_reports, then raw_credit_reports) and attaches the
     # full payload to the user message for the LLM. Does not mutate session context.
-    chat_enrichment_refresh_credit_from_raw_db: bool = True
+    chat_enrichment_refresh_credit_from_raw_db: bool = False
 
     # Max characters of serialized raw credit JSON injected into chat (0 = no limit).
     chat_credit_report_json_max_chars: int = 0
diff --git a/loangen-agent/agent/pipeline.py b/loangen-agent/agent/pipeline.py
index 6f3c157..b6199f9 100644
--- a/loangen-agent/agent/pipeline.py
+++ b/loangen-agent/agent/pipeline.py
@@ -206,7 +206,7 @@ class LoanGenPipeline:
             )
 
         # Some connected
-        if connected:
+        if connected is not None:
             connected_str = ", ".join(connected)
             missing_str   = " and ".join(missing) if missing else ""
             base = f"Welcome! I have access to your {connected_str}."
@@ -233,7 +233,7 @@ class LoanGenPipeline:
         """Detect the user's intent from their message."""
         message_lower = message.lower().strip()
 
-        for intent, patterns in INTENT_PATTERNS.items():
+        for intent, patterns in sorted(INTENT_PATTERNS.items()):
             for pattern in patterns:
                 if re.search(pattern, message_lower):
                     return intent
@@ -721,7 +721,7 @@ class LoanGenPipeline:
         for pattern in amount_patterns:
             match = re.search(pattern, message, re.IGNORECASE)
             if match:
-                raw = match.group(1).replace(",", "")
+                raw = match.group(1).replace(",", "").replace(".", "")
                 amount = float(raw)
                 if "k" in pattern.lower() or "thousand" in pattern:
                     amount *= 1_000
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Collapse history: the planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
