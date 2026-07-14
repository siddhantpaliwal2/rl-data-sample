#!/bin/sh
# Oracle solution — reverse-applies the planted defect patch, restoring the
# correct boundary logic in apps/native/lib/formatters.ts (the compact-number
# K cutoff, the address abbreviation floor, the email full-match anchor, the
# phone minimum-length gate, and the crypto precision-band boundary).
set -eu
cd /app
git apply -R --check - <<'DEFECT_PATCH_EOF' && git apply -R - <<'DEFECT_PATCH_EOF'
diff --git a/lib/formatters.ts b/lib/formatters.ts
index e227f99..249c29d 100644
--- a/lib/formatters.ts
+++ b/lib/formatters.ts
@@ -28,7 +28,7 @@ export const formatCompactNumber = (value: number): string => {
   if (value >= 1e6) {
     return `${(value / 1e6).toFixed(2)}M`;
   }
-  if (value >= 1e3) {
+  if (value > 1e3) {
     return `${(value / 1e3).toFixed(2)}K`;
   }
   return value.toFixed(2);
@@ -124,7 +124,7 @@ export const formatCryptoAmount = (
   let decimals = minDecimals;
   
   // Use more decimals for very small amounts
-  if (value < 0.01) {
+  if (value <= 0.01) {
     decimals = maxDecimals;
   } else if (value < 1) {
     decimals = 4;
@@ -147,7 +147,7 @@ export const truncateText = (text: string, maxLength: number): string => {
  * Format wallet address
  */
 export const formatAddress = (address: string, chars: number = 4): string => {
-  if (address.length <= chars * 2) {
+  if (address.length < chars * 2) {
     return address;
   }
   return `${address.slice(0, chars)}...${address.slice(-chars)}`;
@@ -157,7 +157,7 @@ export const formatAddress = (address: string, chars: number = 4): string => {
  * Validate email
  */
 export const isValidEmail = (email: string): boolean => {
-  const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
+  const re = /^[^\s@]+@[^\s@]+\.[^\s@]+/;
   return re.test(email);
 };
 
@@ -166,7 +166,7 @@ export const isValidEmail = (email: string): boolean => {
  */
 export const isValidPhone = (phone: string): boolean => {
   const re = /^\+?[\d\s\-()]+$/;
-  return re.test(phone) && phone.replace(/\D/g, '').length >= 10;
+  return re.test(phone) && phone.replace(/\D/g, '').length > 10;
 };
 
 /**
DEFECT_PATCH_EOF
diff --git a/lib/formatters.ts b/lib/formatters.ts
index e227f99..249c29d 100644
--- a/lib/formatters.ts
+++ b/lib/formatters.ts
@@ -28,7 +28,7 @@ export const formatCompactNumber = (value: number): string => {
   if (value >= 1e6) {
     return `${(value / 1e6).toFixed(2)}M`;
   }
-  if (value >= 1e3) {
+  if (value > 1e3) {
     return `${(value / 1e3).toFixed(2)}K`;
   }
   return value.toFixed(2);
@@ -124,7 +124,7 @@ export const formatCryptoAmount = (
   let decimals = minDecimals;
   
   // Use more decimals for very small amounts
-  if (value < 0.01) {
+  if (value <= 0.01) {
     decimals = maxDecimals;
   } else if (value < 1) {
     decimals = 4;
@@ -147,7 +147,7 @@ export const truncateText = (text: string, maxLength: number): string => {
  * Format wallet address
  */
 export const formatAddress = (address: string, chars: number = 4): string => {
-  if (address.length <= chars * 2) {
+  if (address.length < chars * 2) {
     return address;
   }
   return `${address.slice(0, chars)}...${address.slice(-chars)}`;
@@ -157,7 +157,7 @@ export const formatAddress = (address: string, chars: number = 4): string => {
  * Validate email
  */
 export const isValidEmail = (email: string): boolean => {
-  const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
+  const re = /^[^\s@]+@[^\s@]+\.[^\s@]+/;
   return re.test(email);
 };
 
@@ -166,7 +166,7 @@ export const isValidEmail = (email: string): boolean => {
  */
 export const isValidPhone = (phone: string): boolean => {
   const re = /^\+?[\d\s\-()]+$/;
-  return re.test(phone) && phone.replace(/\D/g, '').length >= 10;
+  return re.test(phone) && phone.replace(/\D/g, '').length > 10;
 };
 
 /**
DEFECT_PATCH_EOF
