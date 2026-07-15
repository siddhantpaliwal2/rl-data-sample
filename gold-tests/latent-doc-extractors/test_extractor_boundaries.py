"""Boundary / edge-case correctness for CRE document field extraction.

These feed raw document text straight into the ``extract_*`` helpers and assert
the correct structured value on exact-threshold and minimum-cardinality inputs
that the broader extraction suite never exercises: an appraisal sitting exactly
on the minimum-value floor, a rent roll with only the fewest rows that still
count as a roll, a settlement statement whose loan figure lands exactly on the
plausibility floor, a personal-financial-statement total sitting exactly on its
scan floor, and a credit score at the very top of the valid band. The existing
extraction tests only ever feed values comfortably away from these edges, so a
boundary regression here stays invisible to them.
"""

from __future__ import annotations

import unittest

from agent.documents.extractors.cre_fields import (
    extract_appraisal_fields,
    extract_credit_report_fields,
    extract_hud_fields,
    extract_pfs_from_text,
    extract_rent_roll_fields,
)


class TestAppraisalValueFloor(unittest.TestCase):
    def test_value_exactly_on_100k_floor_is_kept(self) -> None:
        # A property appraised at exactly the $100k minimum is a real value,
        # not OCR noise, and must be returned rather than discarded.
        facts = extract_appraisal_fields("As-Is Value: $100,000")
        self.assertEqual(facts.get("as_is_value"), 100_000.0)

    def test_value_above_floor_is_kept(self) -> None:
        facts = extract_appraisal_fields("As-Is Value: $150,000")
        self.assertEqual(facts.get("as_is_value"), 150_000.0)

    def test_value_below_floor_is_discarded(self) -> None:
        # Sub-$100k figures on an appraisal are almost always OCR fragments and
        # are intentionally dropped.
        facts = extract_appraisal_fields("As-Is Value: $90,000")
        self.assertIsNone(facts.get("as_is_value"))


class TestRentRollSum(unittest.TestCase):
    def test_two_rent_lines_are_summed(self) -> None:
        # Two rent lines are the smallest set that still reads as a rent roll to
        # aggregate; their monthly figures must be summed into gross potential
        # rent (there is nothing to "sum" with fewer than two figures).
        text = "Suite 101 rent $2,000\nSuite 102 rent $2,500"
        facts = extract_rent_roll_fields(text)
        self.assertEqual(facts.get("gross_potential_rent"), 4_500.0)

    def test_three_rent_lines_are_summed(self) -> None:
        text = "Suite 101 rent $2,000\nSuite 102 rent $2,500\nSuite 103 rent $3,000"
        facts = extract_rent_roll_fields(text)
        self.assertEqual(facts.get("gross_potential_rent"), 7_500.0)

    def test_single_rent_line_is_not_a_roll(self) -> None:
        # One line alone is not enough to trust as a summed rent-roll total.
        facts = extract_rent_roll_fields("Suite 101 rent $2,000")
        self.assertIsNone(facts.get("gross_potential_rent"))


class TestHudLoanFloor(unittest.TestCase):
    def test_loan_exactly_on_minimum_is_kept(self) -> None:
        # A loan amount of exactly the plausibility floor is a real figure at
        # (not below) the minimum, and must be retained.
        facts = extract_hud_fields("Loan Amount: $10,000")
        self.assertEqual(facts.get("hud_loan_amount"), 10_000.0)

    def test_loan_above_minimum_is_kept(self) -> None:
        facts = extract_hud_fields("Loan Amount: $50,000")
        self.assertEqual(facts.get("hud_loan_amount"), 50_000.0)

    def test_loan_below_minimum_is_discarded(self) -> None:
        facts = extract_hud_fields("Loan Amount: $5,000")
        self.assertIsNone(facts.get("hud_loan_amount"))


class TestPfsAssetFloor(unittest.TestCase):
    def test_total_assets_exactly_on_scan_floor_is_kept(self) -> None:
        # A total-assets figure sitting exactly on the scan's minimum-amount
        # floor is a legitimate value at the floor, not sub-floor noise, and
        # must be captured.
        text = "22. Total of All Assets\n100,000"
        facts = extract_pfs_from_text(text)
        self.assertEqual(facts.get("total_assets"), 100_000.0)

    def test_total_assets_above_floor_is_kept(self) -> None:
        text = "22. Total of All Assets\n150,000"
        facts = extract_pfs_from_text(text)
        self.assertEqual(facts.get("total_assets"), 150_000.0)

    def test_total_assets_below_floor_is_discarded(self) -> None:
        text = "22. Total of All Assets\n80,000"
        facts = extract_pfs_from_text(text)
        self.assertIsNone(facts.get("total_assets"))


class TestFicoBand(unittest.TestCase):
    def test_top_of_band_score_is_kept(self) -> None:
        # 850 is the maximum valid FICO and must be kept, not treated as
        # out-of-range and dropped.
        facts = extract_credit_report_fields("FICO Classic v5 850")
        self.assertEqual(facts.get("primary_fico_score"), 850)

    def test_in_band_score_below_top_is_kept(self) -> None:
        facts = extract_credit_report_fields("FICO Classic v5 840")
        self.assertEqual(facts.get("primary_fico_score"), 840)

    def test_out_of_band_score_is_dropped(self) -> None:
        # A sub-300 value is not a valid FICO and yields no bureau score.
        facts = extract_credit_report_fields("FICO Classic v5 200")
        self.assertIsNone(facts.get("primary_fico_score"))


if __name__ == "__main__":
    unittest.main()
