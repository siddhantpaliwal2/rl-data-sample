# syntax=docker/dockerfile:1
# Planted-defect task image for the FIU-adapter parsing / object-copy /
# request-validation / config-mapping helpers. The boundary suite is
# deterministic, pure-input JUnit 5 (no Spring context, no DB, no network) and
# runs fully offline: fiu-repo:v1 warms the Maven cache, installs the sibling
# modules, and warms the Surefire JUnit-platform provider at build time.
#
# Locally this is the repo image built from silver-tasks scratch
# (Dockerfile.repo: maven:3.9-eclipse-temurin-8 + git + python3, sibling modules
# installed, LF-normalized working tree of the fiu_adapter repo). On the
# platform, replace with the approved registry reference, e.g.
# FROM <your-registry>/repo-images/fiu-xxxxx:v1@sha256:...
FROM fiu-repo:v1

USER root
WORKDIR /app

# Plant the subtle boundary defects into the working tree. Every kept path still
# behaves correctly with these applied; only untested exact-edge inputs (a
# two-segment token instead of the required three, the wrong split position of a
# dotted token, a null-vs-non-null property filter, a single-vs-multiple missing
# field count, and a swapped source getter in a config mapper) are wrong.
RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/consentnotification/ConsentNotificationValidationImpl.java b/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/consentnotification/ConsentNotificationValidationImpl.java
index 448234c..219ff3a 100644
--- a/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/consentnotification/ConsentNotificationValidationImpl.java
+++ b/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/consentnotification/ConsentNotificationValidationImpl.java
@@ -36,7 +36,7 @@ public class ConsentNotificationValidationImpl implements ConsentNotificationVal
     public void validateRequestFields(ConsentNotificationRequest consentNotificationRequest) throws InvalidRequestException, ParseException, DataException {
         String errorMsg = schematicErrorCheck(consentNotificationRequest);
 
-        if(errorMsg.split(",").length == 1 && errorMsg != ""){
+        if(errorMsg.split(",").length == 2 && errorMsg != ""){
             throw new InvalidRequestException(consentNotificationRequest.getTxnid(), GeneralConstants.INVALID_REQUEST,errorMsg+GeneralConstants.ERROR_MESSAGE,HttpStatus.BAD_REQUEST);
         }
 
diff --git a/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/externalentity/AAEntityServiceImpl.java b/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/externalentity/AAEntityServiceImpl.java
index 654cfcb..e35508e 100644
--- a/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/externalentity/AAEntityServiceImpl.java
+++ b/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/externalentity/AAEntityServiceImpl.java
@@ -154,7 +154,7 @@ public class AAEntityServiceImpl extends AbstractController implements AAEntityS
         OneMoneyConfigeResponse oneMoneyConfigeResponse = new OneMoneyConfigeResponse();
         oneMoneyConfigeResponse.setCompanyLogo(entityDetails.getCompanyLogo());
         oneMoneyConfigeResponse.setCompanyColor(entityDetails.getCompanyColor());
-        oneMoneyConfigeResponse.setCompanyName(entityDetails.getCompanyName());
+        oneMoneyConfigeResponse.setCompanyName(entityDetails.getCompanyColor());
         oneMoneyConfigeResponse.setAppIdentifier(applicationConfigurationBean.getAppIdentifier());
         oneMoneyConfigeResponse.setBaseURL(applicationConfigurationBean.getBaseURL());
         oneMoneyConfigeResponse.setClient_id(applicationConfigurationBean.getClient_id());
diff --git a/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/signature/verification/HeaderTokenSignatureVerificationServiceImpl.java b/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/signature/verification/HeaderTokenSignatureVerificationServiceImpl.java
index a488671..946f474 100644
--- a/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/signature/verification/HeaderTokenSignatureVerificationServiceImpl.java
+++ b/webservice/src/main/java/com/finbit/fiuadapter/webservice/service/signature/verification/HeaderTokenSignatureVerificationServiceImpl.java
@@ -58,7 +58,7 @@ public class HeaderTokenSignatureVerificationServiceImpl implements HeaderTokenS
         }
 
         List<String> split_string = Arrays.asList(aaApiKey.split("\\."));
-        if(split_string.size() < 3){
+        if(split_string.size() < 2){
             throw new DataException(
                     GeneralConstants.UNAUTHORIZED,
                     GeneralConstants.INVALID_AA_API_KEY_PROVIDED,
diff --git a/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/BeansUtils.java b/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/BeansUtils.java
index d58ea4e..e252b9d 100644
--- a/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/BeansUtils.java
+++ b/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/BeansUtils.java
@@ -30,7 +30,7 @@ public class BeansUtils {
     {
         final BeanWrapper wrappedSource = new BeanWrapperImpl(source);
         return Stream.of(wrappedSource.getPropertyDescriptors()).map(FeatureDescriptor::getName)
-                .filter(propertyName -> wrappedSource.getPropertyValue(propertyName) == null).toArray(String[]::new);
+                .filter(propertyName -> wrappedSource.getPropertyValue(propertyName) != null).toArray(String[]::new);
     }
 }
 
diff --git a/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/GetDetachedBody.java b/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/GetDetachedBody.java
index 70223c1..67dc3aa 100644
--- a/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/GetDetachedBody.java
+++ b/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/GetDetachedBody.java
@@ -16,7 +16,7 @@ public class GetDetachedBody {
      */
     public static String getDetached( String body )
     {
-        return body.split("\\.")[2];
+        return body.split("\\.")[1];
 
     }
 }
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
