#!/bin/sh
# Oracle solution — reverse-applies the planted defect patch, restoring the
# correct boundary behaviour in the FIU-adapter helpers: the detached-signature
# helper returns the third (signature) segment (split("\.")[2]), the object copy
# ignores only the null source properties (getPropertyValue == null), a signed
# api key with fewer than three segments is rejected (size() < 3), a single
# missing field yields the single-field message (split(",").length == 1), and the
# config mapper maps the company name from the company name
# (setCompanyName(getCompanyName())). Any equivalent boundary correction also
# passes the gold tests.
set -eu
cd /app

cat > /tmp/defects.patch <<'DEFECT_PATCH_EOF'
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
DEFECT_PATCH_EOF

git apply -R /tmp/defects.patch
rm -f /tmp/defects.patch
