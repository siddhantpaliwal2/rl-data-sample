"""Boundary / edge-case correctness for the financial-data analysis tools.

These assert the correct outputs on exact-threshold, minimal-window and
even-sized-set inputs that the broader analytics suite never exercises: a
credit score sitting exactly on a scoring-band floor, a two-month cash-flow
series whose volatility must still be measured, a revolving line at exactly the
near-limit utilization cutoff, a profit-and-loss summary at its minimum
reportable column width, a tradeline carrying a single severe late mark, and a
bureau field holding a "not-applicable" sentinel code that must be discarded
rather than read as a real number. Away from those edges every number is
already correct, which is why a boundary regression here stays invisible to the
rest of the suite (it only ever feeds values comfortably away from the edges).
"""

from __future__ import annotations

import unittest

from agent.analytics.services.credit_bureau_analytics import (
    _classify_risk_tier,
    _safe_float,
    build_credit_analytics_checklist_v1,
)
from agent.analytics.services.plaid_analytics import (
    _compute_volatility,
    build_bank_analytics_checklist_v1,
)
from agent.analytics.services.quickbooks_analytics import _extract_monthly_from_summary


def _near_limit_count(accounts: list[dict]) -> int:
    checklist = build_bank_analytics_checklist_v1({"accounts": accounts})
    return checklist["account_structure"]["credit_exposure"]["near_limit_accounts_count"]


def _severe_delinquency_count(tradelines: list[dict]) -> int:
    checklist = build_credit_analytics_checklist_v1({"tradelines": tradelines})
    return checklist["tradeline_signals"]["severe_delinquency_tradelines"]


def _monthly_from_cols(values: list[str], num_months: int) -> list[float]:
    section = {"Summary": {"ColData": [{"value": v} for v in values]}}
    return _extract_monthly_from_summary(section, num_months)


class TestCreditRiskTierBoundary(unittest.TestCase):
    def test_score_exactly_on_good_floor_is_good(self) -> None:
        # 740 is the lowest score that still earns the "good" tier; the sibling
        # band floors (>= 800, >= 670) are all inclusive.
        self.assertEqual(_classify_risk_tier(740)[0], "good")

    def test_score_just_above_good_floor_is_good(self) -> None:
        self.assertEqual(_classify_risk_tier(741)[0], "good")

    def test_score_just_below_good_floor_is_fair(self) -> None:
        self.assertEqual(_classify_risk_tier(739)[0], "fair")


class TestCashFlowVolatilityWindow(unittest.TestCase):
    def test_two_month_series_reports_volatility(self) -> None:
        # Two observations are enough to measure dispersion (statistics.stdev
        # is defined for n >= 2); the metric must be computed, not collapsed to
        # zero as if the series were a single point.
        self.assertEqual(_compute_volatility([100.0, 200.0]), 47.1)

    def test_two_month_series_wider_spread_reports_volatility(self) -> None:
        self.assertEqual(_compute_volatility([100.0, 300.0]), 70.7)

    def test_single_month_series_has_zero_volatility(self) -> None:
        self.assertEqual(_compute_volatility([100.0]), 0.0)

    def test_three_month_series_reports_volatility(self) -> None:
        self.assertEqual(_compute_volatility([100.0, 200.0, 300.0]), 50.0)


class TestBankNearLimitUtilization(unittest.TestCase):
    def test_account_exactly_on_near_limit_cutoff_counts(self) -> None:
        # Per BANK_ANALYTICS_CHECKLIST.md the near-limit count is accounts with
        # utilization_pct >= 75, so exactly 75% must be counted.
        accounts = [{"type": "credit", "utilization_pct": 75.0, "credit_limit": 1000}]
        self.assertEqual(_near_limit_count(accounts), 1)

    def test_two_accounts_one_exactly_on_cutoff_both_count(self) -> None:
        accounts = [
            {"type": "credit", "utilization_pct": 75.0, "credit_limit": 1000},
            {"type": "credit", "utilization_pct": 90.0, "credit_limit": 1000},
        ]
        self.assertEqual(_near_limit_count(accounts), 2)

    def test_account_just_above_cutoff_counts(self) -> None:
        accounts = [{"type": "credit", "utilization_pct": 75.5, "credit_limit": 1000}]
        self.assertEqual(_near_limit_count(accounts), 1)

    def test_account_just_below_cutoff_is_excluded(self) -> None:
        accounts = [{"type": "credit", "utilization_pct": 74.9, "credit_limit": 1000}]
        self.assertEqual(_near_limit_count(accounts), 0)


class TestQbMonthlySummaryWidth(unittest.TestCase):
    def test_minimal_width_summary_yields_monthly_values(self) -> None:
        # A [label, month..., TOTAL] summary at its minimum reportable width
        # (num_months + 2 columns) is well-formed and its months must be read.
        # _row_to_line_item accepts the same len >= num_months + 2.
        self.assertEqual(
            _monthly_from_cols(["Total Income", "100", "200", "300"], 2),
            [100.0, 200.0],
        )

    def test_minimal_width_three_month_summary_yields_values(self) -> None:
        self.assertEqual(
            _monthly_from_cols(["Total Income", "100", "200", "300", "400"], 3),
            [100.0, 200.0, 300.0],
        )

    def test_wider_summary_yields_monthly_values(self) -> None:
        self.assertEqual(
            _monthly_from_cols(["L", "100", "200", "300", "TOTAL"], 2),
            [100.0, 200.0],
        )

    def test_too_narrow_summary_yields_empty(self) -> None:
        self.assertEqual(_monthly_from_cols(["L", "100", "200"], 2), [])


class TestCreditSevereDelinquency(unittest.TestCase):
    def test_single_severe_late_counts_as_severe(self) -> None:
        # One 90-day-late mark on a tradeline already makes it a severe
        # delinquency; it must not require a second occurrence to count. The
        # sibling delinquent_open_count treats late_90 > 0 as delinquent.
        tradelines = [{"is_open": True, "late_90": 1, "monthly_payment": 100}]
        self.assertEqual(_severe_delinquency_count(tradelines), 1)

    def test_two_severe_lates_still_counts(self) -> None:
        tradelines = [{"is_open": True, "late_90": 2, "monthly_payment": 100}]
        self.assertEqual(_severe_delinquency_count(tradelines), 1)

    def test_no_severe_lates_not_counted(self) -> None:
        tradelines = [{"is_open": True, "late_90": 0, "monthly_payment": 100}]
        self.assertEqual(_severe_delinquency_count(tradelines), 0)


class TestCreditSummarySentinelValues(unittest.TestCase):
    def test_not_applicable_sentinel_is_discarded(self) -> None:
        # -5 ("Not applicable for this bureau") is a documented special code,
        # not a real figure; it must be treated as missing exactly as -3 and -4
        # are. The sibling _safe_int discards the same {-3, -4, -5} set.
        self.assertIsNone(_safe_float("-5"))

    def test_not_applicable_sentinel_falls_back_to_default(self) -> None:
        self.assertEqual(_safe_float("-5", 0.0), 0.0)

    def test_other_special_codes_still_discarded(self) -> None:
        self.assertIsNone(_safe_float("-3"))
        self.assertIsNone(_safe_float("-4"))

    def test_real_negative_value_is_kept(self) -> None:
        # -2 is not a sentinel code; it is a genuine value and must survive.
        self.assertEqual(_safe_float("-2"), -2.0)

    def test_ordinary_value_is_kept(self) -> None:
        self.assertEqual(_safe_float("1234.5"), 1234.5)


if __name__ == "__main__":
    unittest.main()
