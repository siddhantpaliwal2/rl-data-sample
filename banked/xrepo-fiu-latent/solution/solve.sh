#!/bin/sh
# Oracle solution — reverse-applies the planted defect patch, restoring the
# correct boundary behaviour in the FIU-adapter helpers: the day delta advances
# the day-of-month (Calendar.DATE), the virtual-address parser keeps the handle
# after '@' (split index 1), the UUID pattern requires the full 12-hex final
# group, a whitespace-only string is treated as empty (val.trim().isEmpty()),
# and the ISO timestamp uses the 24-hour clock (HH). Any equivalent boundary
# correction also passes the gold tests.
set -eu
cd /app

cat > /tmp/defects.patch <<'DEFECT_PATCH_EOF'
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
diff --git a/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/DateTimeUtil.java b/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/DateTimeUtil.java
index b0dd085..00c2a9a 100644
--- a/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/DateTimeUtil.java
+++ b/webservice/src/main/java/com/finbit/fiuadapter/webservice/utils/DateTimeUtil.java
@@ -28,7 +28,7 @@ public class DateTimeUtil {
         DateTime date = new DateTime(currentMilliSecond, DateTimeZone.UTC);
         Calendar c = Calendar.getInstance();
         c.setTime(date.toDate());
-        c.add(Calendar.DATE, days);
+        c.add(Calendar.MONTH, days);
         c.add(Calendar.MONTH, month);
         return getISOTimeStamp(new DateTime(c.getTimeInMillis(), DateTimeZone.UTC).getMillis());
     }
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
DEFECT_PATCH_EOF

git apply -R /tmp/defects.patch
rm -f /tmp/defects.patch
