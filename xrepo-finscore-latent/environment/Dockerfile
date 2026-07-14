# syntax=docker/dockerfile:1
# Planted-defect task image for the FinScore analysis / scoring math.
# The boundary suite is deterministic, pure-input JUnit (no Spring context, no
# DB, no network) and runs fully offline: finscore-repo:v1 warms the Maven
# cache and the Surefire JUnit-platform provider at build time.
#
# Locally this is the repo image built from silver-tasks scratch
# (Dockerfile.repo: maven:3.9-eclipse-temurin-8 + git + warmed cache, LF-
# normalized working tree of the finscore repo). On the platform, replace with
# the approved registry reference, e.g.
# FROM us-docker.pkg.dev/afterqueryai/silver-repo-images/finscore-xxxxx:v1@sha256:...
FROM finscore-repo:v1

USER root
WORKDIR /app

# The finscore-repo:v1 working tree is already the clean LF base (its embedded
# .git HEAD is a stale CRLF snapshot and is discarded by the seal below), so we
# do NOT git reset. Plant the subtle boundary defects into the working tree.
# Every kept test still passes with these applied; only untested exact-edge
# inputs (a max/min extremum, the leading sorted element, an average-vs-total
# divisor, a top-N cap, a percent scale factor) are wrong.
RUN cat > /tmp/defects.patch <<'PATCH_EOF'
diff --git a/src/main/java/com/finbit/finscore/mapper/FinScoreAnalysisMapper.java b/src/main/java/com/finbit/finscore/mapper/FinScoreAnalysisMapper.java
index 51bbc71..fc01e58 100644
--- a/src/main/java/com/finbit/finscore/mapper/FinScoreAnalysisMapper.java
+++ b/src/main/java/com/finbit/finscore/mapper/FinScoreAnalysisMapper.java
@@ -148,7 +148,7 @@ public class FinScoreAnalysisMapper {
                     }
                 }
                 if (averageIncome > 0 && averageBankBalance > 0) {
-                    double averageMonthlyIncomePercent = roundOff((averageBankBalance / averageIncome) * 100);
+                    double averageMonthlyIncomePercent = roundOff((averageBankBalance / averageIncome) * 10);
                     result.setAverageMonthlyIncomePercent(averageMonthlyIncomePercent);
                 }
             }
@@ -191,7 +191,7 @@ public class FinScoreAnalysisMapper {
         if (!DataEmptyNullUtil.isNull(bankScoreDetailDTO) && !DataEmptyNullUtil.isNullOrEmpty(bankScoreDetailDTO.getData().getBankAnalysisDetails())) {
             for (BankAnalysisDetailDTO bankAnalysisDetailDTO : bankScoreDetailDTO.getData().getBankAnalysisDetails()) {
                 if (bankAnalysisDetailDTO.getParameter().equals("Income") && !DataEmptyNullUtil.isNullOrEmpty(bankAnalysisDetailDTO.getMonthlyTotal())) {
-                    double percentOfTotalIncome = !DataEmptyNullUtil.isNullOrEmpty(result.getSpendingCategoryList()) ? roundOff((result.getSpendingCategoryList().get(0).getTotal() / bankAnalysisDetailDTO.getTotal()) * 100) : 0;
+                    double percentOfTotalIncome = !DataEmptyNullUtil.isNullOrEmpty(result.getSpendingCategoryList()) ? roundOff((result.getSpendingCategoryList().get(1).getTotal() / bankAnalysisDetailDTO.getTotal()) * 100) : 0;
                     result.setPercentOfTotalIncome(percentOfTotalIncome);
                 }
             }
@@ -260,7 +260,7 @@ public class FinScoreAnalysisMapper {
                 }
             }
             if (!DataEmptyNullUtil.isNullOrEmpty(result.getMonthlyCreditCardUtilization())) {
-                MonthlyExpensesDTO highestValue = result.getMonthlyCreditCardUtilization().stream().max(Comparator.comparing(MonthlyExpensesDTO::getValue)).orElse(null);
+                MonthlyExpensesDTO highestValue = result.getMonthlyCreditCardUtilization().stream().min(Comparator.comparing(MonthlyExpensesDTO::getValue)).orElse(null);
                 result.setHighestCreditCardUtilization(!DataEmptyNullUtil.isNull(highestValue) ? highestValue.getValue() : 0);
             }
         }
@@ -286,7 +286,7 @@ public class FinScoreAnalysisMapper {
             Collections.sort(merchantDetailDTO.getMerchantAnalysis(), merchantAnalysisDTOComparator.reversed());
             List<MerchantAnalysisDTO> merchantAnalysisDTOS = null;
             if (merchantDetailDTO.getMerchantAnalysis().size() >= 5) {
-                merchantAnalysisDTOS = merchantDetailDTO.getMerchantAnalysis().stream().limit(5).collect(Collectors.toList());
+                merchantAnalysisDTOS = merchantDetailDTO.getMerchantAnalysis().stream().limit(4).collect(Collectors.toList());
             } else {
                 merchantAnalysisDTOS = merchantDetailDTO.getMerchantAnalysis();
             }
@@ -327,7 +327,7 @@ public class FinScoreAnalysisMapper {
         if (!DataEmptyNullUtil.isNull(bankScoreDetailDTO) && !DataEmptyNullUtil.isNullOrEmpty(bankScoreDetailDTO.getData().getBankAnalysisDetails())) {
             for (BankAnalysisDetailDTO bankAnalysisDetailDTO : bankScoreDetailDTO.getData().getBankAnalysisDetails()) {
                 if (bankAnalysisDetailDTO.getParameter().equals("Income") && !DataEmptyNullUtil.isNullOrEmpty(bankAnalysisDetailDTO.getMonthlyTotal())) {
-                    double percentAverageMonthlyIncome = result.getAverageMonthlyObligation() != 0 ? roundOff((result.getAverageMonthlyObligation() / bankAnalysisDetailDTO.getAverage()) * 100) : 0;
+                    double percentAverageMonthlyIncome = result.getAverageMonthlyObligation() != 0 ? roundOff((result.getAverageMonthlyObligation() / bankAnalysisDetailDTO.getTotal()) * 100) : 0;
                     result.setPercentageAverageMonthlyIncome(percentAverageMonthlyIncome);
                 }
             }
PATCH_EOF

RUN git apply /tmp/defects.patch && rm -f /tmp/defects.patch

# Drop the shipped Spring context-load smoke test: it needs a live Postgres +
# Keycloak and cannot run offline, so it is not part of the agent-visible suite
# (which is therefore green/empty) and is unrelated to the planted math bugs.
RUN rm -f src/test/java/com/finbit/finscore/FinscoreApplicationTests.java

# Collapse history: the planted state must not be recoverable via
# git diff/log/reflog. target/ is gitignored, so the warmed build stays out of
# the tree while remaining on disk for offline verify-time compilation.
RUN rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"

RUN mkdir -p /logs/verifier

WORKDIR /app
