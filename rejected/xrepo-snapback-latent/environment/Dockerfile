# syntax=docker/dockerfile:1
# Planted-defect task image for the snapback shared standup utilities.
# The shared package is deterministic and fully offline; node_modules (zod) is
# warmed into snapback-repo:v1 at build time, so the verifier runs with no
# network. Locally, snapback-repo:v1 is built from the base_ctx Dockerfile
# (a clean, isolated copy of packages/shared on oven/bun:1 with git + python3).
# On the platform, replace with the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/snapback-xxxxx:v1@sha256:...
FROM snapback-repo:v1

USER root
WORKDIR /app

# Plant the subtle boundary defects into the clean working tree. Every existing
# shared unit test still passes with these applied; only untested edge inputs
# (afternoon/midnight time keys, the day-after key, the instagram callback
# action, blank integration-item titles, fractional workflow indices) are wrong.
RUN cat > /tmp/defects.patch <<'PATCH_EOF'
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
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Collapse history: planted state must not be recoverable via git diff/log/reflog.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app
