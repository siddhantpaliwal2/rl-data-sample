# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# Planted-defect task image for the credit-PDF line classification / normalization.
# The credit-PDF pipeline suite is deterministic, fully offline, and needs no
# secrets beyond the JWT_SECRET_KEY already baked into loangenus-repo:v1.
# Locally this is the repo image built from the loangenus root Dockerfile.
# On the platform, replace with the approved registry reference, e.g.
# FROM <your-registry>/repo-images/loangenus-xxxxx:v1@sha256:...
FROM loangenus-repo:v1

USER root
WORKDIR /app

# Reset to the clean base HEAD, then plant the subtle boundary defects into the
# working tree. Every existing test still passes with these applied; only
# untested edge inputs are wrong.
RUN git reset --hard 04b8abc5515c22bdb7a2da32bf2719c8ac702174 && git clean -fdq

RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/loangen-agent/agent/documents/credit_pdf/junk_filter.py b/loangen-agent/agent/documents/credit_pdf/junk_filter.py
index 181a58e..c7202fb 100644
--- a/loangen-agent/agent/documents/credit_pdf/junk_filter.py
+++ b/loangen-agent/agent/documents/credit_pdf/junk_filter.py
@@ -36,7 +36,7 @@ def is_junk_creditor_name(creditor: str) -> bool:
         return True
     if not is_plausible_creditor_line(name):
         return True
-    if name.lower() in _UNKNOWN_CREDITOR:
+    if name in _UNKNOWN_CREDITOR:
         return True
     for pattern in _JUNK_CREDITOR_PATTERNS:
         if pattern.search(name):
@@ -65,7 +65,7 @@ def dedupe_tradelines(tradelines: List[ParsedTradeline]) -> List[ParsedTradeline
     seen: set[str] = set()
     out: List[ParsedTradeline] = []
     for tl in tradelines:
-        key = f"{(tl.creditor or '').lower()}|{tl.account_number or ''}"
+        key = f"{(tl.creditor or '')}|{tl.account_number or ''}"
         if key in seen:
             continue
         seen.add(key)
diff --git a/loangen-agent/agent/documents/credit_pdf/normalize.py b/loangen-agent/agent/documents/credit_pdf/normalize.py
index 3985c7d..fbfc459 100644
--- a/loangen-agent/agent/documents/credit_pdf/normalize.py
+++ b/loangen-agent/agent/documents/credit_pdf/normalize.py
@@ -82,7 +82,7 @@ def bureau_tags_from_text(text: str) -> Set[str]:
     """Map TUC-B1 / EXP-B1 / EQX-B1 (and comma-separated) to bureau keys."""
     found: Set[str] = set()
     upper = (text or "").upper()
-    for token in re.findall(r"\b(TUC|EXP|EQX|TU|EFX)-B\d*\b", upper):
+    for token in re.findall(r"\b(TUC|EXP|EQX|TU)-B\d*\b", upper):
         prefix = token.split("-")[0]
         bureau = _BUREAU_TAG_MAP.get(prefix)
         if bureau:
@@ -115,7 +115,7 @@ def is_plausible_creditor_line(line: str) -> bool:
         return False
     if re.match(r"^\d{3}[-\s]?\d{2}[-\s]?\d{4}$", line):
         return False
-    if re.match(r"^[\d\$\.,\s%]+$", line):
+    if re.match(r"^[\d\$\.,\s%]+", line):
         return False
     if line.lower().startswith("http"):
         return False
@@ -150,7 +150,7 @@ def is_address_or_contact_line(line: str) -> bool:
     if re.match(r"^\d+\s+\w", text):  # street address
         return True
     if re.match(
-        r"^(blvd|st|street|ave|avenue|dr|drive|rd|road|way|lane|ln|ct|court|ste|suite)\.?$",
+        r"^(blvd|st|street|ave|avenue|dr|drive|rd|road|way|lane|ln|ct|court|ste|suite)\.?",
         text,
         re.I,
     ):
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Collapse history: planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app/loangen-agent
