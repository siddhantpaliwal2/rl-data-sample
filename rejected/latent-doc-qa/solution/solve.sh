#!/bin/sh
# Oracle solution — reverse-applies the planted defect patch at base_commit,
# restoring the correct boundary math in the document Q&A hybrid-retrieval
# helpers (all within agent/documents/document_qa/retrieval.py).
set -eu
cd /app
git apply -R --check - <<'DEFECT_PATCH_EOF' && git apply -R - <<'DEFECT_PATCH_EOF'
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
 
DEFECT_PATCH_EOF
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
 
DEFECT_PATCH_EOF
