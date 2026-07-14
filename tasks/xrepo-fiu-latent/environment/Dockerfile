# syntax=docker/dockerfile:1
# Planted-defect task image for the FIU-adapter parsing / validation / timestamp
# helpers. The boundary suite is deterministic, pure-input JUnit 5 (no Spring
# context, no DB, no network) and runs fully offline: fiu-repo:v1 warms the
# Maven cache, installs the sibling modules, and warms the Surefire
# JUnit-platform provider at build time.
#
# Locally this is the repo image built from the adjacent Dockerfile.repo
# (maven:3.9-eclipse-temurin-8 + git + python3, sibling modules
# installed, LF-normalized working tree of the fiu_adapter repo). On the
# platform, replace with the approved registry reference, e.g.
# FROM <your-registry>/repo-images/fiu-xxxxx:v1@sha256:...
FROM fiu-repo:v1

USER root
WORKDIR /app

# Plant the subtle boundary defects into the working tree. Every kept path still
# behaves correctly with these applied; only untested exact-edge inputs (a
# standard vs URL-safe base64 alphabet, the token after '@' vs before it, the
# final UUID group length, a whitespace-only string, and a 24- vs 12-hour clock)
# are wrong.
RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/webservice/src/main/java/com/finbit/fiuadapter/webservice/constants/GeneralConstants.java b/webservice/src/main/java/com/finbit/fiuadapter/webservice/constants/GeneralConstants.java
index 41a3098..6925b08 100644
--- a/webservice/src/main/java/com/finbit/fiuadapter/webservice/constants/GeneralConstants.java
+++ b/webservice/src/main/java/com/finbit/fiuadapter/webservice/constants/GeneralConstants.java
@@ -40,7 +40,7 @@ public class GeneralConstants {
     public static final String INVALID_CONSENT_STATUS_MSG = "Consent status value should be as given [ACTIVE, PAUSED, REVOKED, EXPIRED, PENDING, REJECTED]";
     public static final String INVALID_CONSENT_STATUS = "InvalidConsentStatus";
     public static final String INVALID_VERSION = "Invalid Api version";
-    public static final String VALID_PATTERN_UUID = "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$";
+    public static final String VALID_PATTERN_UUID = "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{11}$";
     public static final String FI_DATA_READY = "FI_DATA_READY";
     public static final String NOTIFIER_AA = "AA";
     public static final String INVALID_NOTIFIER = "InvalidNotifier";
diff --git a/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/consentinit/ConsentInitServiceImpl.java b/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/consentinit/ConsentInitServiceImpl.java
index e6e340f..961a7e8 100644
--- a/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/consentinit/ConsentInitServiceImpl.java
+++ b/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/consentinit/ConsentInitServiceImpl.java
@@ -94,7 +94,7 @@ public class ConsentInitServiceImpl implements ConsentInitService {
             {
                 List<String> customerIdSplit = Arrays.asList(customerId.trim().split("@"));
                 if(customerIdSplit.size() > 1) {
-                    return "@" + customerId.trim().split("@")[1].trim();
+                    return "@" + customerId.trim().split("@")[0].trim();
                 }else{
                     log.error("Invalid Customer ID : " + customerId);
                     throw new DataException(HttpStatus.BAD_REQUEST.getReasonPhrase(), "Invalid Customer ID",
diff --git a/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/Base64Decoder.java b/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/Base64Decoder.java
index 7b4c171..7458c4a 100644
--- a/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/Base64Decoder.java
+++ b/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/Base64Decoder.java
@@ -16,7 +16,7 @@ public class Base64Decoder {

     public static Object getDecodedObject( String body, Class<?> type ) throws JWSSignatureException
     {
-        return JsonUtil.convertJsonToObject(new String(Base64.getUrlDecoder().decode(body), StandardCharsets.UTF_8),
+        return JsonUtil.convertJsonToObject(new String(Base64.getDecoder().decode(body), StandardCharsets.UTF_8),
                 type);

     }
diff --git a/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/DateTimeUtil.java b/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/DateTimeUtil.java
index b0dd085..97b6a24 100644
--- a/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/DateTimeUtil.java
+++ b/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/DateTimeUtil.java
@@ -45,7 +45,7 @@ public class DateTimeUtil {

     public static String getISOTimeStamp( Long milliSecond )
     {
-        DateTimeFormatter formatter = DateTimeFormat.forPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
+        DateTimeFormatter formatter = DateTimeFormat.forPattern("yyyy-MM-dd'T'hh:mm:ss.SSS'Z'");
         DateTime currentDate = new DateTime(milliSecond, DateTimeZone.UTC);
         return currentDate.toString(formatter);
     }
diff --git a/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/NullEmptyUtils.java b/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/NullEmptyUtils.java
index f95410c..6f94322 100644
--- a/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/NullEmptyUtils.java
+++ b/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/NullEmptyUtils.java
@@ -11,7 +11,7 @@ public class NullEmptyUtils {

     public static boolean isNullorEmpty( String val )
     {
-        return isNull(val) || val.trim().isEmpty() || val.equals("null");
+        return isNull(val) || val.isEmpty() || val.equals("null");
     }

     public static boolean isNullorEmpty( List<?> val )
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Drop every shipped test source. They are JUnit 4 / PowerMock unit tests that
# the surefire junit-platform provider (junit-vintage excluded) never executes,
# so the agent-visible suite is empty/green; none of them exercise the planted
# helpers. The gold JUnit-5 boundary suite is injected only at grade time from
# config.json's test_patch. Also clear any stale compiled test class.
RUN rm -rf webservice/src/test jws-signature/src/test webservice/target/test-classes

# Collapse history: the planted state must not be recoverable via
# git diff/log/reflog. target/ is gitignored, so the warmed build stays out of
# the tree while remaining on disk for offline verify-time compilation.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app
