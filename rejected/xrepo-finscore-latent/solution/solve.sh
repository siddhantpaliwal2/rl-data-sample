#!/bin/sh
# Oracle solution — reverse-applies the planted defect patch, restoring the
# correct boundary math in FinScoreAnalysisMapper: the MAX credit-card
# extremum, the leading (index 0) sorted category, the average-income divisor,
# the top-5 merchant cap, and the *100 percent scale factor. Any equivalent
# boundary correction also passes the gold tests.
set -eu
cd /app
git apply -R --check - <<'DEFECT_PATCH_EOF' && git apply -R - <<'DEFECT_PATCH_EOF'
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
DEFECT_PATCH_EOF
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
DEFECT_PATCH_EOF
