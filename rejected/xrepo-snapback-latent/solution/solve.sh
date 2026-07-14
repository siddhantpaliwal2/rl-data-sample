#!/bin/sh
# Oracle solution — reverse-applies the planted defect patch, restoring the
# correct boundary logic in the four shared modules (callbacks.ts, dates.ts,
# schemas.ts, time.ts). This is the minimal correct fix; any equivalent
# boundary correction that makes the gold tests pass is also accepted.
set -eu
cd /app
git apply -R --check - <<'DEFECT_PATCH_EOF' && git apply -R - <<'DEFECT_PATCH_EOF'
diff --git a/packages/shared/src/callbacks.ts b/packages/shared/src/callbacks.ts
index 1e2f160..06b7dfe 100644
--- a/packages/shared/src/callbacks.ts
+++ b/packages/shared/src/callbacks.ts
@@ -4,7 +4,6 @@ const separator = ":";

 export const callbackActionSchema = z.enum([
   "wake",
-  "instagram",
   "habit",
   "task",
 ]);
diff --git a/packages/shared/src/dates.ts b/packages/shared/src/dates.ts
index 5f72915..670dc3c 100644
--- a/packages/shared/src/dates.ts
+++ b/packages/shared/src/dates.ts
@@ -16,6 +16,6 @@ export function toDateKey(date: Date, timezone: string): string {
 }

 export function tomorrowDateKey(timezone: string): string {
-  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000);
+  const tomorrow = new Date(Date.now() - 24 * 60 * 60 * 1000);
   return toDateKey(tomorrow, timezone);
 }
diff --git a/packages/shared/src/schemas.ts b/packages/shared/src/schemas.ts
index e18b5f8..53cd08e 100644
--- a/packages/shared/src/schemas.ts
+++ b/packages/shared/src/schemas.ts
@@ -10,7 +10,7 @@ export const taskReviewStatusSchema = z.enum(["done", "partial", "not_done"]);

 export const integrationItemSchema = z.object({
   id: z.string().min(1),
-  title: z.string().min(1),
+  title: z.string().min(0),
   status: z.string().optional(),
   dueDate: z.string().optional(),
   metadata: z.record(z.string(), z.unknown()).optional(),
@@ -37,7 +37,7 @@ export const standupStateSchema = z.object({
   plannedWakeAnswer: answerValueSchema.optional(),
   instagramAnswer: answerValueSchema.optional(),
   habits: z.array(integrationItemSchema),
-  habitIndex: z.number().int().min(0),
+  habitIndex: z.number().min(0),
   tasks: z.array(integrationItemSchema),
   taskIndex: z.number().int().min(0),
   completedHabitIds: z.array(z.string()),
diff --git a/packages/shared/src/time.ts b/packages/shared/src/time.ts
index aae2ad7..3166cad 100644
--- a/packages/shared/src/time.ts
+++ b/packages/shared/src/time.ts
@@ -68,7 +68,7 @@ export function formatStandupTime(time: string): string {
 export function toTimeKey(date: Date, timezone: string): string {
   const parts = new Intl.DateTimeFormat("en-GB", {
     hour: "2-digit",
-    hour12: false,
+    hour12: true,
     minute: "2-digit",
     timeZone: timezone,
   }).formatToParts(date);
DEFECT_PATCH_EOF
diff --git a/packages/shared/src/callbacks.ts b/packages/shared/src/callbacks.ts
index 1e2f160..06b7dfe 100644
--- a/packages/shared/src/callbacks.ts
+++ b/packages/shared/src/callbacks.ts
@@ -4,7 +4,6 @@ const separator = ":";

 export const callbackActionSchema = z.enum([
   "wake",
-  "instagram",
   "habit",
   "task",
 ]);
diff --git a/packages/shared/src/dates.ts b/packages/shared/src/dates.ts
index 5f72915..670dc3c 100644
--- a/packages/shared/src/dates.ts
+++ b/packages/shared/src/dates.ts
@@ -16,6 +16,6 @@ export function toDateKey(date: Date, timezone: string): string {
 }

 export function tomorrowDateKey(timezone: string): string {
-  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000);
+  const tomorrow = new Date(Date.now() - 24 * 60 * 60 * 1000);
   return toDateKey(tomorrow, timezone);
 }
diff --git a/packages/shared/src/schemas.ts b/packages/shared/src/schemas.ts
index e18b5f8..53cd08e 100644
--- a/packages/shared/src/schemas.ts
+++ b/packages/shared/src/schemas.ts
@@ -10,7 +10,7 @@ export const taskReviewStatusSchema = z.enum(["done", "partial", "not_done"]);

 export const integrationItemSchema = z.object({
   id: z.string().min(1),
-  title: z.string().min(1),
+  title: z.string().min(0),
   status: z.string().optional(),
   dueDate: z.string().optional(),
   metadata: z.record(z.string(), z.unknown()).optional(),
@@ -37,7 +37,7 @@ export const standupStateSchema = z.object({
   plannedWakeAnswer: answerValueSchema.optional(),
   instagramAnswer: answerValueSchema.optional(),
   habits: z.array(integrationItemSchema),
-  habitIndex: z.number().int().min(0),
+  habitIndex: z.number().min(0),
   tasks: z.array(integrationItemSchema),
   taskIndex: z.number().int().min(0),
   completedHabitIds: z.array(z.string()),
diff --git a/packages/shared/src/time.ts b/packages/shared/src/time.ts
index aae2ad7..3166cad 100644
--- a/packages/shared/src/time.ts
+++ b/packages/shared/src/time.ts
@@ -68,7 +68,7 @@ export function formatStandupTime(time: string): string {
 export function toTimeKey(date: Date, timezone: string): string {
   const parts = new Intl.DateTimeFormat("en-GB", {
     hour: "2-digit",
-    hour12: false,
+    hour12: true,
     minute: "2-digit",
     timeZone: timezone,
   }).formatToParts(date);
DEFECT_PATCH_EOF
